import hashlib
import hmac
import json
import os
import re
import secrets
import sqlite3
import string
import time
import urllib.error
import urllib.request
from datetime import datetime, timezone, timedelta
from pathlib import Path

from flask import Flask, jsonify, request, send_from_directory, Response

app = Flask(__name__)
app.config["MAX_CONTENT_LENGTH"] = 1 * 1024 * 1024

REPORTS_DIR = Path(os.environ.get("REPORTS_DIR", "/tmp/inrpf-reports"))
REPORT_TOKEN = os.environ.get("INRPF_REPORT_TOKEN", "")
LICENSE_DB = os.environ.get("INRPF_LICENSE_DB", "/var/data/inrpf-licenses.sqlite3")
LICENSE_PEPPER = os.environ.get("INRPF_LICENSE_PEPPER", "")
LICENSE_ADMIN_TOKEN = os.environ.get("INRPF_LICENSE_ADMIN_TOKEN", "")
ADMIN_PASSWORD = os.environ.get("INRPF_ADMIN_PASSWORD", "")
CODE_ALPHABET = "23456789ABCDEFGHJKLMNPQRSTUVWXYZ"
ALLOWED_FEATURES = {"github_tools", "ai_repair_pro", "advanced_ftp", "advanced_ai_providers", "gemini_tool"}
GEMINI_PROJECT_ID = os.environ.get("GOOGLE_CLOUD_PROJECT_ID", "")
GEMINI_SERVICE_ACCOUNT_JSON = os.environ.get("GOOGLE_SERVICE_ACCOUNT_JSON", "")
GEMINI_ENCRYPTION_KEY = os.environ.get("INRPF_GEMINI_ENCRYPTION_KEY", "")


def utc_now():
    return datetime.now(timezone.utc).isoformat()


class _PostgresConnection:
    """Small DB-API compatibility layer for the existing SQLite-oriented queries."""

    def __init__(self, connection):
        self._connection = connection

    def execute(self, query, params=()):
        query = query.replace("BEGIN IMMEDIATE", "BEGIN").replace("?", "%s")
        return self._connection.execute(query, params)

    def close(self):
        self._connection.close()


def _migrate_legacy_sqlite(connection):
    """Import the old on-disk SQLite license store once; never delete or modify it."""
    path = Path(LICENSE_DB)
    if not path.is_file():
        return

    connection.execute("""
        CREATE TABLE IF NOT EXISTS schema_migrations (
            version TEXT PRIMARY KEY,
            applied_at TEXT NOT NULL
        )
    """)
    connection.execute("BEGIN")
    try:
        # Serialize concurrent Gunicorn workers attempting the one-time import.
        connection.execute("SELECT pg_advisory_xact_lock(%s)", (81420261116,))
        applied = connection.execute(
            "SELECT 1 FROM schema_migrations WHERE version=%s",
            ("legacy-sqlite-license-import-v1",)
        ).fetchone()
        if applied:
            connection.execute("COMMIT")
            return

        with sqlite3.connect(f"file:{path.resolve()}?mode=ro", uri=True) as legacy:
            legacy.row_factory = sqlite3.Row
            tables = {
                row[0] for row in legacy.execute(
                    "SELECT name FROM sqlite_master WHERE type='table'"
                ).fetchall()
            }
            if "premium_codes" in tables:
                columns = {
                    row[1] for row in legacy.execute(
                        "PRAGMA table_info(premium_codes)"
                    ).fetchall()
                }
                expires_expr = "expires_at" if "expires_at" in columns else "NULL"
                duration_expr = "duration_seconds" if "duration_seconds" in columns else "NULL"
                rows = legacy.execute(
                    "SELECT code_hash,code_hint,status,features_json,created_at,"
                    f"redeemed_at,activation_id,{expires_expr},{duration_expr} "
                    "FROM premium_codes"
                ).fetchall()
                for row in rows:
                    connection.execute(
                        "INSERT INTO premium_codes "
                        "(code_hash,code_hint,status,features_json,created_at,redeemed_at,"
                        "activation_id,expires_at,duration_seconds) "
                        "VALUES(%s,%s,%s,%s,%s,%s,%s,%s,%s) "
                        "ON CONFLICT(code_hash) DO NOTHING",
                        tuple(row)
                    )

            if "gemini_keys" in tables:
                rows = legacy.execute(
                    "SELECT id,resource_name,encrypted_key,key_hint,created_at FROM gemini_keys"
                ).fetchall()
                for row in rows:
                    connection.execute(
                        "INSERT INTO gemini_keys(id,resource_name,encrypted_key,key_hint,created_at) "
                        "VALUES(%s,%s,%s,%s,%s) ON CONFLICT(id) DO NOTHING",
                        tuple(row)
                    )

        connection.execute(
            "INSERT INTO schema_migrations(version,applied_at) VALUES(%s,%s) "
            "ON CONFLICT(version) DO NOTHING",
            ("legacy-sqlite-license-import-v1", utc_now())
        )
        connection.execute("COMMIT")
        app.logger.info("Legacy SQLite license-store import completed; source file retained.")
    except Exception:
        connection.execute("ROLLBACK")
        app.logger.exception("Legacy SQLite license-store import failed")
        raise


def db():
    database_url = os.environ.get("DATABASE_URL", "").strip()
    if not database_url and os.environ.get("RENDER_SERVICE_ID"):
        raise RuntimeError("DATABASE_URL is required for the Render production service")
    if database_url:
        try:
            import psycopg
            from psycopg.rows import dict_row

            raw = psycopg.connect(
                database_url,
                row_factory=dict_row,
                autocommit=True,
                connect_timeout=10
            )
            connection = _PostgresConnection(raw)
            connection.execute("""
                CREATE TABLE IF NOT EXISTS gemini_keys (
                    id INTEGER PRIMARY KEY CHECK(id = 1),
                    resource_name TEXT NOT NULL,
                    encrypted_key TEXT NOT NULL,
                    key_hint TEXT NOT NULL,
                    created_at TEXT NOT NULL
                )
            """)
            connection.execute("""
                CREATE TABLE IF NOT EXISTS premium_codes (
                    code_hash TEXT PRIMARY KEY,
                    code_hint TEXT NOT NULL,
                    status TEXT NOT NULL CHECK(status IN ('unused','redeemed','revoked')),
                    features_json TEXT NOT NULL,
                    created_at TEXT NOT NULL,
                    redeemed_at TEXT,
                    activation_id TEXT,
                    expires_at TEXT,
                    duration_seconds BIGINT
                )
            """)
            connection.execute(
                "ALTER TABLE premium_codes ADD COLUMN IF NOT EXISTS expires_at TEXT"
            )
            connection.execute(
                "ALTER TABLE premium_codes ADD COLUMN IF NOT EXISTS duration_seconds BIGINT"
            )
            _migrate_legacy_sqlite(connection)
            return connection
        except Exception:
            app.logger.exception("PostgreSQL connection/schema initialization failed")
            raise

    # SQLite remains available for local development and the existing isolated tests.
    path = Path(LICENSE_DB)
    path.parent.mkdir(parents=True, exist_ok=True)
    connection = sqlite3.connect(str(path), timeout=15, isolation_level=None)
    connection.row_factory = sqlite3.Row
    connection.execute("PRAGMA journal_mode=WAL")
    connection.execute("PRAGMA busy_timeout=15000")
    connection.execute("""
        CREATE TABLE IF NOT EXISTS gemini_keys (
            id INTEGER PRIMARY KEY CHECK(id = 1), resource_name TEXT NOT NULL,
            encrypted_key TEXT NOT NULL, key_hint TEXT NOT NULL, created_at TEXT NOT NULL
        )
    """)
    connection.execute("""
        CREATE TABLE IF NOT EXISTS premium_codes (
            code_hash TEXT PRIMARY KEY,
            code_hint TEXT NOT NULL,
            status TEXT NOT NULL CHECK(status IN ('unused','redeemed','revoked')),
            features_json TEXT NOT NULL,
            created_at TEXT NOT NULL,
            redeemed_at TEXT,
            activation_id TEXT,
            expires_at TEXT,
            duration_seconds INTEGER
        )
    """)
    columns = {row[1] for row in connection.execute("PRAGMA table_info(premium_codes)").fetchall()}
    if "expires_at" not in columns:
        connection.execute("ALTER TABLE premium_codes ADD COLUMN expires_at TEXT")
    if "duration_seconds" not in columns:
        connection.execute("ALTER TABLE premium_codes ADD COLUMN duration_seconds INTEGER")
    return connection


def code_digest(code):
    if not LICENSE_PEPPER:
        raise RuntimeError("INRPF_LICENSE_PEPPER is not configured")
    normalized = re.sub(r"[^A-Z0-9]", "", str(code).upper())
    return hmac.new(LICENSE_PEPPER.encode(), normalized.encode(), hashlib.sha256).hexdigest()


def authorized():
    supplied = request.headers.get("Authorization", "")
    return bool(REPORT_TOKEN) and hmac.compare_digest(supplied, f"Bearer {REPORT_TOKEN}")


def admin_authorized():
    supplied = request.headers.get("Authorization", "")
    return (
        (bool(LICENSE_ADMIN_TOKEN) and hmac.compare_digest(supplied, f"Bearer {LICENSE_ADMIN_TOKEN}"))
        or (bool(ADMIN_PASSWORD) and hmac.compare_digest(supplied, f"Bearer {ADMIN_PASSWORD}"))
    )


def licensing_ready():
    return bool(LICENSE_PEPPER and LICENSE_ADMIN_TOKEN)


def make_code():
    groups = ["".join(secrets.choice(CODE_ALPHABET) for _ in range(4)) for _ in range(4)]
    return "INRPF-" + "-".join(groups)

def gemini_crypto():
    if not GEMINI_ENCRYPTION_KEY:
        raise RuntimeError("INRPF_GEMINI_ENCRYPTION_KEY is not configured")
    from cryptography.fernet import Fernet
    return Fernet(GEMINI_ENCRYPTION_KEY.encode())


def gemini_credentials():
    if not GEMINI_PROJECT_ID or not GEMINI_SERVICE_ACCOUNT_JSON:
        raise RuntimeError("Google Cloud project and service account are not configured")
    from google.oauth2 import service_account
    return service_account.Credentials.from_service_account_info(
        json.loads(GEMINI_SERVICE_ACCOUNT_JSON),
        scopes=["https://www.googleapis.com/auth/cloud-platform"]
    )


def create_google_gemini_key():
    from google.auth.transport.requests import AuthorizedSession
    session = AuthorizedSession(gemini_credentials())
    url = f"https://apikeys.googleapis.com/v2/projects/{GEMINI_PROJECT_ID}/locations/global/keys"
    response = session.post(url, json={"displayName": "INRPF Gemini API", "restrictions": {"apiTargets": [{"service": "generativelanguage.googleapis.com"}]}})
    response.raise_for_status()
    operation_name = response.json().get("name")
    if not operation_name:
        raise RuntimeError("Google API did not return an operation")
    for _ in range(30):
        operation = session.get("https://apikeys.googleapis.com/v2/" + operation_name)
        operation.raise_for_status()
        state = operation.json()
        if state.get("done"):
            if state.get("error"):
                raise RuntimeError("Google API key creation failed")
            resource = state.get("response", {})
            key_value, resource_name = resource.get("keyString"), resource.get("name")
            if not key_value or not resource_name:
                raise RuntimeError("Google did not return the API key")
            encrypted = gemini_crypto().encrypt(key_value.encode()).decode()
            connection = db()
            try:
                connection.execute(
                    "INSERT INTO gemini_keys(id,resource_name,encrypted_key,key_hint,created_at) VALUES(1,?,?,?,?) "
                    "ON CONFLICT(id) DO UPDATE SET resource_name=excluded.resource_name,encrypted_key=excluded.encrypted_key,key_hint=excluded.key_hint,created_at=excluded.created_at",
                    (resource_name, encrypted, key_value[-4:], utc_now())
                )
            finally:
                connection.close()
            return {"key_hint": key_value[-4:], "resource_name": resource_name}
        time.sleep(1)
    raise RuntimeError("Google API key creation timed out")


def load_gemini_key():
    connection = db()
    try:
        row = connection.execute("SELECT encrypted_key FROM gemini_keys WHERE id=1").fetchone()
        return gemini_crypto().decrypt(row["encrypted_key"].encode()).decode() if row else None
    finally:
        connection.close()


def activation_features(activation_id):
    if not activation_id or len(activation_id) > 128 or not LICENSE_PEPPER:
        return None
    digest = hmac.new(LICENSE_PEPPER.encode(), ("activation:" + activation_id).encode(), hashlib.sha256).hexdigest()
    connection = db()
    try:
        row = connection.execute(
            "SELECT features_json,expires_at FROM premium_codes WHERE activation_id=? AND status='redeemed'",
            (digest,)
        ).fetchone()
        if row is None or (row["expires_at"] and row["expires_at"] <= utc_now()):
            return None
        return json.loads(row["features_json"])
    finally:
        connection.close()


def proxy_gemini(path):
    supplied = request.headers.get("Authorization", "")
    features = activation_features(supplied[7:].strip()) if supplied.startswith("Bearer ") else None
    if not features or "gemini_tool" not in features:
        return jsonify({"error": {"message": "Gemini tool license required"}}), 403
    api_key = load_gemini_key()
    if not api_key:
        return jsonify({"error": {"message": "Gemini service is not configured"}}), 503
    headers = {"Authorization": "Bearer " + api_key, "Accept": "application/json"}
    body = request.get_data() if request.method == "POST" else None
    if body is not None:
        headers["Content-Type"] = "application/json"
    upstream = urllib.request.Request(
        "https://generativelanguage.googleapis.com/v1beta/openai/" + path,
        data=body, headers=headers, method=request.method
    )
    try:
        with urllib.request.urlopen(upstream, timeout=90) as result:
            return Response(result.read(), status=result.status,
                            content_type=result.headers.get("Content-Type", "application/json"))
    except urllib.error.HTTPError as error:
        return Response(error.read(), status=error.code,
                        content_type=error.headers.get("Content-Type", "application/json"))
    except Exception:
        app.logger.exception("Gemini upstream request failed")
        return jsonify({"error": {"message": "Gemini upstream request failed"}}), 502


@app.get("/")
def index():
    return jsonify({"service": "INRPF Server", "status": "online", "health": "/health", "admin": "/admin"})


@app.post("/api/admin/auth")
def admin_auth():
    # The dashboard password may use either supported admin credential.
    configured_credentials = [value for value in (ADMIN_PASSWORD, LICENSE_ADMIN_TOKEN) if value]
    if not configured_credentials:
        return jsonify({"ok": False, "error": "admin_password_not_configured"}), 503
    payload = request.get_json(silent=True) or {}
    supplied = payload.get("password", "")
    if not isinstance(supplied, str) or not any(
        hmac.compare_digest(supplied, expected) for expected in configured_credentials
    ):
        return jsonify({"ok": False, "error": "unauthorized"}), 401
    return jsonify({"ok": True})


@app.get("/admin")
def admin_page():
    return send_from_directory(Path(__file__).parent / "admin", "index.html")


@app.get("/health")
def health():
    connection = None
    try:
        connection = db()
        connection.execute("SELECT 1").fetchone()
        return jsonify({
            "ok": True,
            "service": "inrpf-server",
            "database_ready": True,
            "database_backend": "postgresql" if os.environ.get("DATABASE_URL") else "sqlite-local",
            "licensing_configured": licensing_ready()
        })
    except Exception:
        app.logger.exception("Health check failed because the database is unavailable")
        return jsonify({
            "ok": False,
            "service": "inrpf-server",
            "database_ready": False,
            "error": "database_unavailable"
        }), 503
    finally:
        if connection is not None:
            connection.close()


@app.post("/api/admin/codes/generate")
def generate_codes():
    if not licensing_ready():
        return jsonify({"ok": False, "error": "licensing_not_configured"}), 503
    if not admin_authorized():
        return jsonify({"ok": False, "error": "unauthorized"}), 401
    payload = request.get_json(silent=True) or {}
    count = payload.get("count", 60)
    features = payload.get("features", ["github_tools"])
    if "duration_hours" in payload:
        duration_hours = payload.get("duration_hours")
        if not isinstance(duration_hours, int) or isinstance(duration_hours, bool) or duration_hours not in {3, 12, 24}:
            return jsonify({"ok": False, "error": "duration_hours_must_be_3_12_or_24"}), 400
        duration_days = None
        duration_seconds = duration_hours * 3600
    else:
        # Backward compatibility: legacy duration_days also starts on first activation.
        duration_days = payload.get("duration_days", 30)
        if duration_days is not None and (
            not isinstance(duration_days, int) or isinstance(duration_days, bool)
            or duration_days < 1 or duration_days > 3650
        ):
            return jsonify({"ok": False, "error": "duration_days_must_be_1_to_3650_or_null"}), 400
        duration_hours = None
        duration_seconds = None if duration_days is None else duration_days * 86400
    expires_at = None
    if not isinstance(count, int) or isinstance(count, bool) or count < 1 or count > 100:
        return jsonify({"ok": False, "error": "count_must_be_1_to_100"}), 400
    if not isinstance(features, list) or not features or any(
        not isinstance(feature, str) or feature not in ALLOWED_FEATURES for feature in features
    ):
        return jsonify({"ok": False, "error": "invalid_features"}), 400
    features = sorted(set(features))
    generated = []
    connection = db()
    try:
        connection.execute("BEGIN IMMEDIATE")
        for _ in range(count):
            for attempt in range(5):
                code = make_code()
                digest = code_digest(code)
                try:
                    connection.execute(
                        "INSERT INTO premium_codes(code_hash,code_hint,status,features_json,created_at,expires_at,duration_seconds) VALUES(?,?,?,?,?,?,?)",
                        (digest, code[-4:], "unused", json.dumps(features), utc_now(), expires_at, duration_seconds)
                    )
                    generated.append(code)
                    break
                except sqlite3.IntegrityError:
                    if attempt == 4:
                        raise
        connection.execute("COMMIT")
    except Exception:
        connection.execute("ROLLBACK")
        app.logger.exception("Premium code generation failed")
        return jsonify({"ok": False, "error": "generation_failed"}), 500
    finally:
        connection.close()
    # Plaintext codes are returned once and are never stored in the database or logs.
    return jsonify({"ok": True, "count": len(generated), "features": features,
                    "duration_hours": duration_hours, "duration_days": duration_days,
                    "duration_seconds": duration_seconds, "expires_at": expires_at, "codes": generated}), 201


@app.get("/api/admin/codes")
def list_codes():
    if not licensing_ready():
        return jsonify({"ok": False, "error": "licensing_not_configured"}), 503
    if not admin_authorized():
        return jsonify({"ok": False, "error": "unauthorized"}), 401
    connection = db()
    try:
        rows = connection.execute(
            "SELECT code_hash,code_hint,status,features_json,created_at,redeemed_at,expires_at,duration_seconds FROM premium_codes ORDER BY created_at DESC LIMIT 500"
        ).fetchall()
        return jsonify({"ok": True, "codes": [
            {"id": row["code_hash"], "last4": row["code_hint"], "status": row["status"],
             "features": json.loads(row["features_json"]), "created_at": row["created_at"],
             "redeemed_at": row["redeemed_at"], "expires_at": row["expires_at"],
             "duration_seconds": row["duration_seconds"]} for row in rows
        ]})
    finally:
        connection.close()


@app.post("/api/admin/codes/revoke")
def revoke_code():
    if not licensing_ready():
        return jsonify({"ok": False, "error": "licensing_not_configured"}), 503
    if not admin_authorized():
        return jsonify({"ok": False, "error": "unauthorized"}), 401
    payload = request.get_json(silent=True) or {}
    last4 = payload.get("last4", "")
    if not isinstance(last4, str) or not re.fullmatch(r"[A-Z0-9]{4}", last4.upper()):
        return jsonify({"ok": False, "error": "invalid_last4"}), 400
    connection = db()
    try:
        cursor = connection.execute(
            "UPDATE premium_codes SET status='revoked' WHERE code_hint=? AND status='unused'",
            (last4.upper(),)
        )
        return jsonify({"ok": True, "updated": cursor.rowcount})
    finally:
        connection.close()


@app.delete("/api/admin/codes/bulk")
def delete_codes_bulk():
    if not licensing_ready():
        return jsonify({"ok": False, "error": "licensing_not_configured"}), 503
    if not admin_authorized():
        return jsonify({"ok": False, "error": "unauthorized"}), 401
    payload = request.get_json(silent=True) or {}
    code_hashes = payload.get("ids")
    if not isinstance(code_hashes, list) or not code_hashes or len(code_hashes) > 500:
        return jsonify({"ok": False, "error": "ids_must_be_a_list_of_1_to_500_hashes"}), 400
    if any(not isinstance(item, str) or not re.fullmatch(r"[a-fA-F0-9]{64}", item) for item in code_hashes):
        return jsonify({"ok": False, "error": "invalid_code_id"}), 400
    code_hashes = list(dict.fromkeys(item.lower() for item in code_hashes))
    placeholders = ",".join("?" for _ in code_hashes)
    connection = db()
    try:
        connection.execute("BEGIN IMMEDIATE")
        cursor = connection.execute(
            "DELETE FROM premium_codes WHERE code_hash IN (" + placeholders + ")",
            tuple(code_hashes)
        )
        deleted = cursor.rowcount
        connection.execute("COMMIT")
        return jsonify({"ok": True, "deleted": deleted})
    except Exception:
        connection.execute("ROLLBACK")
        app.logger.exception("Bulk premium-code deletion failed")
        return jsonify({"ok": False, "error": "bulk_delete_failed"}), 500
    finally:
        connection.close()


@app.post("/api/license/validate")
def validate_activation():
    if not LICENSE_PEPPER:
        return jsonify({"ok": False, "error": "licensing_not_configured"}), 503
    supplied = request.headers.get("Authorization", "")
    if not supplied.startswith("Bearer "):
        return jsonify({"ok": False, "error": "unauthorized"}), 401
    activation_id = supplied[7:].strip()
    if not activation_id or len(activation_id) > 128:
        return jsonify({"ok": False, "error": "unauthorized"}), 401
    activation_hash = hmac.new(
        LICENSE_PEPPER.encode(), ("activation:" + activation_id).encode(), hashlib.sha256
    ).hexdigest()
    connection = db()
    try:
        row = connection.execute(
            "SELECT features_json,expires_at FROM premium_codes WHERE activation_id=? AND status='redeemed'",
            (activation_hash,)
        ).fetchone()
        if row is None:
            return jsonify({"ok": False, "active": False, "error": "activation_not_found"}), 401
        if row["expires_at"] and row["expires_at"] <= utc_now():
            return jsonify({"ok": False, "active": False, "error": "license_expired"}), 403
        return jsonify({"ok": True, "active": True, "features": json.loads(row["features_json"]),
                        "expires_at": row["expires_at"]})
    finally:
        connection.close()


@app.post("/api/license/redeem")
def redeem_code():
    if not LICENSE_PEPPER:
        return jsonify({"ok": False, "error": "licensing_not_configured"}), 503
    payload = request.get_json(silent=True) or {}
    code = payload.get("code", "")
    if not isinstance(code, str) or not re.fullmatch(r"(?i)INRPF(?:-[A-Z0-9]{4}){4}", code.strip()):
        return jsonify({"ok": False, "error": "invalid_code"}), 400
    try:
        digest = code_digest(code)
    except RuntimeError:
        return jsonify({"ok": False, "error": "licensing_not_configured"}), 503
    activation_id = secrets.token_urlsafe(24)
    connection = db()
    try:
        connection.execute("BEGIN IMMEDIATE")
        row = connection.execute(
            "SELECT status,features_json,expires_at,duration_seconds FROM premium_codes WHERE code_hash=?", (digest,)
        ).fetchone()
        if row is None:
            connection.execute("ROLLBACK")
            return jsonify({"ok": False, "error": "code_not_found"}), 404
        if row["status"] != "unused":
            connection.execute("ROLLBACK")
            return jsonify({"ok": False, "error": "code_already_used"}), 409
        now = datetime.fromisoformat(utc_now())
        # New duration-based codes start their validity period only at first redemption.
        # Older records with an absolute expires_at and no duration_seconds retain legacy expiry.
        if row["duration_seconds"] is not None:
            expires_at = (now + timedelta(seconds=row["duration_seconds"])).isoformat()
        else:
            expires_at = row["expires_at"]
        if expires_at and expires_at <= utc_now():
            connection.execute("ROLLBACK")
            return jsonify({"ok": False, "error": "license_expired"}), 403
        activation_hash = hmac.new(
            LICENSE_PEPPER.encode(), ("activation:" + activation_id).encode(), hashlib.sha256
        ).hexdigest()
        connection.execute(
            "UPDATE premium_codes SET status='redeemed',redeemed_at=?,activation_id=?,expires_at=? WHERE code_hash=? AND status='unused'",
            (utc_now(), activation_hash, expires_at, digest)
        )
        features = json.loads(row["features_json"])
        connection.execute("COMMIT")
        return jsonify({"ok": True, "activation_id": activation_id, "features": features,
                        "expires_at": expires_at, "status": "active"}), 200
    except Exception:
        connection.execute("ROLLBACK")
        app.logger.exception("License redemption failed")
        return jsonify({"ok": False, "error": "redemption_failed"}), 500
    finally:
        connection.close()



@app.post("/api/admin/gemini/create")
def admin_create_gemini_key():
    if not admin_authorized():
        return jsonify({"ok": False, "error": "unauthorized"}), 401
    try:
        return jsonify({"ok": True, **create_google_gemini_key()}), 201
    except Exception as error:
        app.logger.exception("Gemini API key creation failed")
        return jsonify({"ok": False, "error": "gemini_key_creation_failed", "message": str(error)[:240]}), 503


@app.get("/api/admin/gemini/status")
def admin_gemini_status():
    if not admin_authorized():
        return jsonify({"ok": False, "error": "unauthorized"}), 401
    connection = db()
    try:
        row = connection.execute("SELECT resource_name,key_hint,created_at FROM gemini_keys WHERE id=1").fetchone()
        return jsonify({"ok": True, "configured": row is not None,
                        "key_hint": row["key_hint"] if row else None,
                        "created_at": row["created_at"] if row else None,
                        "google_cloud_ready": bool(GEMINI_PROJECT_ID and GEMINI_SERVICE_ACCOUNT_JSON and GEMINI_ENCRYPTION_KEY)})
    finally:
        connection.close()



@app.delete("/api/admin/gemini")
def admin_delete_gemini_key():
    if not admin_authorized():
        return jsonify({"ok": False, "error": "unauthorized"}), 401
    connection = db()
    try:
        row = connection.execute("SELECT resource_name FROM gemini_keys WHERE id=1").fetchone()
        if row is None:
            return jsonify({"ok": True, "deleted": False})
        from google.auth.transport.requests import AuthorizedSession
        session = AuthorizedSession(gemini_credentials())
        response = session.delete("https://apikeys.googleapis.com/v2/" + row["resource_name"])
        response.raise_for_status()
        connection.execute("DELETE FROM gemini_keys WHERE id=1")
        return jsonify({"ok": True, "deleted": True})
    except Exception:
        app.logger.exception("Gemini API key deletion failed")
        return jsonify({"ok": False, "error": "gemini_key_delete_failed"}), 503
    finally:
        connection.close()


@app.get("/api/gemini/v1/models")
def gemini_models():
    return proxy_gemini("models")


@app.post("/api/gemini/v1/chat/completions")
def gemini_chat_completions():
    return proxy_gemini("chat/completions")


@app.post("/api/reports")
def receive_report():
    if not REPORT_TOKEN:
        return jsonify({"ok": False, "error": "report_ingestion_not_configured",
                        "message": "Set INRPF_REPORT_TOKEN in the hosting environment before sending reports."}), 503
    if not authorized():
        return jsonify({"ok": False, "error": "unauthorized"}), 401
    payload = request.get_json(silent=True)
    if not isinstance(payload, dict):
        return jsonify({"ok": False, "error": "expected_json_object"}), 400
    report_id = payload.get("report_id")
    if report_id is not None and (
        not isinstance(report_id, str) or not re.fullmatch(r"[A-Za-z0-9_-]{1,80}", report_id)
    ):
        return jsonify({"ok": False, "error": "invalid_report_id"}), 400
    record = {"received_at": utc_now(), "report": payload}
    try:
        REPORTS_DIR.mkdir(parents=True, exist_ok=True)
        with (REPORTS_DIR / "reports.jsonl").open("a", encoding="utf-8") as stream:
            stream.write(json.dumps(record, ensure_ascii=False) + "\n")
    except OSError:
        app.logger.exception("Could not store report")
        return jsonify({"ok": False, "error": "storage_error"}), 500
    return jsonify({"ok": True, "report_id": report_id}), 201


@app.get("/api/reports")
def list_reports():
    if not REPORT_TOKEN:
        return jsonify({"ok": False, "error": "report_ingestion_not_configured"}), 503
    if not authorized():
        return jsonify({"ok": False, "error": "unauthorized"}), 401
    path = REPORTS_DIR / "reports.jsonl"
    if not path.exists():
        return jsonify({"ok": True, "count": 0, "reports": []})
    reports = []
    try:
        with path.open("r", encoding="utf-8") as stream:
            for line in stream:
                try:
                    record = json.loads(line)
                    payload = record.get("report", {})
                    reports.append({
                        "received_at": record.get("received_at", ""),
                        "report_id": payload.get("report_id", ""),
                        "app_version": payload.get("app_version", ""),
                        "build_number": payload.get("build_number", ""),
                        "passed_count": payload.get("passed_count", 0),
                        "failed_count": payload.get("failed_count", 0),
                        "all_passed": payload.get("all_passed", False),
                    })
                except (json.JSONDecodeError, AttributeError):
                    continue
    except OSError:
        app.logger.exception("Could not read reports")
        return jsonify({"ok": False, "error": "storage_error"}), 500
    reports = reports[-100:][::-1]
    return jsonify({"ok": True, "count": len(reports), "reports": reports})


@app.errorhandler(413)
def too_large(_error):
    return jsonify({"ok": False, "error": "request_too_large", "max_bytes": 1048576}), 413


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=int(os.environ.get("PORT", "10000")))

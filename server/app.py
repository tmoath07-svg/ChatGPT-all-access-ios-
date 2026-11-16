import hashlib
import hmac
import json
import os
import re
import secrets
import sqlite3
import string
from datetime import datetime, timezone
from pathlib import Path

from flask import Flask, jsonify, request, send_from_directory

app = Flask(__name__)
app.config["MAX_CONTENT_LENGTH"] = 1 * 1024 * 1024

REPORTS_DIR = Path(os.environ.get("REPORTS_DIR", "/tmp/inrpf-reports"))
REPORT_TOKEN = os.environ.get("INRPF_REPORT_TOKEN", "")
LICENSE_DB = os.environ.get("INRPF_LICENSE_DB", "/var/data/inrpf-licenses.sqlite3")
LICENSE_PEPPER = os.environ.get("INRPF_LICENSE_PEPPER", "")
LICENSE_ADMIN_TOKEN = os.environ.get("INRPF_LICENSE_ADMIN_TOKEN", "")
CODE_ALPHABET = "23456789ABCDEFGHJKLMNPQRSTUVWXYZ"
ALLOWED_FEATURES = {"github_tools", "ai_repair_pro", "advanced_ftp", "advanced_ai_providers"}


def utc_now():
    return datetime.now(timezone.utc).isoformat()


def db():
    path = Path(LICENSE_DB)
    path.parent.mkdir(parents=True, exist_ok=True)
    connection = sqlite3.connect(str(path), timeout=15, isolation_level=None)
    connection.row_factory = sqlite3.Row
    connection.execute("PRAGMA journal_mode=WAL")
    connection.execute("PRAGMA busy_timeout=15000")
    connection.execute("""
        CREATE TABLE IF NOT EXISTS premium_codes (
            code_hash TEXT PRIMARY KEY,
            code_hint TEXT NOT NULL,
            status TEXT NOT NULL CHECK(status IN ('unused','redeemed','revoked')),
            features_json TEXT NOT NULL,
            created_at TEXT NOT NULL,
            redeemed_at TEXT,
            activation_id TEXT,
            expires_at TEXT
        )
    """)
    columns = {row[1] for row in connection.execute("PRAGMA table_info(premium_codes)").fetchall()}
    if "expires_at" not in columns:
        connection.execute("ALTER TABLE premium_codes ADD COLUMN expires_at TEXT")
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
    return bool(LICENSE_ADMIN_TOKEN) and hmac.compare_digest(
        supplied, f"Bearer {LICENSE_ADMIN_TOKEN}"
    )


def licensing_ready():
    return bool(LICENSE_PEPPER and LICENSE_ADMIN_TOKEN)


def make_code():
    groups = ["".join(secrets.choice(CODE_ALPHABET) for _ in range(4)) for _ in range(4)]
    return "INRPF-" + "-".join(groups)


@app.get("/")
def index():
    return jsonify({"service": "INRPF Server", "status": "online", "health": "/health", "admin": "/admin"})


@app.get("/admin")
def admin_page():
    return send_from_directory(Path(__file__).parent / "admin", "index.html")


@app.get("/health")
def health():
    return jsonify({"ok": True, "service": "inrpf-server", "licensing_configured": licensing_ready()})


@app.post("/api/admin/codes/generate")
def generate_codes():
    if not licensing_ready():
        return jsonify({"ok": False, "error": "licensing_not_configured"}), 503
    if not admin_authorized():
        return jsonify({"ok": False, "error": "unauthorized"}), 401
    payload = request.get_json(silent=True) or {}
    count = payload.get("count", 60)
    features = payload.get("features", ["github_tools"])
    duration_days = payload.get("duration_days", 30)
    if duration_days is not None and (
        not isinstance(duration_days, int) or isinstance(duration_days, bool)
        or duration_days < 1 or duration_days > 3650
    ):
        return jsonify({"ok": False, "error": "duration_days_must_be_1_to_3650_or_null"}), 400
    expires_at = None if duration_days is None else (
        datetime.now(timezone.utc) + __import__("datetime").timedelta(days=duration_days)
    ).isoformat()
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
                        "INSERT INTO premium_codes(code_hash,code_hint,status,features_json,created_at,expires_at) VALUES(?,?,?,?,?,?)",
                        (digest, code[-4:], "unused", json.dumps(features), utc_now(), expires_at)
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
                    "duration_days": duration_days, "expires_at": expires_at, "codes": generated}), 201


@app.get("/api/admin/codes")
def list_codes():
    if not licensing_ready():
        return jsonify({"ok": False, "error": "licensing_not_configured"}), 503
    if not admin_authorized():
        return jsonify({"ok": False, "error": "unauthorized"}), 401
    connection = db()
    try:
        rows = connection.execute(
            "SELECT code_hint,status,features_json,created_at,redeemed_at,expires_at FROM premium_codes ORDER BY created_at DESC LIMIT 500"
        ).fetchall()
        return jsonify({"ok": True, "codes": [
            {"last4": row["code_hint"], "status": row["status"],
             "features": json.loads(row["features_json"]), "created_at": row["created_at"],
             "redeemed_at": row["redeemed_at"], "expires_at": row["expires_at"]} for row in rows
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
            "SELECT status,features_json,expires_at FROM premium_codes WHERE code_hash=?", (digest,)
        ).fetchone()
        if row is None:
            connection.execute("ROLLBACK")
            return jsonify({"ok": False, "error": "code_not_found"}), 404
        if row["status"] != "unused":
            connection.execute("ROLLBACK")
            return jsonify({"ok": False, "error": "code_already_used"}), 409
        if row["expires_at"] and row["expires_at"] <= utc_now():
            connection.execute("ROLLBACK")
            return jsonify({"ok": False, "error": "license_expired"}), 403
        activation_hash = hmac.new(
            LICENSE_PEPPER.encode(), ("activation:" + activation_id).encode(), hashlib.sha256
        ).hexdigest()
        connection.execute(
            "UPDATE premium_codes SET status='redeemed',redeemed_at=?,activation_id=? WHERE code_hash=? AND status='unused'",
            (utc_now(), activation_hash, digest)
        )
        features = json.loads(row["features_json"])
        connection.execute("COMMIT")
        return jsonify({"ok": True, "activation_id": activation_id, "features": features,
                        "expires_at": row["expires_at"], "status": "active"}), 200
    except Exception:
        connection.execute("ROLLBACK")
        app.logger.exception("License redemption failed")
        return jsonify({"ok": False, "error": "redemption_failed"}), 500
    finally:
        connection.close()


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

import hmac
import json
import os
import re
from datetime import datetime, timezone
from pathlib import Path

from flask import Flask, jsonify, request

app = Flask(__name__)
app.config["MAX_CONTENT_LENGTH"] = 1 * 1024 * 1024

REPORTS_DIR = Path(os.environ.get("REPORTS_DIR", "/tmp/inrpf-reports"))
REPORT_TOKEN = os.environ.get("INRPF_REPORT_TOKEN", "")


def authorized():
    supplied = request.headers.get("Authorization", "")
    return bool(REPORT_TOKEN) and hmac.compare_digest(supplied, f"Bearer {REPORT_TOKEN}")


@app.get("/")
def index():
    return jsonify({"service": "INRPF Server", "status": "online", "health": "/health"})


@app.get("/health")
def health():
    return jsonify({"ok": True, "service": "inrpf-server"})


@app.post("/api/reports")
def receive_report():
    if not REPORT_TOKEN:
        return jsonify({
            "ok": False,
            "error": "report_ingestion_not_configured",
            "message": "Set INRPF_REPORT_TOKEN in the hosting environment before sending reports."
        }), 503
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

    record = {"received_at": datetime.now(timezone.utc).isoformat(), "report": payload}
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
    return jsonify({"ok": False, "error": "report_too_large", "max_bytes": 1048576}), 413


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=int(os.environ.get("PORT", "10000")))

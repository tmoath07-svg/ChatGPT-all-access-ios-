# INRPF Server

Small Python/Flask service for INRPF health checks and authenticated test-report intake.

## Local run

```bash
pip install -r requirements.txt
INRPF_REPORT_TOKEN="replace-with-a-long-random-secret" python app.py
```

## Render settings

- Runtime: Python 3
- Root Directory: `server`
- Build Command: `pip install -r requirements.txt`
- Start Command: `gunicorn app:app --bind 0.0.0.0:$PORT`
- Health Check Path: `/health`

Add an environment variable named `INRPF_REPORT_TOKEN` with a long random secret before enabling report uploads. Keep it private and do not place it in the iPad app source. The app must send it in the `Authorization: Bearer ...` header.

## Endpoints

- `GET /` service status
- `GET /health` health check
- `POST /api/reports` authenticated JSON report intake (maximum 1 MiB)

Reports are currently written to `/tmp/inrpf-reports/reports.jsonl`. This is temporary storage and may be cleared when the service restarts or redeploys. Configure durable storage before relying on long-term report retention.

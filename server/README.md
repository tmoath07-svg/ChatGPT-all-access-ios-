# INRPF Server

Flask API for INRPF health checks, authenticated test reports, and one-time premium license codes.

## Render deployment

- Runtime: Python 3
- Root Directory: `server`
- Build Command: `pip install -r requirements.txt`
- Start Command: `gunicorn app:app --bind 0.0.0.0:$PORT`
- Health Check Path: `/health`
- Add a **persistent disk** mounted at `/var/data` before using licenses.

### Required environment variables

Create strong random values in Render (do not commit them):

- `INRPF_LICENSE_ADMIN_TOKEN`: long private admin password used by the web dashboard.
- `INRPF_LICENSE_PEPPER`: independent random secret used to HMAC code values.
- `INRPF_LICENSE_DB`: `/var/data/inrpf-licenses.sqlite3` (must be on the persistent disk).
- `INRPF_REPORT_TOKEN`: existing report-ingestion token, if reports are enabled.

Open `https://YOUR-SERVICE.onrender.com/admin` to manage codes.

## Premium license API

- `POST /api/admin/codes/generate` — admin-only; JSON: `{"count":60,"features":["github_tools"]}`. Returns plaintext codes once.
- `GET /api/admin/codes` — admin-only inventory; only masked suffixes are returned.
- `POST /api/admin/codes/revoke` — admin-only; JSON: `{"last4":"ABCD"}`; revokes unused codes sharing that suffix.
- `POST /api/license/redeem` — public one-time redemption; JSON: `{"code":"INRPF-XXXX-XXXX-XXXX-XXXX"}`.

Codes are generated with Python's cryptographic random source. Only an HMAC-SHA256 digest is stored. Redemption uses a SQLite `BEGIN IMMEDIATE` transaction and a conditional state transition, so concurrent attempts cannot successfully redeem the same code twice.

**iOS integration:** The GitHub workspace now displays a premium gate, redeems a one-time code, stores its activation credential in Keychain, and revalidates the activation with this API on launch. The feature is not production-ready until the current iOS workflow passes and this service is deployed with the required secrets and persistent disk. A modified client can still be patched; server-side validation is the authority. For production, keep the database on a persistent disk and use HTTPS.

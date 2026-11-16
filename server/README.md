# INRPF Server

Flask API for INRPF health checks, authenticated test reports, and one-time premium license codes.

## Render deployment

- Runtime: Python 3
- Root Directory: `server`
- Build Command: `pip install -r requirements.txt`
- Start Command: `gunicorn app:app --bind 0.0.0.0:$PORT`
- Health Check Path: `/health`
- Set `DATABASE_URL` to the Render PostgreSQL **Internal Database URL**. The service and database must be in the same Render region.

### Required environment variables

Create strong random values in Render (do not commit them):

- `INRPF_LICENSE_ADMIN_TOKEN`: long private admin password used by the web dashboard.
- `INRPF_LICENSE_PEPPER`: independent random secret used to HMAC code values.
- `INRPF_LICENSE_DB`: optional legacy SQLite source path. If that file exists when the PostgreSQL backend initializes, the server imports its license and Gemini-key rows once into PostgreSQL without deleting or modifying the source file. Leave this at `/var/data/inrpf-licenses.sqlite3` only if an older SQLite file is actually present.
- `INRPF_REPORT_TOKEN`: existing report-ingestion token, if reports are enabled.
- `GOOGLE_CLOUD_PROJECT_ID`: Google Cloud project ID used to create the Gemini API key.
- `GOOGLE_SERVICE_ACCOUNT_JSON`: service-account JSON content with `roles/serviceusage.apiKeysAdmin` and `roles/serviceusage.serviceUsageViewer` on the project. Enable both `apikeys.googleapis.com` and `generativelanguage.googleapis.com` before using the dashboard.
- `INRPF_GEMINI_ENCRYPTION_KEY`: Fernet key used to encrypt the Google API key at rest; generate once with `python -c 'from cryptography.fernet import Fernet; print(Fernet.generate_key().decode())'` and keep it stable.

Open `https://YOUR-SERVICE.onrender.com/admin` to manage codes.

## Premium license API

- `POST /api/admin/codes/generate` — admin-only; JSON: `{"count":60,"features":["github_tools"],"duration_days":30}`. Set `duration_days` to 1–3650, or `null` for codes that never expire. Returns plaintext codes once.
- `GET /api/admin/codes` — admin-only inventory; only masked suffixes are returned.
- `POST /api/admin/codes/revoke` — admin-only; JSON: `{"last4":"ABCD"}`; revokes unused codes sharing that suffix.
- `POST /api/admin/gemini/create` — admin-only; creates a Google Cloud API key and stores it encrypted.
- `GET /api/admin/gemini/status` — admin-only; returns only masked key metadata.
- `GET /api/gemini/v1/models` and `POST /api/gemini/v1/chat/completions` — proxy requests after validating a `gemini_tool` activation; the Google key is never sent to the app.
- `POST /api/license/redeem` — public one-time redemption; JSON: `{"code":"INRPF-XXXX-XXXX-XXXX-XXXX"}`.

The Arabic admin dashboard at `/admin` lets an administrator provision the managed Gemini API key from Google Cloud, choose a batch size, license feature, and expiry (7/30/90/180/365/730 days or no expiry), then generate new batches whenever needed. Each batch is displayed once with copy and TXT export. Expiry is enforced both when redeeming a code and when validating its activation.

Codes are generated with Python's cryptographic random source. Only an HMAC-SHA256 digest is stored. Production uses Render PostgreSQL transactions and a conditional single-use state transition, so concurrent attempts cannot successfully redeem the same code twice. SQLite is retained only for local development and isolated unit tests. When `DATABASE_URL` is configured, PostgreSQL is the active store.

**iOS integration:** The iOS client contract remains unchanged: it redeems a one-time code, stores its activation credential in Keychain, and revalidates the activation with this API on launch. This server-only change does not modify iOS files or workflows. A modified client can still be patched; server-side validation is the authority. Use the Render PostgreSQL internal connection and HTTPS.

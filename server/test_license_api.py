import tempfile
import unittest
from pathlib import Path

import app as server


class PremiumLicenseTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        server.LICENSE_DB = str(Path(self.temp.name) / "licenses.sqlite3")
        server.LICENSE_PEPPER = "test-pepper-that-is-not-for-production"
        server.LICENSE_ADMIN_TOKEN = "test-admin-token"
        self.client = server.app.test_client()
        self.headers = {"Authorization": "Bearer test-admin-token"}

    def tearDown(self):
        self.temp.cleanup()

    def test_generate_sixty_unique_codes_and_store_only_hashes(self):
        response = self.client.post(
            "/api/admin/codes/generate", headers=self.headers,
            json={"count": 60, "features": ["github_tools"]}
        )
        self.assertEqual(response.status_code, 201)
        codes = response.get_json()["codes"]
        self.assertEqual(len(codes), 60)
        self.assertEqual(len(set(codes)), 60)
        raw_db = Path(server.LICENSE_DB).read_bytes()
        for code in codes:
            self.assertNotIn(code.encode(), raw_db)
        inventory = self.client.get("/api/admin/codes", headers=self.headers)
        self.assertEqual(len(inventory.get_json()["codes"]), 60)
        self.assertNotIn("INRPF-", inventory.get_data(as_text=True))

    def test_code_is_single_use_and_activation_is_validated(self):
        code = self.client.post(
            "/api/admin/codes/generate", headers=self.headers,
            json={"count": 1, "features": ["github_tools"]}
        ).get_json()["codes"][0]
        first = self.client.post("/api/license/redeem", json={"code": code})
        self.assertEqual(first.status_code, 200)
        activation = first.get_json()["activation_id"]
        self.assertEqual(first.get_json()["features"], ["github_tools"])
        second = self.client.post("/api/license/redeem", json={"code": code})
        self.assertEqual(second.status_code, 409)
        checked = self.client.post(
            "/api/license/validate", headers={"Authorization": "Bearer " + activation}
        )
        self.assertEqual(checked.status_code, 200)
        self.assertTrue(checked.get_json()["active"])

    def test_admin_authentication_and_feature_allowlist(self):
        denied = self.client.post(
            "/api/admin/codes/generate", headers={"Authorization": "Bearer wrong"},
            json={"count": 60, "features": ["github_tools"]}
        )
        self.assertEqual(denied.status_code, 401)
        invalid = self.client.post(
            "/api/admin/codes/generate", headers=self.headers,
            json={"count": 1, "features": ["unrestricted_admin"]}
        )
        self.assertEqual(invalid.status_code, 400)


if __name__ == "__main__":
    unittest.main()

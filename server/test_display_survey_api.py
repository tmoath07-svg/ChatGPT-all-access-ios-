import tempfile
import unittest
from pathlib import Path

import app as server


class DisplaySurveyTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        server.LICENSE_DB = str(Path(self.temp.name) / "survey.sqlite3")
        server.LICENSE_PEPPER = "survey-test-pepper"
        server.LICENSE_ADMIN_TOKEN = "survey-admin-token"
        self.client = server.app.test_client()
        self.admin = {"Authorization": "Bearer survey-admin-token"}

    def tearDown(self):
        self.temp.cleanup()

    def payload(self):
        return {
            "issue": "square",
            "frequency": "always",
            "interface_mode": "ios",
            "device_family": "iPad",
            "device_model": "iPad",
            "os_version": "27.3",
            "screen_size": "1194x834",
            "screen_scale": "2.0",
            "orientation": "landscape",
            "horizontal_size_class": "compact",
            "vertical_size_class": "regular",
            "app_version": "6.10",
            "build_number": "80",
            "notes": "Appears in a small centered frame"
        }

    def test_accept_and_list_display_survey(self):
        response = self.client.post("/api/display-surveys", json=self.payload())
        self.assertEqual(response.status_code, 201)
        denied = self.client.get("/api/admin/display-surveys")
        self.assertEqual(denied.status_code, 401)
        listed = self.client.get("/api/admin/display-surveys", headers=self.admin)
        self.assertEqual(listed.status_code, 200)
        body = listed.get_json()
        self.assertEqual(body["count"], 1)
        self.assertEqual(body["surveys"][0]["issue"], "square")
        self.assertEqual(body["surveys"][0]["device_family"], "iPad")
        self.assertEqual(body["surveys"][0]["notes"], "Appears in a small centered frame")

    def test_reject_invalid_choices_and_oversized_notes(self):
        invalid = self.payload()
        invalid["issue"] = "send-me-secrets"
        self.assertEqual(self.client.post("/api/display-surveys", json=invalid).status_code, 400)
        too_long = self.payload()
        too_long["notes"] = "x" * 301
        self.assertEqual(self.client.post("/api/display-surveys", json=too_long).status_code, 400)

    def test_survey_is_stored_in_license_database_not_ephemeral_report_folder(self):
        self.client.post("/api/display-surveys", json=self.payload())
        self.assertTrue(Path(server.LICENSE_DB).exists())
        listed = self.client.get("/api/admin/display-surveys", headers=self.admin).get_json()
        self.assertEqual(listed["count"], 1)


if __name__ == "__main__":
    unittest.main()

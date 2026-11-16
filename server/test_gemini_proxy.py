import io
import json
import unittest
from unittest.mock import patch

import app as server


class FakeResponse:
    def __init__(self, body):
        self.body = body
        self.status = 200
        self.headers = {"Content-Type": "application/json"}

    def __enter__(self):
        return self

    def __exit__(self, *args):
        return False

    def read(self):
        return self.body


class GeminiProxyTests(unittest.TestCase):
    def setUp(self):
        self.client = server.app.test_client()
        self.headers = {"Authorization": "Bearer test-activation"}

    @patch.object(server, "load_gemini_key", return_value="test-key")
    @patch.object(server, "activation_features", return_value=["gemini_tool"])
    @patch("app.urllib.request.urlopen")
    def test_success_is_forwarded(self, urlopen, _features, _key):
        body = b'{"choices":[{"message":{"content":"hello"}}]}'
        urlopen.return_value = FakeResponse(body)
        response = self.client.post("/api/gemini/v1/chat/completions", headers=self.headers,
                                    json={"model": "gemini-2.5-flash", "messages": []})
        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.data, body)
        upstream = urlopen.call_args.args[0]
        self.assertTrue(upstream.full_url.endswith("/v1beta/openai/chat/completions"))
        self.assertEqual(upstream.get_header("Authorization"), "Bearer test-key")

    @patch.object(server, "load_gemini_key", return_value="test-key")
    @patch.object(server, "activation_features", return_value=["gemini_tool"])
    @patch("app.urllib.request.urlopen")
    def test_429_error_body_is_preserved(self, urlopen, _features, _key):
        body = json.dumps({"error": {"message": "quota exceeded"}}).encode()
        urlopen.side_effect = server.urllib.error.HTTPError(
            "https://google.invalid", 429, "Too Many Requests",
            {"Content-Type": "application/json"}, io.BytesIO(body))
        response = self.client.post("/api/gemini/v1/chat/completions",
                                    headers=self.headers, json={})
        self.assertEqual(response.status_code, 429)
        self.assertEqual(response.get_json()["error"]["message"], "quota exceeded")

    @patch.object(server, "load_gemini_key", return_value="test-key")
    @patch.object(server, "activation_features", return_value=["gemini_tool"])
    @patch("app.urllib.request.urlopen")
    def test_400_error_body_is_preserved(self, urlopen, _features, _key):
        body = json.dumps({"error": {"message": "invalid model"}}).encode()
        urlopen.side_effect = server.urllib.error.HTTPError(
            "https://google.invalid", 400, "Bad Request",
            {"Content-Type": "application/json"}, io.BytesIO(body))
        response = self.client.post("/api/gemini/v1/chat/completions",
                                    headers=self.headers, json={})
        self.assertEqual(response.status_code, 400)
        self.assertEqual(response.get_json()["error"]["message"], "invalid model")

    @patch("app.urllib.request.urlopen")
    @patch.object(server, "activation_features", return_value=None)
    def test_unlicensed_request_never_reaches_google(self, _features, urlopen):
        response = self.client.post("/api/gemini/v1/chat/completions", json={})
        self.assertEqual(response.status_code, 403)
        urlopen.assert_not_called()


if __name__ == "__main__":
    unittest.main()

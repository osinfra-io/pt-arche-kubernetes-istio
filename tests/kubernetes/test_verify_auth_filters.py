"""Exercise effective-chain detection without a Kubernetes cluster."""

import importlib.util
from pathlib import Path
import unittest


spec = importlib.util.spec_from_file_location(
    "verify_auth_filters", Path(__file__).with_name("verify-auth-filters.py"),
)
verifier = importlib.util.module_from_spec(spec)
spec.loader.exec_module(verifier)


class FilterOrderTest(unittest.TestCase):
    def setUp(self):
        self.strip = {
            "name": "envoy.filters.http.lua",
            "typed_config": {"inlineCode": "handle:headers():remove(key)"},
        }
        self.auth = {"name": "envoy.filters.http.ext_authz"}
        self.guard = {
            "name": "envoy.filters.http.lua",
            "typed_config": {"inlineCode": "Declared application access denied"},
        }

    def test_real_listener_nesting(self):
        self.assertEqual(verifier.check_filter_order({
            "configs": [{"listeners": [{"http_filters": [self.strip, self.auth, self.guard]}]}],
        }), 1)

    def test_wrong_order_and_duplicates_fail(self):
        for filters in [
            [self.strip, self.guard, self.auth],
            [self.guard, self.auth, self.strip],
            [self.auth, self.guard],
            [self.strip, self.auth, self.auth, self.guard],
        ]:
            with self.subTest(filters=filters), self.assertRaises(ValueError):
                verifier.check_filter_order({"http_filters": filters})

    def test_no_guard_is_not_proof(self):
        self.assertEqual(verifier.check_filter_order({
            "http_filters": [self.strip, self.auth],
        }), 0)

    def test_envoy_normalized_source_code(self):
        guard = {
            "name": "envoy.filters.http.lua",
            "typed_config": {
                "default_source_code": {"inline_string": "Declared application access denied"},
            },
        }
        strip = {
            "name": "envoy.filters.http.lua",
            "typed_config": {"inline_code": "handle:headers():remove(key)"},
        }
        self.assertEqual(verifier.check_filter_order({
            "http_filters": [strip, self.auth, guard],
        }), 1)


if __name__ == "__main__":
    unittest.main()

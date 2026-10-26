import importlib
import json
import os
import sys
import types
import unittest
from unittest.mock import Mock


class StubClientError(Exception):
    def __init__(self, error_code):
        self.response = {"Error": {"Code": error_code}}


class _S3:
    exceptions = types.SimpleNamespace(ClientError=StubClientError)

    def head_object(self, **_kwargs):
        return {"ContentLength": 100, "ContentType": "image/jpeg"}


_boto3 = types.ModuleType("boto3")
_boto3.client = lambda *_args, **_kwargs: types.SimpleNamespace()
_boto3.resource = lambda *_args, **_kwargs: types.SimpleNamespace()
_botocore = types.ModuleType("botocore")
_botocore_exceptions = types.ModuleType("botocore.exceptions")
_botocore_exceptions.ClientError = StubClientError
_botocore.exceptions = _botocore_exceptions
sys.modules.setdefault("boto3", _boto3)
sys.modules.setdefault("botocore", _botocore)
sys.modules.setdefault("botocore.exceptions", _botocore_exceptions)
os.environ.setdefault("IMAGE_BUCKET", "ava-test-images")
sys.path.insert(0, os.path.dirname(__file__))
lambda_function = importlib.import_module("lambda_function")


class LambdaRouteTests(unittest.TestCase):
    def setUp(self):
        lambda_function.s3 = _S3()
        lambda_function.rekognition = types.SimpleNamespace(
            detect_text=Mock(),
            detect_labels=Mock(
                return_value={
                    "Labels": [{"Name": "Bottle", "Confidence": 98.5}]
                }
            )
        )
        lambda_function.translate = types.SimpleNamespace(
            translate_text=Mock(
                return_value={
                    "TranslatedText": "नमस्ते",
                    "SourceLanguageCode": "en",
                    "TargetLanguageCode": "hi",
                }
            )
        )

    def _event(self, route, payload):
        return {"routeKey": route, "body": json.dumps(payload)}

    def test_describe_returns_normal_scene_result(self):
        result = lambda_function.lambda_handler(
            self._event(
                "POST /describe",
                {"bucket": "ava-test-images", "key": "uploads/test.jpg"},
            ),
            None,
        )

        self.assertEqual(result["statusCode"], 200)
        body = json.loads(result["body"])
        self.assertIn("bottle", body["description"].lower())
        self.assertEqual(body["labels"][0]["name"], "Bottle")

    def test_translate_accepts_typed_regional_language_text(self):
        result = lambda_function.lambda_handler(
            self._event(
                "POST /translate",
                {
                    "text": "Hello",
                    "sourceLanguageCode": "en",
                    "targetLanguageCode": "hi",
                },
            ),
            None,
        )

        self.assertEqual(result["statusCode"], 200)
        body = json.loads(result["body"])
        self.assertEqual(body["translatedText"], "नमस्ते")
        lambda_function.translate.translate_text.assert_called_once_with(
            Text="Hello", SourceLanguageCode="en", TargetLanguageCode="hi"
        )

    def test_translate_rejects_invalid_language_code_without_calling_aws(self):
        result = lambda_function.lambda_handler(
            self._event(
                "POST /translate",
                {
                    "text": "Hello",
                    "sourceLanguageCode": ["en"],
                    "targetLanguageCode": "hi",
                },
            ),
            None,
        )

        self.assertEqual(result["statusCode"], 400)
        lambda_function.translate.translate_text.assert_not_called()

    def test_photo_translation_rejects_unreadable_source_script(self):
        result = lambda_function.lambda_handler(
            self._event(
                "POST /translate",
                {
                    "bucket": "ava-test-images",
                    "key": "uploads/test.jpg",
                    "sourceLanguageCode": "ml",
                    "targetLanguageCode": "en",
                },
            ),
            None,
        )

        self.assertEqual(result["statusCode"], 400)
        self.assertIn("Photo translation can read", json.loads(result["body"])["error"])
        lambda_function.rekognition.detect_text.assert_not_called()


if __name__ == "__main__":
    unittest.main()

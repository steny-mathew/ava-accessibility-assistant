"""Ava's HTTP API handler for secure image uploads, OCR, translation, and alerts."""

import json
import os
import uuid
from urllib.parse import unquote

import boto3
from botocore.exceptions import ClientError


REGION = os.environ.get("AWS_REGION", "us-east-1")
BUCKET = os.environ["IMAGE_BUCKET"]
ALLOWED_CONTENT_TYPES = {"image/jpeg", "image/png"}
s3 = boto3.client("s3", region_name=REGION)
rekognition = boto3.client("rekognition", region_name=REGION)
translate = boto3.client("translate", region_name=REGION)
sns = boto3.client("sns", region_name=REGION)
EMERGENCY_TOPIC_ARN = os.environ.get("EMERGENCY_TOPIC_ARN", "")
SUPPORTED_LANGUAGES = {
    "ar": "Arabic",
    "de": "German",
    "en": "English",
    "es": "Spanish",
    "fr": "French",
    "hi": "Hindi",
    "it": "Italian",
    "ja": "Japanese",
    "ko": "Korean",
    "ml": "Malayalam",
    "mr": "Marathi",
    "pt": "Portuguese",
    "ta": "Tamil",
    "te": "Telugu",
    "ur": "Urdu",
    "zh": "Chinese (Simplified)",
}


def _response(status_code, payload):
    return {
        "statusCode": status_code,
        "headers": {
            "Content-Type": "application/json",
            "Access-Control-Allow-Origin": "*",
            "Access-Control-Allow-Headers": "content-type",
            "Access-Control-Allow-Methods": "POST,OPTIONS",
        },
        "body": json.dumps(payload),
    }


def _body(event):
    body = event.get("body") or "{}"
    if event.get("isBase64Encoded"):
        import base64

        body = base64.b64decode(body).decode("utf-8")
    return json.loads(body)


def lambda_handler(event, context):
    route = event.get("routeKey", "")
    if route == "POST /upload-url":
        return _create_upload_url(_body(event))
    if route == "POST /read-text":
        return _read_text(_body(event))
    if route == "POST /translate":
        return _translate_image(_body(event))
    if route == "POST /describe":
        return _describe_surroundings(_body(event))
    if route == "POST /emergency-alert":
        return _send_emergency_alert(_body(event))
    return _response(404, {"error": "Route not found"})


def _create_upload_url(payload):
    content_type = payload.get("contentType")
    content_length = payload.get("contentLength")
    if content_type not in ALLOWED_CONTENT_TYPES:
        return _response(400, {"error": "Only JPEG and PNG images are supported"})
    if not isinstance(content_length, int) or not 0 < content_length <= 5 * 1024 * 1024:
        return _response(400, {"error": "Image must be between 1 byte and 5 MB"})

    extension = "jpg" if content_type == "image/jpeg" else "png"
    key = f"uploads/{uuid.uuid4()}.{extension}"
    upload_url = s3.generate_presigned_url(
        "put_object",
        Params={
            "Bucket": BUCKET,
            "Key": key,
            "ContentType": content_type,
            "ContentLength": content_length,
        },
        ExpiresIn=60,
        HttpMethod="PUT",
    )
    return _response(
        200,
        {"uploadUrl": upload_url, "bucket": BUCKET, "key": key, "contentType": content_type},
    )


def _read_text(payload):
    bucket = payload.get("bucket")
    key = unquote(payload.get("key", ""))
    if bucket != BUCKET or not key.startswith("uploads/") or ".." in key:
        return _response(400, {"error": "Invalid uploaded image reference"})

    try:
        metadata = s3.head_object(Bucket=BUCKET, Key=key)
    except s3.exceptions.ClientError as error:
        code = error.response.get("Error", {}).get("Code")
        if code in {"404", "NoSuchKey", "NotFound"}:
            return _response(404, {"error": "Uploaded image was not found"})
        raise

    if metadata.get("ContentLength", 0) > 5 * 1024 * 1024:
        return _response(413, {"error": "Image exceeds the 5 MB recognition limit"})
    if metadata.get("ContentType") not in ALLOWED_CONTENT_TYPES:
        return _response(400, {"error": "Uploaded object is not a JPEG or PNG image"})

    try:
        result = rekognition.detect_text(
            Image={"S3Object": {"Bucket": BUCKET, "Name": key}}
        )
    except ClientError as error:
        error_code = error.response.get("Error", {}).get("Code")
        if error_code == "SubscriptionRequiredException":
            return _response(
                503,
                {
                    "error": (
                        "Amazon Rekognition is unavailable to this AWS account. "
                        "Check the account plan or contact AWS Support."
                    )
                },
            )
        raise
    lines = [
        detection["DetectedText"]
        for detection in result.get("TextDetections", [])
        if detection.get("Type") == "LINE" and detection.get("DetectedText")
    ]
    return _response(200, {"text": "\n".join(lines), "lines": lines})


def _translate_image(payload):
    bucket = payload.get("bucket")
    key = unquote(payload.get("key", ""))
    target_language = payload.get("targetLanguageCode")
    source_language = payload.get("sourceLanguageCode")
    if source_language not in SUPPORTED_LANGUAGES:
        return _response(400, {"error": "Choose a supported source language"})
    if target_language not in SUPPORTED_LANGUAGES:
        return _response(400, {"error": "Choose a supported target language"})
    if bucket != BUCKET or not key.startswith("uploads/") or ".." in key:
        return _response(400, {"error": "Invalid uploaded image reference"})

    try:
        metadata = s3.head_object(Bucket=BUCKET, Key=key)
    except s3.exceptions.ClientError as error:
        code = error.response.get("Error", {}).get("Code")
        if code in {"404", "NoSuchKey", "NotFound"}:
            return _response(404, {"error": "Uploaded image was not found"})
        raise

    if metadata.get("ContentLength", 0) > 5 * 1024 * 1024:
        return _response(413, {"error": "Image exceeds the 5 MB recognition limit"})
    if metadata.get("ContentType") not in ALLOWED_CONTENT_TYPES:
        return _response(400, {"error": "Uploaded object is not a JPEG or PNG image"})

    try:
        result = rekognition.detect_text(
            Image={"S3Object": {"Bucket": BUCKET, "Name": key}}
        )
    except ClientError as error:
        if error.response.get("Error", {}).get("Code") == "SubscriptionRequiredException":
            return _response(503, {"error": "Amazon Rekognition is unavailable for this account."})
        raise

    lines = [
        detection["DetectedText"]
        for detection in result.get("TextDetections", [])
        if detection.get("Type") == "LINE" and detection.get("DetectedText")
    ]
    source_text = "\n".join(lines).strip()
    if not source_text:
        return _response(422, {"error": "No readable text was found. Try a closer, sharper photo."})

    try:
        result = translate.translate_text(
            Text=source_text,
            SourceLanguageCode=source_language,
            TargetLanguageCode=target_language,
        )
    except ClientError as error:
        error_code = error.response.get("Error", {}).get("Code")
        if error_code == "SubscriptionRequiredException":
            return _response(503, {"error": "Amazon Translate is unavailable for this account."})
        if error_code in {"AccessDenied", "AccessDeniedException", "UnauthorizedException"}:
            return _response(
                503,
                {
                    "error": "The ava-lambda-role needs translate:TranslateText permission."
                },
            )
        raise

    return _response(
        200,
        {
            "text": source_text,
            "translatedText": result.get("TranslatedText", ""),
            "sourceLanguageCode": result.get("SourceLanguageCode", ""),
            "targetLanguageCode": result.get("TargetLanguageCode", target_language),
            "sourceLanguageName": SUPPORTED_LANGUAGES[source_language],
            "targetLanguageName": SUPPORTED_LANGUAGES[target_language],
        },
    )


def _describe_surroundings(payload):
    bucket = payload.get("bucket")
    key = unquote(payload.get("key", ""))
    if bucket != BUCKET or not key.startswith("uploads/") or ".." in key:
        return _response(400, {"error": "Invalid uploaded image reference"})

    try:
        metadata = s3.head_object(Bucket=BUCKET, Key=key)
    except s3.exceptions.ClientError as error:
        code = error.response.get("Error", {}).get("Code")
        if code in {"404", "NoSuchKey", "NotFound"}:
            return _response(404, {"error": "Uploaded image was not found"})
        raise

    if metadata.get("ContentLength", 0) > 5 * 1024 * 1024:
        return _response(413, {"error": "Image exceeds the 5 MB recognition limit"})
    if metadata.get("ContentType") not in ALLOWED_CONTENT_TYPES:
        return _response(400, {"error": "Uploaded object is not a JPEG or PNG image"})

    try:
        result = rekognition.detect_labels(
            Image={"S3Object": {"Bucket": BUCKET, "Name": key}},
            MaxLabels=10,
            MinConfidence=70.0,
        )
    except ClientError as error:
        error_code = error.response.get("Error", {}).get("Code")
        if error_code == "SubscriptionRequiredException":
            return _response(503, {"error": "Amazon Rekognition labels are unavailable for this account."})
        if error_code in {"AccessDenied", "AccessDeniedException", "UnauthorizedException"}:
            return _response(
                503,
                {"error": "The ava-lambda-role needs rekognition:DetectLabels permission."},
            )
        raise

    labels = []
    seen = set()
    for item in result.get("Labels", []):
        name = item.get("Name", "").strip()
        if name and name.casefold() not in seen:
            seen.add(name.casefold())
            labels.append(
                {
                    "name": name,
                    "confidence": round(float(item.get("Confidence", 0)), 1),
                }
            )

    if not labels:
        return _response(422, {"error": "Ava could not identify clear objects or scenes. Try another photo."})

    names = [item["name"].lower() for item in labels[:8]]
    if len(names) == 1:
        description = f"Ava recognizes {names[0]} in the image."
    else:
        description = f"Ava recognizes {', '.join(names[:-1])}, and {names[-1]} in the image."
    return _response(200, {"description": description, "labels": labels})


def _send_emergency_alert(payload):
    if not EMERGENCY_TOPIC_ARN:
        return _response(503, {"error": "Emergency email alerts are not configured."})

    is_test = payload.get("test") is True
    subject = "Ava SNS test alert" if is_test else "Ava emergency assistance requested"
    message = (
        "This is a test of Ava's SNS email notification. No assistance is needed."
        if is_test
        else (
            "Ava's Emergency Assistance button was activated. "
            "Please check in with the person using Ava. "
            "This alert does not include their location or identity."
        )
    )
    try:
        sns.publish(
            TopicArn=EMERGENCY_TOPIC_ARN,
            Subject=subject,
            Message=message,
        )
    except ClientError as error:
        error_code = error.response.get("Error", {}).get("Code")
        if error_code in {"AuthorizationError", "AccessDenied", "AccessDeniedException"}:
            return _response(
                503,
                {"error": "The ava-lambda-role needs sns:Publish for its alert topic."},
            )
        raise

    return _response(200, {"sent": True, "message": "Emergency email alert sent."})

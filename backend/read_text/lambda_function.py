"""Ava's HTTP API handler for secure image uploads, OCR, translation, and alerts."""

import json
import os
import re
import uuid
from datetime import datetime, timezone
from urllib.parse import unquote

import boto3
from botocore.exceptions import ClientError


REGION = os.environ.get("AWS_REGION", "us-east-1")
BUCKET = os.environ["IMAGE_BUCKET"]
ALLOWED_CONTENT_TYPES = {"image/jpeg", "image/png"}
s3 = boto3.client("s3", region_name=REGION)
rekognition = boto3.client("rekognition", region_name=REGION)
textract = boto3.client("textract", region_name=REGION)
translate = boto3.client("translate", region_name=REGION)
sns = boto3.client("sns", region_name=REGION)
dynamodb = boto3.resource("dynamodb", region_name=REGION)
ITEM_MEMORY_TABLE = os.environ.get("ITEM_MEMORY_TABLE", "")
EMERGENCY_TOPIC_ARN = os.environ.get("EMERGENCY_TOPIC_ARN", "")
SUPPORTED_LANGUAGES = {
    "ar": "Arabic",
    "bn": "Bengali",
    "de": "German",
    "en": "English",
    "es": "Spanish",
    "fr": "French",
    "gu": "Gujarati",
    "hi": "Hindi",
    "it": "Italian",
    "ja": "Japanese",
    "kn": "Kannada",
    "ko": "Korean",
    "ml": "Malayalam",
    "mr": "Marathi",
    "pt": "Portuguese",
    "pa": "Punjabi",
    "ru": "Russian",
    "ta": "Tamil",
    "te": "Telugu",
    "ur": "Urdu",
    "zh": "Chinese (Simplified)",
}
PHOTO_TEXT_LANGUAGES = {"ar", "de", "en", "es", "fr", "it", "pt", "ru"}


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


def _normalized_words(value):
    words = re.findall(r"[a-z0-9]+", value.casefold())
    ignored = {"a", "an", "find", "for", "i", "me", "my", "the", "to"}
    normalized = set()
    for word in words:
        if word in ignored:
            continue
        if len(word) > 3 and word.endswith("ies"):
            word = f"{word[:-3]}y"
        elif len(word) > 3 and word.endswith("s") and not word.endswith(("ss", "us", "is")):
            word = word[:-1]
        normalized.add(word)
    return normalized


def _label_matches_target(target, label):
    target_words = _normalized_words(target)
    candidates = [label.get("Name", "")]
    candidates.extend(alias.get("Name", "") for alias in label.get("Aliases", []))
    candidates.extend(parent.get("Name", "") for parent in label.get("Parents", []))
    for candidate in candidates:
        candidate_words = _normalized_words(candidate)
        if target_words and candidate_words and target_words.intersection(candidate_words):
            return True
    return False


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
        payload = _body(event)
        if "text" in payload:
            return _translate_text(payload)
        return _translate_image(payload)
    if route == "POST /describe":
        return _describe_surroundings(_body(event))
    if route == "POST /emergency-alert":
        return _send_emergency_alert(_body(event))
    if route == "POST /item-memory":
        return _item_memory(event, _body(event))
    return _response(404, {"error": "Route not found"})


def _item_memory(event, payload):
    """Store, recall, or forget one item location for the signed-in user."""
    if not ITEM_MEMORY_TABLE:
        return _response(503, {"error": "Item memory is not configured yet."})

    claims = (
        event.get("requestContext", {})
        .get("authorizer", {})
        .get("jwt", {})
        .get("claims", {})
    )
    user_id = claims.get("sub")
    if not user_id:
        return _response(401, {"error": "Sign in to use item memory."})

    action = payload.get("action")
    item_name = payload.get("itemName")
    if action not in {"remember", "recall", "forget"}:
        return _response(400, {"error": "Choose remember, recall, or forget."})
    if not isinstance(item_name, str) or not item_name.strip() or len(item_name.strip()) > 80:
        return _response(400, {"error": "Item name must be 1 to 80 characters."})

    item_name = " ".join(item_name.split())
    item_key = re.sub(r"^(?:my|our|the|a|an)\s+", "", item_name.casefold())
    table = dynamodb.Table(ITEM_MEMORY_TABLE)

    if action == "remember":
        location = payload.get("location")
        if not isinstance(location, str) or not location.strip() or len(location.strip()) > 240:
            return _response(400, {"error": "Location must be 1 to 240 characters."})
        table.put_item(
            Item={
                "userId": user_id,
                "itemKey": item_key,
                "itemName": item_name,
                "location": " ".join(location.split()),
                "updatedAt": datetime.now(timezone.utc).isoformat(),
            }
        )
        return _response(200, {"saved": True, "itemName": item_name})

    if action == "forget":
        table.delete_item(Key={"userId": user_id, "itemKey": item_key})
        return _response(200, {"deleted": True, "itemName": item_name})

    result = table.get_item(Key={"userId": user_id, "itemKey": item_key})
    item = result.get("Item")
    if not item:
        return _response(200, {"found": False, "itemName": item_name})
    return _response(
        200,
        {
            "found": True,
            "itemName": item.get("itemName", item_name),
            "location": item.get("location", ""),
            "updatedAt": item.get("updatedAt", ""),
        },
    )


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
        result = textract.detect_document_text(
            Document={"S3Object": {"Bucket": BUCKET, "Name": key}}
        )
    except ClientError as error:
        error_code = error.response.get("Error", {}).get("Code")
        if error_code in {"AccessDenied", "AccessDeniedException", "UnauthorizedOperation"}:
            return _response(
                503,
                {
                    "error": (
                        "The Lambda execution role needs textract:DetectDocumentText permission."
                    )
                },
            )
        raise
    lines = [
        block["Text"]
        for block in result.get("Blocks", [])
        if block.get("BlockType") == "LINE" and block.get("Text")
    ]
    return _response(200, {"text": "\n".join(lines), "lines": lines})


def _translate_image(payload):
    bucket = payload.get("bucket")
    key = unquote(payload.get("key", ""))
    target_language = payload.get("targetLanguageCode")
    source_language = payload.get("sourceLanguageCode")
    if not isinstance(source_language, str) or source_language not in PHOTO_TEXT_LANGUAGES:
        return _response(
            400,
            {
                "error": (
                    "Photo translation can read English, Arabic, Russian, German, "
                    "French, Italian, Portuguese, and Spanish text."
                )
            },
        )
    if not isinstance(target_language, str) or target_language not in SUPPORTED_LANGUAGES:
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


def _translate_text(payload):
    source_text = payload.get("text")
    source_language = payload.get("sourceLanguageCode")
    target_language = payload.get("targetLanguageCode")
    if not isinstance(source_text, str) or not source_text.strip():
        return _response(400, {"error": "Enter text to translate."})
    source_text = source_text.strip()
    if len(source_text) > 5000:
        return _response(400, {"error": "Text must be 5,000 characters or fewer."})
    if not isinstance(source_language, str) or source_language not in SUPPORTED_LANGUAGES:
        return _response(400, {"error": "Choose a supported source language."})
    if not isinstance(target_language, str) or target_language not in SUPPORTED_LANGUAGES:
        return _response(400, {"error": "Choose a supported target language."})

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
                {"error": "The ava-lambda-role needs translate:TranslateText permission."},
            )
        raise

    return _response(
        200,
        {
            "text": source_text,
            "translatedText": result.get("TranslatedText", ""),
            "sourceLanguageCode": result.get("SourceLanguageCode", source_language),
            "targetLanguageCode": result.get("TargetLanguageCode", target_language),
            "sourceLanguageName": SUPPORTED_LANGUAGES[source_language],
            "targetLanguageName": SUPPORTED_LANGUAGES[target_language],
        },
    )


def _describe_surroundings(payload):
    bucket = payload.get("bucket")
    key = unquote(payload.get("key", ""))
    target = payload.get("target")
    if target is not None and (not isinstance(target, str) or len(target.strip()) > 80):
        return _response(400, {"error": "The item to find must be 1 to 80 characters"})
    target = target.strip() if isinstance(target, str) else ""
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
    matches = []
    target_detected = False
    seen = set()
    for item in result.get("Labels", []):
        name = item.get("Name", "").strip()
        if name and name.casefold() not in seen:
            seen.add(name.casefold())
            confidence = round(float(item.get("Confidence", 0)), 1)
            labels.append(
                {
                    "name": name,
                    "confidence": confidence,
                }
            )
            if target and _label_matches_target(target, item):
                target_detected = True
                for instance in item.get("Instances", []):
                    box = instance.get("BoundingBox") or {}
                    width = float(box.get("Width", 0))
                    height = float(box.get("Height", 0))
                    left = float(box.get("Left", 0))
                    top = float(box.get("Top", 0))
                    if width <= 0 or height <= 0:
                        continue
                    center_x = left + width / 2
                    center_y = top + height / 2
                    horizontal = "left" if center_x < 0.34 else "right" if center_x > 0.66 else "center"
                    vertical = "top" if center_y < 0.34 else "bottom" if center_y > 0.66 else "middle"
                    location = f"{vertical} {horizontal}" if vertical != "middle" else horizontal
                    matches.append(
                        {
                            "name": name,
                            "confidence": round(float(instance.get("Confidence", confidence)), 1),
                            "location": location,
                        }
                    )

    if not labels:
        return _response(422, {"error": "Ava could not identify clear objects or scenes. Try another photo."})

    names = [item["name"].lower() for item in labels[:8]]
    if len(names) == 1:
        description = f"Ava recognizes {names[0]} in the image."
    else:
        description = f"Ava recognizes {', '.join(names[:-1])}, and {names[-1]} in the image."
    response = {"description": description, "labels": labels}
    if target:
        response["target"] = target
        response["targetDetected"] = target_detected
        response["matches"] = matches
        response["found"] = bool(matches)
        return _response(200, response)
    return _response(200, response)


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

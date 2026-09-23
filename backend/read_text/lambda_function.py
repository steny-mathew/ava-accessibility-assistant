"""Ava's HTTP API handler for secure image uploads and OCR."""

import json
import os
import uuid
from urllib.parse import unquote

import boto3


REGION = os.environ.get("AWS_REGION", "us-east-1")
BUCKET = os.environ["IMAGE_BUCKET"]
ALLOWED_CONTENT_TYPES = {"image/jpeg", "image/png"}
s3 = boto3.client("s3", region_name=REGION)
textract = boto3.client("textract", region_name=REGION)


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
    return _response(404, {"error": "Route not found"})


def _create_upload_url(payload):
    content_type = payload.get("contentType")
    if content_type not in ALLOWED_CONTENT_TYPES:
        return _response(400, {"error": "Only JPEG and PNG images are supported"})

    extension = "jpg" if content_type == "image/jpeg" else "png"
    key = f"uploads/{uuid.uuid4()}.{extension}"
    upload_url = s3.generate_presigned_url(
        "put_object",
        Params={"Bucket": BUCKET, "Key": key, "ContentType": content_type},
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
        return _response(413, {"error": "Image exceeds Textract's 5 MB synchronous limit"})
    if metadata.get("ContentType") not in ALLOWED_CONTENT_TYPES:
        return _response(400, {"error": "Uploaded object is not a JPEG or PNG image"})

    result = textract.detect_document_text(
        Document={"S3Object": {"Bucket": BUCKET, "Name": key}}
    )
    lines = [
        block["Text"]
        for block in result.get("Blocks", [])
        if block.get("BlockType") == "LINE" and block.get("Text")
    ]
    return _response(200, {"text": "\n".join(lines), "lines": lines})

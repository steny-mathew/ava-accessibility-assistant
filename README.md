# Ava — AI-Powered Cloud Accessibility Assistant

Ava is a Flutter accessibility assistant designed to help people interact with printed information and their surroundings using voice and a camera. The project combines a Flutter client with a serverless AWS backend. AWS credentials are kept out of the Flutter app.

## Implemented so far

- Speech input and voice-command routing for Read Text, Describe Surroundings, Translate, and Emergency Assistance.
- Camera preview and image capture for the camera-based actions.
- Read Text upload flow: Flutter requests a short-lived presigned S3 upload URL, uploads the image, then requests OCR through API Gateway.
- Translate flow: Flutter uploads through the same presigned S3 flow, then asks the Lambda to detect printed text and translate it from the selected source language to the selected target language.
- Python 3.12 Lambda handler calls Amazon Rekognition `DetectText` and Amazon Translate `TranslateText`.
- OCR result screen with selectable text, retry on errors, and **Read aloud / Stop reading** using the device or browser text-to-speech engine.
- A clearly labeled sample read-aloud demo, so the text-to-speech feature can be demonstrated while Textract account access is pending.
- S3 upload validation for JPEG/PNG images and a 5 MB limit.

## Architecture

```text
Flutter camera
  → API Gateway HTTP API (/upload-url)
  → short-lived presigned PUT to private S3 bucket
  → API Gateway HTTP API (/read-text)
  → Lambda (Python 3.12, boto3)
  → Amazon Rekognition DetectText
  → JSON text response in Flutter

Translation uses the same upload path, followed by `POST /translate`, Rekognition text detection, and Amazon Translate.
```

## Run in Chrome

From the project root, run:

```bash
flutter pub get
flutter run -d chrome --web-port 8080 --dart-define=AVA_API_BASE_URL=https://36emce4it9.execute-api.us-east-1.amazonaws.com
```

Allow camera access in Chrome when prompted. Choose **Try a read-aloud demo** to demonstrate speech output without AWS. The sample is labeled as demo content; it is not presented as OCR output. For a live OCR demo, capture text and press **Read aloud** on the returned result. Chrome needs a working system/browser speech voice.

## AWS configuration

- Region: `us-east-1`
- HTTP API: `https://36emce4it9.execute-api.us-east-1.amazonaws.com`
- Routes: `POST /upload-url`, `POST /read-text`, and `POST /translate`
- S3 bucket: `ava-accessibility-images-1789928506`
- Lambda: `ava-read-text`

The Flutter app uses only the API URL. It does not contain AWS access keys or secret keys.

## Current limitation

Amazon Textract currently returns `SubscriptionRequiredException` for this AWS account, so Ava's Read Text endpoint uses Amazon Rekognition `DetectText` instead. Rekognition text detection has a 100-word limit per image. Translate supports English, Arabic, Chinese (Simplified), French, German, Hindi, Italian, Japanese, Korean, Malayalam, Marathi, Portuguese, Spanish, Tamil, Telugu, and Urdu. Its Lambda role needs `translate:TranslateText`. Amazon Translate returned `SubscriptionRequiredException` during the live integration test, so translation is not confirmed available for this AWS account yet.

## Next implementation steps

1. Run a camera-based Read Text scan in Chrome and on a phone.
2. Resolve Textract account access if longer document OCR is needed.
3. Add the Describe Surroundings processing backend.
4. Add persistent scan history and user preferences, then expand accessibility checks.

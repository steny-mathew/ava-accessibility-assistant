# Ava — AI-Powered Cloud Accessibility Assistant

Ava is a Flutter accessibility assistant designed to help people interact with printed information and their surroundings using voice and a camera. The project combines a Flutter client with a serverless AWS backend. AWS credentials are kept out of the Flutter app.

## Implemented so far

- Speech input and voice-command routing for Read Text, Describe Surroundings, Translate, and Emergency Assistance.
- Camera preview and image capture for the camera-based actions.
- Read Text upload flow: Flutter requests a short-lived presigned S3 upload URL, uploads the image, then requests OCR through API Gateway.
- Translate flow: Flutter uploads through the same presigned S3 flow, then asks the Lambda to detect printed text and translate it from the selected source language to the selected target language.
- Emergency email alert: the user confirms before Ava asks the existing Lambda to publish a fixed alert message to the confirmed SNS email topic.
- Describe Surroundings: Flutter uploads a captured photo through the presigned S3 flow, then Amazon Rekognition DetectLabels returns detected object and scene labels for display and read-aloud.
- Find an item: voice command or button entry selects an item; Ava reuses the same image upload and Rekognition DetectLabels call, and speaks an approximate image region when Rekognition returns an object box. The camera supports both an accessible shutter button and a voice shutter command (“take photo”).
- Remember an item: save a spoken or typed item and place, then ask “Where are my keys?” to hear the last place saved. Memories are isolated by the signed-in Cognito user and can be deleted from the memory screen.
- Python 3.12 Lambda handler uses Amazon Textract `DetectDocumentText` for Read Text and Amazon Translate `TranslateText` for translation. Translation image extraction still uses Rekognition `DetectText`.
- OCR result screen with selectable text, retry on errors, and **Read aloud / Stop reading** using the device or browser text-to-speech engine.
- A clearly labeled sample read-aloud demo, so speech output can be demonstrated without presenting sample content as OCR output.
- S3 upload validation for JPEG/PNG images and a 5 MB limit.
- Cognito email sign-up/sign-in; ID and refresh tokens are stored in iOS Keychain using `flutter_secure_storage`.
- API Gateway JWT authorization on all five routes. The mobile Cognito client has no client secret, and Flutter contains no AWS credentials.

## Architecture

```text
Flutter camera
  → API Gateway HTTP API (/upload-url)
  → short-lived presigned PUT to private S3 bucket
  → API Gateway HTTP API (/read-text)
  → Lambda (Python 3.12, boto3)
  → Amazon Textract DetectDocumentText
  → JSON text response in Flutter
```

Translation uses the same upload path, followed by `POST /translate`, Rekognition text detection, and Amazon Translate. Output targets include Hindi, Malayalam, Marathi, Tamil, Telugu, Bengali, Gujarati, Kannada, and Punjabi. Rekognition's current text detection supports English, Arabic, Russian, German, French, Italian, Portuguese, and Spanish, so scanning Indic-script text for translation is not supported by that separate OCR path yet. Read-aloud depends on available device voices; AWS Polly currently lists Hindi and Indian English, but not Malayalam or the other regional languages.

Item memory uses the authenticated `POST /item-memory` route. The Lambda reads the user identity from verified Cognito JWT claims and stores the item and place in DynamoDB; the client cannot choose another user's partition key. Ava reports the last saved place and does not verify that the item is still there.

Emergency Assistance asks before sending. `POST /emergency-alert` publishes a fixed message through Amazon SNS to the configured topic. The email alert does not include location, does not identify the user, and does not contact emergency services.

Describe Surroundings uses `POST /describe` and Rekognition `DetectLabels`. It reports detected labels with confidence of at least 70% and reads the summary aloud. These labels may miss details and are not a complete natural-language scene description.

Find an item uses the same `/describe` endpoint and DetectLabels request, so it adds no extra AWS service or recognition request per scan. When available, Rekognition object bounding boxes are converted to coarse image regions such as left, center, or right. This is an experimental visual aid, not indoor navigation: a single photo can miss or misidentify an item, and position is approximate.

All API routes require a valid Cognito JWT bearer token. Create an account and confirm its email before using AWS-backed features.

## Run in Chrome

From the project root, run:

```bash
flutter pub get
flutter run -d chrome --web-port 8080 --dart-define=AVA_API_BASE_URL=https://36emce4it9.execute-api.us-east-1.amazonaws.com
```

Allow camera access in Chrome when prompted. Choose **Try a read-aloud demo** to demonstrate speech output without AWS. The sample is labeled as demo content; it is not presented as OCR output. For a live OCR demo, capture text and press **Read aloud** on the returned result. Chrome needs a working system/browser speech voice.

## Run on iPhone with sign-in

Run the app with this project's Cognito configuration:

```bash
flutter run -d <your-iphone-device-id> \
  --dart-define=AVA_API_BASE_URL=https://36emce4it9.execute-api.us-east-1.amazonaws.com \
  --dart-define=AVA_COGNITO_USER_POOL_ID=us-east-1_fNY6RbZDj \
  --dart-define=AVA_COGNITO_CLIENT_ID=2komp6so6khm8r4i9s7e4valm9
```

In Ava, choose **Create account**, enter your email and password, and enter the verification code Cognito emails you. These IDs are public app configuration; never put a password, verification code, or AWS access key in source code.

## AWS configuration

- Region: `us-east-1`
- HTTP API: `https://36emce4it9.execute-api.us-east-1.amazonaws.com`
- Routes: `POST /upload-url`, `POST /read-text`, `POST /translate`, `POST /describe`, `POST /emergency-alert`, and `POST /item-memory`
- S3 bucket: `ava-accessibility-images-1789928506`
- Lambda: `ava-read-text`
- Cognito user pool: `us-east-1_fNY6RbZDj` (Lite tier)
- Cognito public app client: `2komp6so6khm8r4i9s7e4valm9` (no client secret)
- API Gateway JWT authorizer: `AvaCognitoJwtAuthorizer`

The Flutter app uses only the API URL. It does not contain AWS access keys or secret keys.

Item memory uses the `ava-item-memories` DynamoDB table with on-demand billing, partition key `userId`, and sort key `itemKey`. The Lambda needs the `ITEM_MEMORY_TABLE` environment variable and only `dynamodb:PutItem`, `dynamodb:GetItem`, and `dynamodb:DeleteItem` on that table.

The Lambda requires `EMERGENCY_TOPIC_ARN` and `sns:Publish` scoped to that topic. The SNS email subscription must be confirmed before messages can be delivered.

API Gateway applies stage throttling: the default limit is 5 requests per second with a burst of 10, and `POST /emergency-alert` is limited to 1 request per minute with a burst of 1. These limits are shared across callers and reduce bursts; they are not authentication.

## Current limitation

Read Text uses Amazon Textract `DetectDocumentText`. A live Lambda test on a synthetic image returned the exact word `TEXTRACT`; a longer test showed OCR can miss or reorder characters, so review important text. The separate Translate route still uses Rekognition `DetectText`, which has a 100-word limit per image and supports English, Arabic, Russian, German, French, Italian, Portuguese, and Spanish. Amazon Translate additionally supports Bengali, Gujarati, Kannada, Malayalam, Marathi, Punjabi, Tamil, Telugu, and Hindi as output languages. The existing Lambda role has `translate:TranslateText` permission.

## Next implementation steps

1. Test Describe Surroundings with real camera photos on the iPhone and review label quality.
2. Sign up and confirm an account on the iPhone, then verify authenticated Read Text and other backend calls from the app.
3. Extend the translation flow to use Textract where appropriate, so text in Indic scripts can be extracted before translation.
4. Test voice memory and screen-reader interaction with blind and low-vision users.

The DynamoDB table can incur charges for stored data and read/write requests. On-demand billing charges according to use; check AWS Billing for account-specific credits and current charges.

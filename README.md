# Ava — an accessibility companion

## Project description

Ava is a voice-first mobile and web companion for people who are blind or have low vision, and for people who need help understanding text across languages. It brings a few practical tasks together in one accessible app: read printed text aloud, translate a spoken or typed message, hear a short list of objects recognized in a photo, and remember where the user said they put an item. A user can also choose to send a pre-confirmed email alert to a trusted contact.

Ava is designed to make these tasks easier to start by voice and usable with a camera, large controls, spoken results, and typed alternatives. It is a prototype and should be tested with people with disabilities before being relied on in daily life.

## What the app currently offers

- **Read printed text:** take a photo; Ava uploads it through a short-lived S3 upload URL and asks Amazon Textract to extract text. The result is selectable and can be read by the device’s installed speech voice.
- **Translate a message:** type, paste, or dictate text, choose a source and target language, and translate using Amazon Translate. The current app list includes Bengali, Gujarati, Hindi, Kannada, Malayalam, Marathi, Punjabi, Tamil, Telugu, Urdu, and other supported languages. Dictation and read-aloud depend on voices available on the user’s device; typed input and displayed translation do not.
- **Translate a sign or label:** photograph text in a script supported by Amazon Rekognition text detection, then translate it. The photo OCR path currently supports English, Arabic, Russian, German, French, Italian, Portuguese, and Spanish. It cannot read Indic-script signs; use Translate a message for text you can enter or dictate.
- **Describe a photo:** hear a short summary based on object and scene labels detected by Amazon Rekognition. This is label-based and may miss or misidentify things.
- **Find an item in a photo:** Ava can report an approximate region only when Rekognition recognizes the named item and returns a bounding box. This is not continuous detection or navigation.
- **Remember an item:** save a user-entered item and place in a per-user DynamoDB record, then ask Ava where it was last saved. This is a saved note, not a live check.
- **Trusted-contact email:** after confirmation, Ava sends a fixed email alert to the configured, confirmed SNS email subscription. It does not contact emergency services or share location.

## Important safety and privacy limits

- OCR can misread text. Check medicine names, strengths, dosage instructions, addresses, and other important details with a trusted person or source before acting on them.
- Photo descriptions and item positions are estimates from one image. Ava does not provide obstacle detection, turn-by-turn directions, or safe navigation.
- Translation may be inaccurate or lose context. Confirm important medical, legal, or safety information with a fluent person.
- Device speech recognition and read-aloud languages vary by phone, operating system, browser, and installed voices. If a voice is unavailable, Ava keeps the text on screen.
- Images uploaded for camera features are stored in the existing private S3 bucket. There is no automatic image-expiration policy configured at this time. Do not scan sensitive documents unless you are comfortable with that storage behavior.
- Ava’s emergency feature is only an email notification. It is not an emergency response service.

## How it is built

```text
Flutter app
  ├─ Cognito sign-in (JWT)
  ├─ Camera images → short-lived presigned S3 upload
  └─ API Gateway HTTP API → Python 3.12 Lambda (boto3)
       ├─ Textract DetectDocumentText (read text)
       ├─ Rekognition DetectText / DetectLabels (photo text and labels)
       ├─ Translate TranslateText (typed or extracted text)
       ├─ DynamoDB (user item memories)
       └─ SNS (confirmed email alert)
```

AWS credentials are not embedded in Flutter. The app signs in with Amazon Cognito and sends its JWT to API Gateway. The Lambda execution role accesses AWS services. Region: `us-east-1`.

## Existing AWS setup

- HTTP API base URL: `https://36emce4it9.execute-api.us-east-1.amazonaws.com`
- Existing API routes: `POST /upload-url`, `POST /read-text`, `POST /translate`, `POST /describe`, `POST /emergency-alert`, and `POST /item-memory`
- Existing Lambda: `ava-read-text` (Python 3.12)
- Existing private S3 bucket: `ava-accessibility-images-1789928506`
- Cognito user pool: `us-east-1_fNY6RbZDj`
- Public Cognito app client: `2komp6so6khm8r4i9s7e4valm9` (no client secret)
- Item memory table: `ava-item-memories`

All six API routes require an authenticated Cognito JWT. The `/translate` route accepts either uploaded-photo references or text; typed text is limited to 5,000 characters.

## Run locally

Install Flutter and Xcode (for iPhone development), then from the project root:

```bash
flutter pub get
flutter run -d chrome --web-port 8080 \
  --dart-define=AVA_API_BASE_URL=https://36emce4it9.execute-api.us-east-1.amazonaws.com \
  --dart-define=AVA_COGNITO_USER_POOL_ID=us-east-1_fNY6RbZDj \
  --dart-define=AVA_COGNITO_CLIENT_ID=2komp6so6khm8r4i9s7e4valm9
```

For iPhone, replace `chrome` with the device ID shown by `flutter devices`. Camera, microphone, and speech features need the corresponding operating-system permissions.

The existing hosted web app is <https://production.d35huwahmnztc9.amplifyapp.com>. It is manually deployed to AWS Amplify and is not connected to GitHub for automatic deployment.

## Costs

Camera operations can call Textract, Rekognition, or Translate, which are usage-priced AWS services. Typed translation calls Amazon Translate. Check current service pricing and account credits before frequent use. Lambda, API Gateway, S3 storage/requests, Cognito, DynamoDB, and SNS may also incur charges depending on usage and account eligibility. No cost-free behavior is promised for cloud-backed requests.

## Development checks

Run Flutter checks with:

```bash
flutter analyze
flutter test
```

Run the local Lambda handler tests (they stub AWS clients and do not call paid AWS services) with:

```bash
python3 -m unittest backend.read_text.test_lambda_function
```

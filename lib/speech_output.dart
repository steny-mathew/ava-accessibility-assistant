import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';

/// Prepares iOS audio output for spoken accessibility feedback.
Future<void> configureSpeechOutput(FlutterTts tts) async {
  if (defaultTargetPlatform != TargetPlatform.iOS) return;

  await tts.setSharedInstance(true);
  await tts.setIosAudioCategory(
    IosTextToSpeechAudioCategory.playback,
    [
      IosTextToSpeechAudioCategoryOptions.allowBluetooth,
      IosTextToSpeechAudioCategoryOptions.allowBluetoothA2DP,
    ],
    IosTextToSpeechAudioMode.spokenAudio,
  );
}

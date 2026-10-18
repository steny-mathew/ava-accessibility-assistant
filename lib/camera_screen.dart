import 'dart:async';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;

import 'read_text_service.dart';
import 'speech_output.dart';

class CameraScreen extends StatefulWidget {
  final String mode;
  final String? demoText;
  final String? targetItem;

  const CameraScreen({
    super.key,
    required this.mode,
    this.demoText,
    this.targetItem,
  });

  @override
  State<CameraScreen> createState() => _CameraScreenState();
}

class _CameraScreenState extends State<CameraScreen> {
  final FlutterTts _textToSpeech = FlutterTts();
  final stt.SpeechToText _captureSpeech = stt.SpeechToText();
  CameraController? _controller;
  List<CameraDescription> _cameras = [];

  bool _isInitialized = false;
  bool _isReadingText = false;
  bool _isTranslating = false;
  bool _isDescribing = false;
  bool _isSpeaking = false;
  bool _isListeningForCapture = false;
  String? _extractedText;
  String? _translatedText;
  String? _sceneDescription;
  List<String> _sceneLabels = [];
  String? _sourceLanguageCode;
  String? _sourceLanguageName;
  String? _targetLanguageName;
  String? _readError;
  String _sourceLanguageInputCode = 'en';
  String _targetLanguageCode = 'es';

  static const _languages = <String, String>{
    'en': 'English',
    'ar': 'Arabic',
    'de': 'German',
    'es': 'Spanish',
    'fr': 'French',
    'hi': 'Hindi',
    'it': 'Italian',
    'ja': 'Japanese',
    'ko': 'Korean',
    'ml': 'Malayalam',
    'mr': 'Marathi',
    'pt': 'Portuguese',
    'ta': 'Tamil',
    'te': 'Telugu',
    'ur': 'Urdu',
    'zh': 'Chinese (Simplified)',
  };

  @override
  void initState() {
    super.initState();
    _textToSpeech.setCompletionHandler(() {
      if (mounted) setState(() => _isSpeaking = false);
    });
    _textToSpeech.setCancelHandler(() {
      if (mounted) setState(() => _isSpeaking = false);
    });
    _textToSpeech.setErrorHandler((_) {
      if (mounted) setState(() => _isSpeaking = false);
    });
    if (widget.demoText != null) {
      _extractedText = widget.demoText;
    } else {
      _initializeCamera();
      if (widget.mode == 'Find Item') {
        unawaited(_announceFindInstructions());
      }
    }
  }

  Future<void> _announceFindInstructions() async {
    final item = widget.targetItem?.trim();
    final request = item == null || item.isEmpty
        ? 'Point your camera toward the area, then take a photo.'
        : 'Ava will look for $item. Point your camera toward the area, then tap the microphone and say take photo, or use the take photo button.';
    await configureSpeechOutput(_textToSpeech);
    await _textToSpeech.setSpeechRate(0.45);
    await _textToSpeech.setVolume(1.0);
    await _textToSpeech.speak(
      '$request The result is an estimate from one photo.',
    );
  }

  Future<void> _listenForCapture() async {
    if (_isListeningForCapture) {
      await _captureSpeech.stop();
      if (mounted) setState(() => _isListeningForCapture = false);
      return;
    }

    try {
      final available = await _captureSpeech.initialize(
        onStatus: (status) {
          if (status == 'done' && mounted) {
            setState(() => _isListeningForCapture = false);
          }
        },
        onError: (_) {
          if (mounted) setState(() => _isListeningForCapture = false);
        },
      );
      if (!available) {
        await _toggleReadAloud(
          'Voice capture is unavailable. Use the photo button.',
        );
        return;
      }

      if (mounted) setState(() => _isListeningForCapture = true);
      await _toggleReadAloud('Listening. Say take photo when ready.');
      await _captureSpeech.listen(
        listenOptions: stt.SpeechListenOptions(
          listenFor: const Duration(seconds: 10),
        ),
        onResult: (result) {
          if (!result.finalResult) return;
          final command = result.recognizedWords.toLowerCase();
          final takePhoto = RegExp(
            r'\b(take|capture|snap)\b.*\b(photo|picture|image)\b|\b(photo|picture|image)\b.*\b(take|capture|snap)\b',
          ).hasMatch(command);
          if (takePhoto && mounted) {
            unawaited(_captureSpeech.stop());
            setState(() => _isListeningForCapture = false);
            unawaited(_takePicture());
          }
        },
      );
    } catch (_) {
      if (mounted) setState(() => _isListeningForCapture = false);
      await _toggleReadAloud(
        'Voice capture did not start. Use the photo button.',
      );
    }
  }

  Future<void> _initializeCamera() async {
    try {
      _cameras = await availableCameras();

      if (_cameras.isEmpty) {
        return;
      }

      final camera = _cameras.first;

      _controller = CameraController(
        camera,
        ResolutionPreset.medium,
        enableAudio: false,
      );

      await _controller!.initialize();

      if (!mounted) return;

      setState(() {
        _isInitialized = true;
      });
    } catch (e) {
      debugPrint('Camera initialization error: $e');
    }
  }

  @override
  void dispose() {
    unawaited(_textToSpeech.stop());
    unawaited(_captureSpeech.stop());
    _controller?.dispose();
    super.dispose();
  }

  Future<void> _toggleReadAloud(
    String text, {
    String speechLanguageCode = 'en',
  }) async {
    if (_isSpeaking) {
      await _textToSpeech.stop();
      if (mounted) setState(() => _isSpeaking = false);
      return;
    }

    try {
      await configureSpeechOutput(_textToSpeech);
      final speechLocale = _speechLocale(speechLanguageCode);
      final languageAvailable = await _textToSpeech.isLanguageAvailable(
        speechLocale,
      );
      if (languageAvailable != true) {
        if (!mounted) return;
        setState(() => _isSpeaking = false);
        final languageName = _languages[speechLanguageCode] ?? 'This language';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '$languageName speech is not available on this iPhone. The translation is still shown as text.',
            ),
          ),
        );
        return;
      }
      await _textToSpeech.setLanguage(speechLocale);
      await _textToSpeech.setSpeechRate(0.45);
      await _textToSpeech.setVolume(1.0);
      await _textToSpeech.awaitSpeakCompletion(true);
      if (mounted) setState(() => _isSpeaking = true);
      await _textToSpeech.speak(text);
      if (mounted) setState(() => _isSpeaking = false);
    } catch (error) {
      if (!mounted) return;
      setState(() => _isSpeaking = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not read the text aloud: $error')),
      );
    }
  }

  String _speechLocale(String code) {
    const locales = {
      'ar': 'ar-SA',
      'de': 'de-DE',
      'es': 'es-ES',
      'fr': 'fr-FR',
      'hi': 'hi-IN',
      'it': 'it-IT',
      'ja': 'ja-JP',
      'ko': 'ko-KR',
      'ml': 'ml-IN',
      'mr': 'mr-IN',
      'pt': 'pt-BR',
      'ta': 'ta-IN',
      'te': 'te-IN',
      'ur': 'ur-PK',
      'zh': 'zh-CN',
    };
    return locales[code] ?? 'en-US';
  }

  Future<void> _takePicture() async {
    if (_controller == null || !_controller!.value.isInitialized) {
      return;
    }

    try {
      final image = await _controller!.takePicture();

      if (!mounted) return;
      if (widget.mode == 'Find Item') {
        await HapticFeedback.mediumImpact();
      }

      if (widget.mode == 'Read Text') {
        setState(() {
          _isReadingText = true;
          _readError = null;
          _extractedText = null;
        });
        try {
          final text = await ReadTextService().readImage(image);
          if (!mounted) return;
          setState(() {
            _isReadingText = false;
            _extractedText = text;
          });
        } catch (error) {
          if (!mounted) return;
          setState(() {
            _isReadingText = false;
            _readError = error.toString().replaceFirst('Exception: ', '');
          });
        }
        return;
      }

      if (widget.mode == 'Translate') {
        setState(() {
          _isTranslating = true;
          _readError = null;
          _extractedText = null;
          _translatedText = null;
        });
        try {
          final result = await TranslationService().translateImage(
            image,
            sourceLanguageCode: _sourceLanguageInputCode,
            targetLanguageCode: _targetLanguageCode,
          );
          if (!mounted) return;
          setState(() {
            _isTranslating = false;
            _extractedText = result['text'];
            _translatedText = result['translatedText'];
            _sourceLanguageCode = result['sourceLanguageCode'];
            _sourceLanguageName = result['sourceLanguageName'];
            _targetLanguageName = result['targetLanguageName'];
          });
        } catch (error) {
          if (!mounted) return;
          setState(() {
            _isTranslating = false;
            _readError = error.toString().replaceFirst('Exception: ', '');
          });
        }
        return;
      }

      if (widget.mode == 'Describe Surroundings' ||
          widget.mode == 'Find Item') {
        setState(() {
          _isDescribing = true;
          _readError = null;
          _sceneDescription = null;
          _sceneLabels = [];
        });
        try {
          if (widget.mode == 'Find Item') {
            await _toggleReadAloud(
              'Photo captured. Checking for ${widget.targetItem ?? 'the item'} now.',
            );
          }
          final result = await DescribeSurroundingsService().describeImage(
            image,
            targetItem: widget.mode == 'Find Item' ? widget.targetItem : null,
          );
          if (!mounted) return;
          final labels = (result['labels'] as List<dynamic>? ?? [])
              .whereType<Map<String, dynamic>>()
              .map((label) => label['name'] as String? ?? '')
              .where((name) => name.isNotEmpty)
              .toList();
          var description = result['description'] as String? ?? '';
          if (widget.mode == 'Find Item') {
            final target =
                result['target'] as String? ??
                widget.targetItem?.trim() ??
                'the item';
            final matches = (result['matches'] as List<dynamic>? ?? [])
                .whereType<Map<String, dynamic>>()
                .toList();
            if (matches.isNotEmpty) {
              final locations = matches
                  .map((match) => match['location'] as String? ?? '')
                  .where((location) => location.isNotEmpty)
                  .toSet();
              description = locations.isEmpty
                  ? 'Ava may have detected $target, but could not estimate its position in the photo.'
                  : 'Ava may see $target near the ${locations.join(' and ')} of the camera view. This is only an approximate image location.';
            } else if (result['targetDetected'] == true) {
              description =
                  'Ava may see $target, but could not estimate its position in the photo. Try another angle.';
            } else {
              description =
                  'Ava could not identify $target in this photo. Try pointing toward a different area and take another photo.';
            }
          }
          setState(() {
            _isDescribing = false;
            _sceneDescription = description;
            _sceneLabels = labels;
          });
          if (widget.mode == 'Find Item') {
            unawaited(_toggleReadAloud(description));
          }
        } catch (error) {
          if (!mounted) return;
          setState(() {
            _isDescribing = false;
            _readError = error.toString().replaceFirst('Exception: ', '');
          });
        }
        return;
      }

      if (!mounted) return;
      Navigator.pop(context, image.path);
    } catch (e) {
      debugPrint('Camera capture error: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(backgroundColor: Colors.black, title: Text(widget.mode)),
      body:
          widget.mode == 'Translate' &&
              (_translatedText != null || _readError != null || _isTranslating)
          ? _buildTranslationResult()
          : widget.mode == 'Describe Surroundings' &&
                (_sceneDescription != null ||
                    _readError != null ||
                    _isDescribing)
          ? _buildDescriptionResult()
          : _extractedText != null || _readError != null || _isReadingText
          ? _buildReadResult()
          : _isInitialized && _controller != null
          ? Stack(
              fit: StackFit.expand,
              children: [
                Semantics(
                  label: 'Live camera view',
                  child: CameraPreview(_controller!),
                ),

                if (widget.mode == 'Find Item')
                  Positioned(
                    top: 18,
                    left: 20,
                    right: 20,
                    child: Semantics(
                      liveRegion: true,
                      child: Card(
                        color: const Color(0xEE171C2B),
                        child: Padding(
                          padding: const EdgeInsets.all(14),
                          child: Text(
                            'Looking for ${widget.targetItem ?? 'an item'}. Point the camera around, then take a photo.',
                            style: const TextStyle(fontSize: 16, height: 1.4),
                          ),
                        ),
                      ),
                    ),
                  ),

                if (widget.mode == 'Find Item')
                  Positioned(
                    bottom: 134,
                    left: 20,
                    right: 20,
                    child: FilledButton.icon(
                      onPressed: _listenForCapture,
                      icon: Icon(
                        _isListeningForCapture
                            ? Icons.mic_rounded
                            : Icons.mic_none_rounded,
                      ),
                      label: Text(
                        _isListeningForCapture
                            ? 'Listening — say “take photo”'
                            : 'Use voice to take photo',
                      ),
                    ),
                  ),

                if (widget.mode == 'Translate')
                  Positioned(
                    top: 18,
                    left: 20,
                    right: 20,
                    child: Card(
                      color: const Color(0xEE171C2B),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            _languagePicker('From', _sourceLanguageInputCode, (
                              code,
                            ) {
                              if (code != null) {
                                setState(() => _sourceLanguageInputCode = code);
                              }
                            }),
                            _languagePicker(
                              'Translate to',
                              _targetLanguageCode,
                              (code) {
                                if (code != null) {
                                  setState(() => _targetLanguageCode = code);
                                }
                              },
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),

                // Capture button
                Align(
                  alignment: Alignment.bottomCenter,
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 40),
                    child: Semantics(
                      button: true,
                      label: widget.mode == 'Find Item'
                          ? 'Take photo to look for ${widget.targetItem ?? 'an item'}'
                          : 'Take photo',
                      onTap: _takePicture,
                      child: GestureDetector(
                        onTap: _takePicture,
                        child: Container(
                          width: 76,
                          height: 76,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: Colors.white,
                            border: Border.all(color: Colors.white70, width: 5),
                          ),
                          child: const Icon(
                            Icons.camera_alt,
                            color: Colors.black,
                            size: 32,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            )
          : const Center(child: CircularProgressIndicator()),
    );
  }

  Widget _languagePicker(
    String label,
    String value,
    ValueChanged<String?> onChanged,
  ) {
    return Row(
      children: [
        SizedBox(width: 100, child: Text(label)),
        Expanded(
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: value,
              isExpanded: true,
              dropdownColor: const Color(0xFF171C2B),
              items: _languages.entries
                  .map(
                    (language) => DropdownMenuItem(
                      value: language.key,
                      child: Text(language.value),
                    ),
                  )
                  .toList(),
              onChanged: onChanged,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildTranslationResult() {
    if (_isTranslating) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 20),
            Text('Reading and translating text…'),
          ],
        ),
      );
    }

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              _readError == null ? 'Translation' : 'Could not translate',
              style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            if (_readError == null)
              Text(
                '${_sourceLanguageName ?? _languages[_sourceLanguageCode] ?? 'Source'} · ${_targetLanguageName ?? _languages[_targetLanguageCode]}',
                style: const TextStyle(color: Colors.white70),
              ),
            const SizedBox(height: 16),
            Expanded(
              child: SingleChildScrollView(
                child: _readError != null
                    ? Text(
                        _readError!,
                        style: const TextStyle(fontSize: 18, height: 1.5),
                      )
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _TranslationTextCard(
                            title: 'Original text',
                            text: _extractedText ?? '',
                          ),
                          const SizedBox(height: 14),
                          _TranslationTextCard(
                            title: _targetLanguageName ?? 'Translation',
                            text: _translatedText ?? '',
                            emphasized: true,
                          ),
                        ],
                      ),
              ),
            ),
            if (_translatedText != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: FilledButton.icon(
                  onPressed: () => _toggleReadAloud(
                    _translatedText!,
                    speechLanguageCode: _targetLanguageCode,
                  ),
                  icon: Icon(
                    _isSpeaking ? Icons.stop_rounded : Icons.volume_up_rounded,
                  ),
                  label: Text(
                    _isSpeaking ? 'Stop reading' : 'Read translation aloud',
                  ),
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(54),
                  ),
                ),
              ),
            FilledButton.icon(
              onPressed: () => setState(() {
                _readError = null;
                _extractedText = null;
                _translatedText = null;
              }),
              icon: const Icon(Icons.camera_alt),
              label: const Text('Scan another text'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildReadResult() {
    if (_isReadingText) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 20),
            Text('Uploading image and reading text…'),
          ],
        ),
      );
    }

    final text = _extractedText;
    final hasText = text != null && text.trim().isNotEmpty;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              widget.demoText == null ? 'Recognized text' : 'Sample text demo',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),
            if (widget.demoText != null) ...[
              const SizedBox(height: 12),
              const Text(
                'Demo content only. This sample was not captured or processed by Textract.',
                style: TextStyle(fontSize: 14, color: Colors.white70),
              ),
            ],
            const SizedBox(height: 16),
            Expanded(
              child: SingleChildScrollView(
                child: SelectableText(
                  _readError ?? (text!.isEmpty ? 'No text was found.' : text),
                  style: const TextStyle(fontSize: 20, height: 1.5),
                ),
              ),
            ),
            if (hasText)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: FilledButton.icon(
                  onPressed: () => _toggleReadAloud(text),
                  icon: Icon(
                    _isSpeaking ? Icons.stop_rounded : Icons.volume_up_rounded,
                  ),
                  label: Text(_isSpeaking ? 'Stop reading' : 'Read aloud'),
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(54),
                  ),
                ),
              ),
            if (_readError != null)
              FilledButton.icon(
                onPressed: () => setState(() {
                  _readError = null;
                  _extractedText = null;
                }),
                icon: const Icon(Icons.camera_alt),
                label: const Text('Try again'),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildDescriptionResult() {
    if (_isDescribing) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 20),
            Semantics(
              liveRegion: true,
              child: Text(
                widget.mode == 'Find Item'
                    ? 'Photo captured. Checking for ${widget.targetItem ?? 'the item'}…'
                    : 'Uploading photo and identifying objects…',
              ),
            ),
          ],
        ),
      );
    }

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              _readError == null
                  ? widget.mode == 'Find Item'
                        ? 'Item check'
                        : 'What Ava noticed'
                  : 'Could not describe image',
              style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: SingleChildScrollView(
                child: _readError != null
                    ? Text(
                        _readError!,
                        style: const TextStyle(fontSize: 18, height: 1.5),
                      )
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            _sceneDescription ?? '',
                            style: const TextStyle(fontSize: 20, height: 1.5),
                          ),
                          if (_sceneLabels.isNotEmpty) ...[
                            const SizedBox(height: 20),
                            const Text(
                              'Detected labels',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: _sceneLabels
                                  .map((label) => Chip(label: Text(label)))
                                  .toList(),
                            ),
                            const SizedBox(height: 14),
                            const Text(
                              'These are AI-detected labels and may miss details. Ava does not identify people.',
                              style: TextStyle(
                                color: Colors.white70,
                                fontSize: 13,
                                height: 1.4,
                              ),
                            ),
                          ],
                          if (widget.mode == 'Find Item') ...[
                            const SizedBox(height: 12),
                            const Text(
                              'The position is approximate and based on one photo. Ava may miss the item or mistake another object for it.',
                              style: TextStyle(
                                color: Colors.white70,
                                fontSize: 13,
                                height: 1.4,
                              ),
                            ),
                          ],
                        ],
                      ),
              ),
            ),
            if (_sceneDescription != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: FilledButton.icon(
                  onPressed: () => _toggleReadAloud(_sceneDescription!),
                  icon: Icon(
                    _isSpeaking ? Icons.stop_rounded : Icons.volume_up_rounded,
                  ),
                  label: Text(
                    _isSpeaking ? 'Stop reading' : 'Read description aloud',
                  ),
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(54),
                  ),
                ),
              ),
            FilledButton.icon(
              onPressed: () => setState(() {
                _readError = null;
                _sceneDescription = null;
                _sceneLabels = [];
              }),
              icon: const Icon(Icons.camera_alt),
              label: Text(
                widget.mode == 'Find Item'
                    ? 'Scan another area'
                    : 'Describe another photo',
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TranslationTextCard extends StatelessWidget {
  final String title;
  final String text;
  final bool emphasized;

  const _TranslationTextCard({
    required this.title,
    required this.text,
    this.emphasized = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: emphasized ? const Color(0xFF292651) : const Color(0xFF1D2332),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: emphasized ? const Color(0xFF7B70D8) : const Color(0xFF343C4D),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(color: Colors.white70, fontSize: 14),
          ),
          const SizedBox(height: 8),
          SelectableText(
            text,
            style: const TextStyle(fontSize: 19, height: 1.45),
          ),
        ],
      ),
    );
  }
}

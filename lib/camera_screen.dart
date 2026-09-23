import 'dart:async';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';

import 'read_text_service.dart';

class CameraScreen extends StatefulWidget {
  final String mode;
  final String? demoText;

  const CameraScreen({super.key, required this.mode, this.demoText});

  @override
  State<CameraScreen> createState() => _CameraScreenState();
}

class _CameraScreenState extends State<CameraScreen> {
  final FlutterTts _textToSpeech = FlutterTts();
  CameraController? _controller;
  List<CameraDescription> _cameras = [];

  bool _isInitialized = false;
  bool _isReadingText = false;
  bool _isTranslating = false;
  bool _isSpeaking = false;
  String? _extractedText;
  String? _translatedText;
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
      await _textToSpeech.setLanguage(_speechLocale(speechLanguageCode));
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
          : _extractedText != null || _readError != null || _isReadingText
          ? _buildReadResult()
          : _isInitialized && _controller != null
          ? Stack(
              fit: StackFit.expand,
              children: [
                CameraPreview(_controller!),

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
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 20),
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

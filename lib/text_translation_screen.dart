import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;

import 'ava_theme.dart';
import 'languages.dart';
import 'read_text_service.dart';
import 'speech_output.dart';

class TextTranslationScreen extends StatefulWidget {
  const TextTranslationScreen({super.key});

  @override
  State<TextTranslationScreen> createState() => _TextTranslationScreenState();
}

class _TextTranslationScreenState extends State<TextTranslationScreen> {
  final _input = TextEditingController();
  final _speech = stt.SpeechToText();
  final _tts = FlutterTts();
  String _sourceCode = 'en';
  String _targetCode = 'hi';
  String? _translatedText;
  bool _busy = false;
  bool _listening = false;
  bool _speaking = false;

  @override
  void dispose() {
    unawaited(_speech.stop());
    unawaited(_tts.stop());
    _input.dispose();
    super.dispose();
  }

  void _message(String text) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _dictate() async {
    if (_listening) {
      await _speech.stop();
      if (mounted) setState(() => _listening = false);
      return;
    }

    try {
      final available = await _speech.initialize(
        onStatus: (status) {
          if ((status == 'done' || status == 'notListening') && mounted) {
            setState(() => _listening = false);
          }
        },
        onError: (_) {
          if (mounted) setState(() => _listening = false);
        },
      );
      if (!available) {
        _message('Voice input is unavailable. Type or paste your message.');
        return;
      }

      final locales = await _speech.locales();
      final preferredLocale = avaSpeechLocales[_sourceCode]!
          .toLowerCase()
          .replaceAll('-', '_');
      final languagePrefix = _sourceCode.toLowerCase();
      stt.LocaleName? locale;
      for (final candidate in locales) {
        final candidateId = candidate.localeId.toLowerCase().replaceAll(
          '-',
          '_',
        );
        if (candidateId == preferredLocale) {
          locale = candidate;
          break;
        }
        if (locale == null &&
            (candidateId == languagePrefix ||
                candidateId.startsWith('${languagePrefix}_'))) {
          locale = candidate;
        }
      }
      if (locale == null) {
        _message(
          'This device has no ${avaTranslationLanguages[_sourceCode]} speech input voice. You can type or paste text instead.',
        );
        return;
      }

      if (mounted) setState(() => _listening = true);
      await _speech.listen(
        listenOptions: stt.SpeechListenOptions(
          localeId: locale.localeId,
          listenFor: const Duration(seconds: 45),
          partialResults: true,
        ),
        onResult: (result) {
          if (!mounted) return;
          setState(() {
            _input.text = result.recognizedWords;
            _input.selection = TextSelection.collapsed(
              offset: _input.text.length,
            );
            _translatedText = null;
            if (result.finalResult) _listening = false;
          });
        },
      );
    } catch (_) {
      if (mounted) setState(() => _listening = false);
      _message('Voice input did not start. Type or paste your message.');
    }
  }

  Future<void> _translate() async {
    final text = _input.text.trim();
    if (text.isEmpty) {
      _message('Type, paste, or dictate a message first.');
      return;
    }
    if (text.length > 5000) {
      _message('Messages can be up to 5,000 characters.');
      return;
    }

    setState(() {
      _busy = true;
      _translatedText = null;
    });
    try {
      final result = await TranslationService().translateText(
        text: text,
        sourceLanguageCode: _sourceCode,
        targetLanguageCode: _targetCode,
      );
      if (mounted) setState(() => _translatedText = result['translatedText']);
    } catch (error) {
      if (mounted) {
        _message(error.toString().replaceFirst('Exception: ', ''));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _readTranslation() async {
    final text = _translatedText;
    if (text == null || text.isEmpty) return;
    if (_speaking) {
      await _tts.stop();
      if (mounted) setState(() => _speaking = false);
      return;
    }

    try {
      await configureSpeechOutput(_tts);
      final locale = avaSpeechLocales[_targetCode] ?? 'en-US';
      if (await _tts.isLanguageAvailable(locale) != true) {
        _message(
          '${avaTranslationLanguages[_targetCode]} is shown as text, but this device does not have a matching read-aloud voice installed.',
        );
        return;
      }
      await _tts.setLanguage(locale);
      await _tts.setSpeechRate(0.44);
      await _tts.setVolume(1);
      await _tts.awaitSpeakCompletion(true);
      if (mounted) setState(() => _speaking = true);
      await _tts.speak(text);
      if (mounted) setState(() => _speaking = false);
    } catch (_) {
      if (mounted) {
        setState(() => _speaking = false);
        _message('A read-aloud voice is not available for this language.');
      }
    }
  }

  void _swapLanguages() {
    setState(() {
      final oldSource = _sourceCode;
      _sourceCode = _targetCode;
      _targetCode = oldSource;
      _input.text = _translatedText ?? _input.text;
      _translatedText = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Translate a message')),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 680),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
              children: [
                const Text(
                  'Understand a message in your language.',
                  style: TextStyle(
                    color: AvaColors.ink,
                    fontSize: 25,
                    fontWeight: FontWeight.w700,
                    height: 1.2,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Type, paste, or dictate text. Translation runs through Ava’s secure AWS service; no AWS keys are stored on this device.',
                  style: TextStyle(
                    color: AvaColors.muted,
                    fontSize: 15,
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: 22),
                _languageDropdown(
                  label: 'Message language',
                  value: _sourceCode,
                  onChanged: (code) => setState(() {
                    _sourceCode = code!;
                    _translatedText = null;
                  }),
                ),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton.icon(
                    onPressed: _swapLanguages,
                    icon: const Icon(Icons.swap_vert_rounded),
                    label: const Text('Swap languages'),
                  ),
                ),
                _languageDropdown(
                  label: 'Translate into',
                  value: _targetCode,
                  onChanged: (code) => setState(() {
                    _targetCode = code!;
                    _translatedText = null;
                  }),
                ),
                const SizedBox(height: 18),
                TextField(
                  controller: _input,
                  minLines: 5,
                  maxLines: 9,
                  maxLength: 5000,
                  textCapitalization: TextCapitalization.sentences,
                  onChanged: (_) {
                    if (_translatedText != null) {
                      setState(() => _translatedText = null);
                    }
                  },
                  decoration: const InputDecoration(
                    labelText: 'Message to translate',
                    hintText: 'Type or paste the text here',
                    alignLabelWithHint: true,
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: _busy ? null : _dictate,
                  icon: Icon(_listening ? Icons.stop : Icons.mic_none_rounded),
                  label: Text(
                    _listening ? 'Stop dictation' : 'Dictate message',
                  ),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size.fromHeight(52),
                  ),
                ),
                const SizedBox(height: 10),
                FilledButton.icon(
                  onPressed: _busy || _listening ? null : _translate,
                  icon: _busy
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.translate_rounded),
                  label: Text(_busy ? 'Translating…' : 'Translate message'),
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(54),
                  ),
                ),
                if (_translatedText != null) ...[
                  const SizedBox(height: 22),
                  Semantics(
                    liveRegion: true,
                    label:
                        'Translation into ${avaTranslationLanguages[_targetCode]}',
                    child: Card(
                      color: AvaColors.sage,
                      child: Padding(
                        padding: const EdgeInsets.all(18),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text(
                              avaTranslationLanguages[_targetCode]!,
                              style: const TextStyle(
                                color: AvaColors.primary,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 10),
                            SelectableText(
                              _translatedText!,
                              style: const TextStyle(
                                color: AvaColors.ink,
                                fontSize: 21,
                                height: 1.5,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  OutlinedButton.icon(
                    onPressed: () => _readTranslation(),
                    icon: Icon(
                      _speaking ? Icons.stop_rounded : Icons.volume_up_rounded,
                    ),
                    label: Text(
                      _speaking ? 'Stop reading' : 'Read translation aloud',
                    ),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size.fromHeight(52),
                    ),
                  ),
                  TextButton.icon(
                    onPressed: () async {
                      await Clipboard.setData(
                        ClipboardData(text: _translatedText!),
                      );
                      if (mounted) _message('Translation copied.');
                    },
                    icon: const Icon(Icons.copy_rounded),
                    label: const Text('Copy translation'),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _languageDropdown({
    required String label,
    required String value,
    required ValueChanged<String?> onChanged,
  }) {
    return DropdownButtonFormField<String>(
      key: ValueKey('$label-$value'),
      initialValue: value,
      isExpanded: true,
      decoration: InputDecoration(labelText: label),
      items: avaTranslationLanguages.entries
          .map(
            (language) => DropdownMenuItem(
              value: language.key,
              child: Text(language.value),
            ),
          )
          .toList(),
      onChanged: onChanged,
    );
  }
}

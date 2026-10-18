import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;

import 'item_memory_service.dart';
import 'speech_output.dart';
import 'ava_theme.dart';

class ItemMemoryScreen extends StatefulWidget {
  final String initialAction;
  final String initialItem;
  final String initialLocation;

  const ItemMemoryScreen({
    super.key,
    this.initialAction = 'remember',
    this.initialItem = '',
    this.initialLocation = '',
  });

  @override
  State<ItemMemoryScreen> createState() => _ItemMemoryScreenState();
}

class _ItemMemoryScreenState extends State<ItemMemoryScreen> {
  final _itemController = TextEditingController();
  final _locationController = TextEditingController();
  final _speech = stt.SpeechToText();
  final _tts = FlutterTts();
  bool _busy = false;
  bool _listening = false;
  String? _result;
  bool _showForget = false;

  @override
  void initState() {
    super.initState();
    _itemController.text = widget.initialItem;
    _locationController.text = widget.initialLocation;
    if (widget.initialAction == 'recall' && widget.initialItem.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _recall());
    } else if (widget.initialItem.isNotEmpty &&
        widget.initialLocation.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _announce(
          'I heard ${widget.initialItem} in ${widget.initialLocation}. Check it, then save.',
        ),
      );
    }
  }

  @override
  void dispose() {
    unawaited(_speech.stop());
    unawaited(_tts.stop());
    _itemController.dispose();
    _locationController.dispose();
    super.dispose();
  }

  Future<void> _listenToMemory() async {
    if (_listening) {
      await _speech.stop();
      if (mounted) setState(() => _listening = false);
      return;
    }

    try {
      final available = await _speech.initialize(
        onStatus: (status) {
          if (status == 'done' && mounted) setState(() => _listening = false);
        },
        onError: (_) {
          if (mounted) setState(() => _listening = false);
        },
      );
      if (!available) {
        await _announce(
          'Voice input is unavailable. You can type the item and place.',
        );
        return;
      }
      await _announce('Listening. Say an item and where you put it.');
      if (mounted) setState(() => _listening = true);
      await _speech.listen(
        listenOptions: stt.SpeechListenOptions(
          listenFor: const Duration(seconds: 12),
          partialResults: false,
        ),
        onResult: (result) {
          if (!result.finalResult) return;
          final parsed = _parseMemory(result.recognizedWords);
          if (mounted) {
            setState(() {
              _listening = false;
              if (parsed != null) {
                _itemController.text = parsed.$1;
                _locationController.text = parsed.$2;
                _result = 'Check the item and place, then save your memory.';
                _showForget = false;
              } else {
                _result = 'I could not separate the item and place. Try “my keys are in the top drawer”.';
              }
            });
          }
          if (parsed == null) {
            unawaited(
              _announce(
                'I could not separate the item and place. Try saying, my keys are in the top drawer.',
              ),
            );
          } else {
            unawaited(
              _announce(
                'I heard ${parsed.$1} in ${parsed.$2}. Check it, then save.',
              ),
            );
          }
        },
      );
    } catch (_) {
      if (mounted) setState(() => _listening = false);
      await _announce(
        'Voice input did not start. You can type the item and place.',
      );
    }
  }

  (String, String)? _parseMemory(String phrase) {
    var clean = phrase.trim().replaceAll(RegExp(r'[?.!,]+$'), '');
    clean = clean.replaceFirst(
      RegExp(
        r'^(?:please\s+)?(?:remember\s+that\s+|remember\s+|note\s+that\s+)',
        caseSensitive: false,
      ),
      '',
    );
    clean = clean.replaceFirst(
      RegExp(
        r'^(?:i\s+(?:put|left|placed|keep|store)\s+)',
        caseSensitive: false,
      ),
      '',
    );
    final match = RegExp(
      r'^(.+?)\s+(?:(?:is|are|was|were)\s+)?(?:in|on|at|inside|near|by)\s+(.+)$',
      caseSensitive: false,
    ).firstMatch(clean);
    if (match == null) return null;
    final item = match
        .group(1)!
        .trim()
        .replaceFirst(RegExp(r'^(?:my|the|a|an)\s+', caseSensitive: false), '');
    final place = match.group(2)!.trim();
    if (item.isEmpty ||
        place.isEmpty ||
        item.length > 80 ||
        place.length > 240) {
      return null;
    }
    return (item, place);
  }

  Future<void> _remember() async {
    final item = _itemController.text.trim();
    final location = _locationController.text.trim();
    if (item.isEmpty || location.isEmpty) {
      await _announce('Enter both the item and where you put it.');
      return;
    }
    setState(() {
      _busy = true;
      _result = null;
      _showForget = false;
    });
    try {
      await ItemMemoryService().remember(item, location);
      if (!mounted) return;
      setState(() => _result = 'I’ll remember that $item is in $location.');
      await _announce('I’ll remember that $item is in $location.');
    } catch (error) {
      if (!mounted) return;
      final message = error.toString().replaceFirst('Exception: ', '');
      setState(() => _result = 'Could not save: $message');
      await _announce('I could not save that memory. $message');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _recall() async {
    final item = _itemController.text.trim();
    if (item.isEmpty) {
      await _announce('Enter the name of the item you want to find.');
      return;
    }
    setState(() {
      _busy = true;
      _result = null;
      _showForget = false;
    });
    try {
      final result = await ItemMemoryService().recall(item);
      if (!mounted) return;
      if (result['found'] == true) {
        final savedItem = result['itemName'] as String? ?? item;
        final location = result['location'] as String? ?? '';
        final sentence = 'You last told Ava that $savedItem is in $location.';
        setState(() {
          _itemController.text = savedItem;
          _locationController.text = location;
          _result = sentence;
          _showForget = true;
        });
        await _announce(
          '$sentence This is a saved memory, not a live camera check.',
        );
      } else {
        setState(() => _result = 'I do not have a saved place for $item yet.');
        await _announce('I do not have a saved place for $item yet.');
      }
    } catch (error) {
      if (!mounted) return;
      final message = error.toString().replaceFirst('Exception: ', '');
      setState(() => _result = 'Could not look that up: $message');
      await _announce('I could not look that up. $message');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _forget() async {
    final item = _itemController.text.trim();
    if (item.isEmpty) return;
    setState(() {
      _busy = true;
      _result = null;
    });
    try {
      await ItemMemoryService().forget(item);
      if (!mounted) return;
      setState(() {
        _locationController.clear();
        _showForget = false;
        _result = 'I forgot the saved place for $item.';
      });
      await _announce('I forgot the saved place for $item.');
    } catch (error) {
      if (!mounted) return;
      setState(() => _result = 'Could not delete that memory: $error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _announce(String text) async {
    try {
      await configureSpeechOutput(_tts);
      await _tts.setSpeechRate(0.44);
      await _tts.awaitSpeakCompletion(true);
      await _tts.speak(text);
    } catch (_) {
      // The on-screen status remains available if device speech is unavailable.
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Remember an item')),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
              children: [
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(18),
                    child: const Text(
                      'Tell Ava where you put something. Later, ask “Where are my keys?” Ava will recall the place you saved.',
                      style: TextStyle(
                        color: AvaColors.ink,
                        fontSize: 17,
                        height: 1.5,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                OutlinedButton.icon(
                  onPressed: _busy ? null : _listenToMemory,
                  icon: Icon(
                    _listening ? Icons.stop_rounded : Icons.mic_rounded,
                  ),
                  label: Text(
                    _listening ? 'Stop listening' : 'Speak item and place',
                  ),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size.fromHeight(58),
                  ),
                ),
                const SizedBox(height: 18),
                TextField(
                  controller: _itemController,
                  textCapitalization: TextCapitalization.sentences,
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(
                    labelText: 'What item?',
                    hintText: 'For example, keys',
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _locationController,
                  textCapitalization: TextCapitalization.sentences,
                  textInputAction: TextInputAction.done,
                  onSubmitted: (_) => _remember(),
                  decoration: const InputDecoration(
                    labelText: 'Where did you put it?',
                    hintText: 'For example, top drawer by the door',
                  ),
                ),
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: _busy ? null : _remember,
                  icon: const Icon(Icons.bookmark_add_outlined),
                  label: const Text('Save this place'),
                ),
                const SizedBox(height: 10),
                FilledButton.tonalIcon(
                  onPressed: _busy ? null : _recall,
                  icon: const Icon(Icons.search_rounded),
                  label: const Text('Where is it?'),
                ),
                if (_showForget) ...[
                  const SizedBox(height: 10),
                  TextButton.icon(
                    onPressed: _busy ? null : _forget,
                    icon: const Icon(Icons.delete_outline_rounded),
                    label: const Text('Forget this saved place'),
                  ),
                ],
                if (_busy) ...[
                  const SizedBox(height: 20),
                  const Center(child: CircularProgressIndicator()),
                ],
                if (_result != null) ...[
                  const SizedBox(height: 18),
                  Semantics(
                    liveRegion: true,
                    child: Card(
                      color: AvaColors.sage,
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Text(
                          _result!,
                          style: const TextStyle(
                            color: AvaColors.ink,
                            fontSize: 17,
                            height: 1.5,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 22),
                const Text(
                  'Saved places are tied to your Ava account. Ava recalls what you saved; it does not verify the item’s current location.',
                  style: TextStyle(
                    color: AvaColors.muted,
                    fontSize: 14,
                    height: 1.5,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

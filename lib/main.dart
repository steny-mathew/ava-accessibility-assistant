import 'dart:async';

import 'package:flutter/material.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;

import 'auth_screen.dart';
import 'camera_screen.dart';
import 'item_memory_screen.dart';
import 'read_text_service.dart';
import 'ava_theme.dart';

void main() {
  runApp(const AvaApp());
}

class AvaApp extends StatelessWidget {
  const AvaApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Ava',
      theme: buildAvaTheme(),
      home: AuthGate(
        signedInBuilder: (onSignOut) => AvaHomePage(onSignOut: onSignOut),
      ),
    );
  }
}

class AvaHomePage extends StatefulWidget {
  final VoidCallback onSignOut;

  const AvaHomePage({super.key, required this.onSignOut});

  @override
  State<AvaHomePage> createState() => _AvaHomePageState();
}

class _AvaHomePageState extends State<AvaHomePage> {
  static const _readAloudDemoText =
      'Hello, this is a sample reading from Ava. Use Read Text to scan a sign, '
      'label, or page and hear the words aloud. You can stop the reading at any time.';

  final stt.SpeechToText _speech = stt.SpeechToText();

  bool _isListening = false;
  bool _isSendingEmergencyAlert = false;
  String _spokenText = '';

  Future<void> _listen() async {
    if (_isListening) {
      await _speech.stop();
      if (mounted) setState(() => _isListening = false);
      return;
    }

    try {
      final available = await _speech.initialize(
        onStatus: (status) {
          if (status == 'done' && mounted) {
            setState(() => _isListening = false);
          }
        },
        onError: (_) {
          if (mounted) setState(() => _isListening = false);
        },
      );

      if (!mounted) return;
      if (!available) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Voice input is unavailable. Choose a tool below.'),
          ),
        );
        return;
      }

      setState(() {
        _isListening = true;
        _spokenText = '';
      });
      await _speech.listen(
        listenOptions: stt.SpeechListenOptions(
          listenFor: const Duration(seconds: 20),
        ),
        onResult: (result) {
          if (!mounted) return;
          setState(() => _spokenText = result.recognizedWords);
          if (result.finalResult && result.recognizedWords.trim().isNotEmpty) {
            unawaited(_speech.stop());
            _handleCommand(result.recognizedWords);
          }
        },
      );
    } catch (_) {
      if (!mounted) return;
      setState(() => _isListening = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Could not start voice input. You can choose a tool below.',
          ),
        ),
      );
    }
  }

  // Open the camera for a specific accessibility task.
  Future<void> _openCamera(
    String mode, {
    String? demoText,
    String? targetItem,
  }) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => CameraScreen(
          mode: mode,
          demoText: demoText,
          targetItem: targetItem,
        ),
      ),
    );
  }

  Future<void> _openItemMemory({
    String action = 'remember',
    String item = '',
    String location = '',
  }) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ItemMemoryScreen(
          initialAction: action,
          initialItem: item,
          initialLocation: location,
        ),
      ),
    );
  }

  // Understand what the user asked Ava to do.
  void _handleCommand(String command) {
    final text = command.toLowerCase();

    // Translation is checked first because
    // "translate this text" also contains "text".
    final emergencyCommand = RegExp(
      r'^(?:please\s+)?(?:help|emergency|send\s+(?:an?\s+)?emergency\s+alert|send\s+help|call\s+for\s+help|i\s+need\s+help)(?:\s+please)?[.!?]*$',
    ).hasMatch(text.trim());
    if (emergencyCommand) {
      _sendEmergencyAlert();
    } else if (_isRememberCommand(text)) {
      final memory = _parseMemoryCommand(text);
      _openItemMemory(
        action: 'remember',
        item: memory?.$1 ?? '',
        location: memory?.$2 ?? '',
      );
    } else if (_isRecallCommand(text)) {
      _openItemMemory(action: 'recall', item: _itemToRecall(text));
    } else if (text.contains('translate') || text.contains('translation')) {
      _openCamera('Translate');
    } else if (text.contains('find ') ||
        text.contains('locate ') ||
        text.contains('where is ') ||
        text.contains('where are ') ||
        text.contains('look for ')) {
      final target = _itemFromCommand(text);
      if (target.isEmpty) {
        _showMessage('What should I find?', 'Try saying “find my keys”.');
      } else {
        _openCamera('Find Item', targetItem: target);
      }
    } else if (text.contains('describe') ||
        text.contains('surroundings') ||
        text.contains('around me')) {
      _openCamera('Describe Surroundings');
    } else if (text.contains('medicine') ||
        text.contains('read') ||
        text.contains('text')) {
      _openCamera('Read Text');
    } else {
      _showMessage('I heard you', 'You said: "$command"');
    }
  }

  bool _isRememberCommand(String text) =>
      text.startsWith('remember ') ||
      text.startsWith('i put ') ||
      text.startsWith('i left ') ||
      text.startsWith('i placed ');

  bool _isRecallCommand(String text) =>
      text.contains('where did i put') ||
      text.contains('where did i leave') ||
      text.contains('where is my ') ||
      text.contains('where are my ') ||
      text.contains('where is the ') ||
      text.contains('where are the ');

  (String, String)? _parseMemoryCommand(String text) {
    var clean = text.trim().replaceAll(RegExp(r'[?.!,]+$'), '');
    clean = clean.replaceFirst(
      RegExp(
        r'^(?:please\s+)?(?:remember\s+that\s+|remember\s+)',
        caseSensitive: false,
      ),
      '',
    );
    clean = clean.replaceFirst(
      RegExp(r'^i\s+(?:put|left|placed)\s+', caseSensitive: false),
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
    final location = match.group(2)!.trim();
    if (item.isEmpty ||
        location.isEmpty ||
        item.length > 80 ||
        location.length > 240) {
      return null;
    }
    return (item, location);
  }

  String _itemToRecall(String text) {
    final match = RegExp(
      r'\b(?:where\s+(?:is|are)|where\s+did\s+i\s+(?:put|leave))\s+(?:my|the)\s+(.+)$',
    ).firstMatch(text);
    final item = (match?.group(1) ?? '')
        .replaceAll(RegExp(r'[?.!,]+$'), '')
        .trim();
    return item.length > 80 ? item.substring(0, 80).trim() : item;
  }

  String _itemFromCommand(String command) {
    final match = RegExp(
      r'\b(?:find|locate|look for)\s+(?:(?:me|my)\s+)?(.+)$|\bwhere\s+(?:is|are)\s+(?:my\s+)?(.+)$',
    ).firstMatch(command);
    final target = (match?.group(1) ?? match?.group(2) ?? '')
        .replaceAll(RegExp(r'[?.!,]+$'), '')
        .trim();
    return target.length > 80 ? target.substring(0, 80).trim() : target;
  }

  Future<void> _askWhatToFind() async {
    final controller = TextEditingController();
    final item = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('What should Ava look for?'),
        content: TextField(
          controller: controller,
          autofocus: true,
          textCapitalization: TextCapitalization.sentences,
          textInputAction: TextInputAction.done,
          onSubmitted: (value) => Navigator.pop(context, value.trim()),
          decoration: const InputDecoration(
            hintText: 'For example, water bottle',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('Continue'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (!mounted || item == null || item.isEmpty) return;
    await _openCamera('Find Item', targetItem: item);
  }

  Future<void> _sendEmergencyAlert() async {
    if (_isSendingEmergencyAlert) return;

    final shouldSend = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Send emergency email?'),
        content: const Text(
          'Ava will email your confirmed alert address. This does not contact '
          'emergency services or share your location.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.pop(context, true),
            icon: const Icon(Icons.email_outlined),
            label: const Text('Send email'),
          ),
        ],
      ),
    );
    if (shouldSend != true || !mounted) return;

    setState(() => _isSendingEmergencyAlert = true);
    try {
      await EmergencyAlertService().sendAlert();
      if (mounted) {
        _showMessage(
          'Email alert sent',
          'SNS accepted the emergency alert for delivery. This does not '
              'contact emergency services.',
        );
      }
    } catch (error) {
      if (mounted) {
        _showMessage(
          'Could not send alert',
          error.toString().replaceFirst('Exception: ', ''),
        );
      }
    } finally {
      if (mounted) setState(() => _isSendingEmergencyAlert = false);
    }
  }

  // Display a message to the user.
  void _showMessage(String title, String message) {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(title),
          content: Text(message),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(context);
              },
              child: const Text('OK'),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
              children: [
                _buildHeader(),
                const SizedBox(height: 30),
                Text(
                  _isListening ? 'I’m listening.' : 'How can Ava help today?',
                  style: const TextStyle(
                    color: AvaColors.ink,
                    fontSize: 29,
                    height: 1.15,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.6,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  _isListening
                      ? 'Say what you need in your own words.'
                      : 'Choose a tool, or speak to Ava.',
                  style: const TextStyle(
                    color: AvaColors.muted,
                    fontSize: 16,
                    height: 1.45,
                  ),
                ),
                const SizedBox(height: 20),
                _buildVoiceCard(),
                const SizedBox(height: 30),
                const _SectionHeading(
                  title: 'Your tools',
                  subtitle: 'Practical help, one step at a time',
                ),
                const SizedBox(height: 14),
                _ActionCard(
                  icon: Icons.document_scanner_outlined,
                  title: 'Read printed text',
                  description: 'Scan a label, sign, or page and hear it aloud.',
                  accent: AvaColors.primary,
                  onTap: () => _openCamera('Read Text'),
                ),
                const SizedBox(height: 10),
                _ActionCard(
                  icon: Icons.translate_outlined,
                  title: 'Translate text',
                  description:
                      'Capture text and translate it into another language.',
                  accent: AvaColors.amber,
                  onTap: () => _openCamera('Translate'),
                ),
                const SizedBox(height: 10),
                _ActionCard(
                  icon: Icons.visibility_outlined,
                  title: 'Describe surroundings',
                  description:
                      'Hear a short summary of objects Ava recognizes.',
                  accent: const Color(0xFF386E68),
                  onTap: () => _openCamera('Describe Surroundings'),
                ),
                const SizedBox(height: 10),
                _ActionCard(
                  icon: Icons.search_rounded,
                  title: 'Find an item',
                  description: 'Ask Ava to look for something in a photo.',
                  accent: const Color(0xFF526D47),
                  onTap: _askWhatToFind,
                ),
                const SizedBox(height: 10),
                _ActionCard(
                  icon: Icons.bookmark_add_outlined,
                  title: 'Remember an item',
                  description:
                      'Save where you put something and ask Ava later.',
                  accent: AvaColors.amber,
                  onTap: () => _openItemMemory(),
                ),
                const SizedBox(height: 18),
                _buildDemoCard(),
                const SizedBox(height: 24),
                OutlinedButton.icon(
                  onPressed: _isSendingEmergencyAlert
                      ? null
                      : _sendEmergencyAlert,
                  icon: _isSendingEmergencyAlert
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.emergency_outlined),
                  label: Text(
                    _isSendingEmergencyAlert
                        ? 'Sending email alert…'
                        : 'Send emergency email',
                  ),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AvaColors.danger,
                    side: const BorderSide(color: AvaColors.danger),
                    minimumSize: const Size.fromHeight(54),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
                const Padding(
                  padding: EdgeInsets.fromLTRB(8, 8, 8, 0),
                  child: Text(
                    'This sends an email alert. It does not contact emergency services.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: AvaColors.muted,
                      fontSize: 13,
                      height: 1.4,
                    ),
                  ),
                ),
                const SizedBox(height: 22),
                const Text(
                  'Camera results can miss details and are not navigation guidance.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AvaColors.muted, fontSize: 13),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Row(
      children: [
        Container(
          width: 46,
          height: 46,
          decoration: BoxDecoration(
            color: AvaColors.sage,
            borderRadius: BorderRadius.circular(14),
          ),
          child: const Icon(Icons.spa_outlined, color: AvaColors.primary),
        ),
        const SizedBox(width: 12),
        const Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Ava',
                style: TextStyle(
                  color: AvaColors.ink,
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.4,
                ),
              ),
              SizedBox(height: 2),
              Text(
                'ACCESSIBILITY COMPANION',
                style: TextStyle(
                  color: AvaColors.muted,
                  fontSize: 10,
                  letterSpacing: 1,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
        IconButton(
          onPressed: widget.onSignOut,
          tooltip: 'Sign out',
          icon: const Icon(Icons.logout_rounded),
        ),
      ],
    );
  }

  Widget _buildVoiceCard() {
    return Card(
      color: _isListening ? AvaColors.primaryPressed : AvaColors.primary,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _isListening ? 'Listening now' : 'Speak to Ava',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        _isListening
                            ? 'Try “read this”, “remember my keys in the drawer”, or “where are my keys?”.'
                            : 'Tap the microphone and say what you need.',
                        style: const TextStyle(
                          color: Color(0xFFE8F1EB),
                          fontSize: 15,
                          height: 1.45,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 14),
                IconButton.filledTonal(
                  onPressed: _listen,
                  tooltip: _isListening ? 'Stop listening' : 'Speak to Ava',
                  style: IconButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: AvaColors.primary,
                    minimumSize: const Size(64, 64),
                  ),
                  icon: Icon(
                    _isListening ? Icons.stop_rounded : Icons.mic_rounded,
                    size: 30,
                  ),
                ),
              ],
            ),
            if (_spokenText.isNotEmpty) ...[
              const SizedBox(height: 16),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFF194638),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '“$_spokenText”',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    height: 1.45,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildDemoCard() {
    return Card(
      child: InkWell(
        onTap: () => _openCamera('Read Text', demoText: _readAloudDemoText),
        borderRadius: BorderRadius.circular(16),
        child: const ListTile(
          contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          leading: Icon(Icons.volume_up_outlined, color: AvaColors.primary),
          title: Text('Hear a sample'),
          subtitle: Text('A short read-aloud demonstration'),
          trailing: Icon(Icons.chevron_right_rounded, color: AvaColors.muted),
        ),
      ),
    );
  }
}

class _SectionHeading extends StatelessWidget {
  final String title;
  final String subtitle;

  const _SectionHeading({required this.title, required this.subtitle});

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        title,
        style: const TextStyle(
          color: AvaColors.ink,
          fontSize: 20,
          fontWeight: FontWeight.w700,
        ),
      ),
      const SizedBox(height: 3),
      Text(
        subtitle,
        style: const TextStyle(color: AvaColors.muted, fontSize: 14),
      ),
    ],
  );
}

class _ActionCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String description;
  final Color accent;
  final VoidCallback onTap;

  const _ActionCard({
    required this.icon,
    required this.title,
    required this.description,
    required this.accent,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(14);
    return Semantics(
      button: true,
      label: '$title. $description',
      onTap: onTap,
      child: ExcludeSemantics(
        child: Material(
          color: Colors.transparent,
          borderRadius: radius,
          child: Ink(
            decoration: BoxDecoration(
              borderRadius: radius,
              color: AvaColors.surface,
              border: Border.all(color: AvaColors.border),
            ),
            child: InkWell(
              onTap: onTap,
              borderRadius: radius,
              child: Padding(
                padding: const EdgeInsets.all(15),
                child: Row(
                  children: [
                    Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: accent.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(icon, color: accent, size: 25),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            title,
                            style: const TextStyle(
                              color: AvaColors.ink,
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            description,
                            style: const TextStyle(
                              color: AvaColors.muted,
                              fontSize: 14,
                              height: 1.4,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    const Icon(
                      Icons.chevron_right_rounded,
                      color: AvaColors.muted,
                      size: 20,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

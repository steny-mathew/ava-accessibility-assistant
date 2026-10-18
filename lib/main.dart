import 'package:flutter/material.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;

import 'auth_screen.dart';
import 'camera_screen.dart';
import 'item_memory_screen.dart';
import 'read_text_service.dart';

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
      theme: ThemeData(
        brightness: Brightness.dark,
        useMaterial3: true,
        scaffoldBackgroundColor: const Color(0xFF080C16),
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF8B83FF),
          brightness: Brightness.dark,
        ),
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            minimumSize: const Size(48, 56),
            textStyle: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(18),
            ),
          ),
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF080C16),
          foregroundColor: Colors.white,
          surfaceTintColor: Colors.transparent,
        ),
      ),
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
      'Hello, this is a sample reading from Ava. When text recognition is connected, '
      'Ava can read signs, labels, and printed instructions aloud. You can stop the '
      'reading at any time using the button below.';

  final stt.SpeechToText _speech = stt.SpeechToText();

  bool _isListening = false;
  bool _isSendingEmergencyAlert = false;
  String _spokenText = '';

  Future<void> _listen() async {
    if (!_isListening) {
      final available = await _speech.initialize(
        onStatus: (status) {
          if (status == 'done') {
            setState(() {
              _isListening = false;
            });
          }
        },
        onError: (error) {
          setState(() {
            _isListening = false;
          });
        },
      );

      if (available) {
        setState(() {
          _isListening = true;
          _spokenText = '';
        });

        await _speech.listen(
          onResult: (result) {
            setState(() {
              _spokenText = result.recognizedWords;
            });

            if (result.finalResult && result.recognizedWords.isNotEmpty) {
              _handleCommand(result.recognizedWords);
            }
          },
        );
      }
    } else {
      await _speech.stop();

      setState(() {
        _isListening = false;
      });
    }
  }

  // Open the camera for a specific accessibility task.
  Future<void> _openCamera(
    String mode, {
    String? demoText,
    String? targetItem,
  }) async {
    final imagePath = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => CameraScreen(
          mode: mode,
          demoText: demoText,
          targetItem: targetItem,
        ),
      ),
    );

    if (imagePath != null) {
      _showMessage(
        '$mode Image Captured',
        'Image captured successfully.\n\nPath: $imagePath',
      );
    }
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
    if (text.contains('emergency') || text.contains('help')) {
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
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF12172B), Color(0xFF090D17), Color(0xFF080C16)],
          ),
        ),
        child: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) => Align(
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 640),
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(20, 14, 20, 32),
                  children: [
                    _buildHeader(),
                    const SizedBox(height: 22),
                    _buildWelcomeCard(),
                    const SizedBox(height: 14),
                    _buildVoiceCard(),
                    const SizedBox(height: 30),
                    const _SectionHeading(
                      title: 'Choose a tool',
                      subtitle: 'Tap a card or ask Ava by voice',
                    ),
                    const SizedBox(height: 14),
                    _ActionCard(
                      icon: Icons.bookmark_add_outlined,
                      title: 'Remember an item',
                      description:
                          'Save where you put something and ask Ava later.',
                      accent: const Color(0xFFFFC48A),
                      onTap: () => _openItemMemory(),
                    ),
                    const SizedBox(height: 12),
                    _ActionCard(
                      icon: Icons.document_scanner_rounded,
                      title: 'Read printed text',
                      description:
                          'Scan a label, sign, or page and hear it aloud.',
                      accent: const Color(0xFFB7AEFF),
                      gradient: const [Color(0xFF34306A), Color(0xFF211F48)],
                      onTap: () => _openCamera('Read Text'),
                    ),
                    const SizedBox(height: 12),
                    _ActionCard(
                      icon: Icons.search_rounded,
                      title: 'Find an item',
                      description:
                          'Ask Ava to look for something in a camera photo.',
                      accent: const Color(0xFFFFC48A),
                      onTap: _askWhatToFind,
                    ),
                    const SizedBox(height: 12),
                    _ActionCard(
                      icon: Icons.visibility_rounded,
                      title: 'Describe surroundings',
                      description:
                          'Hear a short summary of objects Ava recognizes.',
                      accent: const Color(0xFF8CE6D2),
                      onTap: () => _openCamera('Describe Surroundings'),
                    ),
                    const SizedBox(height: 12),
                    _ActionCard(
                      icon: Icons.translate_rounded,
                      title: 'Translate text',
                      description: 'Capture printed text for translation.',
                      accent: const Color(0xFFFFD18A),
                      onTap: () => _openCamera('Translate'),
                    ),
                    const SizedBox(height: 20),
                    _buildDemoCard(),
                    const SizedBox(height: 12),
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
                          : const Icon(Icons.emergency_rounded),
                      label: Text(
                        _isSendingEmergencyAlert
                            ? 'Sending email alert…'
                            : 'Send emergency email',
                      ),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFFFF9B9B),
                        side: const BorderSide(color: Color(0xFF733E50)),
                        minimumSize: const Size.fromHeight(58),
                        textStyle: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(18),
                        ),
                      ),
                    ),
                    const Padding(
                      padding: EdgeInsets.fromLTRB(8, 8, 8, 0),
                      child: Text(
                        'This sends an email alert. It does not contact emergency services.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Color(0xFFD5DAE8),
                          fontSize: 13,
                          height: 1.4,
                        ),
                      ),
                    ),
                    const SizedBox(height: 22),
                    const Center(
                      child: Text(
                        'Camera results can miss details and are not navigation guidance.',
                        style: TextStyle(
                          color: Color(0xFF778198),
                          fontSize: 13,
                        ),
                      ),
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

  Widget _buildWelcomeCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF292851), Color(0xFF171D34)],
        ),
        border: Border.all(color: const Color(0xFF45416F)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _isListening ? 'I’m listening' : 'How can I help?',
                  style: const TextStyle(
                    fontSize: 28,
                    height: 1.15,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.4,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  _isListening
                      ? 'Tell me what you need, in your own words.'
                      : 'Use your voice or choose one of the tools below.',
                  style: const TextStyle(
                    fontSize: 16,
                    height: 1.45,
                    color: Color(0xFFE0E2F0),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 14),
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: const Color(0xFFB2A8FF).withValues(alpha: 0.16),
              border: Border.all(color: const Color(0xFF9D91FF)),
            ),
            child: const Icon(
              Icons.auto_awesome_rounded,
              color: Color(0xFFD1CAFF),
              size: 28,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Row(
      children: [
        Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF9B8BFF), Color(0xFF6657D9)],
            ),
            boxShadow: const [
              BoxShadow(
                color: Color(0x446C63FF),
                blurRadius: 20,
                offset: Offset(0, 8),
              ),
            ],
          ),
          child: const Icon(Icons.auto_awesome_rounded, color: Colors.white),
        ),
        const SizedBox(width: 12),
        const Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'AVA',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 2.5,
                ),
              ),
              SizedBox(height: 2),
              Text(
                'ACCESSIBILITY ASSISTANT',
                style: TextStyle(
                  color: Color(0xFFAAB4C9),
                  fontSize: 10,
                  letterSpacing: 1.1,
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
    final accent = _isListening
        ? const Color(0xFFFF858F)
        : const Color(0xFFB5ADFF);
    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(26),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF242746), Color(0xFF181C31)],
        ),
        border: Border.all(
          color: _isListening
              ? const Color(0xFFFF858F)
              : const Color(0xFF454B70),
          width: _isListening ? 1.6 : 1,
        ),
        boxShadow: _isListening
            ? const [
                BoxShadow(
                  color: Color(0x337E617E),
                  blurRadius: 22,
                  spreadRadius: 1,
                ),
              ]
            : const [],
      ),
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
                        color: Color(0xFFE0E2F0),
                        fontSize: 15,
                        height: 1.45,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 14),
              Semantics(
                button: true,
                label: _isListening ? 'Stop listening to Ava' : 'Talk to Ava',
                onTap: _listen,
                child: Material(
                  color: accent.withValues(alpha: 0.16),
                  shape: const CircleBorder(),
                  child: InkWell(
                    onTap: _listen,
                    customBorder: const CircleBorder(),
                    child: SizedBox(
                      width: 76,
                      height: 76,
                      child: Icon(
                        _isListening ? Icons.stop_rounded : Icons.mic_rounded,
                        color: accent,
                        size: 32,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
          if (_spokenText.isNotEmpty) ...[
            const SizedBox(height: 16),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: const Color(0xFF101526),
                borderRadius: BorderRadius.circular(15),
              ),
              child: Text(
                '“$_spokenText”',
                style: const TextStyle(fontSize: 16, height: 1.45),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildDemoCard() {
    return Material(
      color: const Color(0xFF131B2B),
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        onTap: () => _openCamera('Read Text', demoText: _readAloudDemoText),
        borderRadius: BorderRadius.circular(18),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
          child: Row(
            children: [
              const Icon(Icons.volume_up_rounded, color: Color(0xFFB5ADFF)),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Try the read-aloud demo',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                    SizedBox(height: 3),
                    Text(
                      'Hear Ava speak sample text',
                      style: TextStyle(color: Color(0xFFAAB4C9), fontSize: 13),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.arrow_forward_ios_rounded, size: 16),
            ],
          ),
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
        style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w700),
      ),
      const SizedBox(height: 3),
      Text(
        subtitle,
        style: const TextStyle(color: Color(0xFFAAB4C9), fontSize: 13),
      ),
    ],
  );
}

class _ActionCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String description;
  final Color accent;
  final List<Color>? gradient;
  final VoidCallback onTap;

  const _ActionCard({
    required this.icon,
    required this.title,
    required this.description,
    required this.accent,
    required this.onTap,
    this.gradient,
  });

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(20);
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
              color: gradient == null ? const Color(0xFF141C2D) : null,
              gradient: gradient == null
                  ? null
                  : LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: gradient!,
                    ),
              border: Border.all(color: const Color(0xFF39455E)),
            ),
            child: InkWell(
              onTap: onTap,
              borderRadius: radius,
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Row(
                  children: [
                    Container(
                      width: 56,
                      height: 56,
                      decoration: BoxDecoration(
                        color: accent.withValues(alpha: 0.16),
                        borderRadius: BorderRadius.circular(17),
                      ),
                      child: Icon(icon, color: accent, size: 29),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            title,
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            description,
                            style: const TextStyle(
                              color: Color(0xFFD5DAE8),
                              fontSize: 14,
                              height: 1.4,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    const Icon(
                      Icons.arrow_forward_rounded,
                      color: Colors.white70,
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

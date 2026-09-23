import 'package:flutter/material.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;

import 'camera_screen.dart';

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
        scaffoldBackgroundColor: const Color(0xFF0A1020),
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF8B83FF),
          brightness: Brightness.dark,
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF0A1020),
          foregroundColor: Colors.white,
          surfaceTintColor: Colors.transparent,
        ),
      ),
      home: const AvaHomePage(),
    );
  }
}

class AvaHomePage extends StatefulWidget {
  const AvaHomePage({super.key});

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
  Future<void> _openCamera(String mode, {String? demoText}) async {
    final imagePath = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => CameraScreen(mode: mode, demoText: demoText),
      ),
    );

    if (imagePath != null) {
      _showMessage(
        '$mode Image Captured',
        'Image captured successfully.\n\nPath: $imagePath',
      );
    }
  }

  // Understand what the user asked Ava to do.
  void _handleCommand(String command) {
    final text = command.toLowerCase();

    // Translation is checked first because
    // "translate this text" also contains "text".
    if (text.contains('translate') || text.contains('translation')) {
      _openCamera('Translate');
    } else if (text.contains('describe') ||
        text.contains('surroundings') ||
        text.contains('around me')) {
      _openCamera('Describe Surroundings');
    } else if (text.contains('emergency') || text.contains('help')) {
      _showMessage(
        'Emergency Assistance',
        'Ava is ready to help with an emergency.',
      );
    } else if (text.contains('medicine') ||
        text.contains('read') ||
        text.contains('text')) {
      _openCamera('Read Text');
    } else {
      _showMessage('I heard you', 'You said: "$command"');
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
            colors: [Color(0xFF10172B), Color(0xFF090E19), Color(0xFF090E19)],
          ),
        ),
        child: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) => Align(
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 720),
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(22, 18, 22, 30),
                  children: [
                    _buildHeader(),
                    const SizedBox(height: 32),
                    Text(
                      _isListening ? 'I’m listening' : 'How can I help?',
                      style: const TextStyle(
                        fontSize: 32,
                        height: 1.12,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.7,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _isListening
                          ? 'Tell me what you need, in your own words.'
                          : 'Choose a tool or ask Ava out loud.',
                      style: const TextStyle(
                        fontSize: 16,
                        height: 1.45,
                        color: Color(0xFFB7C0D3),
                      ),
                    ),
                    const SizedBox(height: 20),
                    _buildVoiceCard(),
                    const SizedBox(height: 30),
                    const _SectionHeading(
                      title: 'Your tools',
                      subtitle: 'A quick way to get started',
                    ),
                    const SizedBox(height: 14),
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
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: _ActionCard(
                            icon: Icons.visibility_rounded,
                            title: 'Describe',
                            description:
                                'Get help understanding what’s around you.',
                            accent: const Color(0xFF8CE6D2),
                            onTap: () => _openCamera('Describe Surroundings'),
                            compact: true,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _ActionCard(
                            icon: Icons.translate_rounded,
                            title: 'Translate',
                            description: 'Capture text for translation.',
                            accent: const Color(0xFFFFD18A),
                            onTap: () => _openCamera('Translate'),
                            compact: true,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    _buildDemoCard(),
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      onPressed: () => _handleCommand('emergency'),
                      icon: const Icon(Icons.emergency_rounded),
                      label: const Text('Emergency assistance'),
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
                    const SizedBox(height: 22),
                    const Center(
                      child: Text(
                        'A little help, right when you need it.',
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
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
          decoration: BoxDecoration(
            color: const Color(0xFF17251F),
            borderRadius: BorderRadius.circular(30),
            border: Border.all(color: const Color(0xFF294537)),
          ),
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.circle, size: 8, color: Color(0xFF79D7A5)),
              SizedBox(width: 7),
              Text(
                'READY',
                style: TextStyle(
                  color: Color(0xFFB7E9CA),
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.8,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildVoiceCard() {
    final accent = _isListening
        ? const Color(0xFFFF858F)
        : const Color(0xFFB5ADFF);
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(26),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF242746), Color(0xFF181C31)],
        ),
        border: Border.all(color: const Color(0xFF343957)),
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
                      _isListening ? 'Listening now' : 'Talk to Ava',
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      _isListening
                          ? 'Say “read this” or “describe my surroundings”.'
                          : 'Tell me what you need, hands-free.',
                      style: const TextStyle(
                        color: Color(0xFFC0C6D8),
                        fontSize: 14,
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 14),
              Semantics(
                button: true,
                label: _isListening ? 'Stop listening to Ava' : 'Talk to Ava',
                child: Material(
                  color: accent.withValues(alpha: 0.16),
                  shape: const CircleBorder(),
                  child: InkWell(
                    onTap: _listen,
                    customBorder: const CircleBorder(),
                    child: SizedBox(
                      width: 68,
                      height: 68,
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
                style: const TextStyle(fontSize: 15, height: 1.4),
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
  final bool compact;

  const _ActionCard({
    required this.icon,
    required this.title,
    required this.description,
    required this.accent,
    required this.onTap,
    this.gradient,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(20);
    return Material(
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
          border: Border.all(color: const Color(0xFF2A344A)),
        ),
        child: InkWell(
          onTap: onTap,
          borderRadius: radius,
          child: Padding(
            padding: EdgeInsets.all(compact ? 16 : 18),
            child: Row(
              children: [
                Container(
                  width: compact ? 42 : 52,
                  height: compact ? 42 : 52,
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(15),
                  ),
                  child: Icon(icon, color: accent, size: compact ? 22 : 27),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          fontSize: compact ? 15 : 17,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        description,
                        style: TextStyle(
                          color: const Color(0xFFC0C6D8),
                          fontSize: compact ? 12 : 13,
                          height: 1.35,
                        ),
                      ),
                    ],
                  ),
                ),
                if (!compact) ...[
                  const SizedBox(width: 8),
                  const Icon(
                    Icons.arrow_forward_rounded,
                    color: Colors.white70,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

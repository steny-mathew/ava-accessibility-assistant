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
        scaffoldBackgroundColor: const Color(0xFF0B1220),
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF6C63FF),
          brightness: Brightness.dark,
        ),
        fontFamily: 'Arial',
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

            if (result.finalResult &&
                result.recognizedWords.isNotEmpty) {
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
  Future<void> _openCamera(String mode) async {
    final imagePath = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => CameraScreen(mode: mode),
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
    if (text.contains('translate') ||
        text.contains('translation')) {
      _openCamera('Translate');
    } else if (text.contains('describe') ||
        text.contains('surroundings') ||
        text.contains('around me')) {
      _openCamera('Describe Surroundings');
    } else if (text.contains('emergency') ||
        text.contains('help')) {
      _showMessage(
        'Emergency Assistance',
        'Ava is ready to help with an emergency.',
      );
    } else if (text.contains('medicine') ||
        text.contains('read') ||
        text.contains('text')) {
      _openCamera('Read Text');
    } else {
      _showMessage(
        'I heard you',
        'You said: "$command"',
      );
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
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: 24,
            vertical: 20,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'AVA',
                        style: TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 4,
                        ),
                      ),
                      SizedBox(height: 4),
                      Text(
                        'Your accessibility assistant',
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.white60,
                        ),
                      ),
                    ],
                  ),
                  IconButton(
                    onPressed: () {},
                    icon: const Icon(
                      Icons.settings_outlined,
                    ),
                    tooltip: 'Settings',
                  ),
                ],
              ),

              const Spacer(),

              // Main interaction area
              Center(
                child: Column(
                  children: [
                    Text(
                      _isListening
                          ? 'I\'m listening...'
                          : 'How can I help?',
                      style: const TextStyle(
                        fontSize: 30,
                        fontWeight: FontWeight.w600,
                      ),
                      textAlign: TextAlign.center,
                    ),

                    const SizedBox(height: 10),

                    Text(
                      _isListening
                          ? 'Speak clearly and tell Ava what you need.'
                          : 'Tap the microphone and tell Ava what you need.',
                      style: TextStyle(
                        fontSize: 16,
                        color: Colors.white.withOpacity(0.65),
                      ),
                      textAlign: TextAlign.center,
                    ),

                    const SizedBox(height: 40),

                    // Microphone button
                    Semantics(
                      button: true,
                      label: _isListening
                          ? 'Stop listening'
                          : 'Talk to Ava',
                      child: GestureDetector(
                        onTap: _listen,
                        child: AnimatedContainer(
                          duration: const Duration(
                            milliseconds: 250,
                          ),
                          width: _isListening ? 170 : 150,
                          height: _isListening ? 170 : 150,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: _isListening
                                ? Colors.redAccent
                                : const Color(0xFF6C63FF),
                            boxShadow: [
                              BoxShadow(
                                color: (_isListening
                                        ? Colors.redAccent
                                        : const Color(0xFF6C63FF))
                                    .withOpacity(0.35),
                                blurRadius: 35,
                                spreadRadius: 8,
                              ),
                            ],
                          ),
                          child: Icon(
                            _isListening
                                ? Icons.stop_rounded
                                : Icons.mic_rounded,
                            size: 70,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),

                    const SizedBox(height: 24),

                    Text(
                      _isListening
                          ? 'Tap to stop'
                          : 'Tap to speak',
                      style: const TextStyle(
                        fontSize: 15,
                        color: Colors.white70,
                      ),
                    ),

                    const SizedBox(height: 20),

                    // Recognized speech
                    if (_spokenText.isNotEmpty)
                      Container(
                        constraints: const BoxConstraints(
                          maxWidth: 650,
                        ),
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: const Color(0xFF151E30),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Text(
                          _spokenText,
                          style: const TextStyle(
                            fontSize: 17,
                            color: Colors.white,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                  ],
                ),
              ),

              const Spacer(),

              // Quick actions
              const Text(
                'Quick actions',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                ),
              ),

              const SizedBox(height: 14),

              Row(
                children: [
                  Expanded(
                    child: _QuickAction(
                      icon: Icons.document_scanner_outlined,
                      title: 'Read text',
                      onTap: () {
                        _openCamera('Read Text');
                      },
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _QuickAction(
                      icon: Icons.visibility_outlined,
                      title: 'Describe',
                      onTap: () {
                        _openCamera('Describe Surroundings');
                      },
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _QuickAction(
                      icon: Icons.translate_rounded,
                      title: 'Translate',
                      onTap: () {
                        _openCamera('Translate');
                      },
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 12),

              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () {
                    _handleCommand('emergency');
                  },
                  icon: const Icon(
                    Icons.emergency_outlined,
                  ),
                  label: const Text(
                    'Emergency Assistance',
                  ),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.redAccent,
                    side: const BorderSide(
                      color: Colors.redAccent,
                    ),
                    padding: const EdgeInsets.symmetric(
                      vertical: 16,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _QuickAction extends StatelessWidget {
  final IconData icon;
  final String title;
  final VoidCallback onTap;

  const _QuickAction({
    required this.icon,
    required this.title,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFF151E30),
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            vertical: 18,
            horizontal: 8,
          ),
          child: Column(
            children: [
              Icon(
                icon,
                size: 28,
                color: const Color(0xFF9B94FF),
              ),
              const SizedBox(height: 8),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 13,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
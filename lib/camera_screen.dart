import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

import 'read_text_service.dart';

class CameraScreen extends StatefulWidget {
  final String mode;

  const CameraScreen({super.key, required this.mode});

  @override
  State<CameraScreen> createState() => _CameraScreenState();
}

class _CameraScreenState extends State<CameraScreen> {
  CameraController? _controller;
  List<CameraDescription> _cameras = [];

  bool _isInitialized = false;
  bool _isReadingText = false;
  String? _extractedText;
  String? _readError;

  @override
  void initState() {
    super.initState();
    _initializeCamera();
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
    _controller?.dispose();
    super.dispose();
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
      body: _extractedText != null || _readError != null || _isReadingText
          ? _buildReadResult()
          : _isInitialized && _controller != null
          ? Stack(
              fit: StackFit.expand,
              children: [
                CameraPreview(_controller!),

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
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Recognized text',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            Expanded(
              child: SingleChildScrollView(
                child: SelectableText(
                  _readError ?? (text!.isEmpty ? 'No text was found.' : text),
                  style: const TextStyle(fontSize: 20, height: 1.5),
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

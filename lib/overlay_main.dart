import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_overlay_window/flutter_overlay_window.dart';
import 'package:screen_capturer/screen_capturer.dart';
import 'package:path_provider/path_provider.dart';
import 'translation_service.dart';

class BubbleOverlay extends StatefulWidget {
  const BubbleOverlay({super.key});

  @override
  State<BubbleOverlay> createState() => _BubbleOverlayState();
}

class _BubbleOverlayState extends State<BubbleOverlay> {
  final TranslationService _translationService = TranslationService();
  bool _isProcessing = false;
  String? _recognizedText;
  String? _translatedText;

  @override
  void initState() {
    super.initState();
    _translationService.initialize();
  }

  @override
  void dispose() {
    _translationService.dispose();
    super.dispose();
  }

  Future<void> _handleCaptureAndTranslate() async {
    setState(() {
      _isProcessing = true;
      _recognizedText = null;
      _translatedText = null;
    });

    try {
      // 1. Capture screen
      final directory = await getTemporaryDirectory();
      String imagePath = '${directory.path}/screenshot_${DateTime.now().millisecondsSinceEpoch}.png';

      final capturedData = await screenCapturer.capture(
        mode: CaptureMode.screen,
        imagePath: imagePath,
        silent: true,
      );

      if (capturedData != null && capturedData.imagePath != null) {
        final capturedImageFile = File(capturedData.imagePath!);
        
        // 2. OCR Text Recognition
        final text = await _translationService.recognizeText(capturedImageFile);
        setState(() {
          _recognizedText = text;
        });

        // 3. Translate
        if (text.isNotEmpty) {
          final translation = await _translationService.translateText(text);
          setState(() {
            _translatedText = translation;
          });
        } else {
           setState(() {
            _translatedText = "No text found.";
          });
        }
      } else {
        setState(() {
          _translatedText = "Failed to capture screen.";
        });
      }
    } catch (e) {
      setState(() {
        _translatedText = "Error: $e";
      });
    } finally {
      setState(() {
        _isProcessing = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: GestureDetector(
        onTap: _handleCaptureAndTranslate,
        child: Container(
          padding: const EdgeInsets.all(8.0),
          decoration: BoxDecoration(
            color: Colors.black.withOpacity(0.8),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.blueAccent, width: 2),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.translate, color: Colors.white, size: 40),
              if (_isProcessing) 
                const Padding(
                  padding: EdgeInsets.only(top: 8.0),
                  child: SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(color: Colors.blue, strokeWidth: 2),
                  ),
                ),
              if (_translatedText != null)
                Flexible(
                  child: Padding(
                    padding: const EdgeInsets.only(top: 8.0),
                    child: SingleChildScrollView(
                      child: Text(
                        _translatedText!,
                        style: const TextStyle(color: Colors.white, fontSize: 14),
                        textAlign: TextAlign.center,
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

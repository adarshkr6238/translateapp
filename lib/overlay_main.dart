import 'dart:io';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_overlay_window/flutter_overlay_window.dart';
import 'package:screen_capturer/screen_capturer.dart';
import 'package:path_provider/path_provider.dart';
import 'package:image/image.dart' as img;
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
  bool _isResultVisible = false;

  // Mode: 'fullscreen' or 'region'
  String _mode = 'fullscreen';

  // Bubble position
  double _bubbleTop = 100;
  double _bubbleLeft = 300;

  // Box position and size (for region mode)
  double _boxTop = 200;
  double _boxLeft = 50;
  double _boxWidth = 250;
  double _boxHeight = 150;

  StreamSubscription? _overlayListener;

  @override
  void initState() {
    super.initState();
    _translationService.initialize();
    _overlayListener = FlutterOverlayWindow.overlayListener.listen((data) {
      if (data is Map && data.containsKey('mode')) {
        setState(() {
          _mode = data['mode'];
        });
      }
    });
  }

  @override
  void dispose() {
    _translationService.dispose();
    _overlayListener?.cancel();
    super.dispose();
  }

  Future<void> _handleCaptureAndTranslate() async {
    if (_isResultVisible) {
      return; // Do nothing if result is already visible, let the close button handle it
    }

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
        String finalImagePath = capturedData.imagePath!;

        // 2. Crop if in region mode
        if (_mode == 'region') {
          final bytes = await File(finalImagePath).readAsBytes();
          img.Image? image = img.decodeImage(bytes);
          if (image != null) {
            final pixelRatio = MediaQuery.of(context).devicePixelRatio;
            // Crop the image
            img.Image cropped = img.copyCrop(
              image,
              x: (_boxLeft * pixelRatio).toInt(),
              y: (_boxTop * pixelRatio).toInt(),
              width: (_boxWidth * pixelRatio).toInt(),
              height: (_boxHeight * pixelRatio).toInt(),
            );
            await File(finalImagePath).writeAsBytes(img.encodePng(cropped));
          }
        }

        final capturedImageFile = File(finalImagePath);
        
        // 3. OCR Text Recognition
        final text = await _translationService.recognizeText(capturedImageFile);
        setState(() {
          _recognizedText = text;
        });

        // 4. Translate
        if (text.isNotEmpty) {
          final translation = await _translationService.translateText(text);
          setState(() {
            _translatedText = translation;
            _isResultVisible = true;
          });
        } else {
           setState(() {
            _translatedText = "No text found in region.";
            _isResultVisible = true;
          });
        }
      } else {
        setState(() {
          _translatedText = "Failed to capture screen.";
          _isResultVisible = true;
        });
      }
    } catch (e) {
      setState(() {
        _translatedText = "Error: $e";
        _isResultVisible = true;
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
      child: Stack(
        children: [
          // Region Selection Box
          if (_mode == 'region' && !_isResultVisible) _buildResizableBox(),

          // Draggable Bubble / Result View
          Positioned(
            top: _bubbleTop,
            left: _bubbleLeft,
            child: _buildBubble(),
          ),
        ],
      ),
    );
  }

  Widget _buildBubble() {
    return Container(
      constraints: const BoxConstraints(maxWidth: 300, maxHeight: 500),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.8),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.blueAccent, width: 2),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.5),
            blurRadius: 10,
            spreadRadius: 2,
          )
        ],
      ),
      child: Stack(
        children: [
          GestureDetector(
            onPanUpdate: (details) {
              setState(() {
                _bubbleTop += details.delta.dy;
                _bubbleLeft += details.delta.dx;
              });
            },
            onTap: _handleCaptureAndTranslate,
            child: Padding(
              padding: const EdgeInsets.all(8.0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    _isResultVisible ? Icons.translate : Icons.translate,
                    color: Colors.white,
                    size: 40,
                  ),
                  if (_isProcessing)
                    const Padding(
                      padding: EdgeInsets.only(top: 8.0),
                      child: SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(color: Colors.blue, strokeWidth: 2),
                      ),
                    ),
                  if (_isResultVisible && _translatedText != null)
                    Flexible(
                      child: Padding(
                        padding: const EdgeInsets.only(top: 24.0, left: 8.0, right: 8.0, bottom: 8.0),
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
          if (_isResultVisible)
            Positioned(
              top: 0,
              right: 0,
              child: IconButton(
                icon: const Icon(Icons.close, color: Colors.white, size: 20),
                onPressed: () {
                  setState(() {
                    _isResultVisible = false;
                    _translatedText = null;
                    _recognizedText = null;
                  });
                },
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildResizableBox() {
    return Stack(
      children: [
        // The Box itself (draggable to move)
        Positioned(
          top: _boxTop,
          left: _boxLeft,
          child: GestureDetector(
            onPanUpdate: (details) {
              setState(() {
                _boxTop += details.delta.dy;
                _boxLeft += details.delta.dx;
              });
            },
            child: Container(
              width: _boxWidth,
              height: _boxHeight,
              decoration: BoxDecoration(
                color: Colors.blueAccent.withOpacity(0.1),
                border: Border.all(color: Colors.blueAccent.withOpacity(0.5), width: 2),
              ),
              child: const Center(
                child: Icon(Icons.crop_free, color: Colors.blueAccent),
              ),
            ),
          ),
        ),
        // Cancel button: Top Right
        Positioned(
          top: _boxTop - 10,
          left: _boxLeft + _boxWidth - 20,
          child: GestureDetector(
            onTap: () {
              setState(() {
                _mode = 'fullscreen';
              });
              FlutterOverlayWindow.shareData({'mode': 'fullscreen'});
            },
            child: Container(
              padding: const EdgeInsets.all(2),
              decoration: const BoxDecoration(
                color: Colors.redAccent,
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.close, size: 18, color: Colors.white),
            ),
          ),
        ),
        // Resize handle: Bottom Right
        Positioned(
          top: _boxTop + _boxHeight - 15,
          left: _boxLeft + _boxWidth - 15,
          child: GestureDetector(
            onPanUpdate: (details) {
              setState(() {
                _boxWidth = (_boxWidth + details.delta.dx).clamp(50.0, 1000.0);
                _boxHeight = (_boxHeight + details.delta.dy).clamp(50.0, 1000.0);
              });
            },
            child: Container(
              width: 30,
              height: 30,
              decoration: const BoxDecoration(
                color: Colors.blueAccent,
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.open_in_full, size: 15, color: Colors.white),
            ),
          ),
        ),
      ],
    );
  }

}

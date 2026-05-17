import 'dart:io';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:google_mlkit_translation/google_mlkit_translation.dart';
import 'package:google_mlkit_language_id/google_mlkit_language_id.dart';

class TranslationService {
  late TextRecognizer _textRecognizer;
  final LanguageIdentifier _languageIdentifier = LanguageIdentifier(confidenceThreshold: 0.5);
  
  OnDeviceTranslator? _translator;
  TranslateLanguage? _sourceLanguage;
  final TranslateLanguage _targetLanguage = TranslateLanguage.english;

  void initialize() {
    _textRecognizer = TextRecognizer(script: TextRecognitionScript.latin);
  }

  Future<String> recognizeText(File imageFile) async {
    final inputImage = InputImage.fromFile(imageFile);
    final RecognizedText recognizedText = await _textRecognizer.processImage(inputImage);
    return recognizedText.text;
  }

  Future<String> translateText(String text) async {
    if (text.trim().isEmpty) return "";

    try {
      // 1. Identify Language
      final List<IdentifiedLanguage> languages = await _languageIdentifier.identifyPossibleLanguages(text);
      if (languages.isEmpty) return "Could not detect language.";

      final String detectedBcpCode = languages.first.languageTag;
      final TranslateLanguage? detectedLanguage = _getTranslateLanguageFromBcp(detectedBcpCode);

      if (detectedLanguage == null) {
        return "Unsupported language detected: $detectedBcpCode";
      }

      if (detectedLanguage == _targetLanguage) {
        return text; // Already in English
      }

      // 2. Initialize Translator if needed
      if (_sourceLanguage != detectedLanguage || _translator == null) {
        _sourceLanguage = detectedLanguage;
        _translator?.close();
        _translator = OnDeviceTranslator(
          sourceLanguage: _sourceLanguage!,
          targetLanguage: _targetLanguage,
        );
      }

      // 3. Ensure models are downloaded
      await _downloadModel(_sourceLanguage!);
      await _downloadModel(_targetLanguage);

      // 4. Translate
      final String translatedText = await _translator!.translateText(text);
      return translatedText;
    } catch (e) {
      return "Translation failed: $e";
    }
  }

  Future<void> _downloadModel(TranslateLanguage language) async {
    final modelManager = OnDeviceTranslatorModelManager();
    final bool isDownloaded = await modelManager.isModelDownloaded(language.bcpCode);

    if (!isDownloaded) {
      await modelManager.downloadModel(language.bcpCode);
    }
  }

  TranslateLanguage? _getTranslateLanguageFromBcp(String bcpCode) {
    try {
      return TranslateLanguage.values.firstWhere((element) => element.bcpCode == bcpCode);
    } catch (_) {
      // Handle cases where bcpCode might be slightly different or missing
      // Simple mapping for common ones if needed
      if (bcpCode.startsWith('zh')) return TranslateLanguage.chinese;
      return null;
    }
  }

  void dispose() {
    _textRecognizer.close();
    _languageIdentifier.close();
    _translator?.close();
  }
}

import 'package:paddle_ocr_native/paddle_ocr_native.dart';

class OcrService {
  static final PaddleOcr _ocr = PaddleOcr();
  static Future<void>? _initializing;
  static bool _ready = false;

  static Future<void> ensureReady() async {
    if (_ready) return;
    _initializing ??= _init();
    await _initializing;
  }

  static Future<void> _init() async {
    await _ocr.init(
      config: const PaddleOcrConfig(),
      engine: const EngineConfig(numThreads: 4),
    );
    _ready = true;
  }

  static Future<String> recognize(String imagePath) async {
    await ensureReady();
    final run = await _ocr.recognize(imagePath);
    final regions = [...run.results];
    regions.sort((a, b) {
      final top = a.boundingBox.top.compareTo(b.boundingBox.top);
      if (top != 0) return top;
      return a.boundingBox.left.compareTo(b.boundingBox.left);
    });
    return regions
        .map((region) => region.text.trim())
        .where((text) => text.isNotEmpty)
        .join('\n');
  }
}

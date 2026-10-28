import 'package:flutter/foundation.dart';
import 'package:paddle_ocr_native/paddle_ocr_native.dart';

/// OCR 封装：初始化失败可重试，识别异常转成可读错误，不让界面卡死。
class OcrService {
  static final PaddleOcr _ocr = PaddleOcr();
  static Future<void>? _initializing;
  static bool _ready = false;

  /// 上一次失败原因，供界面提示。
  static String? lastError;

  static Future<void> ensureReady() async {
    if (_ready) return;
    _initializing ??= _init();
    try {
      await _initializing;
    } catch (e) {
      // 初始化失败要把 future 清掉，否则后续重试永远拿到同一个失败结果。
      _initializing = null;
      lastError = 'OCR 初始化失败：$e';
      rethrow;
    }
  }

  static Future<void> _init() async {
    await _ocr.init(
      config: const PaddleOcrConfig(),
      engine: const EngineConfig(numThreads: 4),
    );
    _ready = true;
    lastError = null;
  }

  static Future<String> recognize(String imagePath) async {
    await ensureReady();
    try {
      final run = await _ocr.recognize(imagePath);
      final regions = [...run.results];
      regions.sort((a, b) {
        final top = a.boundingBox.top.compareTo(b.boundingBox.top);
        if (top != 0) return top;
        return a.boundingBox.left.compareTo(b.boundingBox.left);
      });
      final text = regions
          .map((region) => region.text.trim())
          .where((text) => text.isNotEmpty)
          .join('\n');
      lastError = null;
      return text;
    } catch (e, st) {
      lastError = '识别失败：$e';
      debugPrint('OcrService.recognize failed: $e\n$st');
      rethrow;
    }
  }

  /// 释放 native 会话；下次 recognize 会重新初始化。
  static Future<void> reset() async {
    try {
      await _ocr.dispose();
    } catch (_) {}
    _ready = false;
    _initializing = null;
  }
}

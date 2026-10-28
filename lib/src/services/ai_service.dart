import 'dart:convert';
import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../models/ai_extracted_question.dart';

enum AiProvider {
  deepSeek,
  qwen,
  zhipu,
  siliconFlow,
  openai,
  claude,
  gemini,
  custom;

  static AiProvider fromCode(String? code) {
    return AiProvider.values.firstWhere(
      (item) => item.name == code,
      orElse: () => AiProvider.deepSeek,
    );
  }

  String get label {
    switch (this) {
      case AiProvider.deepSeek:
        return 'DeepSeek';
      case AiProvider.qwen:
        return '通义千问';
      case AiProvider.zhipu:
        return '智谱';
      case AiProvider.siliconFlow:
        return '硅基流动';
      case AiProvider.openai:
        return 'OpenAI';
      case AiProvider.claude:
        return 'Claude';
      case AiProvider.gemini:
        return 'Gemini';
      case AiProvider.custom:
        return '自定义';
    }
  }

  String get defaultBaseUrl {
    switch (this) {
      case AiProvider.deepSeek:
        return 'https://api.deepseek.com/v1';
      case AiProvider.qwen:
        return 'https://dashscope.aliyuncs.com/compatible-mode/v1';
      case AiProvider.zhipu:
        return 'https://open.bigmodel.cn/api/paas/v4';
      case AiProvider.siliconFlow:
        return 'https://api.siliconflow.cn/v1';
      case AiProvider.openai:
        return 'https://api.openai.com/v1';
      case AiProvider.claude:
        return 'https://api.anthropic.com';
      case AiProvider.gemini:
        return 'https://generativelanguage.googleapis.com';
      case AiProvider.custom:
        return '';
    }
  }

  String get defaultModel {
    switch (this) {
      case AiProvider.deepSeek:
        return 'deepseek-chat';
      case AiProvider.qwen:
        return 'qwen-plus';
      case AiProvider.zhipu:
        return 'glm-4-flash';
      case AiProvider.siliconFlow:
        return 'Qwen/Qwen2.5-7B-Instruct';
      case AiProvider.openai:
        return 'gpt-4o-mini';
      case AiProvider.claude:
        return 'claude-3-5-sonnet-latest';
      case AiProvider.gemini:
        return 'gemini-2.0-flash';
      case AiProvider.custom:
        return '';
    }
  }
}

class AiSettings {
  const AiSettings({
    required this.provider,
    required this.baseUrl,
    required this.model,
    this.apiKey = '',
  });

  final AiProvider provider;
  final String baseUrl;
  final String model;
  final String apiKey;

  AiSettings copyWith({
    AiProvider? provider,
    String? baseUrl,
    String? model,
    String? apiKey,
  }) {
    return AiSettings(
      provider: provider ?? this.provider,
      baseUrl: baseUrl ?? this.baseUrl,
      model: model ?? this.model,
      apiKey: apiKey ?? this.apiKey,
    );
  }

  bool get ready =>
      baseUrl.trim().isNotEmpty &&
      model.trim().isNotEmpty &&
      apiKey.trim().isNotEmpty;

  /// 缺哪一项，用于给出准确提示而不是笼统的一句"请先填写"。
  String get missingHint {
    final miss = <String>[];
    if (baseUrl.trim().isEmpty) miss.add('接口地址');
    if (model.trim().isEmpty) miss.add('模型名');
    if (apiKey.trim().isEmpty) miss.add('API Key');
    if (miss.isEmpty) return '';
    return '还缺：${miss.join('、')}';
  }
}

class AiSettingsStore {
  static const _secure = FlutterSecureStorage();
  static const _keyProvider = 'ai_provider';
  static const _keyBaseUrl = 'ai_base_url';
  static const _keyModel = 'ai_model';
  static const _keyApiKey = 'ai_api_key';
  static const _keyVision = 'ai_send_image';

  /// 是否让模型直接看图作答（多模态）。默认开启。
  static bool sendImage = true;

  static Future<AiSettings> load() async {
    final prefs = await SharedPreferences.getInstance();
    final provider = AiProvider.fromCode(prefs.getString(_keyProvider));
    final key = await _secure.read(key: _keyApiKey) ?? '';
    final savedModel = prefs.getString(_keyModel) ?? '';
    final savedBase = prefs.getString(_keyBaseUrl) ?? '';
    sendImage = prefs.getBool(_keyVision) ?? true;
    return AiSettings(
      provider: provider,
      baseUrl: savedBase.isEmpty ? provider.defaultBaseUrl : savedBase,
      // 自定义服务商没有默认模型；此时若用户没填，就留空，由界面提示补填。
      model: savedModel,
      apiKey: key,
    );
  }

  static Future<void> save(AiSettings settings, {bool? sendImageValue}) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyProvider, settings.provider.name);
    await prefs.setString(_keyBaseUrl, settings.baseUrl.trim());
    await prefs.setString(_keyModel, settings.model.trim());
    if (sendImageValue != null) {
      await prefs.setBool(_keyVision, sendImageValue);
      sendImage = sendImageValue;
    }
    if (settings.apiKey.trim().isEmpty) {
      await _secure.delete(key: _keyApiKey);
    } else {
      await _secure.write(key: _keyApiKey, value: settings.apiKey.trim());
    }
  }
}

class AiAnswer {
  const AiAnswer({
    required this.answer,
    this.explanation = '',
    this.steps = '',
    this.uncertainty = '',
    this.uncertain = false,
  });

  final String answer;
  final String explanation;
  final String steps;
  final String uncertainty;
  final bool uncertain;
}

class AiService {
  static const _systemPrompt = '''
你是一个中文答题助手。请根据用户给出的题目自由作答。
必须只返回 JSON，不要 Markdown 代码块，不要额外解释。
JSON 字段：
- answer: 最终答案
- explanation: 解析
- steps: 解题步骤，字符串
- uncertain: 布尔值，没把握时为 true
- uncertainty: 没把握的原因；有把握时为空字符串
按题型作答：单选/多选写选项字母和内容；判断写正确或错误；填空/简答写完整答案。
''';

  /// 看图作答的提示：明确要求模型自己读图，不依赖 OCR 文本。
  static const _visionPrompt = '''
图片里是一道中文题目。请你自己直接看清楚图片里的题干和全部选项，独立解题。
要求：
1. 先在心里完整读取题干与每个选项，注意不要漏掉"错误的是""不属于"这类否定词。
2. 只依据图片内容作答，不要臆测图片里没有的文字。
3. 逐项判断每个选项，说明为什么对、为什么错。
''';

  static Future<String?> imageBase64(String path) async {
    try {
      final file = File(path);
      if (!await file.exists()) return null;
      final bytes = await file.readAsBytes();
      if (bytes.isEmpty) return null;
      if (bytes.length > 4 * 1024 * 1024) return null;
      return base64Encode(bytes);
    } catch (_) {
      return null;
    }
  }

  static String mimeOf(String path) {
    final lower = path.toLowerCase();
    if (lower.endsWith('.png')) return 'image/png';
    if (lower.endsWith('.webp')) return 'image/webp';
    return 'image/jpeg';
  }

  /// 手机在 IPv6 优先网络下访问只有 A 记录的域名时，dart:io 可能报
  /// "Failed host lookup (...) errno = 7"。这里显式只查 IPv4，绕开 AAAA。
  static String? _ipv4Cache;

  static Future<String?> _resolveIpv4Host(String host) async {
    if (InternetAddress.tryParse(host) != null) return host;
    if (_ipv4Cache != null) return _ipv4Cache;
    try {
      final list = await InternetAddress.lookup(host, type: InternetAddressType.IPv4);
      for (final addr in list) {
        if (addr.type == InternetAddressType.IPv4 && addr.address.isNotEmpty) {
          _ipv4Cache = addr.address;
          return _ipv4Cache;
        }
      }
    } catch (_) {}
    return null;
  }

  /// 用 HttpClient 发请求，强制 IPv4（lookup 指定 IPv4）。
  static Future<http.Response> _postJson(Uri uri, Map<String, String> headers, String body) async {
    try {
      return await _sendWithHost(uri, headers, body);
    } catch (e) {
      final isLookup = e is SocketException ||
          e.toString().contains('Failed host lookup') ||
          e.toString().contains('errno = 7');
      if (!isLookup) rethrow;
      final ip = await _resolveIpv4Host(uri.host);
      if (ip == null) rethrow;
      // 用 IP 作为连接目标，但 Host 头仍写原域名，服务端路由与证书校验都不受影响
      final plain = HttpClient();
      try {
        plain.connectionTimeout = const Duration(seconds: 25);
        final req = await plain.openUrl('POST', uri.replace(host: ip));
        req.headers.set(HttpHeaders.hostHeader, uri.host);
        headers.forEach(req.headers.set);
        req.add(utf8.encode(body));
        final resp = await req.close();
        final bytes = await resp.fold<List<int>>(<int>[], (acc, c) => acc..addAll(c));
        return http.Response.bytes(bytes, resp.statusCode, headers: {
          'content-type': resp.headers.value('content-type') ?? 'application/json',
        });
      } finally {
        plain.close();
      }
    }
  }

  static Future<http.Response> _sendWithHost(Uri uri, Map<String, String> headers, String body) async {
    final client = HttpClient();
    try {
      client.connectionTimeout = const Duration(seconds: 25);
      final request = await client.postUrl(uri);
      headers.forEach(request.headers.set);
      request.add(utf8.encode(body));
      final response = await request.close();
      final bytes = await response.fold<List<int>>(<int>[], (acc, chunk) => acc..addAll(chunk));
      return http.Response.bytes(bytes, response.statusCode, headers: {
        'content-type': response.headers.value('content-type') ?? 'application/json',
      });
    } finally {
      client.close();
    }
  }

  static Future<AiAnswer> ask({
    required AiSettings settings,
    required String questionText,
    String? imagePath,
    bool preferImage = true,
  }) async {
    if (!settings.ready) {
      throw Exception('AI 配置不完整，${settings.missingHint}');
    }
    final url = settings.baseUrl.replaceAll(RegExp(r'/+$'), '');

    String? b64;
    if (preferImage && imagePath != null && imagePath.isNotEmpty) {
      b64 = await imageBase64(imagePath);
    }
    final hasImage = b64 != null;
    final textPart = questionText.trim().isEmpty && !hasImage
        ? '请给出你的答案'
        : questionText.trim();
    final userText = hasImage
        ? '$_visionPrompt\n\n（OCR 参考文字，可能有误，请以图片为准）：\n$textPart'
        : textPart;

    http.Response response;
    if (settings.provider == AiProvider.claude) {
      final content = <Map<String, dynamic>>[];
      if (hasImage) {
        content.add({
          'type': 'image',
          'source': {
            'type': 'base64',
            'media_type': mimeOf(imagePath!),
            'data': b64,
          },
        });
      }
      content.add({'type': 'text', 'text': userText});
      response = await _postJson(
        Uri.parse('$url/v1/messages'),
        {
          'content-type': 'application/json',
          'x-api-key': settings.apiKey,
          'anthropic-version': '2023-06-01',
        },
        jsonEncode({
          'model': settings.model.trim(),
          'max_tokens': 2048,
          'system': _systemPrompt,
          'messages': [
            {'role': 'user', 'content': content},
          ],
        }),
      ).timeout(const Duration(seconds: 120));
    } else if (settings.provider == AiProvider.gemini) {
      final parts = <Map<String, dynamic>>[];
      if (hasImage) {
        parts.add({
          'inline_data': {'mime_type': mimeOf(imagePath!), 'data': b64},
        });
      }
      parts.add({'text': userText});
      response = await _postJson(
        Uri.parse('$url/v1beta/models/${settings.model.trim()}:generateContent?key=${settings.apiKey}'),
        {'content-type': 'application/json'},
        jsonEncode({
          'systemInstruction': {
            'parts': [
              {'text': _systemPrompt},
            ],
          },
          'contents': [
            {'role': 'user', 'parts': parts},
          ],
          'generationConfig': {'temperature': 0.2},
        }),
      ).timeout(const Duration(seconds: 120));
    } else {
      final userContent = <Map<String, dynamic>>[
        {'type': 'text', 'text': userText},
      ];
      if (hasImage) {
        userContent.add({
          'type': 'image_url',
          'image_url': {'url': 'data:${mimeOf(imagePath!)};base64,$b64'},
        });
      }
      response = await _postJson(
        Uri.parse('$url/chat/completions'),
        {
          'content-type': 'application/json',
          'authorization': 'Bearer ${settings.apiKey}',
        },
        jsonEncode({
          'model': settings.model.trim(),
          'messages': [
            {'role': 'system', 'content': _systemPrompt},
            {'role': 'user', 'content': userContent},
          ],
          'temperature': 0.2,
        }),
      ).timeout(const Duration(seconds: 120));
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('AI 接口返回 ${response.statusCode}: ${response.body}');
    }
    final json = jsonDecode(response.body) as Map<String, dynamic>;
    final content = extractText(json, settings.provider);
    return _parseAnswer(content);
  }

  static String extractText(Map<String, dynamic> json, AiProvider provider) {
    if (provider == AiProvider.claude) {
      final content = json['content'];
      if (content is List && content.isNotEmpty) {
        final first = content.first;
        if (first is Map) return (first['text'] ?? '').toString();
      }
      return '';
    }
    if (provider == AiProvider.gemini) {
      final candidates = json['candidates'];
      if (candidates is List && candidates.isNotEmpty) {
        final content = (candidates.first as Map)['content'];
        if (content is Map) {
          final parts = content['parts'];
          if (parts is List && parts.isNotEmpty) {
            return (parts.first as Map)['text'].toString();
          }
        }
      }
      return '';
    }
    final choices = json['choices'];
    if (choices is List && choices.isNotEmpty) {
      final message = (choices.first as Map)['message'];
      if (message is Map) return (message['content'] ?? '').toString();
    }
    return '';
  }

  static AiAnswer _parseAnswer(String raw) {
    final cleaned = raw.trim().replaceFirst(RegExp(r'^```(?:json)?\s*'), '').replaceFirst(RegExp(r'\s*```$'), '');
    try {
      final data = jsonDecode(cleaned);
      if (data is Map) {
        return AiAnswer(
          answer: (data['answer'] ?? '').toString(),
          explanation: (data['explanation'] ?? '').toString(),
          steps: (data['steps'] ?? '').toString(),
          uncertainty: (data['uncertainty'] ?? '').toString(),
          uncertain: data['uncertain'] == true,
        );
      }
    } catch (_) {
      // 模型没按 JSON 返回时，保留原文，不丢用户结果。
    }
    return AiAnswer(answer: raw.trim());
  }

  static const extractSystemPrompt = '''
你是题目结构化助手。你的任务只是把图片里的题目原样抄录成结构化数据，
不要答题，不要解释，不要补充图片里没有的内容。
必须只返回 JSON，不要 Markdown 代码块。
''';

  static String buildExtractPrompt(int maxCount) => '''
图片里可能有 1 到 $maxCount 道中文题目。请全部提取出来，最多 $maxCount 道，超出的忽略。

要求：
1. 每道题的 stem 只放题干正文，去掉开头的题号（如"1."、"（3）"）。
2. options 放该题所有选项的正文，不要带 A. B. 前缀；判断题或填空简答给空数组。
3. type 只能是 single、multiple、judge、fill、short 之一。
4. answer 留空字符串，不要自己答题。
5. 如果图片里有题号，按图片顺序排列。
6. 只抄录看得清的文字；看不清的宁可用空字符串，也不要编。

返回格式（严格 JSON 对象）：
{"questions":[{"stem":"题干","type":"single","options":["选项1","选项2"],"answer":""}]}
''';

  /// 从整页图片里提取题目（不答题）。最多 [maxCount] 道。
  static Future<List<AiExtractedQuestion>> extractQuestions({
    required AiSettings settings,
    required String imagePath,
    int maxCount = 10,
  }) async {
    if (!settings.ready) {
      throw Exception('AI 配置不完整，${settings.missingHint}');
    }
    final b64 = await imageBase64(imagePath);
    if (b64 == null) {
      throw Exception('图片读取失败或超过 4MB，请压缩后重试');
    }
    final url = settings.baseUrl.replaceAll(RegExp(r'/+$'), '');
    final prompt = buildExtractPrompt(maxCount);
    final mime = mimeOf(imagePath);

    http.Response response;
    if (settings.provider == AiProvider.claude) {
      response = await _postJson(
        Uri.parse('$url/v1/messages'),
        {
          'content-type': 'application/json',
          'x-api-key': settings.apiKey,
          'anthropic-version': '2023-06-01',
        },
        jsonEncode({
          'model': settings.model.trim(),
          'max_tokens': 4096,
          'system': extractSystemPrompt,
          'messages': [
            {
              'role': 'user',
              'content': [
                {
                  'type': 'image',
                  'source': {'type': 'base64', 'media_type': mime, 'data': b64},
                },
                {'type': 'text', 'text': prompt},
              ],
            }
          ],
        }),
      ).timeout(const Duration(seconds: 120));
    } else if (settings.provider == AiProvider.gemini) {
      response = await _postJson(
        Uri.parse('$url/v1beta/models/${settings.model.trim()}:generateContent?key=${settings.apiKey}'),
        {'content-type': 'application/json'},
        jsonEncode({
          'systemInstruction': {
            'parts': [
              {'text': extractSystemPrompt},
            ],
          },
          'contents': [
            {
              'role': 'user',
              'parts': [
                {'inline_data': {'mime_type': mime, 'data': b64}},
                {'text': prompt},
              ],
            }
          ],
          'generationConfig': {'temperature': 0.1},
        }),
      ).timeout(const Duration(seconds: 120));
    } else {
      response = await _postJson(
        Uri.parse('$url/chat/completions'),
        {
          'content-type': 'application/json',
          'authorization': 'Bearer ${settings.apiKey}',
        },
        jsonEncode({
          'model': settings.model.trim(),
          'messages': [
            {'role': 'system', 'content': extractSystemPrompt},
            {
              'role': 'user',
              'content': [
                {'type': 'text', 'text': prompt},
                {'type': 'image_url', 'image_url': {'url': 'data:$mime;base64,$b64'}},
              ],
            },
          ],
          'temperature': 0.1,
        }),
      ).timeout(const Duration(seconds: 120));
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('AI 接口返回 ${response.statusCode}: ${response.body}');
    }
    final json = jsonDecode(response.body) as Map<String, dynamic>;
    final content = extractText(json, settings.provider);
    return _parseExtracted(content, maxCount);
  }

  static List<AiExtractedQuestion> _parseExtracted(String raw, int maxCount) {
    final cleaned = raw
        .trim()
        .replaceFirst(RegExp(r'^```(?:json)?\s*'), '')
        .replaceFirst(RegExp(r'\s*```$'), '');
    dynamic data;
    try {
      data = jsonDecode(cleaned);
    } catch (_) {
      // 模型可能夹带解释文字，尝试截取第一个 { 到最后一个 }
      final s = cleaned.indexOf('{');
      final e = cleaned.lastIndexOf('}');
      if (s < 0 || e <= s) return const [];
      try {
        data = jsonDecode(cleaned.substring(s, e + 1));
      } catch (_) {
        return const [];
      }
    }
    final list = data is Map ? data['questions'] : data;
    if (list is! List) return const [];
    final out = <AiExtractedQuestion>[];
    for (final item in list) {
      if (item is! Map) continue;
      final stem = (item['stem'] ?? '').toString().trim();
      if (stem.isEmpty) continue;
      final optsRaw = item['options'];
      final options = <String>[];
      if (optsRaw is List) {
        for (final o in optsRaw) {
          final t = o is Map ? (o['text'] ?? '').toString() : o.toString();
          if (t.trim().isNotEmpty) options.add(t.trim());
        }
      }
      out.add(AiExtractedQuestion(
        stem: stem,
        type: (item['type'] ?? 'single').toString(),
        options: options,
        answer: (item['answer'] ?? '').toString().trim(),
      ));
      if (out.length >= maxCount) break;
    }
    return out;
  }

}

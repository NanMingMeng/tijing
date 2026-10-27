import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

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
}

class AiSettingsStore {
  static const _secure = FlutterSecureStorage();
  static const _keyProvider = 'ai_provider';
  static const _keyBaseUrl = 'ai_base_url';
  static const _keyModel = 'ai_model';
  static const _keyApiKey = 'ai_api_key';

  static Future<AiSettings> load() async {
    final prefs = await SharedPreferences.getInstance();
    final provider = AiProvider.fromCode(prefs.getString(_keyProvider));
    final key = await _secure.read(key: _keyApiKey) ?? '';
    return AiSettings(
      provider: provider,
      baseUrl: prefs.getString(_keyBaseUrl) ?? provider.defaultBaseUrl,
      model: prefs.getString(_keyModel) ?? provider.defaultModel,
      apiKey: key,
    );
  }

  static Future<void> save(AiSettings settings) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyProvider, settings.provider.name);
    await prefs.setString(_keyBaseUrl, settings.baseUrl.trim());
    await prefs.setString(_keyModel, settings.model.trim());
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

  static Future<AiAnswer> ask({
    required AiSettings settings,
    required String questionText,
  }) async {
    if (!settings.ready) {
      throw Exception('请先在设置里填写接口地址、模型和 API Key');
    }
    final url = settings.baseUrl.replaceAll(RegExp(r'/+$'), '');
    final body = <String, dynamic>{
      'model': settings.model.trim(),
      'messages': [
        {'role': 'system', 'content': _systemPrompt},
        {'role': 'user', 'content': questionText},
      ],
      'temperature': 0.2,
    };
    http.Response response;
    if (settings.provider == AiProvider.claude) {
      response = await http.post(
        Uri.parse('$url/v1/messages'),
        headers: {
          'content-type': 'application/json',
          'x-api-key': settings.apiKey,
          'anthropic-version': '2023-06-01',
        },
        body: jsonEncode({
          'model': settings.model.trim(),
          'max_tokens': 2048,
          'system': _systemPrompt,
          'messages': [
            {'role': 'user', 'content': questionText},
          ],
        }),
      ).timeout(const Duration(seconds: 90));
    } else if (settings.provider == AiProvider.gemini) {
      final model = settings.model.trim();
      response = await http.post(
        Uri.parse('$url/v1beta/models/$model:generateContent?key=${settings.apiKey}'),
        headers: {'content-type': 'application/json'},
        body: jsonEncode({
          'systemInstruction': {
            'parts': [
              {'text': _systemPrompt},
            ],
          },
          'contents': [
            {
              'role': 'user',
              'parts': [
                {'text': questionText},
              ],
            }
          ],
          'generationConfig': {'temperature': 0.2},
        }),
      ).timeout(const Duration(seconds: 90));
    } else {
      response = await http.post(
        Uri.parse('$url/chat/completions'),
        headers: {
          'content-type': 'application/json',
          'authorization': 'Bearer ${settings.apiKey}',
        },
        body: jsonEncode(body),
      ).timeout(const Duration(seconds: 90));
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('AI 接口返回 ${response.statusCode}: ${response.body}');
    }
    final json = jsonDecode(response.body) as Map<String, dynamic>;
    final content = _extractContent(json, settings.provider);
    return _parseAnswer(content);
  }

  static String _extractContent(Map<String, dynamic> json, AiProvider provider) {
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
}

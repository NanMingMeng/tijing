import 'dart:convert';

import 'package:http/http.dart' as http;

import '../data/app_database.dart';
import '../models/question.dart';
import '../models/question_ai_index.dart';
import 'ai_service.dart';

/// 让模型把题库提炼成可本地检索的索引（方案 B）。
/// 每个请求只带一小批题，避免一次把整个题库塞进上下文。
class AiIndexBuilder {
  AiIndexBuilder(this.db);

  final AppDatabase db;

  /// 每批发给模型的题目数
  static const batchSize = 25;

  static const _system = '''
你是题库索引助手。给你若干道中文题目，请为每道题提炼检索用的索引。
必须只返回 JSON，不要 Markdown 代码块，不要解释。
''';

  static String _prompt(List<Question> batch) {
    final buf = StringBuffer();
    buf.writeln('请为下面每道题生成检索索引，输出严格 JSON：');
    buf.writeln('{"items":[{"id":"题目id","key_points":"核心考点短语","keywords":"易混关键词，逗号分隔","canonical":"改写后的标准问法"}]}');
    buf.writeln('要求：');
    buf.writeln('1. id 必须原样照抄我给的 id，不要改动。');
    buf.writeln('2. key_points 用 10-25 字概括这道题考什么。');
    buf.writeln('3. keywords 给 3-6 个最容易被 OCR 认错或换说法的词，逗号分隔。');
    buf.writeln('4. canonical 换一种说法重写题干，保留所有关键限定词（如"错误的是""不属于"）。');
    buf.writeln('5. 不要答题。');
    buf.writeln();
    for (final q in batch) {
      final opts = q.options.map((o) => o.text).join(' / ');
      buf.writeln('id=${q.id}');
      buf.writeln('题干：${q.stem}');
      if (opts.isNotEmpty) buf.writeln('选项：$opts');
      buf.writeln();
    }
    return buf.toString();
  }

  /// 构建索引。[onProgress] 汇报 (已完成, 总数)。
  Future<AiIndexBuildResult> build({
    required String bankId,
    required AiSettings settings,
    void Function(int done, int total)? onProgress,
  }) async {
    final questions = await db.getQuestions(bankId: bankId);
    if (questions.isEmpty) {
      return const AiIndexBuildResult(ok: 0, failed: 0, total: 0);
    }
    var ok = 0;
    var failed = 0;
    for (var start = 0; start < questions.length; start += batchSize) {
      final end = (start + batchSize).clamp(0, questions.length);
      final batch = questions.sublist(start, end);
      try {
        final entries = await _askBatch(settings, batch);
        if (entries.isNotEmpty) {
          await db.saveAiIndex(bankId, entries);
          ok += entries.length;
        }
        failed += batch.length - entries.length;
      } catch (_) {
        failed += batch.length;
      }
      onProgress?.call(end, questions.length);
    }
    return AiIndexBuildResult(ok: ok, failed: failed, total: questions.length);
  }

  Future<List<QuestionAiIndexEntry>> _askBatch(
    AiSettings settings,
    List<Question> batch,
  ) async {
    final url = settings.baseUrl.replaceAll(RegExp(r'/+$'), '');
    final model = settings.model.trim();
    final prompt = _prompt(batch);

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
          'model': model,
          'max_tokens': 4096,
          'system': _system,
          'messages': [
            {
              'role': 'user',
              'content': prompt,
            }
          ],
        }),
      ).timeout(const Duration(seconds: 120));
    } else if (settings.provider == AiProvider.gemini) {
      response = await http.post(
        Uri.parse('$url/v1beta/models/$model:generateContent?key=${settings.apiKey}'),
        headers: {'content-type': 'application/json'},
        body: jsonEncode({
          'systemInstruction': {
            'parts': [
              {'text': _system},
            ],
          },
          'contents': [
            {
              'role': 'user',
              'parts': [
                {'text': prompt},
              ],
            }
          ],
          'generationConfig': {'temperature': 0.1},
        }),
      ).timeout(const Duration(seconds: 120));
    } else {
      response = await http.post(
        Uri.parse('$url/chat/completions'),
        headers: {
          'content-type': 'application/json',
          'authorization': 'Bearer ${settings.apiKey}',
        },
        body: jsonEncode({
          'model': model,
          'messages': [
            {'role': 'system', 'content': _system},
            {'role': 'user', 'content': prompt},
          ],
          'temperature': 0.1,
        }),
      ).timeout(const Duration(seconds: 120));
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('HTTP ${response.statusCode}');
    }
    final json = jsonDecode(response.body) as Map<String, dynamic>;
    final content = AiService.extractText(json, settings.provider);
    return _parse(content, batch, model);
  }

  List<QuestionAiIndexEntry> _parse(
    String raw,
    List<Question> batch,
    String model,
  ) {
    final cleaned = raw
        .trim()
        .replaceFirst(RegExp(r'^```(?:json)?\s*'), '')
        .replaceFirst(RegExp(r'\s*```$'), '');
    dynamic data;
    try {
      data = jsonDecode(cleaned);
    } catch (_) {
      final s = cleaned.indexOf('{');
      final e = cleaned.lastIndexOf('}');
      if (s < 0 || e <= s) return const [];
      try {
        data = jsonDecode(cleaned.substring(s, e + 1));
      } catch (_) {
        return const [];
      }
    }
    final list = data is Map ? data['items'] : data;
    if (list is! List) return const [];

    // 只接受本批题目的 id，防止模型编造
    final valid = batch.map((q) => q.id).toSet();
    final out = <QuestionAiIndexEntry>[];
    for (final item in list) {
      if (item is! Map) continue;
      final id = (item['id'] ?? '').toString().trim();
      if (!valid.contains(id)) continue;
      out.add(QuestionAiIndexEntry(
        questionId: id,
        keyPoints: (item['key_points'] ?? '').toString().trim(),
        keywords: (item['keywords'] ?? '').toString().trim(),
        canonical: (item['canonical'] ?? '').toString().trim(),
        model: model,
      ));
    }
    return out;
  }
}

class AiIndexBuildResult {
  const AiIndexBuildResult({
    required this.ok,
    required this.failed,
    required this.total,
  });

  final int ok;
  final int failed;
  final int total;

  bool get allDone => ok >= total && total > 0;
}

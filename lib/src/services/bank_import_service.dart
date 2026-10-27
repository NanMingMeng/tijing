import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:uuid/uuid.dart';

import '../data/app_database.dart';
import '../models/import_draft.dart';
import '../models/question.dart';
import 'matcher.dart';

typedef ImportProgress = void Function(double value, String label);

class BankImportService {
  BankImportService(this.db);

  final AppDatabase db;
  static const _uuid = Uuid();

  Future<BankImportResult> importDrafts(
    String bankId,
    List<QuestionDraft> drafts, {
    ImportProgress? onProgress,
  }) async {
    onProgress?.call(0.03, '读取已有题库…');
    final existing = await db.getQuestions(bankId: bankId, limit: 100000);
    final existingHashes = existing.map((e) => e.contentHash).toSet();
    final existingBuckets = <String, List<String>>{};
    for (final question in existing) {
      final normalized = _normalize(question.stem);
      if (normalized.isEmpty) continue;
      _bucket(normalized).forEach((key) {
        existingBuckets.putIfAbsent(key, () => []).add(normalized);
      });
    }
    final now = DateTime.now().toIso8601String();
    final toInsert = <Question>[];
    final suspicious = <String>[];
    var skipped = 0;
    var issueCount = 0;

    onProgress?.call(0.08, '检查重复题…');
    for (var index = 0; index < drafts.length; index++) {
      final draft = drafts[index];
      if (draft.stem.trim().isEmpty) {
        skipped++;
        continue;
      }
      if (draft.hasIssues) issueCount++;
      final normalized = _normalize(draft.stem);
      final hash = _hash('$normalized|${draft.options.map((e) => _normalize(e.text)).join('|')}');
      if (existingHashes.contains(hash)) {
        skipped++;
        continue;
      }
      var nearDuplicate = false;
      final candidates = <String>{};
      for (final key in _bucket(normalized)) {
        final bucket = existingBuckets[key];
        if (bucket != null) candidates.addAll(bucket);
      }
      for (final other in candidates) {
        if (!_similarLength(normalized, other)) continue;
        final score = similarityScore(normalized, other);
        if (score >= 0.97) {
          nearDuplicate = true;
          break;
        }
        if (score >= 0.88) {
          suspicious.add(draft.stem.trim());
          break;
        }
      }
      if (nearDuplicate) {
        skipped++;
        continue;
      }
      existingHashes.add(hash);
      for (final key in _bucket(normalized)) {
        existingBuckets.putIfAbsent(key, () => []).add(normalized);
      }
      toInsert.add(Question(
        id: _uuid.v4(),
        bankId: bankId,
        type: draft.type,
        stem: draft.stem.trim(),
        options: draft.options,
        answerKeys: draft.answerKeys,
        answerTexts: draft.answerTexts,
        explanation: draft.explanation,
        source: draft.source,
        subject: draft.subject,
        chapter: draft.chapter,
        tags: draft.tags,
        difficulty: draft.difficulty,
        contentHash: hash,
        createdAt: now,
        updatedAt: now,
      ));
      if (index % 20 == 0) {
        onProgress?.call(
          0.10 + 0.50 * (index + 1) / (drafts.isEmpty ? 1 : drafts.length),
          '检查重复题 ${index + 1}/${drafts.length}',
        );
        await Future<void>.delayed(Duration.zero);
      }
    }

    onProgress?.call(0.65, '写入题库…');
    await db.insertQuestions(
      toInsert,
      onProgress: (done, total) {
        onProgress?.call(
          0.65 + 0.33 * done / (total == 0 ? 1 : total),
          '写入题库 $done/$total',
        );
      },
    );
    onProgress?.call(1, '导入完成');
    return BankImportResult(
      imported: toInsert.length,
      skipped: skipped,
      issueCount: issueCount,
      suspicious: suspicious,
    );
  }

  String _normalize(String value) => normalizeForMatch(value);

  String _hash(String value) => sha256.convert(utf8.encode(value)).toString();

  List<String> _bucket(String normalized) {
    if (normalized.isEmpty) return const [];
    final bucket = <String>[];
    final headLength = normalized.length < 10 ? normalized.length : 10;
    bucket.add('h:${normalized.substring(0, headLength)}');
    final tailStart = normalized.length > 8 ? normalized.length - 8 : 0;
    bucket.add('t:${normalized.substring(tailStart)}');
    bucket.add('l:${normalized.length ~/ 12}');
    return bucket;
  }

  bool _similarLength(String a, String b) {
    if (a.isEmpty || b.isEmpty) return false;
    final max = a.length > b.length ? a.length : b.length;
    final min = a.length > b.length ? b.length : a.length;
    return max > 0 && min / max >= 0.65;
  }
}


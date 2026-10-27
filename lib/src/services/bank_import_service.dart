import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:uuid/uuid.dart';

import '../data/app_database.dart';
import '../models/import_draft.dart';
import '../models/question.dart';
import 'matcher.dart';

class BankImportService {
  BankImportService(this.db);

  final AppDatabase db;
  static const _uuid = Uuid();

  Future<BankImportResult> importDrafts(
    String bankId,
    List<QuestionDraft> drafts,
  ) async {
    final existing = await db.getQuestions(bankId: bankId, limit: 100000);
    final existingHashes = existing.map((e) => e.contentHash).toSet();
    final existingNormalized = existing
        .map((e) => _normalize(e.stem))
        .where((e) => e.isNotEmpty)
        .toList();
    final now = DateTime.now().toIso8601String();
    final toInsert = <Question>[];
    final suspicious = <String>[];
    var skipped = 0;
    var issueCount = 0;

    for (final draft in drafts) {
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
      for (final other in existingNormalized) {
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
      existingNormalized.add(normalized);
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
    }

    await db.insertQuestions(toInsert);
    return BankImportResult(
      imported: toInsert.length,
      skipped: skipped,
      issueCount: issueCount,
      suspicious: suspicious,
    );
  }

  String _normalize(String value) => normalizeForMatch(value);

  String _hash(String value) => sha256.convert(utf8.encode(value)).toString();
}


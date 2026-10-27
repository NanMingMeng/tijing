import 'dart:math' as math;

import '../models/question.dart';

class MatchCandidate {
  const MatchCandidate({
    required this.question,
    required this.score,
    required this.reason,
  });

  final Question question;
  final double score;
  final String reason;
}

class MatchResult {
  const MatchResult({
    required this.candidates,
    required this.confident,
    required this.bestScore,
  });

  final List<MatchCandidate> candidates;
  final bool confident;
  final double bestScore;
}

String normalizeForMatch(String value) {
  final buffer = StringBuffer();
  for (final rune in value.runes) {
    int code = rune;
    if (code >= 0xFF01 && code <= 0xFF5E) {
      code -= 0xFEE0;
    }
    final char = String.fromCharCode(code).toLowerCase();
    if (RegExp(r'[\s\p{P}\p{S}]', unicode: true).hasMatch(char)) {
      continue;
    }
    buffer.write(char);
  }
  return buffer.toString();
}

int _levenshtein(String a, String b) {
  if (a == b) return 0;
  if (a.isEmpty) return b.length;
  if (b.isEmpty) return a.length;
  if (a.length > b.length) {
    final temp = a;
    a = b;
    b = temp;
  }
  var previous = List<int>.generate(a.length + 1, (i) => i);
  var current = List<int>.filled(a.length + 1, 0);
  for (var i = 0; i < b.length; i++) {
    current[0] = i + 1;
    final bCode = b.codeUnitAt(i);
    for (var j = 0; j < a.length; j++) {
      final cost = a.codeUnitAt(j) == bCode ? 0 : 1;
      current[j + 1] = math.min(
        math.min(current[j] + 1, previous[j + 1] + 1),
        previous[j] + cost,
      );
    }
    final temp = previous;
    previous = current;
    current = temp;
  }
  return previous[a.length];
}

double _bigramSimilarity(String a, String b) {
  if (a == b) return 1;
  if (a.isEmpty || b.isEmpty) return 0;
  if (a.length < 2 || b.length < 2) return 0;
  final aSet = <String>{};
  final bSet = <String>{};
  for (var i = 0; i < a.length - 1; i++) {
    aSet.add(a.substring(i, i + 2));
  }
  for (var i = 0; i < b.length - 1; i++) {
    bSet.add(b.substring(i, i + 2));
  }
  final intersection = aSet.intersection(bSet).length;
  final union = aSet.union(bSet).length;
  return union == 0 ? 0 : intersection / union;
}

double similarityScore(String query, String candidate) => _score(query, candidate);

double _score(String query, String candidate) {
  final q = normalizeForMatch(query);
  final c = normalizeForMatch(candidate);
  if (q.isEmpty || c.isEmpty) return 0;
  if (q == c) return 1;
  if (q.length >= 4 && c.contains(q)) return 0.96;
  if (c.length >= 4 && q.contains(c)) return 0.95;
  final maxLen = math.max(q.length, c.length);
  final lev = 1 - (_levenshtein(q, c) / maxLen);
  final bigram = _bigramSimilarity(q, c);
  final lengthPenalty = math.min(q.length, c.length) / maxLen;
  return (0.55 * lev + 0.35 * bigram + 0.10 * lengthPenalty).clamp(0.0, 1.0);
}

MatchResult matchQuestions(
  List<Question> questions,
  String query, {
  int limit = 3,
}) {
  final candidates = <MatchCandidate>[];
  for (final question in questions) {
    final stemScore = _score(query, question.stem);
    final allScore = _score(query, question.searchText);
    final score = math.max(stemScore, allScore);
    if (score >= 0.35) {
      candidates.add(MatchCandidate(
        question: question,
        score: score,
        reason: stemScore >= allScore ? '题干相似' : '题干和选项相似',
      ));
    }
  }
  candidates.sort((a, b) => b.score.compareTo(a.score));
  final top = candidates.take(limit).toList();
  if (top.isEmpty) {
    return const MatchResult(candidates: [], confident: false, bestScore: 0);
  }
  final best = top.first.score;
  final second = top.length > 1 ? top[1].score : 0.0;
  final confident = best >= 0.92 && best - second >= 0.08;
  return MatchResult(candidates: top, confident: confident, bestScore: best);
}


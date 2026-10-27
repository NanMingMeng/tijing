import 'question.dart';

class QuestionDraft {
  QuestionDraft({
    required this.stem,
    required this.type,
    this.options = const [],
    this.answerKeys = const [],
    this.answerTexts = const [],
    this.explanation = '',
    this.source = '',
    this.subject = '',
    this.chapter = '',
    this.tags = const [],
    this.difficulty = 0,
    this.issues = const [],
    this.sourceIndex = 0,
  });

  final String stem;
  final QuestionType type;
  final List<QuestionOption> options;
  final List<String> answerKeys;
  final List<String> answerTexts;
  final String explanation;
  final String source;
  final String subject;
  final String chapter;
  final List<String> tags;
  final int difficulty;
  final List<String> issues;

  /// 这份导入文件里的第几道题（从 1 开始，不含表头）。0 表示来源不明。
  final int sourceIndex;

  bool get hasIssues => issues.isNotEmpty;
}

class ImportPreview {
  const ImportPreview({
    required this.fileName,
    required this.drafts,
    this.headers = const [],
    this.mapping = const {},
    this.warnings = const [],
  });

  final String fileName;
  final List<QuestionDraft> drafts;
  final List<String> headers;
  final Map<String, int> mapping;
  final List<String> warnings;

  int get validCount => drafts.where((d) => d.stem.trim().isNotEmpty).length;
  int get issueCount => drafts.where((d) => d.hasIssues).length;
}

class BankImportResult {
  const BankImportResult({
    required this.imported,
    required this.skipped,
    required this.issueCount,
    this.suspicious = const [],
  });

  final int imported;
  final int skipped;
  final int issueCount;
  final List<String> suspicious;
}

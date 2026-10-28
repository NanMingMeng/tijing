/// AI 题库索引：模型为每道题提炼出的"考点/关键词/标准问法"。
/// 只用于本地匹配校验，不改变题目本身，也不替换题库答案。
class QuestionAiIndex {
  const QuestionAiIndex({
    this.keyPoints = '',
    this.keywords = '',
    this.canonical = '',
    this.model = '',
    this.builtAt = '',
  });

  /// 核心考点短语，例如"LOD300 建模精度"
  final String keyPoints;

  /// 易混关键词，逗号分隔
  final String keywords;

  /// 改写后的标准问法，用于和 OCR 文本做模糊比对
  final String canonical;

  final String model;
  final String builtAt;

  bool get isEmpty =>
      keyPoints.trim().isEmpty && keywords.trim().isEmpty && canonical.trim().isEmpty;
}

/// 写入索引时的载荷
class QuestionAiIndexEntry {
  const QuestionAiIndexEntry({
    required this.questionId,
    required this.keyPoints,
    required this.keywords,
    required this.canonical,
    required this.model,
  });

  final String questionId;
  final String keyPoints;
  final String keywords;
  final String canonical;
  final String model;
}

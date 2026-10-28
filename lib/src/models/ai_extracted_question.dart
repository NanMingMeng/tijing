/// AI 从整张图片中提取出的单道题（只提取，不答题）
class AiExtractedQuestion {
  const AiExtractedQuestion({
    required this.stem,
    required this.type,
    this.options = const [],
    this.answer = '',
  });

  final String stem;
  final String type;
  final List<String> options;
  final String answer;
}

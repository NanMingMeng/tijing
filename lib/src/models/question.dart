import 'dart:convert';

enum QuestionType {
  single,
  multiple,
  judge,
  fill,
  shortAnswer;

  static QuestionType fromCode(String? code) {
    switch (code) {
      case 'multiple':
        return QuestionType.multiple;
      case 'judge':
        return QuestionType.judge;
      case 'fill':
        return QuestionType.fill;
      case 'short':
        return QuestionType.shortAnswer;
      default:
        return QuestionType.single;
    }
  }

  static QuestionType fromLabel(String? label) {
    final value = (label ?? '').trim();
    if (value.contains('多选')) return QuestionType.multiple;
    if (value.contains('判断')) return QuestionType.judge;
    if (value.contains('填空')) return QuestionType.fill;
    if (value.contains('简答') || value.contains('问答')) {
      return QuestionType.shortAnswer;
    }
    return QuestionType.single;
  }

  String get code {
    switch (this) {
      case QuestionType.single:
        return 'single';
      case QuestionType.multiple:
        return 'multiple';
      case QuestionType.judge:
        return 'judge';
      case QuestionType.fill:
        return 'fill';
      case QuestionType.shortAnswer:
        return 'short';
    }
  }

  String get label {
    switch (this) {
      case QuestionType.single:
        return '单选';
      case QuestionType.multiple:
        return '多选';
      case QuestionType.judge:
        return '判断';
      case QuestionType.fill:
        return '填空';
      case QuestionType.shortAnswer:
        return '简答';
    }
  }
}

class QuestionOption {
  const QuestionOption({
    required this.key,
    required this.text,
    this.isCorrect = false,
  });

  final String key;
  final String text;
  final bool isCorrect;

  QuestionOption copyWith({String? key, String? text, bool? isCorrect}) {
    return QuestionOption(
      key: key ?? this.key,
      text: text ?? this.text,
      isCorrect: isCorrect ?? this.isCorrect,
    );
  }

  Map<String, dynamic> toJson() => {
        'key': key,
        'text': text,
        'isCorrect': isCorrect,
      };

  factory QuestionOption.fromJson(Map<String, dynamic> json) {
    return QuestionOption(
      key: (json['key'] ?? '').toString(),
      text: (json['text'] ?? '').toString(),
      isCorrect: json['isCorrect'] == true,
    );
  }
}

class Question {
  const Question({
    required this.id,
    required this.bankId,
    required this.type,
    required this.stem,
    this.options = const [],
    this.answerKeys = const [],
    this.answerTexts = const [],
    this.explanation = '',
    this.source = '',
    this.subject = '',
    this.chapter = '',
    this.tags = const [],
    this.difficulty = 0,
    this.contentHash = '',
    this.createdAt = '',
    this.updatedAt = '',
  });

  final String id;
  final String bankId;
  final QuestionType type;
  final String stem;
  final List<QuestionOption> options;
  final List<String> answerKeys;
  final List<String> answerTexts;
  final String explanation;
  final String source;
  final String subject;
  final String chapter;
  final List<String> tags;
  final int difficulty;
  final String contentHash;
  final String createdAt;
  final String updatedAt;

  String get answerDisplay {
    if (answerTexts.isNotEmpty) return answerTexts.join('、');
    return answerKeys.join('、');
  }

  String get searchText {
    final buffer = StringBuffer(stem);
    for (final option in options) {
      buffer.write(' ');
      buffer.write(option.text);
    }
    return buffer.toString();
  }

  Question copyWith({
    String? id,
    String? bankId,
    QuestionType? type,
    String? stem,
    List<QuestionOption>? options,
    List<String>? answerKeys,
    List<String>? answerTexts,
    String? explanation,
    String? source,
    String? subject,
    String? chapter,
    List<String>? tags,
    int? difficulty,
    String? contentHash,
    String? createdAt,
    String? updatedAt,
  }) {
    return Question(
      id: id ?? this.id,
      bankId: bankId ?? this.bankId,
      type: type ?? this.type,
      stem: stem ?? this.stem,
      options: options ?? this.options,
      answerKeys: answerKeys ?? this.answerKeys,
      answerTexts: answerTexts ?? this.answerTexts,
      explanation: explanation ?? this.explanation,
      source: source ?? this.source,
      subject: subject ?? this.subject,
      chapter: chapter ?? this.chapter,
      tags: tags ?? this.tags,
      difficulty: difficulty ?? this.difficulty,
      contentHash: contentHash ?? this.contentHash,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, Object?> toMap() {
    return {
      'id': id,
      'bank_id': bankId,
      'type': type.code,
      'stem': stem,
      'options_json': jsonEncode(options.map((e) => e.toJson()).toList()),
      'answer_keys_json': jsonEncode(answerKeys),
      'answer_texts_json': jsonEncode(answerTexts),
      'explanation': explanation,
      'source': source,
      'subject': subject,
      'chapter': chapter,
      'tags_json': jsonEncode(tags),
      'difficulty': difficulty,
      'content_hash': contentHash,
      'search_text': searchText,
      'created_at': createdAt,
      'updated_at': updatedAt,
    };
  }

  factory Question.fromMap(Map<String, Object?> map) {
    final options = <QuestionOption>[];
    final optionsRaw = jsonDecode((map['options_json'] as String?) ?? '[]');
    if (optionsRaw is List) {
      for (final item in optionsRaw) {
        if (item is Map) {
          options.add(QuestionOption.fromJson(Map<String, dynamic>.from(item)));
        }
      }
    }
    final keysRaw = jsonDecode((map['answer_keys_json'] as String?) ?? '[]');
    final textsRaw = jsonDecode((map['answer_texts_json'] as String?) ?? '[]');
    final tagsRaw = jsonDecode((map['tags_json'] as String?) ?? '[]');
    return Question(
      id: (map['id'] ?? '').toString(),
      bankId: (map['bank_id'] ?? '').toString(),
      type: QuestionType.fromCode(map['type']?.toString()),
      stem: (map['stem'] ?? '').toString(),
      options: options,
      answerKeys: keysRaw is List ? keysRaw.map((e) => e.toString()).toList() : [],
      answerTexts: textsRaw is List ? textsRaw.map((e) => e.toString()).toList() : [],
      explanation: (map['explanation'] ?? '').toString(),
      source: (map['source'] ?? '').toString(),
      subject: (map['subject'] ?? '').toString(),
      chapter: (map['chapter'] ?? '').toString(),
      tags: tagsRaw is List ? tagsRaw.map((e) => e.toString()).toList() : [],
      difficulty: int.tryParse((map['difficulty'] ?? '0').toString()) ?? 0,
      contentHash: (map['content_hash'] ?? '').toString(),
      createdAt: (map['created_at'] ?? '').toString(),
      updatedAt: (map['updated_at'] ?? '').toString(),
    );
  }
}

class QuestionBank {
  const QuestionBank({
    required this.id,
    required this.name,
    this.description = '',
    this.createdAt = '',
    this.updatedAt = '',
    this.questionCount = 0,
  });

  final String id;
  final String name;
  final String description;
  final String createdAt;
  final String updatedAt;
  final int questionCount;

  QuestionBank copyWith({int? questionCount, String? name, String? description}) {
    return QuestionBank(
      id: id,
      name: name ?? this.name,
      description: description ?? this.description,
      createdAt: createdAt,
      updatedAt: updatedAt,
      questionCount: questionCount ?? this.questionCount,
    );
  }
}

class AiRecord {
  const AiRecord({
    this.id,
    required this.questionId,
    required this.bankId,
    required this.provider,
    required this.model,
    required this.answer,
    this.explanation = '',
    this.steps = '',
    this.uncertainty = '',
    this.createdAt = '',
  });

  final int? id;
  final String questionId;
  final String bankId;
  final String provider;
  final String model;
  final String answer;
  final String explanation;
  final String steps;
  final String uncertainty;
  final String createdAt;

  Map<String, Object?> toMap() {
    return {
      'question_id': questionId,
      'bank_id': bankId,
      'provider': provider,
      'model': model,
      'answer': answer,
      'explanation': explanation,
      'steps': steps,
      'uncertainty': uncertainty,
      'created_at': createdAt,
    };
  }

  factory AiRecord.fromMap(Map<String, Object?> map) {
    return AiRecord(
      id: int.tryParse((map['id'] ?? '').toString()),
      questionId: (map['question_id'] ?? '').toString(),
      bankId: (map['bank_id'] ?? '').toString(),
      provider: (map['provider'] ?? '').toString(),
      model: (map['model'] ?? '').toString(),
      answer: (map['answer'] ?? '').toString(),
      explanation: (map['explanation'] ?? '').toString(),
      steps: (map['steps'] ?? '').toString(),
      uncertainty: (map['uncertainty'] ?? '').toString(),
      createdAt: (map['created_at'] ?? '').toString(),
    );
  }
}

import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:xml/xml.dart';

import '../models/import_draft.dart';
import '../models/question.dart';

class ExcelParseResult {
  const ExcelParseResult({
    required this.headers,
    required this.rows,
    required this.suggestedMapping,
  });

  final List<String> headers;
  final List<List<String>> rows;
  final Map<String, int> suggestedMapping;
}

class ExcelImportService {
  static const fieldLabels = {
    'stem': '题目',
    'type': '题型',
    'options': '选项内容',
    'answer': '答案',
    'source': '题源',
    'explanation': '解析',
    'subject': '科目',
    'chapter': '章节',
    'tags': '标签',
    'difficulty': '难度',
  };

  ExcelParseResult parseBytes(Uint8List bytes) {
    final archive = ZipDecoder().decodeBytes(bytes);
    final sharedStrings = _readSharedStrings(archive);
    final sheetPath = _firstSheetPath(archive);
    final sheetFile = archive.findFile(sheetPath);
    if (sheetFile == null) throw const FormatException('Excel 里没有工作表');
    final document = XmlDocument.parse(utf8.decode(sheetFile.content as List<int>));
    final rows = <List<String>>[];
    for (final row in document.descendants.whereType<XmlElement>()) {
      if (row.name.local != 'row') continue;
      final values = <int, String>{};
      for (final cell in row.descendants.whereType<XmlElement>()) {
        if (cell.name.local != 'c') continue;
        final ref = cell.getAttribute('r') ?? '';
        final index = _columnIndex(ref);
        if (index < 0) continue;
        final type = cell.getAttribute('t');
        final value = _cellText(cell, type, sharedStrings);
        values[index] = value;
      }
      if (values.isEmpty) continue;
      final max = values.keys.reduce((a, b) => a > b ? a : b);
      final line = List<String>.filled(max + 1, '');
      for (final entry in values.entries) {
        line[entry.key] = entry.value;
      }
      if (line.any((value) => value.trim().isNotEmpty)) rows.add(line);
    }
    if (rows.isEmpty) throw const FormatException('Excel 是空的');
    final headers = rows.first;
    return ExcelParseResult(
      headers: headers,
      rows: rows.skip(1).toList(),
      suggestedMapping: _suggestMapping(headers),
    );
  }

  List<String> _readSharedStrings(Archive archive) {
    final file = archive.findFile('xl/sharedStrings.xml');
    if (file == null) return [];
    final document = XmlDocument.parse(utf8.decode(file.content as List<int>));
    return [
      for (final si in document.descendants.whereType<XmlElement>())
        if (si.name.local == 'si')
          si.descendants.whereType<XmlElement>().where((e) => e.name.local == 't').map((e) => e.innerText).join(),
    ];
  }

  String _firstSheetPath(Archive archive) {
    final workbook = archive.findFile('xl/workbook.xml');
    final rels = archive.findFile('xl/_rels/workbook.xml.rels');
    if (workbook == null || rels == null) return 'xl/worksheets/sheet1.xml';
    final workbookDoc = XmlDocument.parse(utf8.decode(workbook.content as List<int>));
    final relDoc = XmlDocument.parse(utf8.decode(rels.content as List<int>));
    final sheet = workbookDoc.descendants.whereType<XmlElement>().firstWhere(
          (e) => e.name.local == 'sheet',
          orElse: () => XmlElement(XmlName('sheet')),
        );
    var relationId = '';
    for (final attr in sheet.attributes) {
      if (attr.name.local == 'id') relationId = attr.value;
    }
    final relation = relDoc.descendants.whereType<XmlElement>().firstWhere(
          (e) => e.name.local == 'Relationship' && e.getAttribute('Id') == relationId,
          orElse: () => XmlElement(XmlName('Relationship')),
        );
    final target = relation.getAttribute('Target') ?? 'worksheets/sheet1.xml';
    if (target.startsWith('/')) return 'xl${target}';
    return 'xl/$target';
  }

  int _columnIndex(String ref) {
    final letters = ref.replaceAll(RegExp(r'[^A-Za-z]'), '').toUpperCase();
    if (letters.isEmpty) return -1;
    var value = 0;
    for (var i = 0; i < letters.length; i++) {
      value = value * 26 + (letters.codeUnitAt(i) - 64);
    }
    return value - 1;
  }

  String _cellText(XmlElement cell, String? type, List<String> sharedStrings) {
    if (type == 'inlineStr') {
      final inline = cell.descendants.whereType<XmlElement>().where((e) => e.name.local == 't');
      return inline.map((e) => e.innerText).join();
    }
    XmlElement? valueElement;
    for (final element in cell.descendants.whereType<XmlElement>()) {
      if (element.name.local == 'v') {
        valueElement = element;
        break;
      }
    }
    final raw = valueElement?.innerText ?? '';
    if (type == 's') {
      final index = int.tryParse(raw);
      if (index != null && index >= 0 && index < sharedStrings.length) {
        return sharedStrings[index];
      }
      return '';
    }
    if (type == 'b') return raw == '1' ? '是' : '否';
    if (type == 'e') return '';
    return raw;
  }

  Map<String, int> _suggestMapping(List<String> headers) {
    final mapping = <String, int>{};
    final aliases = <String, List<String>>{
      'stem': ['题目', '题干', '问题', '试题'],
      'type': ['题型', '类型'],
      'options': ['选项内容', '选项', '备选项'],
      'answer': ['答案', '正确答案', '参考答案'],
      'source': ['题源', '来源', '出处'],
      'explanation': ['解析', '答案解析', '详解'],
      'subject': ['科目', '学科'],
      'chapter': ['章节', '知识点'],
      'tags': ['标签', '分类'],
      'difficulty': ['难度', '星级'],
    };
    for (final entry in aliases.entries) {
      for (var i = 0; i < headers.length; i++) {
        final header = headers[i].replaceAll(' ', '').toLowerCase();
        if (entry.value.any((alias) => header == alias || header.contains(alias))) {
          mapping[entry.key] = i;
          break;
        }
      }
    }
    return mapping;
  }

  List<QuestionDraft> buildDrafts(
    ExcelParseResult parsed,
    Map<String, int> mapping,
  ) {
    final drafts = <QuestionDraft>[];
    for (var rowIndex = 0; rowIndex < parsed.rows.length; rowIndex++) {
      final row = parsed.rows[rowIndex];
      String get(String field) {
        final index = mapping[field];
        if (index == null || index < 0 || index >= row.length) return '';
        return row[index].trim();
      }

      final stem = get('stem');
      if (stem.isEmpty && row.every((value) => value.trim().isEmpty)) {
        continue;
      }
      final rawType = get('type');
      final type = QuestionType.fromLabel(rawType);
      final optionTexts = _splitLines(get('options'));
      final options = <QuestionOption>[
        for (var i = 0; i < optionTexts.length; i++)
          QuestionOption(
            key: _optionKey(optionTexts[i], i),
            text: _stripOptionPrefix(optionTexts[i]),
          ),
      ];
      final rawAnswer = get('answer');
      final directAnswer = _matchAnswer(rawAnswer, options);
      final answerParts = directAnswer != null ? [rawAnswer] : _splitAnswer(rawAnswer);
      final answerKeys = <String>[];
      final answerTexts = <String>[];
      final issues = <String>[];
      if (stem.trim().isEmpty) issues.add('题目为空');
      if (rawAnswer.trim().isEmpty) issues.add('答案为空');
      for (final part in answerParts) {
        final matched = _matchAnswer(part, options);
        if (matched != null) {
          answerKeys.add(matched.key);
          answerTexts.add(matched.text);
        } else if (RegExp(r'^[A-Ha-h]$').hasMatch(part.trim())) {
          answerKeys.add(part.trim().toUpperCase());
          answerTexts.add(part.trim().toUpperCase());
        } else {
          answerTexts.add(part.trim());
        }
      }
      if (type == QuestionType.single && answerKeys.length > 1) {
        issues.add('单选题识别出多个答案，请核对');
      }
      if (options.isEmpty &&
          (type == QuestionType.single || type == QuestionType.multiple)) {
        issues.add('选择题没有识别到选项');
      }
      for (final option in options) {
        if (!answerKeys.contains(option.key) &&
            answerTexts.any((text) => _normalize(text) == _normalize(option.text))) {
          answerKeys.add(option.key);
        }
      }
      drafts.add(QuestionDraft(
        stem: stem,
        type: type,
        sourceIndex: rowIndex + 1,
        options: [
          for (final option in options)
            option.copyWith(isCorrect: answerKeys.contains(option.key)),
        ],
        answerKeys: answerKeys,
        answerTexts: answerTexts,
        explanation: get('explanation'),
        source: get('source'),
        subject: get('subject'),
        chapter: get('chapter'),
        tags: _splitLines(get('tags')),
        difficulty: int.tryParse(get('difficulty')) ?? 0,
        issues: issues,
      ));
    }
    return drafts;
  }

  List<String> _splitLines(String value) {
    return value
        .split(RegExp(r'\r?\n'))
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .toList();
  }

  List<String> _splitAnswer(String value) {
    final normalized = value.replaceAll('；', ';').replaceAll('，', ',');
    final parts = normalized
        .split(RegExp(r'[\r\n,;、]+'))
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .toList();
    return parts.isEmpty ? [value.trim()] : parts;
  }

  String _optionKey(String raw, int index) {
    final match = RegExp(r'^\s*([A-Ha-h])\s*[.)、:：-]?\s*(.*)$').firstMatch(raw);
    if (match != null && match.group(1) != null) {
      return match.group(1)!.toUpperCase();
    }
    return String.fromCharCode(65 + index);
  }

  String _stripOptionPrefix(String raw) {
    return raw.replaceFirst(RegExp(r'^\s*[A-Ha-h]\s*[.)、:：-]\s*'), '').trim();
  }

  QuestionOption? _matchAnswer(String raw, List<QuestionOption> options) {
    final value = raw.trim();
    if (value.isEmpty) return null;
    QuestionOption? byKey;
    for (final option in options) {
      if (option.key.toUpperCase() == value.toUpperCase()) {
        byKey = option;
        break;
      }
    }
    if (byKey != null) return byKey;
    final normalized = _normalize(value);
    for (final option in options) {
      if (_normalize(option.text) == normalized) return option;
    }
    for (final option in options) {
      final optionText = _normalize(option.text);
      if (optionText.isNotEmpty &&
          (optionText.contains(normalized) || normalized.contains(optionText))) {
        return option;
      }
    }
    return null;
  }

  String _normalize(String value) {
    return value
        .toLowerCase()
        .replaceAll(RegExp(r'\s+'), '')
        .replaceAll(RegExp(r'[，。！？；：、“”‘’（）\[\]【】]'), '');
  }
}



import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:xml/xml.dart';

import '../models/import_draft.dart';
import '../models/question.dart';

class WordImportService {
  ImportPreview parseBytes(Uint8List bytes, String fileName) {
    final archive = ZipDecoder().decodeBytes(bytes);
    final document = archive.findFile('word/document.xml');
    if (document == null) {
      throw const FormatException('不是有效的 .docx 文件');
    }
    final xmlText = utf8.decode(document.content as List<int>);
    final xmlDoc = XmlDocument.parse(xmlText);
    final paragraphs = <String>[];
    for (final element in xmlDoc.descendants.whereType<XmlElement>()) {
      if (element.name.local != 'p') continue;
      final buffer = StringBuffer();
      for (final child in element.descendants.whereType<XmlElement>()) {
        if (child.name.local == 't') {
          buffer.write(child.innerText);
        } else if (child.name.local == 'br' || child.name.local == 'tab') {
          buffer.write(' ');
        }
      }
      final text = buffer.toString().trim();
      if (text.isNotEmpty) paragraphs.add(text);
    }
    final drafts = _parseParagraphs(paragraphs);
    return ImportPreview(
      fileName: fileName,
      drafts: drafts,
      warnings: drafts.isEmpty ? ['没有识别到题目，可能需要用大模型补拆'] : const [],
    );
  }

  List<QuestionDraft> _parseParagraphs(List<String> paragraphs) {
    final drafts = <QuestionDraft>[];
    _Builder? current;
    final questionStart = RegExp(r'^\s*(\d{1,4})\s*[.、．)]\s*(.*)$');
    final optionStart = RegExp(r'^\s*([A-Ha-h])\s*[.、．):：]\s*(.*)$');
    final answerLine = RegExp(r'^\s*(答案|正确答案|参考答案)\s*[:：]\s*(.*)$');
    final explanationLine = RegExp(r'^\s*(解析|答案解析|详解)\s*[:：]\s*(.*)$');
    final typeLine = RegExp(r'^\s*(题型|类型)\s*[:：]\s*(.*)$');

    void flush() {
      if (current == null) return;
      drafts.add(current!.build());
      current = null;
    }

    for (final raw in paragraphs) {
      final text = raw.replaceAll(RegExp(r'\s+'), ' ').trim();
      final q = questionStart.firstMatch(text);
      if (q != null) {
        flush();
        current = _Builder(stem: '${q.group(2) ?? ''}'.trim());
        continue;
      }
      if (current == null) continue;
      final a = answerLine.firstMatch(text);
      if (a != null) {
        current!.answer = (a.group(2) ?? '').trim();
        continue;
      }
      final e = explanationLine.firstMatch(text);
      if (e != null) {
        current!.explanation = (e.group(2) ?? '').trim();
        continue;
      }
      final t = typeLine.firstMatch(text);
      if (t != null) {
        current!.typeText = (t.group(2) ?? '').trim();
        continue;
      }
      final op = optionStart.firstMatch(text);
      if (op != null) {
        current!.options.add(QuestionOption(
          key: (op.group(1) ?? '').toUpperCase(),
          text: (op.group(2) ?? '').trim(),
        ));
        continue;
      }
      if (current!.stem.isEmpty) {
        current!.stem = text;
      } else if (current!.options.isNotEmpty) {
        final last = current!.options.removeLast();
        current!.options.add(last.copyWith(text: '${last.text} $text'.trim()));
      } else {
        current!.stem = '${current!.stem} $text'.trim();
      }
    }
    flush();
    return drafts;
  }
}

class _Builder {
  _Builder({required this.stem});

  String stem;
  String typeText = '';
  String answer = '';
  String explanation = '';
  final List<QuestionOption> options = [];

  QuestionDraft build() {
    final type = QuestionType.fromLabel(typeText);
    final answerParts = answer
        .replaceAll('；', ';')
        .replaceAll('，', ',')
        .split(RegExp(r'[\r\n,;、]+'))
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .toList();
    final keys = <String>[];
    final texts = <String>[];
    final issues = <String>[];
    for (final part in answerParts) {
      final matched = _matchAnswer(part, options);
      if (matched != null) {
        keys.add(matched.key);
        texts.add(matched.text);
      } else if (RegExp(r'^[A-Ha-h]$').hasMatch(part)) {
        keys.add(part.toUpperCase());
        texts.add(part.toUpperCase());
      } else {
        texts.add(part);
      }
    }
    if (stem.trim().isEmpty) issues.add('题目为空');
    if (answer.trim().isEmpty) issues.add('答案为空');
    if (options.isEmpty &&
        (type == QuestionType.single || type == QuestionType.multiple)) {
      issues.add('选择题没有识别到选项');
    }
    return QuestionDraft(
      stem: stem.trim(),
      type: type,
      options: options,
      answerKeys: keys,
      answerTexts: texts,
      explanation: explanation,
      issues: issues,
    );
  }

  QuestionOption? _matchAnswer(String raw, List<QuestionOption> options) {
    final value = raw.trim();
    if (value.isEmpty) return null;
    for (final option in options) {
      if (option.key == value.toUpperCase()) return option;
      if (_norm(option.text) == _norm(value)) return option;
    }
    return null;
  }

  String _norm(String value) => value
      .toLowerCase()
      .replaceAll(RegExp(r'\s+'), '')
      .replaceAll(RegExp(r'[，。！？；：、“”‘’（）\[\]【】]'), '');
}

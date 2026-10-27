import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';

import '../data/app_database.dart';
import '../models/question.dart';
import '../services/matcher.dart';

class QuestionEditPage extends StatefulWidget {
  const QuestionEditPage({super.key, required this.question});

  final Question question;

  @override
  State<QuestionEditPage> createState() => _QuestionEditPageState();
}

class _QuestionEditPageState extends State<QuestionEditPage> {
  final _db = AppDatabase.instance;
  late final TextEditingController _stem;
  late final TextEditingController _options;
  late final TextEditingController _answers;
  late final TextEditingController _explanation;
  late final TextEditingController _source;
  late final TextEditingController _subject;
  late final TextEditingController _chapter;
  late final TextEditingController _tags;
  late QuestionType _type;
  late int _difficulty;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final q = widget.question;
    _stem = TextEditingController(text: q.stem);
    _options = TextEditingController(text: q.options.map((e) => '${e.key}. ${e.text}').join('\n'));
    _answers = TextEditingController(text: q.answerTexts.isNotEmpty ? q.answerTexts.join('\n') : q.answerKeys.join('\n'));
    _explanation = TextEditingController(text: q.explanation);
    _source = TextEditingController(text: q.source);
    _subject = TextEditingController(text: q.subject);
    _chapter = TextEditingController(text: q.chapter);
    _tags = TextEditingController(text: q.tags.join('，'));
    _type = q.type;
    _difficulty = q.difficulty;
  }

  @override
  void dispose() {
    for (final controller in [_stem, _options, _answers, _explanation, _source, _subject, _chapter, _tags]) {
      controller.dispose();
    }
    super.dispose();
  }

  List<QuestionOption> _parseOptions() {
    final lines = _options.text.split(RegExp(r'\r?\n')).map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
    return [
      for (var i = 0; i < lines.length; i++)
        QuestionOption(
          key: _optionKey(lines[i], i),
          text: _optionText(lines[i]),
        ),
    ];
  }

  String _optionKey(String line, int index) {
    final match = RegExp(r'^\s*([A-Ha-h])\s*[.)、:：-]\s*(.*)$').firstMatch(line);
    return match?.group(1)?.toUpperCase() ?? String.fromCharCode(65 + index);
  }

  String _optionText(String line) {
    return line.replaceFirst(RegExp(r'^\s*[A-Ha-h]\s*[.)、:：-]\s*'), '').trim();
  }

  Future<void> _save() async {
    if (_stem.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('题干不能为空')));
      return;
    }
    setState(() => _saving = true);
    final options = _parseOptions();
    final answerParts = _answers.text
        .replaceAll('；', ';')
        .replaceAll('，', ',')
        .split(RegExp(r'[\r\n,;、]+'))
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
    final keys = <String>[];
    final texts = <String>[];
    for (final part in answerParts) {
      QuestionOption? matched;
      for (final option in options) {
        if (option.key.toUpperCase() == part.toUpperCase() || normalizeForMatch(option.text) == normalizeForMatch(part)) {
          matched = option;
          break;
        }
      }
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
    final normalized = normalizeForMatch(_stem.text);
    final hashSource = '$normalized|${options.map((e) => normalizeForMatch(e.text)).join('|')}';
    final updated = widget.question.copyWith(
      type: _type,
      stem: _stem.text.trim(),
      options: options,
      answerKeys: keys,
      answerTexts: texts,
      explanation: _explanation.text.trim(),
      source: _source.text.trim(),
      subject: _subject.text.trim(),
      chapter: _chapter.text.trim(),
      tags: _tags.text.split(RegExp(r'[,，、]')).map((e) => e.trim()).where((e) => e.isNotEmpty).toList(),
      difficulty: _difficulty,
      contentHash: sha256.convert(utf8.encode(hashSource)).toString(),
      updatedAt: DateTime.now().toIso8601String(),
    );
    await _db.upsertQuestion(updated);
    if (!mounted) return;
    setState(() => _saving = false);
    Navigator.of(context).pop();
  }

  Future<void> _delete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除这道题？'),
        content: const Text('删除后不能恢复。'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('取消')),
          FilledButton(style: FilledButton.styleFrom(backgroundColor: Colors.red), onPressed: () => Navigator.pop(context, true), child: const Text('删除')),
        ],
      ),
    );
    if (ok == true) {
      await _db.deleteQuestion(widget.question.id);
      if (mounted) Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('编辑题目'),
        actions: [
          IconButton(onPressed: _delete, icon: const Icon(Icons.delete_outline_rounded)),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(18, 8, 18, 30),
        children: [
          DropdownButtonFormField<QuestionType>(
            initialValue: _type,
            decoration: const InputDecoration(labelText: '题型'),
            items: QuestionType.values.map((type) => DropdownMenuItem(value: type, child: Text(type.label))).toList(),
            onChanged: (value) => setState(() => _type = value ?? _type),
          ),
          const SizedBox(height: 12),
          TextField(controller: _stem, minLines: 3, maxLines: 8, decoration: const InputDecoration(labelText: '题目', hintText: '输入题干')),
          const SizedBox(height: 12),
          TextField(controller: _options, minLines: 3, maxLines: 10, decoration: const InputDecoration(labelText: '选项', hintText: '每行一个选项，例如：\nA. 选项一\nB. 选项二')),
          const SizedBox(height: 12),
          TextField(controller: _answers, minLines: 1, maxLines: 4, decoration: const InputDecoration(labelText: '答案', hintText: '选项原文或 A/B/C/D，多个答案换行')),
          const SizedBox(height: 12),
          TextField(controller: _explanation, minLines: 2, maxLines: 6, decoration: const InputDecoration(labelText: '解析')),
          const SizedBox(height: 12),
          TextField(controller: _source, decoration: const InputDecoration(labelText: '题源')),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(child: TextField(controller: _subject, decoration: const InputDecoration(labelText: '科目'))),
            const SizedBox(width: 10),
            Expanded(child: TextField(controller: _chapter, decoration: const InputDecoration(labelText: '章节'))),
          ]),
          const SizedBox(height: 12),
          TextField(controller: _tags, decoration: const InputDecoration(labelText: '标签', hintText: '用逗号分隔')),
          const SizedBox(height: 12),
          DropdownButtonFormField<int>(
            initialValue: _difficulty,
            decoration: const InputDecoration(labelText: '难度'),
            items: const [
              DropdownMenuItem(value: 0, child: Text('未设置')),
              DropdownMenuItem(value: 1, child: Text('容易')),
              DropdownMenuItem(value: 2, child: Text('中等')),
              DropdownMenuItem(value: 3, child: Text('较难')),
              DropdownMenuItem(value: 4, child: Text('困难')),
            ],
            onChanged: (value) => setState(() => _difficulty = value ?? 0),
          ),
          const SizedBox(height: 22),
          FilledButton.icon(
            onPressed: _saving ? null : _save,
            icon: _saving ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Icon(Icons.save_rounded),
            label: Text(_saving ? '保存中…' : '保存修改'),
          ),
        ],
      ),
    );
  }
}



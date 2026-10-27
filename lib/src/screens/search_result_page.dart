import 'dart:io';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/app_database.dart';
import '../models/question.dart';
import '../services/ai_service.dart';
import '../services/matcher.dart';
import '../theme.dart';
import 'settings_page.dart';

class SearchResultPage extends StatefulWidget {
  const SearchResultPage({
    super.key,
    required this.bank,
    required this.recognizedText,
    this.imagePath,
  });

  final QuestionBank bank;
  final String recognizedText;
  final String? imagePath;

  @override
  State<SearchResultPage> createState() => _SearchResultPageState();
}

class _SearchResultPageState extends State<SearchResultPage> {
  final _db = AppDatabase.instance;
  late final TextEditingController _text;
  MatchResult? _result;
  bool _searching = true;
  bool _aiLoading = false;
  AiAnswer? _aiAnswer;
  String? _aiError;

  @override
  void initState() {
    super.initState();
    _text = TextEditingController(text: widget.recognizedText);
    _search();
  }

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    setState(() {
      _searching = true;
      _aiAnswer = null;
      _aiError = null;
    });
    final questions = await _db.getQuestions(bankId: widget.bank.id, limit: 100000);
    final result = matchQuestions(questions, _text.text);
    if (!mounted) return;
    setState(() {
      _result = result;
      _searching = false;
    });
  }

  Future<void> _askAi() async {
    final settings = await AiSettingsStore.load();
    if (!settings.ready) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('请先在设置里填写 AI 接口和密钥')));
      await Navigator.of(context).push(MaterialPageRoute(builder: (_) => const SettingsPage()));
      return;
    }
    final prefs = await SharedPreferences.getInstance();
    final consent = prefs.getBool('ai_consent_v1') ?? false;
    if (!consent) {
      if (!mounted) return;
      final ok = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('使用 AI 作答'),
          content: const Text('题目文字会发送给你选择的模型服务。API Key 只保存在本机安全存储里，不会写进分享文件。'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('取消')),
            FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('继续')),
          ],
        ),
      );
      if (ok != true) return;
      await prefs.setBool('ai_consent_v1', true);
    }
    setState(() {
      _aiLoading = true;
      _aiError = null;
    });
    try {
      final answer = await AiService.ask(settings: settings, questionText: _text.text);
      if (!mounted) return;
      final best = _result?.candidates.isNotEmpty == true ? _result!.candidates.first.question : null;
      await _db.saveAiRecord(AiRecord(
        questionId: best?.id ?? '',
        bankId: widget.bank.id,
        provider: settings.provider.label,
        model: settings.model,
        answer: answer.answer,
        explanation: answer.explanation,
        steps: answer.steps,
        uncertainty: answer.uncertainty,
        createdAt: DateTime.now().toIso8601String(),
      ));
      if (!mounted) return;
      setState(() => _aiAnswer = answer);
    } catch (e) {
      if (!mounted) return;
      setState(() => _aiError = e.toString());
    } finally {
      if (mounted) setState(() => _aiLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('搜索结果')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(18, 8, 18, 30),
        children: [
          if (widget.imagePath != null && File(widget.imagePath!).existsSync())
            ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: Image.file(File(widget.imagePath!), height: 170, width: double.infinity, fit: BoxFit.cover),
            ),
          if (widget.imagePath != null) const SizedBox(height: 14),
          TextField(
            controller: _text,
            minLines: 3,
            maxLines: 8,
            decoration: InputDecoration(
              labelText: '识别到的题目',
              suffixIcon: IconButton(onPressed: _search, icon: const Icon(Icons.search_rounded)),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              const Icon(Icons.info_outline_rounded, size: 16, color: AppTheme.muted),
              const SizedBox(width: 6),
              const Expanded(child: Text('搜错了就改上面的文字，再点搜索。', style: TextStyle(fontSize: 12, color: AppTheme.muted))),
              FilledButton.tonal(onPressed: _search, child: const Text('重新搜索')),
            ],
          ),
          const SizedBox(height: 18),
          if (_searching)
            const Center(child: Padding(padding: EdgeInsets.all(30), child: CircularProgressIndicator()))
          else if (_result == null || _result!.candidates.isEmpty)
            _noMatchCard()
          else ...[
            _resultHeader(_result!),
            const SizedBox(height: 10),
            ..._result!.candidates.map((candidate) => _candidateCard(candidate)),
          ],
          const SizedBox(height: 18),
          OutlinedButton.icon(
            onPressed: _aiLoading ? null : _askAi,
            icon: _aiLoading
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.auto_awesome_rounded),
            label: Text(_aiLoading ? 'AI 正在作答…' : 'AI 作答'),
          ),
          if (_aiError != null) ...[
            const SizedBox(height: 12),
            _errorCard(_aiError!),
          ],
          if (_aiAnswer != null) ...[
            const SizedBox(height: 18),
            _aiAnswerCard(_aiAnswer!),
          ],
        ],
      ),
    );
  }

  Widget _resultHeader(MatchResult result) {
    final confident = result.confident;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: confident ? const Color(0xFFF0FDFA) : const Color(0xFFFFFBEB),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: confident ? const Color(0xFF99F6E4) : const Color(0xFFFDE68A)),
      ),
      child: Row(
        children: [
          Icon(confident ? Icons.check_circle_outline_rounded : Icons.help_outline_rounded, color: confident ? AppTheme.primary : AppTheme.warm),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              _headerText(result),
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }

  String _headerText(MatchResult result) {
    final best = result.candidates.first;
    final q = best.question;
    final where = q.indexDescription.isEmpty ? '' : '，命中$q.indexDescription'.replaceFirst('命中', '命中 ');
    if (result.confident) {
      return '题库里找到原题$where';
    }
    final top = (best.score * 100).toStringAsFixed(0);
    return '还不能确定是哪一道（最像的 ${q.indexDescription.isEmpty ? '候选' : q.indexDescription}，${top}%），请从下面选';
  }

  Widget _candidateCard(MatchCandidate candidate) {
    final question = candidate.question;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: GestureDetector(
        onTap: () => _showQuestion(question),
        child: Container(
          padding: const EdgeInsets.all(15),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppTheme.line),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(color: AppTheme.primary.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(7)),
                    child: Text(question.type.label, style: const TextStyle(fontSize: 11, color: AppTheme.primary, fontWeight: FontWeight.w700)),
                  ),
                  const Spacer(),
                  Text('相似度 ${(candidate.score * 100).toStringAsFixed(0)}%',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: candidate.score >= 0.92 ? AppTheme.primary : AppTheme.muted,
                      )),
                ],
              ),
              if (question.indexDescription.isNotEmpty) ...[
                const SizedBox(height: 8),
                Row(
                  children: [
                    const Icon(Icons.tag_rounded, size: 13, color: AppTheme.muted),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        question.indexDescription,
                        style: const TextStyle(fontSize: 12, color: AppTheme.muted, fontWeight: FontWeight.w600),
                      ),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 9),
              Text(question.stem, maxLines: 3, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 15, height: 1.45, fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              Text('答案：${question.answerDisplay}', style: const TextStyle(fontSize: 13, color: AppTheme.primaryDark, fontWeight: FontWeight.w700), maxLines: 2, overflow: TextOverflow.ellipsis),
            ],
          ),
        ),
      ),
    );
  }

  void _showQuestion(Question question) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.72,
        minChildSize: 0.4,
        maxChildSize: 0.95,
        builder: (context, controller) => Container(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
          decoration: const BoxDecoration(color: Colors.white, borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
          child: ListView(
            controller: controller,
            children: [
              Center(child: Container(width: 42, height: 4, decoration: BoxDecoration(color: AppTheme.line, borderRadius: BorderRadius.circular(99)))),
              const SizedBox(height: 18),
              if (question.indexDescription.isNotEmpty) ...[
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: AppTheme.primary.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(9),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.tag_rounded, size: 14, color: AppTheme.primary),
                      const SizedBox(width: 5),
                      Text(question.indexDescription,
                          style: const TextStyle(fontSize: 12, color: AppTheme.primary, fontWeight: FontWeight.w700)),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
              ],
              Text(question.stem, style: const TextStyle(fontSize: 18, height: 1.5, fontWeight: FontWeight.w700)),
              const SizedBox(height: 16),
              ...question.options.map((option) => Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: option.isCorrect ? const Color(0xFFF0FDFA) : AppTheme.background,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text('${option.key}. ${option.text}', style: TextStyle(fontWeight: option.isCorrect ? FontWeight.w700 : FontWeight.w400)),
                  )),
              const SizedBox(height: 12),
              _section('答案', question.answerDisplay),
              if (question.explanation.isNotEmpty) _section('解析', question.explanation),
              if (question.source.isNotEmpty) _section('题源', question.source),
            ],
          ),
        ),
      ),
    );
  }

  Widget _section(String title, String content) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontSize: 13, color: AppTheme.muted, fontWeight: FontWeight.w600)),
          const SizedBox(height: 5),
          Text(content, style: const TextStyle(fontSize: 15, height: 1.6)),
        ],
      ),
    );
  }

  Widget _noMatchCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(18), border: Border.all(color: AppTheme.line)),
      child: const Column(
        children: [
          Icon(Icons.search_off_rounded, size: 40, color: AppTheme.muted),
          SizedBox(height: 10),
          Text('题库里没有找到相似题', style: TextStyle(fontWeight: FontWeight.w700)),
          SizedBox(height: 6),
          Text('可以先改一下识别文字，或者点下面的 AI 作答', textAlign: TextAlign.center, style: TextStyle(color: AppTheme.muted, fontSize: 13)),
        ],
      ),
    );
  }

  Widget _errorCard(String error) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: const Color(0xFFFEF2F2), borderRadius: BorderRadius.circular(12), border: Border.all(color: const Color(0xFFFECACA))),
      child: Text(error, style: const TextStyle(fontSize: 12, color: Color(0xFFB91C1C))),
    );
  }

  Widget _aiAnswerCard(AiAnswer answer) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(color: const Color(0xFFF5F3FF), borderRadius: BorderRadius.circular(18), border: Border.all(color: const Color(0xFFDDD6FE))),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.auto_awesome_rounded, color: Color(0xFF7C3AED)),
              const SizedBox(width: 8),
              const Text('AI 答案', style: TextStyle(fontWeight: FontWeight.w800, color: Color(0xFF5B21B6))),
              const Spacer(),
              if (answer.uncertain)
                const Text('不确定', style: TextStyle(fontSize: 12, color: AppTheme.warm, fontWeight: FontWeight.w700)),
            ],
          ),
          const SizedBox(height: 12),
          _section('答案', answer.answer.isEmpty ? '模型没有返回答案' : answer.answer),
          if (answer.explanation.isNotEmpty) _section('解析', answer.explanation),
          if (answer.steps.isNotEmpty) _section('步骤', answer.steps),
          if (answer.uncertainty.isNotEmpty) _section('不确定原因', answer.uncertainty),
        ],
      ),
    );
  }
}

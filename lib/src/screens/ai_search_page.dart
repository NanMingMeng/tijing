import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../data/app_database.dart';
import '../models/ai_extracted_question.dart';
import '../models/question.dart';
import '../models/question_ai_index.dart';
import '../services/ai_service.dart';
import '../services/matcher.dart';
import '../theme.dart';
import 'settings_page.dart';

/// AI 查题：整页识别 → 本地题库匹配 → 未命中自动 AI 作答。
class AiSearchPage extends StatefulWidget {
  const AiSearchPage({super.key});

  @override
  State<AiSearchPage> createState() => _AiSearchPageState();
}

/// 单道题的识别 + 匹配 + 作答状态
class _Item {
  _Item(this.extracted);

  final AiExtractedQuestion extracted;
  MatchCandidate? hit;      // 题库命中
  AiAnswer? aiAnswer;       // AI 作答
  String? aiError;
  bool aiLoading = false;
  bool saved = false;
}

class _AiSearchPageState extends State<AiSearchPage> {
  final _picker = ImagePicker();
  final _db = AppDatabase.instance;

  String? _imagePath;
  bool _extracting = false;
  String? _error;
  List<_Item> _items = [];
  QuestionBank? _bank;      // 用于匹配和保存
  Map<String, QuestionAiIndex> _index = {};
  String _stage = '';

  @override
  void initState() {
    super.initState();
    _loadBank();
  }

  Future<void> _loadBank() async {
    final banks = await _db.listBanks();
    if (!mounted) return;
    if (banks.isEmpty) {
      setState(() => _error = '还没有题库。请先到「题库」导入，AI 才能比对。');
      return;
    }
    // 默认用题量最大的题库
    banks.sort((a, b) => b.questionCount.compareTo(a.questionCount));
    final bank = banks.first;
    final index = await _db.loadAiIndex(bank.id);
    if (!mounted) return;
    setState(() {
      _bank = bank;
      _index = index;
    });
  }

  Future<void> _pick(ImageSource source) async {
    setState(() => _error = null);
    XFile? file;
    try {
      file = await _picker.pickImage(source: source, imageQuality: 88, maxWidth: 2000);
    } catch (e) {
      setState(() => _error = '选图失败：$e');
      return;
    }
    if (file == null) return;
    if (!mounted) return;
    setState(() {
      _imagePath = file!.path;
      _items = [];
      _error = null;
    });
    await _runExtract();
  }

  Future<void> _runExtract() async {
    final path = _imagePath;
    if (path == null) return;
    final settings = await AiSettingsStore.load();
    if (!mounted) return;
    if (!settings.ready) {
      setState(() => _error = 'AI 未配置：${settings.missingHint}');
      await Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const SettingsPage()),
      );
      final again = await AiSettingsStore.load();
      if (!again.ready) return;
    }
    setState(() {
      _extracting = true;
      _stage = 'AI 正在读图提取题目…';
      _error = null;
    });
    try {
      final list = await AiService.extractQuestions(
        settings: settings.ready ? settings : await AiSettingsStore.load(),
        imagePath: path,
        maxCount: 10,
      );
      if (!mounted) return;
      if (list.isEmpty) {
        setState(() {
          _extracting = false;
          _error = '没识别出题目。可能是图片太模糊、题目太多，或模型不支持图片输入。';
        });
        return;
      }
      final items = list.map<_Item>((e) => _Item(e)).toList();
      setState(() {
        _items = items;
        _extracting = false;
        _stage = '正在比对题库…';
      });
      await _matchAll();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _extracting = false;
        _error = '提取失败：$e';
      });
    }
  }

  /// 把识别出的题逐道拿去题库匹配；有索引时用索引做二次确认。
  Future<void> _matchAll() async {
    final bank = _bank;
    if (bank == null) return;
    final questions = await _db.getQuestions(bankId: bank.id);
    final byId = {for (final q in questions) q.id: q};

    for (final item in _items) {
      // 1) 用题干(+选项)走现有相似度匹配
      final query = [item.extracted.stem, ...item.extracted.options].join(' ');
      final result = matchQuestions(questions, query, limit: 3);
      MatchCandidate? best = result.candidates.isNotEmpty ? result.candidates.first : null;

      // 2) 有 AI 索引时，用索引里的 canonical/keywords 再算一次，取更可信的那个
      if (_index.isNotEmpty) {
        var bestId = best?.question.id;
        var bestScore = best?.score ?? 0;
        for (final entry in _index.entries) {
          final idx = entry.value;
          if (idx.isEmpty) continue;
          final probe = [idx.canonical, idx.keyPoints, idx.keywords].where((s) => s.trim().isNotEmpty).join(' ');
          if (probe.isEmpty) continue;
          final s = similarityScore(query, probe);
          if (s > bestScore) {
            final q = byId[entry.key];
            if (q != null) {
              bestScore = s;
              bestId = entry.key;
            }
          }
        }
        if (bestId != null && (best == null || best.question.id != bestId)) {
          final q = byId[bestId];
          if (q != null) {
            best = MatchCandidate(question: q, score: bestScore, reason: 'AI 索引匹配');
          }
        }
      }

      // 3) 阈值：够高才算命中
      if (best != null && best.score >= 0.80) {
        item.hit = best;
      } else {
        item.hit = null;
      }
    }
    if (!mounted) return;
    setState(() => _stage = '');
    await _answerMissed();
  }

  /// 未命中的题自动让 AI 作答（用户选的是全自动方案 A）
  Future<void> _answerMissed() async {
    final missed = _items.where((i) => i.hit == null).toList();
    if (missed.isEmpty) return;
    final settings = await AiSettingsStore.load();
    if (!settings.ready) return;

    for (final item in missed) {
      if (!mounted) return;
      setState(() {
        item.aiLoading = true;
        _stage = 'AI 正在作答（${_items.indexOf(item) + 1}/${_items.length}）…';
      });
      try {
        final answer = await AiService.ask(
          settings: settings,
          questionText: [
            item.extracted.stem,
            ...item.extracted.options,
          ].join('\n'),
          imagePath: _imagePath,
          preferImage: false, // 这里用的是已提取文字，避免重复上传整图
        );
        if (!mounted) return;
        setState(() {
          item.aiAnswer = answer;
          item.aiLoading = false;
        });
      } catch (e) {
        if (!mounted) return;
        setState(() {
          item.aiError = e.toString();
          item.aiLoading = false;
        });
      }
    }
    if (!mounted) return;
    setState(() => _stage = '');
  }

  /// 把一道未命中的题存进题库（题号自动续写）
  Future<void> _saveToBank(_Item item) async {
    final bank = _bank;
    if (bank == null || item.saved) return;
    setState(() => _stage = '正在存入题库…');
    try {
      final stem = item.extracted.stem.trim();
      final options = <QuestionOption>[];
      final answerKeys = <String>[];
      final answerTexts = <String>[];
      final aiAns = item.aiAnswer?.answer ?? item.extracted.answer;
      for (var i = 0; i < item.extracted.options.length; i++) {
        final key = String.fromCharCode(65 + i);
        options.add(QuestionOption(key: key, text: item.extracted.options[i]));
      }
      // AI 答案里若出现 "A" / "AB" / "A、B" 之类的字母，就映射成选项
      final letters = RegExp(r'[A-H]').allMatches(aiAns.toUpperCase()).map((m) => m.group(0)!).toSet();
      for (final opt in options) {
        if (letters.contains(opt.key)) {
          answerKeys.add(opt.key);
          answerTexts.add(opt.text);
        }
      }
      if (answerTexts.isEmpty && aiAns.trim().isNotEmpty) {
        answerTexts.add(aiAns.trim());
      }
      final nextOrder = await _db.nextOrderIndex(bank.id);
      final nextSource = await _db.nextSourceIndex(bank.id);
      final now = DateTime.now().toIso8601String();
      final type = QuestionType.fromCode(item.extracted.type);
      await _db.upsertQuestion(Question(
        id: 'ai-${DateTime.now().microsecondsSinceEpoch}',
        bankId: bank.id,
        type: type,
        stem: stem,
        options: [
          for (final o in options)
            o.copyWith(isCorrect: answerKeys.contains(o.key)),
        ],
        answerKeys: answerKeys,
        answerTexts: answerTexts,
        explanation: item.aiAnswer?.explanation ?? '',
        source: 'AI 查题',
        contentHash: '',
        sourceIndex: nextSource,
        orderIndex: nextOrder,
        createdAt: now,
        updatedAt: now,
      ));
      if (!mounted) return;
      setState(() {
        item.saved = true;
        _stage = '';
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('已存入题库')),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _stage = '');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('存入失败：$e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('AI 查题'),
        actions: [
          IconButton(
            onPressed: _extracting ? null : () => _pick(ImageSource.gallery),
            icon: const Icon(Icons.photo_library_outlined),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 30),
        children: [
          _headerCard(),
          if (_stage.isNotEmpty) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                const SizedBox(width: 10),
                Expanded(child: Text(_stage, style: const TextStyle(fontSize: 13, color: AppTheme.muted))),
              ],
            ),
          ],
          if (_error != null) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFFFEF2F2),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFFECACA)),
              ),
              child: Text(_error!, style: const TextStyle(fontSize: 12, color: Color(0xFFB91C1C))),
            ),
          ],
          const SizedBox(height: 14),
          ..._items.map(_itemCard),
        ],
      ),
    );
  }

  Widget _headerCard() {
    final bankName = _bank?.name ?? '（未选择题库）';
    final idxCount = _index.length;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF0F766E), Color(0xFF115E59)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('拍一张整页题目', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w800)),
          const SizedBox(height: 6),
          Text(
            'AI 读出全部题目（最多 10 道），先查「$bankName」，查不到的自己作答。',
            style: TextStyle(color: Colors.white.withValues(alpha: 0.82), fontSize: 13, height: 1.5),
          ),
          const SizedBox(height: 4),
          Text(
            idxCount > 0 ? '已建 AI 索引 $idxCount 题，匹配更准' : '题库还没建 AI 索引，匹配仅靠文字相似度',
            style: TextStyle(color: Colors.white.withValues(alpha: 0.62), fontSize: 11),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: AppTheme.primaryDark,
                    minimumSize: const Size(0, 46),
                  ),
                  onPressed: _extracting ? null : () => _pick(ImageSource.camera),
                  icon: const Icon(Icons.photo_camera_rounded, size: 20),
                  label: const Text('拍照'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.white.withValues(alpha: 0.18),
                    foregroundColor: Colors.white,
                    minimumSize: const Size(0, 46),
                  ),
                  onPressed: _extracting ? null : () => _pick(ImageSource.gallery),
                  icon: const Icon(Icons.photo_library_rounded, size: 20),
                  label: const Text('相册'),
                ),
              ),
            ],
          ),
          if (_imagePath != null) ...[
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: Image.file(
                File(_imagePath!),
                height: 90,
                width: double.infinity,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => const SizedBox.shrink(),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _itemCard(_Item item) {
    final hit = item.hit;
    final q = hit?.question;
    final isHit = q != null;
    final accent = isHit ? const Color(0xFF0F766E) : const Color(0xFFB45309);
    final bg = isHit ? const Color(0xFFF0FDFA) : const Color(0xFFFFFBEB);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 状态行
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(7)),
                child: Text(
                  isHit ? '题库有' : '题库没有',
                  style: TextStyle(fontSize: 11, color: accent, fontWeight: FontWeight.w700),
                ),
              ),
              if (isHit && q.indexDescription.isNotEmpty) ...[
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    q.indexDescription,
                    style: const TextStyle(fontSize: 11, color: AppTheme.muted, fontWeight: FontWeight.w600),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 9),
          Text(
            item.extracted.stem,
            style: const TextStyle(fontSize: 15, height: 1.45, fontWeight: FontWeight.w600),
          ),
          if (item.extracted.options.isNotEmpty) ...[
            const SizedBox(height: 8),
            ...item.extracted.options.map((o) => Padding(
                  padding: const EdgeInsets.only(bottom: 3),
                  child: Text(o, style: const TextStyle(fontSize: 13, color: AppTheme.muted, height: 1.4)),
                )),
          ],
          const SizedBox(height: 10),
          if (isHit)
            Text(
              '题库答案：${q.answerDisplay}',
              style: const TextStyle(fontSize: 13, color: Color(0xFF0F766E), fontWeight: FontWeight.w700),
            )
          else
            _aiBlock(item),
        ],
      ),
    );
  }

  Widget _aiBlock(_Item item) {
    if (item.aiLoading) {
      return Row(
        children: const [
          SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)),
          SizedBox(width: 8),
          Text('AI 正在作答…', style: TextStyle(fontSize: 12, color: AppTheme.muted)),
        ],
      );
    }
    if (item.aiError != null) {
      return Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: const Color(0xFFFEF2F2),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text(item.aiError!, style: const TextStyle(fontSize: 11, color: Color(0xFFB91C1C))),
      );
    }
    final ans = item.aiAnswer;
    if (ans == null) {
      return const Text('（未作答）', style: TextStyle(fontSize: 12, color: AppTheme.muted));
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xFFF5F3FF),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFFDDD6FE)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.auto_awesome_rounded, size: 16, color: Color(0xFF7C3AED)),
                  const SizedBox(width: 6),
                  const Text('AI 答案', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: Color(0xFF5B21B6))),
                  const Spacer(),
                  if (ans.uncertain)
                    const Text('不确定', style: TextStyle(fontSize: 11, color: AppTheme.warm, fontWeight: FontWeight.w700)),
                ],
              ),
              const SizedBox(height: 8),
              Text(ans.answer.isEmpty ? '模型没有返回答案' : ans.answer,
                  style: const TextStyle(fontSize: 13, height: 1.5, fontWeight: FontWeight.w600)),
              if (ans.explanation.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(ans.explanation, style: const TextStyle(fontSize: 12, color: AppTheme.muted, height: 1.5)),
              ],
            ],
          ),
        ),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerRight,
          child: item.saved
              ? const Text('已存入题库', style: TextStyle(fontSize: 12, color: AppTheme.muted))
              : TextButton.icon(
                  onPressed: () => _saveToBank(item),
                  icon: const Icon(Icons.library_add_outlined, size: 18),
                  label: const Text('存入题库'),
                ),
        ),
      ],
    );
  }
}

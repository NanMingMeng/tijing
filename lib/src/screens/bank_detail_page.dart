import 'package:flutter/material.dart';

import '../data/app_database.dart';
import '../models/question.dart';
import '../services/ai_index_builder.dart';
import '../services/ai_service.dart';
import '../services/bank_events.dart';
import '../theme.dart';
import 'import_page.dart';
import 'question_edit_page.dart';

class BankDetailPage extends StatefulWidget {
  const BankDetailPage({super.key, required this.bank});

  final QuestionBank bank;

  @override
  State<BankDetailPage> createState() => _BankDetailPageState();
}

class _BankDetailPageState extends State<BankDetailPage> {
  final _db = AppDatabase.instance;
  final _search = TextEditingController();
  final _scroll = ScrollController();

  static const _pageSize = 120;

  List<Question> _items = [];
  int _total = 0;
  bool _loading = true;
  bool _loadingMore = false;
  bool _hasMore = true;
  int _loadSeq = 0;
  int _indexCount = 0;
  bool _buildingIndex = false;
  String _indexStage = '';

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
    BankEvents.revision.addListener(_onDataChanged);
    _load(reset: true);
    _refreshIndexCount();
  }

  Future<void> _refreshIndexCount() async {
    final n = await _db.countAiIndex(widget.bank.id);
    if (!mounted) return;
    setState(() => _indexCount = n);
  }

  /// 让 AI 把整个题库提炼成检索索引（一次性，之后本地匹配）
  Future<void> _buildIndex() async {
    final settings = await AiSettingsStore.load();
    if (!mounted) return;
    if (!settings.ready) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('AI 未配置：${settings.missingHint}')),
      );
      return;
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('让 AI 整理题库？'),
        content: Text(
          '将把本题库的 $_total 道题分批发给模型，为每道题提炼考点和关键词。\n\n'
          '这是一次性动作，之后搜题在本地比对，不再重复消耗额度。\n'
          '过程中请不要退出应用。',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('开始')),
        ],
      ),
    );
    if (ok != true) return;

    setState(() {
      _buildingIndex = true;
      _indexStage = '准备中…';
    });
    try {
      final result = await AiIndexBuilder(_db).build(
        bankId: widget.bank.id,
        settings: settings,
        onProgress: (done, total) {
          if (!mounted) return;
          setState(() => _indexStage = '已处理 $done / $total');
        },
      );
      if (!mounted) return;
      setState(() {
        _buildingIndex = false;
        _indexStage = '';
      });
      await _refreshIndexCount();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            result.failed == 0
                ? '索引完成：${result.ok} 题'
                : '索引完成：成功 ${result.ok} 题，失败 ${result.failed} 题',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _buildingIndex = false;
        _indexStage = '';
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('建索引失败：$e')),
      );
    }
  }

  void _onScroll() {
    if (!_hasMore || _loading || _loadingMore) return;
    if (!_scroll.hasClients) return;
    if (_scroll.position.pixels >= _scroll.position.maxScrollExtent - 320) {
      _load();
    }
  }

  Future<void> _load({bool reset = false}) async {
    final seq = reset ? ++_loadSeq : _loadSeq;
    if (reset) {
      setState(() {
        _loading = true;
        _items = [];
        _total = 0;
        _hasMore = true;
      });
    } else {
      if (!_hasMore) return;
      setState(() => _loadingMore = true);
    }
    final query = _search.text;
    final total = await _db.countQuestionsByQuery(widget.bank.id, query: query);
    final page = await _db.getQuestions(
      bankId: widget.bank.id,
      query: query,
      limit: _pageSize,
      offset: reset ? 0 : _items.length,
    );
    if (!mounted || seq != _loadSeq) return;
    setState(() {
      if (reset) {
        _items = page;
      } else {
        _items = [..._items, ...page];
      }
      _total = total;
      _hasMore = _items.length < total && page.length == _pageSize;
      _loading = false;
      _loadingMore = false;
    });
  }

  void _onDataChanged() {
    if (!mounted) return;
    _load(reset: true);
  }

  void _refresh() => _onDataChanged();

  @override
  void dispose() {
    BankEvents.revision.removeListener(_onDataChanged);
    _scroll.dispose();
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.bank.name, maxLines: 1, overflow: TextOverflow.ellipsis),
            const Text('题库详情', style: TextStyle(fontSize: 11, color: AppTheme.muted, fontWeight: FontWeight.w400)),
          ],
        ),
        actions: [
          IconButton(
            tooltip: _indexCount > 0 ? '已建 AI 索引 $_indexCount 题，点击重建' : '让 AI 整理题库',
            onPressed: _buildingIndex ? null : _buildIndex,
            icon: _buildingIndex
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                : Icon(
                    _indexCount > 0 ? Icons.auto_awesome_rounded : Icons.auto_awesome_outlined,
                    color: _indexCount > 0 ? AppTheme.primary : null,
                  ),
          ),
          IconButton(
            onPressed: () async {
              await Navigator.of(context).push(MaterialPageRoute(builder: (_) => ImportPage(bank: widget.bank)));
              _refresh();
            },
            icon: const Icon(Icons.upload_file_outlined),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 6, 18, 0),
            child: Row(
              children: [
                Text(
                  _search.text.trim().isEmpty ? '共 $_total 题' : '命中 $_total 题',
                  style: const TextStyle(fontSize: 12, color: AppTheme.muted, fontWeight: FontWeight.w600),
                ),
                const Spacer(),
                if (_buildingIndex)
                  Text(_indexStage, style: const TextStyle(fontSize: 12, color: AppTheme.primary))
                else if (_indexCount > 0)
                  const Row(
                    children: [
                      Icon(Icons.auto_awesome_rounded, size: 12, color: Color(0xFF7C3AED)),
                      SizedBox(width: 4),
                      Text('AI 索引', style: TextStyle(fontSize: 11, color: Color(0xFF7C3AED))),
                    ],
                  ),
                if (_items.isNotEmpty) ...[
                  const SizedBox(width: 8),
                  Text(
                    '已显示 ${_items.length}',
                    style: const TextStyle(fontSize: 12, color: AppTheme.muted),
                  ),
                ],
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 4, 18, 12),
            child: TextField(
              controller: _search,
              onChanged: (_) => _load(reset: true),
              decoration: const InputDecoration(
                hintText: '搜索题干、选项',
                prefixIcon: Icon(Icons.search_rounded),
              ),
            ),
          ),
          Expanded(child: _body()),
        ],
      ),
    );
  }

  Widget _body() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_items.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(30),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.inbox_outlined, size: 48, color: AppTheme.muted),
              const SizedBox(height: 12),
              Text(
                _search.text.trim().isEmpty ? '题库还是空的' : '没有搜到题',
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              Text(
                _search.text.trim().isEmpty ? '导入 Excel 或 Word 开始使用' : '换个关键词试试',
                style: const TextStyle(color: AppTheme.muted),
              ),
              const SizedBox(height: 18),
              if (_search.text.trim().isEmpty)
                FilledButton.icon(
                  onPressed: () async {
                    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => ImportPage(bank: widget.bank)));
                    _refresh();
                  },
                  icon: const Icon(Icons.upload_file_rounded),
                  label: const Text('导入题库'),
                ),
            ],
          ),
        ),
      );
    }
    return ListView.separated(
      controller: _scroll,
      padding: const EdgeInsets.fromLTRB(18, 0, 18, 30),
      itemCount: _items.length + (_hasMore ? 1 : 0),
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        if (index >= _items.length) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 18),
            child: Center(
              child: _loadingMore
                  ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2))
                  : TextButton(
                      onPressed: () => _load(),
                      child: Text('继续加载（已显示 ${_items.length}/$_total）'),
                    ),
            ),
          );
        }
        return _questionCard(_items[index]);
      },
    );
  }

  Widget _questionCard(Question question) {
    return GestureDetector(
      onTap: () async {
        await Navigator.of(context).push(MaterialPageRoute(builder: (_) => QuestionEditPage(question: question)));
        _refresh();
      },
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
                  decoration: BoxDecoration(
                    color: AppTheme.primary.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(7),
                  ),
                  child: Text(question.type.label, style: const TextStyle(fontSize: 11, color: AppTheme.primary, fontWeight: FontWeight.w700)),
                ),
                if (question.orderIndex > 0) ...[
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppTheme.line.withValues(alpha: 0.45),
                      borderRadius: BorderRadius.circular(7),
                    ),
                    child: Text('库内 #${question.orderIndex}',
                        style: const TextStyle(fontSize: 11, color: AppTheme.muted, fontWeight: FontWeight.w700)),
                  ),
                ],
                if (question.sourceIndex > 0) ...[
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
                    decoration: BoxDecoration(
                      color: const Color(0xFFEDE9FE),
                      borderRadius: BorderRadius.circular(7),
                    ),
                    child: Text('原题 #${question.sourceIndex}',
                        style: const TextStyle(fontSize: 11, color: Color(0xFF5B21B6), fontWeight: FontWeight.w700)),
                  ),
                ],
                const Spacer(),
                if (question.source.isNotEmpty)
                  Flexible(
                    child: Text(question.source, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11, color: AppTheme.muted)),
                  ),
              ],
            ),
            const SizedBox(height: 9),
            Text(question.stem, maxLines: 3, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 15, height: 1.45, fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            Text('答案：${question.answerDisplay}', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, color: AppTheme.muted)),
          ],
        ),
      ),
    );
  }
}

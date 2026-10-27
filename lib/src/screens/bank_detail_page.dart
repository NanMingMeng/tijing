import 'package:flutter/material.dart';

import '../data/app_database.dart';
import '../models/question.dart';
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
  late Future<List<Question>> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<List<Question>> _load() => _db.getQuestions(bankId: widget.bank.id, query: _search.text);

  void _refresh() => setState(() => _future = _load());

  @override
  void dispose() {
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
            padding: const EdgeInsets.fromLTRB(18, 4, 18, 12),
            child: TextField(
              controller: _search,
              onChanged: (_) => _refresh(),
              decoration: const InputDecoration(
                hintText: '搜索题干、选项',
                prefixIcon: Icon(Icons.search_rounded),
              ),
            ),
          ),
          Expanded(
            child: FutureBuilder<List<Question>>(
              future: _future,
              builder: (context, snapshot) {
                if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
                final questions = snapshot.data!;
                if (questions.isEmpty) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(30),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.inbox_outlined, size: 48, color: AppTheme.muted),
                          const SizedBox(height: 12),
                          Text(_search.text.isEmpty ? '题库还是空的' : '没有搜到题', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                          const SizedBox(height: 8),
                          Text(_search.text.isEmpty ? '导入 Excel 或 Word 开始使用' : '换个关键词试试', style: const TextStyle(color: AppTheme.muted)),
                          const SizedBox(height: 18),
                          if (_search.text.isEmpty)
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
                  padding: const EdgeInsets.fromLTRB(18, 0, 18, 30),
                  itemCount: questions.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (context, index) => _questionCard(questions[index]),
                );
              },
            ),
          ),
        ],
      ),
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

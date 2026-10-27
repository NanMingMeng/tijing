import 'package:flutter/material.dart';

import '../data/app_database.dart';
import '../models/question.dart';
import '../services/bank_events.dart';
import '../theme.dart';
import 'bank_detail_page.dart';
import 'import_page.dart';

class BankListPage extends StatefulWidget {
  const BankListPage({super.key});

  @override
  State<BankListPage> createState() => _BankListPageState();
}

class _BankListPageState extends State<BankListPage> {
  final _db = AppDatabase.instance;
  late Future<List<QuestionBank>> _future;

  @override
  void initState() {
    super.initState();
    _future = _db.listBanks();
    BankEvents.revision.addListener(_onDataChanged);
  }

  @override
  void dispose() {
    BankEvents.revision.removeListener(_onDataChanged);
    super.dispose();
  }

  void _onDataChanged() {
    if (!mounted) return;
    setState(() => _future = _db.listBanks());
  }

  void _refresh() => _onDataChanged();

  Future<void> _createBank() async {
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('新建题库'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(hintText: '例如：建筑专业知识'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消')),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('创建'),
          ),
        ],
      ),
    );
    if (name == null || name.isEmpty) return;
    final bank = await _db.createBank(name: name);
    BankEvents.bump();
    if (!mounted) return;
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => ImportPage(bank: bank)));
    _refresh();
  }

  Future<void> _deleteBank(QuestionBank bank) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除题库？'),
        content: Text('“${bank.name}”里的 ${bank.questionCount} 道题和 AI 记录都会删除，不能恢复。'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('取消')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (ok == true) {
      await _db.deleteBank(bank.id);
      BankEvents.bump();
      _refresh();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('题库'),
        actions: [
          IconButton(onPressed: _createBank, icon: const Icon(Icons.add_rounded)),
        ],
      ),
      body: FutureBuilder<List<QuestionBank>>(
        future: _future,
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final banks = snapshot.data!;
          if (banks.isEmpty) {
            return _emptyState();
          }
          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(18, 8, 18, 100),
            itemCount: banks.length,
            separatorBuilder: (_, __) => const SizedBox(height: 12),
            itemBuilder: (context, index) {
              final bank = banks[index];
              return _bankCard(bank);
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _createBank,
        icon: const Icon(Icons.add_rounded),
        label: const Text('新建题库'),
      ),
    );
  }

  Widget _bankCard(QuestionBank bank) {
    return GestureDetector(
      onTap: () async {
        await Navigator.of(context).push(MaterialPageRoute(builder: (_) => BankDetailPage(bank: bank)));
        _refresh();
      },
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: AppTheme.line),
        ),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: AppTheme.primary.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(14),
              ),
              child: const Icon(Icons.library_books_rounded, color: AppTheme.primary),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(bank.name, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700), maxLines: 1, overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 5),
                  Text('${bank.questionCount} 道题', style: const TextStyle(color: AppTheme.muted, fontSize: 13)),
                ],
              ),
            ),
            IconButton(
              onPressed: () => _deleteBank(bank),
              icon: const Icon(Icons.more_horiz_rounded, color: AppTheme.muted),
            ),
          ],
        ),
      ),
    );
  }

  Widget _emptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 92,
              height: 92,
              decoration: BoxDecoration(
                color: AppTheme.primary.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(28),
              ),
              child: const Icon(Icons.library_add_outlined, size: 44, color: AppTheme.primary),
            ),
            const SizedBox(height: 22),
            const Text('还没有题库', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            const Text('导入 Excel 或 Word，或者先建一个空题库', textAlign: TextAlign.center, style: TextStyle(color: AppTheme.muted)),
            const SizedBox(height: 22),
            FilledButton.icon(onPressed: _createBank, icon: const Icon(Icons.add_rounded), label: const Text('新建并导入')),
          ],
        ),
      ),
    );
  }
}

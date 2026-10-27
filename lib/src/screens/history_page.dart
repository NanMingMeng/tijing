import 'package:flutter/material.dart';

import '../data/app_database.dart';
import '../models/question.dart';
import '../theme.dart';

class HistoryPage extends StatefulWidget {
  const HistoryPage({super.key});

  @override
  State<HistoryPage> createState() => _HistoryPageState();
}

class _HistoryPageState extends State<HistoryPage> {
  final _db = AppDatabase.instance;
  late Future<List<AiRecord>> _future;

  @override
  void initState() {
    super.initState();
    _future = _db.listAiRecords();
  }

  void _refresh() => setState(() => _future = _db.listAiRecords());

  Future<void> _clear() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('清空 AI 历史？'),
        content: const Text('所有 AI 作答记录都会删除，题库不会受影响。'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('取消')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('清空'),
          ),
        ],
      ),
    );
    if (ok == true) {
      await _db.clearAiRecords();
      _refresh();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('AI 历史'),
        actions: [
          IconButton(onPressed: _clear, icon: const Icon(Icons.delete_sweep_outlined)),
        ],
      ),
      body: FutureBuilder<List<AiRecord>>(
        future: _future,
        builder: (context, snapshot) {
          if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
          final records = snapshot.data!;
          if (records.isEmpty) {
            return const Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.history_toggle_off_rounded, size: 52, color: AppTheme.muted),
                  SizedBox(height: 12),
                  Text('还没有 AI 作答记录', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
                  SizedBox(height: 6),
                  Text('搜题后点“AI 作答”，结果会保存在这里。', style: TextStyle(color: AppTheme.muted, fontSize: 13)),
                ],
              ),
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(18, 8, 18, 30),
            itemCount: records.length,
            separatorBuilder: (_, __) => const SizedBox(height: 10),
            itemBuilder: (context, index) {
              final record = records[index];
              return Dismissible(
                key: ValueKey(record.id),
                direction: DismissDirection.endToStart,
                background: Container(
                  alignment: Alignment.centerRight,
                  padding: const EdgeInsets.only(right: 20),
                  decoration: BoxDecoration(color: Colors.red.shade50, borderRadius: BorderRadius.circular(16)),
                  child: const Icon(Icons.delete_outline, color: Colors.red),
                ),
                onDismissed: (_) async {
                  if (record.id != null) await _db.deleteAiRecord(record.id!);
                  _refresh();
                },
                child: GestureDetector(
                  onTap: () => _showDetail(record),
                  child: Container(
                    padding: const EdgeInsets.all(16),
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
                              decoration: BoxDecoration(color: const Color(0xFFF5F3FF), borderRadius: BorderRadius.circular(7)),
                              child: Text(record.provider, style: const TextStyle(fontSize: 11, color: Color(0xFF7C3AED), fontWeight: FontWeight.w700)),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(record.model, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11, color: AppTheme.muted)),
                            ),
                            Text(_shortTime(record.createdAt), style: const TextStyle(fontSize: 11, color: AppTheme.muted)),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Text(record.answer.isEmpty ? '没有返回答案' : record.answer, maxLines: 3, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 15, height: 1.45, fontWeight: FontWeight.w600)),
                        if (record.explanation.isNotEmpty) ...[
                          const SizedBox(height: 7),
                          Text(record.explanation, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, color: AppTheme.muted)),
                        ],
                      ],
                    ),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }

  String _shortTime(String value) {
    final dt = DateTime.tryParse(value);
    if (dt == null) return '';
    return '${dt.month}-${dt.day} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }

  void _showDetail(AiRecord record) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.72,
        minChildSize: 0.4,
        maxChildSize: 0.95,
        builder: (context, controller) => Container(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 28),
          decoration: const BoxDecoration(color: Colors.white, borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
          child: ListView(
            controller: controller,
            children: [
              Text('${record.provider} · ${record.model}', style: const TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(height: 16),
              _section('答案', record.answer),
              if (record.explanation.isNotEmpty) _section('解析', record.explanation),
              if (record.steps.isNotEmpty) _section('步骤', record.steps),
              if (record.uncertainty.isNotEmpty) _section('不确定原因', record.uncertainty),
            ],
          ),
        ),
      ),
    );
  }

  Widget _section(String title, String content) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontSize: 13, color: AppTheme.muted, fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          Text(content, style: const TextStyle(fontSize: 15, height: 1.6)),
        ],
      ),
    );
  }
}

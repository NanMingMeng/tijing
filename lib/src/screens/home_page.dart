import 'package:flutter/material.dart';

import '../data/app_database.dart';
import '../models/question.dart';
import '../theme.dart';
import 'bank_list_page.dart';
import 'camera_page.dart';
import 'history_page.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final _db = AppDatabase.instance;
  late Future<_HomeStats> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<_HomeStats> _load() async {
    final banks = await _db.listBanks();
    final total = banks.fold<int>(0, (sum, item) => sum + item.questionCount);
    return _HomeStats(banks: banks, totalQuestions: total);
  }

  void _refresh() => setState(() => _future = _load());

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: RefreshIndicator(
        onRefresh: () async => _refresh(),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 28),
          children: [
            Row(
              children: [
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('题镜', style: TextStyle(fontSize: 30, fontWeight: FontWeight.w800, color: AppTheme.ink)),
                      SizedBox(height: 4),
                      Text('拍下题目，找回你自己的题库答案', style: TextStyle(color: AppTheme.muted, fontSize: 14)),
                    ],
                  ),
                ),
                _roundIcon(Icons.auto_awesome_outlined, () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('拍照搜题支持离线 OCR，AI 作答需要配置密钥')),
                  );
                }),
              ],
            ),
            const SizedBox(height: 22),
            FutureBuilder<_HomeStats>(
              future: _future,
              builder: (context, snapshot) {
                final stats = snapshot.data ?? const _HomeStats(banks: [], totalQuestions: 0);
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _heroCard(context, stats),
                    const SizedBox(height: 18),
                    Row(
                      children: [
                        Expanded(
                          child: _entryCard(
                            context,
                            icon: Icons.library_books_rounded,
                            title: '题库',
                            subtitle: '${stats.banks.length} 个题库 · ${stats.totalQuestions} 道题',
                            onTap: () async {
                              await Navigator.of(context).push(MaterialPageRoute(builder: (_) => const BankListPage()));
                              _refresh();
                            },
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _entryCard(
                            context,
                            icon: Icons.history_rounded,
                            title: '历史',
                            subtitle: '查看 AI 作答记录',
                            onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const HistoryPage())),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),
                    Row(
                      children: [
                        const Text('题库概览', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                        const Spacer(),
                        TextButton(onPressed: () async {
                          await Navigator.of(context).push(MaterialPageRoute(builder: (_) => const BankListPage()));
                          _refresh();
                        }, child: const Text('全部')),
                      ],
                    ),
                    if (stats.banks.isEmpty)
                      _emptyCard(context)
                    else
                      ...stats.banks.take(4).map((bank) => Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: _bankRow(context, bank),
                          )),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _heroCard(BuildContext context, _HomeStats stats) {
    return Container(
      padding: const EdgeInsets.fromLTRB(22, 24, 22, 20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF0F766E), Color(0xFF115E59)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(26),
        boxShadow: [
          BoxShadow(color: AppTheme.primary.withValues(alpha: 0.22), blurRadius: 24, offset: const Offset(0, 12)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(15),
                ),
                child: const Icon(Icons.photo_camera_rounded, color: Colors.white, size: 28),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(99),
                ),
                child: const Text('离线 OCR', style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600)),
              ),
            ],
          ),
          const SizedBox(height: 18),
          const Text('拍照搜题', style: TextStyle(color: Colors.white, fontSize: 26, fontWeight: FontWeight.w800)),
          const SizedBox(height: 6),
          Text(
            stats.totalQuestions == 0 ? '先导入一份题库，再开始搜索' : '在 ${stats.totalQuestions} 道题里找最像的答案',
            style: TextStyle(color: Colors.white.withValues(alpha: 0.78), fontSize: 14),
          ),
          const SizedBox(height: 20),
          FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: Colors.white,
              foregroundColor: AppTheme.primaryDark,
              minimumSize: const Size(double.infinity, 54),
            ),
            onPressed: () async {
              if (stats.banks.isEmpty) {
                await Navigator.of(context).push(MaterialPageRoute(builder: (_) => const BankListPage()));
                _refresh();
                return;
              }
              await Navigator.of(context).push(MaterialPageRoute(builder: (_) => CameraPage(banks: stats.banks)));
              _refresh();
            },
            icon: const Icon(Icons.center_focus_strong_rounded),
            label: Text(stats.banks.isEmpty ? '先导入题库' : '开始拍照'),
          ),
        ],
      ),
    );
  }

  Widget _entryCard(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: AppTheme.line),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: AppTheme.primary),
            const SizedBox(height: 14),
            Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            Text(subtitle, style: const TextStyle(fontSize: 12, color: AppTheme.muted), maxLines: 2, overflow: TextOverflow.ellipsis),
          ],
        ),
      ),
    );
  }

  Widget _emptyCard(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppTheme.line),
      ),
      child: const Row(
        children: [
          Icon(Icons.note_add_outlined, color: AppTheme.muted),
          SizedBox(width: 12),
          Expanded(child: Text('还没有题库。导入 Excel 或 Word 后，这里会显示题目数量。', style: TextStyle(color: AppTheme.muted))),
        ],
      ),
    );
  }

  Widget _bankRow(BuildContext context, QuestionBank bank) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.line),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: AppTheme.primary.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.description_outlined, color: AppTheme.primary, size: 21),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(bank.name, style: const TextStyle(fontWeight: FontWeight.w700), maxLines: 1, overflow: TextOverflow.ellipsis),
                const SizedBox(height: 3),
                Text('${bank.questionCount} 道题', style: const TextStyle(fontSize: 12, color: AppTheme.muted)),
              ],
            ),
          ),
          const Icon(Icons.chevron_right_rounded, color: AppTheme.muted),
        ],
      ),
    );
  }

  Widget _roundIcon(IconData icon, VoidCallback onTap) {
    return IconButton.filledTonal(
      onPressed: onTap,
      icon: Icon(icon),
      style: IconButton.styleFrom(backgroundColor: Colors.white, foregroundColor: AppTheme.primary),
    );
  }
}

class _HomeStats {
  const _HomeStats({required this.banks, required this.totalQuestions});

  final List<QuestionBank> banks;
  final int totalQuestions;
}

import 'package:flutter/material.dart';

import '../data/app_database.dart';
import '../services/ai_service.dart';
import '../services/backup_service.dart';
import '../theme.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  final _base = TextEditingController();
  final _model = TextEditingController();
  final _key = TextEditingController();
  AiProvider _provider = AiProvider.deepSeek;
  bool _loading = true;
  bool _saving = false;
  bool _sendImage = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _base.dispose();
    _model.dispose();
    _key.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final settings = await AiSettingsStore.load();
    if (!mounted) return;
    setState(() {
      _provider = settings.provider;
      _base.text = settings.baseUrl;
      _model.text = settings.model;
      _key.text = settings.apiKey;
      _sendImage = AiSettingsStore.sendImage;
      _loading = false;
    });
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    final settings = AiSettings(
      provider: _provider,
      baseUrl: _base.text,
      model: _model.text,
      apiKey: _key.text,
    );
    await AiSettingsStore.save(settings, sendImageValue: _sendImage);
    if (!mounted) return;
    setState(() => _saving = false);
    final hint = settings.missingHint;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(hint.isEmpty ? '设置已保存' : '设置已保存，但${hint}，AI 作答仍不可用'),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('设置')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(18, 8, 18, 30),
              children: [
                const Text('AI 作答', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                const SizedBox(height: 10),
                DropdownButtonFormField<AiProvider>(
                  initialValue: _provider,
                  decoration: const InputDecoration(labelText: '模型服务'),
                  items: AiProvider.values.map((provider) => DropdownMenuItem(value: provider, child: Text(provider.label))).toList(),
                  onChanged: (value) {
                    if (value == null) return;
                    setState(() {
                      _provider = value;
                      if (_base.text.isEmpty || AiProvider.values.any((p) => p.defaultBaseUrl == _base.text)) {
                        _base.text = value.defaultBaseUrl;
                      }
                      final models = AiProvider.values.map((p) => p.defaultModel).toSet();
                      if (_model.text.trim().isEmpty || models.contains(_model.text)) {
                        _model.text = value.defaultModel;
                      }
                    });
                  },
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _base,
                  decoration: const InputDecoration(labelText: '接口地址', hintText: '例如 https://api.deepseek.com/v1'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _model,
                  decoration: const InputDecoration(labelText: '模型名', hintText: '例如 deepseek-chat'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _key,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: 'API Key',
                    hintText: '只保存在本机安全存储，不进备份',
                    helperText: 'API Key 不会写进分享文件或备份文件。',
                  ),
                ),
                const SizedBox(height: 6),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: _sendImage,
                  onChanged: (value) => setState(() => _sendImage = value),
                  title: const Text('让 AI 直接看原图作答', style: TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: const Text(
                    '开启后把题目照片一起发给模型，由模型自己读图，不依赖 OCR 文字，避免识别错误导致答错。需要所选模型支持图像输入（如 gpt-4o、qwen-vl、glm-4v、claude、gemini）。',
                    style: TextStyle(fontSize: 12),
                  ),
                ),
                const SizedBox(height: 10),
                FilledButton.icon(
                  onPressed: _saving ? null : _save,
                  icon: _saving ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Icon(Icons.save_rounded),
                  label: Text(_saving ? '保存中…' : '保存 AI 设置'),
                ),
                const SizedBox(height: 28),
                const Text('备份与恢复', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                const SizedBox(height: 8),
                const Text('备份包含题库、AI 历史和设置，不包含 API Key。建议定期导出。', style: TextStyle(color: AppTheme.muted, fontSize: 13)),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: () async {
                    try {
                      await BackupService(AppDatabase.instance).exportAndShare();
                    } catch (e) {
                      if (!mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('备份失败：$e')));
                    }
                  },
                  icon: const Icon(Icons.ios_share_rounded),
                  label: const Text('一键备份并分享'),
                ),
                const SizedBox(height: 10),
                OutlinedButton.icon(
                  onPressed: () async {
                    try {
                      final message = await BackupService(AppDatabase.instance).importFromFile();
                      if (!mounted) return;
                      await showDialog<void>(
                        context: context,
                        builder: (context) => AlertDialog(
                          title: const Text('恢复备份'),
                          content: Text(message),
                          actions: [FilledButton(onPressed: () => Navigator.pop(context), child: const Text('知道了'))],
                        ),
                      );
                    } catch (e) {
                      if (!mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('恢复失败：$e')));
                    }
                  },
                  icon: const Icon(Icons.restore_rounded),
                  label: const Text('从备份恢复'),
                ),
                const SizedBox(height: 28),
                const Text('关于题镜', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                const SizedBox(height: 8),
                const Text('题镜 0.2.4\n离线 OCR · 本地题库 · AI 兜底', style: TextStyle(color: AppTheme.muted, fontSize: 13, height: 1.6)),
              ],
            ),
    );
  }
}

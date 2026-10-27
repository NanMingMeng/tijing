import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../data/app_database.dart';
import '../models/import_draft.dart';
import '../models/question.dart';
import '../services/bank_import_service.dart';
import '../services/excel_import_service.dart';
import '../services/word_import_service.dart';
import '../theme.dart';

class ImportPage extends StatefulWidget {
  const ImportPage({super.key, required this.bank});

  final QuestionBank bank;

  @override
  State<ImportPage> createState() => _ImportPageState();
}

class _ImportPageState extends State<ImportPage> {
  final _excelService = ExcelImportService();
  final _wordService = WordImportService();
  final _importService = BankImportService(AppDatabase.instance);

  String? _fileName;
  Uint8List? _bytes;
  ExcelParseResult? _excel;
  ImportPreview? _preview;
  Map<String, int> _mapping = {};
  BankImportResult? _result;
  bool _loading = false;

  Future<void> _pickFile() async {
    final file = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: ['xlsx', 'docx', 'doc'],
    );
    if (file == null) return;
    final name = file.name.toLowerCase();
    if (name.endsWith('.doc')) {
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('老式 .doc 暂不支持'),
          content: const Text('请先在 Word 里打开这个文件，另存为 .docx，再回来导入。'),
          actions: [FilledButton(onPressed: () => Navigator.pop(context), child: const Text('知道了'))],
        ),
      );
      return;
    }
    final bytes = await file.readAsBytes();
    setState(() {
      _fileName = file.name;
      _bytes = bytes;
      _excel = null;
      _preview = null;
      _result = null;
    });
    if (name.endsWith('.xlsx')) {
      try {
        final parsed = _excelService.parseBytes(bytes);
        setState(() {
          _excel = parsed;
          _mapping = Map<String, int>.from(parsed.suggestedMapping);
        });
      } catch (e) {
        _showError('Excel 读取失败：$e');
      }
    } else if (name.endsWith('.docx')) {
      try {
        final preview = _wordService.parseBytes(bytes, file.name);
        setState(() => _preview = preview);
      } catch (e) {
        _showError('Word 读取失败：$e');
      }
    }
  }

  Future<void> _import() async {
    if (_bytes == null) return;
    setState(() => _loading = true);
    try {
      List<QuestionDraft> drafts;
      final name = (_fileName ?? '').toLowerCase();
      if (name.endsWith('.xlsx')) {
        if (_excel == null) return;
        if (_mapping['stem'] == null) {
          _showError('至少要指定“题目”是哪一列');
          return;
        }
        drafts = _excelService.buildDrafts(_excel!, _mapping);
      } else {
        if (_preview == null) return;
        drafts = _preview!.drafts;
      }
      final result = await _importService.importDrafts(widget.bank.id, drafts);
      if (!mounted) return;
      setState(() {
        _result = result;
        _preview = ImportPreview(fileName: _fileName ?? '', drafts: drafts, warnings: const []);
      });
    } catch (e) {
      _showError('导入失败：$e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('导入题库')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(18, 8, 18, 30),
        children: [
          Text('导入到：${widget.bank.name}', style: const TextStyle(color: AppTheme.muted)),
          const SizedBox(height: 14),
          _filePickerCard(),
          if (_excel != null) ...[
            const SizedBox(height: 18),
            const Text('列对应关系', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            const Text('系统会自动猜，猜错了你可以手动改。', style: TextStyle(color: AppTheme.muted, fontSize: 13)),
            const SizedBox(height: 12),
            ...ExcelImportService.fieldLabels.entries.map((entry) => _mappingRow(entry.key, entry.value)),
          ],
          if (_preview != null) ...[
            const SizedBox(height: 18),
            _previewCard(_preview!),
          ],
          if (_result != null) ...[
            const SizedBox(height: 18),
            _resultCard(_result!),
          ],
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: _loading || _bytes == null ? null : _import,
            icon: _loading ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Icon(Icons.file_download_done_rounded),
            label: Text(_loading ? '导入中…' : '开始导入'),
          ),
          if (_result != null) ...[
            const SizedBox(height: 10),
            OutlinedButton(onPressed: () => Navigator.of(context).pop(), child: const Text('完成')),
          ],
        ],
      ),
    );
  }

  Widget _filePickerCard() {
    return GestureDetector(
      onTap: _pickFile,
      child: Container(
        padding: const EdgeInsets.all(22),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: AppTheme.line, style: BorderStyle.solid),
        ),
        child: Column(
          children: [
            Container(
              width: 58,
              height: 58,
              decoration: BoxDecoration(color: AppTheme.primary.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(18)),
              child: const Icon(Icons.upload_file_rounded, color: AppTheme.primary, size: 30),
            ),
            const SizedBox(height: 12),
            Text(_fileName ?? '选择 Excel 或 Word 文件', style: const TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 5),
            const Text('支持 .xlsx、.docx；老 .doc 请先另存为 .docx', style: TextStyle(fontSize: 12, color: AppTheme.muted)),
          ],
        ),
      ),
    );
  }

  Widget _mappingRow(String key, String label) {
    final value = _mapping[key];
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          SizedBox(width: 76, child: Text(label, style: const TextStyle(fontWeight: FontWeight.w600))),
          Expanded(
            child: DropdownButtonFormField<int?>(
              initialValue: value,
              isExpanded: true,
              decoration: const InputDecoration(contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8)),
              items: [
                const DropdownMenuItem<int?>(value: null, child: Text('不导入')),
                for (var i = 0; i < (_excel?.headers.length ?? 0); i++)
                  DropdownMenuItem<int?>(value: i, child: Text(_excel!.headers[i])),
              ],
              onChanged: (value) => setState(() {
                if (value == null) {
                  _mapping.remove(key);
                } else {
                  _mapping[key] = value;
                }
              }),
            ),
          ),
        ],
      ),
    );
  }

  Widget _previewCard(ImportPreview preview) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: AppTheme.line)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text('预览', style: TextStyle(fontWeight: FontWeight.w700)),
              const Spacer(),
              Text('${preview.validCount} 道可导入 · ${preview.issueCount} 道有问题', style: const TextStyle(fontSize: 12, color: AppTheme.muted)),
            ],
          ),
          const SizedBox(height: 10),
          ...preview.drafts.take(3).map((draft) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text('• ${draft.stem.isEmpty ? '题目为空' : draft.stem}', maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13)),
              )),
          if (preview.drafts.any((d) => d.hasIssues)) ...[
            const SizedBox(height: 8),
            const Text('问题题目会在导入后保留，可进入题库逐条修改。', style: TextStyle(fontSize: 12, color: AppTheme.warm)),
          ],
        ],
      ),
    );
  }

  Widget _resultCard(BankImportResult result) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(color: const Color(0xFFF0FDFA), borderRadius: BorderRadius.circular(16), border: Border.all(color: const Color(0xFF99F6E4))),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('导入完成', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: AppTheme.primaryDark)),
          const SizedBox(height: 8),
          Text('成功 ${result.imported} 道，跳过重复 ${result.skipped} 道，问题题目 ${result.issueCount} 道'),
          if (result.suspicious.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text('有 ${result.suspicious.length} 道疑似重复，已保留，请进题库核对。', style: const TextStyle(fontSize: 12, color: AppTheme.warm)),
          ],
        ],
      ),
    );
  }
}





import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../data/app_database.dart';
import '../models/question.dart';
import 'ai_service.dart';

class BackupService {
  BackupService(this.db);

  final AppDatabase db;

  Future<void> exportAndShare() async {
    final banks = await db.listBanks();
    final questions = await db.getAllQuestions();
    final aiRecords = await db.listAiRecords(limit: 100000);
    final settings = await AiSettingsStore.load();
    final payload = {
      'format': 'tijing-backup',
      'version': 1,
      'exported_at': DateTime.now().toIso8601String(),
      'banks': [
        for (final bank in banks)
          {
            'id': bank.id,
            'name': bank.name,
            'description': bank.description,
            'created_at': bank.createdAt,
            'updated_at': bank.updatedAt,
          }
      ],
      'questions': [for (final question in questions) question.toMap()],
      'ai_records': [for (final record in aiRecords) record.toMap()],
      'settings': {
        'provider': settings.provider.name,
        'base_url': settings.baseUrl,
        'model': settings.model,
      },
    };
    final bytes = utf8.encode(jsonEncode(payload));
    final archive = Archive()
      ..addFile(ArchiveFile('backup.json', bytes.length, bytes));
    final zip = ZipEncoder().encode(archive) ?? (throw StateError('备份压缩失败'));
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/题镜备份-${DateTime.now().millisecondsSinceEpoch}.tijing');
    await file.writeAsBytes(zip, flush: true);
    await SharePlus.instance.share(ShareParams(
      files: [XFile(file.path)],
      text: '题镜题库备份',
    ));
  }

  Future<String> importFromFile() async {
    final file = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: ['tijing', 'zip'],
    );
    if (file == null) return '没有选择文件';
    final bytes = await file.readAsBytes();
    final archive = ZipDecoder().decodeBytes(bytes);
    final backupFile = archive.findFile('backup.json');
    if (backupFile == null) return '不是有效的题镜备份';
    final jsonText = utf8.decode(backupFile.content as List<int>);
    final data = jsonDecode(jsonText) as Map<String, dynamic>;
    var bankCount = 0;
    var questionCount = 0;
    var aiCount = 0;
    final banks = data['banks'];
    if (banks is List) {
      for (final item in banks) {
        if (item is! Map) continue;
        final map = Map<String, dynamic>.from(item);
        await db.insertBank(QuestionBank(
          id: (map['id'] ?? '').toString(),
          name: (map['name'] ?? '未命名题库').toString(),
          description: (map['description'] ?? '').toString(),
          createdAt: (map['created_at'] ?? DateTime.now().toIso8601String()).toString(),
          updatedAt: (map['updated_at'] ?? DateTime.now().toIso8601String()).toString(),
        ));
        bankCount++;
      }
    }
    final questions = data['questions'];
    if (questions is List) {
      for (final item in questions) {
        if (item is! Map) continue;
        await db.upsertQuestion(Question.fromMap(Map<String, Object?>.from(item)));
        questionCount++;
      }
    }
    final aiRecords = data['ai_records'];
    if (aiRecords is List) {
      for (final item in aiRecords) {
        if (item is! Map) continue;
        await db.saveAiRecord(AiRecord.fromMap(Map<String, Object?>.from(item)));
        aiCount++;
      }
    }
    final settings = data['settings'];
    if (settings is Map) {
      final map = Map<String, dynamic>.from(settings);
      final current = await AiSettingsStore.load();
      await AiSettingsStore.save(current.copyWith(
        provider: AiProvider.fromCode(map['provider']?.toString()),
        baseUrl: (map['base_url'] ?? current.baseUrl).toString(),
        model: (map['model'] ?? current.model).toString(),
      ));
    }
    return '恢复完成：$bankCount 个题库，$questionCount 道题，$aiCount 条 AI 记录';
  }
}



import 'dart:io';

import 'package:tijing/src/services/excel_import_service.dart';

void main(List<String> args) {
  final path = args.isNotEmpty ? args.first : '';
  if (path.isEmpty || !File(path).existsSync()) {
    stderr.writeln('用法: dart run tool/check_import.dart <xlsx路径>');
    exit(1);
  }
  final service = ExcelImportService();
  final parsed = service.parseBytes(File(path).readAsBytesSync());
  final mapping = parsed.suggestedMapping;
  final drafts = service.buildDrafts(parsed, mapping);
  final issues = drafts.where((draft) => draft.hasIssues).length;
  final typeCounts = <String, int>{};
  for (final draft in drafts) {
    typeCounts[draft.type.label] = (typeCounts[draft.type.label] ?? 0) + 1;
  }
  stdout.writeln('文件: $path');
  stdout.writeln('表头: ${parsed.headers.join(' | ')}');
  stdout.writeln('自动映射: $mapping');
  stdout.writeln('总行数: ${parsed.rows.length}');
  stdout.writeln('可解析题数: ${drafts.length}');
  stdout.writeln('问题题数: $issues');
  stdout.writeln('题型分布: $typeCounts');
  for (final draft in drafts.where((draft) => draft.hasIssues).take(5)) {
    stdout.writeln('问题示例: ${draft.stem} => ${draft.issues.join('；')}');
  }
}

import "dart:convert";
import "dart:io";
import "package:tijing/src/services/excel_import_service.dart";

void main(List<String> args) {
  final path = args.first;
  final service = ExcelImportService();
  final parsed = service.parseBytes(File(path).readAsBytesSync());
  final drafts = service.buildDrafts(parsed, parsed.suggestedMapping);
  final out = <Map<String, dynamic>>[];
  for (var i = 0; i < drafts.length; i++) {
    final d = drafts[i];
    out.add({
      "excelRow": i + 2,
      "sourceIndex": d.sourceIndex,
      "stem": d.stem,
      "type": d.type.code,
      "options": d.options.map((o) => {"key": o.key, "text": o.text, "isCorrect": o.isCorrect}).toList(),
      "answerKeys": d.answerKeys,
      "answerTexts": d.answerTexts,
      "explanation": d.explanation,
      "source": d.source,
      "subject": d.subject,
      "chapter": d.chapter,
      "tags": d.tags,
      "difficulty": d.difficulty,
      "issues": d.issues,
    });
  }
  File("/tmp/drafts.json").writeAsStringSync(jsonEncode(out));
  stdout.writeln("drafts=" + out.length.toString());
}

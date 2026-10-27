import 'dart:async';

import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import '../models/question.dart';

class AppDatabase {
  AppDatabase._();

  static final AppDatabase instance = AppDatabase._();
  static const _uuid = Uuid();

  Database? _database;
  Future<Database>? _opening;

  Future<Database> get database async {
    if (_database != null) return _database!;
    _opening ??= _open();
    _database = await _opening!;
    return _database!;
  }

  Future<Database> _open() async {
    final root = await getDatabasesPath();
    final path = p.join(root, 'tijing.db');
    return openDatabase(
      path,
      version: 1,
      onConfigure: (db) async {
        await db.execute('PRAGMA foreign_keys = ON');
      },
      onCreate: _create,
    );
  }

  Future<void> _create(Database db, int version) async {
    await db.execute('''
      CREATE TABLE banks (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        description TEXT NOT NULL DEFAULT '',
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE questions (
        id TEXT PRIMARY KEY,
        bank_id TEXT NOT NULL,
        type TEXT NOT NULL,
        stem TEXT NOT NULL,
        options_json TEXT NOT NULL DEFAULT '[]',
        answer_keys_json TEXT NOT NULL DEFAULT '[]',
        answer_texts_json TEXT NOT NULL DEFAULT '[]',
        explanation TEXT NOT NULL DEFAULT '',
        source TEXT NOT NULL DEFAULT '',
        subject TEXT NOT NULL DEFAULT '',
        chapter TEXT NOT NULL DEFAULT '',
        tags_json TEXT NOT NULL DEFAULT '[]',
        difficulty INTEGER NOT NULL DEFAULT 0,
        content_hash TEXT NOT NULL DEFAULT '',
        search_text TEXT NOT NULL DEFAULT '',
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        FOREIGN KEY (bank_id) REFERENCES banks(id) ON DELETE CASCADE
      )
    ''');
    await db.execute('CREATE INDEX idx_questions_bank ON questions(bank_id)');
    await db.execute('CREATE UNIQUE INDEX idx_questions_hash ON questions(bank_id, content_hash)');
    await db.execute('''
      CREATE TABLE ai_records (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        question_id TEXT NOT NULL,
        bank_id TEXT NOT NULL,
        provider TEXT NOT NULL,
        model TEXT NOT NULL,
        answer TEXT NOT NULL,
        explanation TEXT NOT NULL DEFAULT '',
        steps TEXT NOT NULL DEFAULT '',
        uncertainty TEXT NOT NULL DEFAULT '',
        created_at TEXT NOT NULL
      )
    ''');
    await db.execute('CREATE INDEX idx_ai_question ON ai_records(question_id)');
  }

  Future<QuestionBank> createBank({
    required String name,
    String description = '',
  }) async {
    final db = await database;
    final now = DateTime.now().toIso8601String();
    final bank = QuestionBank(
      id: _uuid.v4(),
      name: name.trim().isEmpty ? '未命名题库' : name.trim(),
      description: description,
      createdAt: now,
      updatedAt: now,
    );
    await db.insert('banks', {
      'id': bank.id,
      'name': bank.name,
      'description': bank.description,
      'created_at': bank.createdAt,
      'updated_at': bank.updatedAt,
    });
    return bank;
  }

  Future<void> insertBank(QuestionBank bank) async {
    final db = await database;
    await db.insert('banks', {
      'id': bank.id,
      'name': bank.name,
      'description': bank.description,
      'created_at': bank.createdAt,
      'updated_at': bank.updatedAt,
    }, conflictAlgorithm: ConflictAlgorithm.ignore);
  }

  Future<List<QuestionBank>> listBanks() async {
    final db = await database;
    final rows = await db.rawQuery('''
      SELECT b.*, COUNT(q.id) AS question_count
      FROM banks b
      LEFT JOIN questions q ON q.bank_id = b.id
      GROUP BY b.id
      ORDER BY b.created_at DESC
    ''');
    return rows
        .map((row) => QuestionBank(
              id: (row['id'] ?? '').toString(),
              name: (row['name'] ?? '').toString(),
              description: (row['description'] ?? '').toString(),
              createdAt: (row['created_at'] ?? '').toString(),
              updatedAt: (row['updated_at'] ?? '').toString(),
              questionCount: int.tryParse((row['question_count'] ?? '0').toString()) ?? 0,
            ))
        .toList();
  }

  Future<void> updateBankName(String id, String name) async {
    final db = await database;
    await db.update(
      'banks',
      {'name': name.trim(), 'updated_at': DateTime.now().toIso8601String()},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> deleteBank(String id) async {
    final db = await database;
    await db.delete('banks', where: 'id = ?', whereArgs: [id]);
  }

  Future<List<Question>> getQuestions({
    required String bankId,
    String query = '',
    int limit = 500,
  }) async {
    final db = await database;
    final where = StringBuffer('bank_id = ?');
    final args = <Object?>[bankId];
    final keyword = query.trim();
    if (keyword.isNotEmpty) {
      where.write(' AND search_text LIKE ?');
      args.add('%$keyword%');
    }
    final rows = await db.query(
      'questions',
      where: where.toString(),
      whereArgs: args,
      orderBy: 'created_at DESC',
      limit: limit,
    );
    return rows.map(Question.fromMap).toList();
  }

  Future<List<Question>> getAllQuestions() async {
    final db = await database;
    final rows = await db.query('questions', orderBy: 'created_at DESC');
    return rows.map(Question.fromMap).toList();
  }

  Future<Question?> getQuestion(String id) async {
    final db = await database;
    final rows = await db.query('questions', where: 'id = ?', whereArgs: [id], limit: 1);
    if (rows.isEmpty) return null;
    return Question.fromMap(rows.first);
  }

  Future<bool> hasHash(String bankId, String contentHash) async {
    final db = await database;
    final rows = await db.query(
      'questions',
      columns: ['id'],
      where: 'bank_id = ? AND content_hash = ?',
      whereArgs: [bankId, contentHash],
      limit: 1,
    );
    return rows.isNotEmpty;
  }

  Future<void> insertQuestions(
    List<Question> questions, {
    void Function(int done, int total)? onProgress,
  }) async {
    if (questions.isEmpty) return;
    final db = await database;
    await db.transaction((txn) async {
      for (var i = 0; i < questions.length; i++) {
        await txn.insert('questions', questions[i].toMap(), conflictAlgorithm: ConflictAlgorithm.ignore);
        if (i % 25 == 0) {
          onProgress?.call(i + 1, questions.length);
          await Future<void>.delayed(Duration.zero);
        }
      }
      onProgress?.call(questions.length, questions.length);
    });
  }

  Future<void> upsertQuestion(Question question) async {
    final db = await database;
    await db.insert('questions', question.toMap(), conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> deleteQuestion(String id) async {
    final db = await database;
    await db.delete('questions', where: 'id = ?', whereArgs: [id]);
  }

  Future<int> countQuestions(String bankId) async {
    final db = await database;
    final result = await db.rawQuery(
      'SELECT COUNT(*) AS c FROM questions WHERE bank_id = ?',
      [bankId],
    );
    return int.tryParse((result.first['c'] ?? '0').toString()) ?? 0;
  }

  Future<int> saveAiRecord(AiRecord record) async {
    final db = await database;
    return db.insert('ai_records', record.toMap());
  }

  Future<List<AiRecord>> listAiRecords({String? questionId, int limit = 200}) async {
    final db = await database;
    final rows = await db.query(
      'ai_records',
      where: questionId == null ? null : 'question_id = ?',
      whereArgs: questionId == null ? null : [questionId],
      orderBy: 'created_at DESC',
      limit: limit,
    );
    return rows.map(AiRecord.fromMap).toList();
  }

  Future<void> deleteAiRecord(int id) async {
    final db = await database;
    await db.delete('ai_records', where: 'id = ?', whereArgs: [id]);
  }

  Future<void> clearAiRecords() async {
    final db = await database;
    await db.delete('ai_records');
  }
}








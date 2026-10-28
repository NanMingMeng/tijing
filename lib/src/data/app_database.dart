import 'dart:async';

import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import '../models/question.dart';
import '../models/question_ai_index.dart';

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
      version: 3,
      onConfigure: (db) async {
        await db.execute('PRAGMA foreign_keys = ON');
      },
      onCreate: _create,
      onUpgrade: _upgrade,
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
        source_index INTEGER NOT NULL DEFAULT 0,
        order_index INTEGER NOT NULL DEFAULT 0,
        search_text TEXT NOT NULL DEFAULT '',
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        FOREIGN KEY (bank_id) REFERENCES banks(id) ON DELETE CASCADE
      )
    ''');
    await db.execute('CREATE INDEX idx_questions_bank ON questions(bank_id)');
    await db.execute('CREATE UNIQUE INDEX idx_questions_hash ON questions(bank_id, content_hash)');
    await db.execute('CREATE INDEX idx_questions_order ON questions(bank_id, order_index)');
    await _createAiIndex(db);
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

  /// AI 题库索引：让模型把每道题提炼成"考点短语 + 易混关键词 + 标准问法"，
  /// 之后搜题时用它在本地做二次校验，避免每次把整个题库塞给模型。
  Future<void> _createAiIndex(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS question_index (
        question_id TEXT PRIMARY KEY,
        bank_id TEXT NOT NULL,
        key_points TEXT NOT NULL DEFAULT '',
        keywords TEXT NOT NULL DEFAULT '',
        canonical TEXT NOT NULL DEFAULT '',
        model TEXT NOT NULL DEFAULT '',
        built_at TEXT NOT NULL
      )
    ''');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_qindex_bank ON question_index(bank_id)');
  }

  /// v1 → v2：新增原题库序号与库内序号，并用 rowid 顺序回填历史数据。
  Future<void> _upgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 3) {
      await _createAiIndex(db);
    }
    if (oldVersion < 2) {
      await db.execute(
          "ALTER TABLE questions ADD COLUMN source_index INTEGER NOT NULL DEFAULT 0");
      await db.execute(
          "ALTER TABLE questions ADD COLUMN order_index INTEGER NOT NULL DEFAULT 0");
      await db.execute(
          'CREATE INDEX IF NOT EXISTS idx_questions_order ON questions(bank_id, order_index)');
      // 老数据没有原始行号，用插入顺序（rowid）作为两个序号的最佳近似。
      await db.execute('''
        UPDATE questions
        SET order_index = (
          SELECT COUNT(*) FROM questions q2
          WHERE q2.bank_id = questions.bank_id AND q2.rowid <= questions.rowid
        )
        WHERE order_index = 0
      ''');
      await db.execute(
          'UPDATE questions SET source_index = order_index WHERE source_index = 0');
    }
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

  /// 查询题库内的题目。
  ///
  /// [limit] 为 null 表示不限制条数（题库详情页需要全量）；
  /// [offset] 用于分页加载。之前默认 limit=500，导致超过 500 题的题库
  /// 只显示前 500 条，看起来像"题丢了"。
  Future<List<Question>> getQuestions({
    required String bankId,
    String query = '',
    int? limit,
    int offset = 0,
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
      orderBy: 'order_index ASC, rowid ASC',
      limit: limit,
      offset: offset > 0 ? offset : null,
    );
    return rows.map(Question.fromMap).toList();
  }

  /// 按关键字统计命中题数，供题库详情页显示"共 N 题"。
  Future<int> countQuestionsByQuery(String bankId, {String query = ''}) async {
    final db = await database;
    final keyword = query.trim();
    if (keyword.isEmpty) return countQuestions(bankId);
    final result = await db.rawQuery(
      'SELECT COUNT(*) AS c FROM questions WHERE bank_id = ? AND search_text LIKE ?',
      [bankId, '%$keyword%'],
    );
    return int.tryParse((result.first['c'] ?? '0').toString()) ?? 0;
  }

  Future<List<Question>> getAllQuestions() async {
    final db = await database;
    final rows = await db.query('questions', orderBy: 'order_index ASC, rowid ASC');
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

  /// 读取某题库已建好的 AI 索引，返回 questionId -> (keywords, canonical, keyPoints)
  Future<Map<String, QuestionAiIndex>> loadAiIndex(String bankId) async {
    final db = await database;
    final rows = await db.query('question_index', where: 'bank_id = ?', whereArgs: [bankId]);
    final map = <String, QuestionAiIndex>{};
    for (final row in rows) {
      final id = (row['question_id'] ?? '').toString();
      if (id.isEmpty) continue;
      map[id] = QuestionAiIndex(
        keyPoints: (row['key_points'] ?? '').toString(),
        keywords: (row['keywords'] ?? '').toString(),
        canonical: (row['canonical'] ?? '').toString(),
        model: (row['model'] ?? '').toString(),
        builtAt: (row['built_at'] ?? '').toString(),
      );
    }
    return map;
  }

  /// 批量写入 AI 索引（覆盖同题旧索引）。
  Future<void> saveAiIndex(String bankId, List<QuestionAiIndexEntry> entries) async {
    if (entries.isEmpty) return;
    final db = await database;
    final now = DateTime.now().toIso8601String();
    await db.transaction((txn) async {
      for (final e in entries) {
        await txn.insert(
          'question_index',
          {
            'question_id': e.questionId,
            'bank_id': bankId,
            'key_points': e.keyPoints,
            'keywords': e.keywords,
            'canonical': e.canonical,
            'model': e.model,
            'built_at': now,
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
    });
  }

  Future<int> countAiIndex(String bankId) async {
    final db = await database;
    final r = await db.rawQuery(
      'SELECT COUNT(*) AS c FROM question_index WHERE bank_id = ?', [bankId]);
    return int.tryParse((r.first['c'] ?? '0').toString()) ?? 0;
  }

  Future<void> clearAiIndex(String bankId) async {
    final db = await database;
    await db.delete('question_index', where: 'bank_id = ?', whereArgs: [bankId]);
  }

  /// 本题库下一个可用的库内序号（删题不重排，保证编号稳定）。
  Future<int> nextOrderIndex(String bankId) async {
    final db = await database;
    final result = await db.rawQuery(
      'SELECT COALESCE(MAX(order_index), 0) AS m FROM questions WHERE bank_id = ?',
      [bankId],
    );
    final current = int.tryParse((result.first['m'] ?? '0').toString()) ?? 0;
    return current + 1;
  }

  /// 本题库下一个可用的原题库序号。
  Future<int> nextSourceIndex(String bankId) async {
    final db = await database;
    final result = await db.rawQuery(
      'SELECT COALESCE(MAX(source_index), 0) AS m FROM questions WHERE bank_id = ?',
      [bankId],
    );
    final current = int.tryParse((result.first['m'] ?? '0').toString()) ?? 0;
    return current + 1;
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








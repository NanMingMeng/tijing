import 'package:flutter_test/flutter_test.dart';
import 'package:tijing/src/models/question.dart';
import 'package:tijing/src/services/matcher.dart';

void main() {
  test('题干完全一致时高置信度命中', () {
    final questions = [
      Question(
        id: '1',
        bankId: 'bank',
        type: QuestionType.single,
        stem: '工程监理人员发现设计不符合质量标准时应当采取什么措施？',
        options: const [
          QuestionOption(key: 'A', text: '要求施工单位改正'),
          QuestionOption(key: 'B', text: '报告建设单位要求设计单位改正'),
        ],
        answerKeys: const ['B'],
        answerTexts: const ['报告建设单位要求设计单位改正'],
      ),
    ];
    final result = matchQuestions(questions, '工程监理人员发现设计不符合质量标准时应当采取什么措施？');
    expect(result.candidates, isNotEmpty);
    expect(result.candidates.first.question.id, '1');
    expect(result.confident, isTrue);
  });

  test('少量识别错误仍能找到候选', () {
    final questions = [
      Question(
        id: '2',
        bankId: 'bank',
        type: QuestionType.single,
        stem: '建筑防火设计规范适用于哪些新建、扩建、改建的建筑？',
      ),
    ];
    final result = matchQuestions(questions, '建筑防火设计规范适用于哪些新建扩建改建的建筑');
    expect(result.candidates, isNotEmpty);
    expect(result.candidates.first.question.id, '2');
  });
}

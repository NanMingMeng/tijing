import 'package:flutter/foundation.dart';

/// 题库数据变更广播。
///
/// 首页和题库页都常驻在 IndexedStack 里，只在 initState 读一次数据库，
/// 所以导入/编辑/删除后必须显式通知它们重新读取。
class BankEvents {
  BankEvents._();

  /// 每次题库内容变化就 +1；监听者据此重建自己的 Future。
  static final ValueNotifier<int> revision = ValueNotifier<int>(0);

  static void bump() => revision.value++;
}

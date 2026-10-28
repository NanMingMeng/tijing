# 题镜

题镜是一个安卓端「私有题库 + 拍照搜题」应用。用户自己导入 Excel 或 Word 题库，拍照后先在本地题库里找最像的原题；找不到时，再调用自己配置的大模型作答。

目标不是做公开题库，而是让每个人管理自己的题库，并能把题库副本分享给同学或老师。

## 当前版本

- 版本：0.3.0（versionCode 11）
- 平台：Android 10+，arm64-v8a
- 开源协议：MIT
- APK：通过 GitHub Releases 分发，本地构建产物不进仓库

## 三种搜题方式

| 方式 | 适合场景 | 原理 |
|---|---|---|
| 拍照搜题 | 单道题，要求识别准确 | 离线 OCR 识别，本地相似度匹配 |
| AI 查题 | 整页多道题（最多 10 道）快速过一遍 | AI 读图提取题目，逐道比对题库，未命中的自动作答 |
| 题库浏览 | 复习、核对 | 题库详情分页浏览，每道题带原题序号 |

## 已实现

### 题库管理

- Excel 导入
  - 自动识别表头，支持手动调整列映射
  - 支持单选、多选、判断、填空、简答
  - 答案可写选项原文或 A/B/C/D
  - 导入时保守查重，几乎完全重复才跳过
  - 导入过程显示进度条
- Word `.docx` 导入：本地规则拆题，识别不到的题标问题，不硬猜
- 老 `.doc` 提示先另存为 `.docx`
- 手机端编辑：改题、删题、加题
- 题库详情分页加载（每页 120 条），顶部显示「共 N 题 / 已显示 M」

### 原题序号

每道题都带两个编号，方便回到原始 Excel 核对：

- **原题库第 N 题**：导入时该题在源文件中的位置（Excel 按行号，Word 按解析顺序）
- **库内第 M 题**：题库内的稳定排序号，删题后不重排，编号不会漂移

查重被跳过的行仍然占用它的原题号，所以编号不会因为去重而错位。

### 拍照搜题

- 相机和相册，手动框选题目区域
- PaddleOCR 离线识别（内置模型，无需联网）
- 显示前 3 道候选，高置信度才自动展开答案
- 候选卡片显示「原题库第 N 题 · 库内第 M 题」

### AI 查题（v0.3.0 新增）

- 底部独立 Tab，拍一张整页题目
- AI 读图提取全部题目（**一次最多 10 道**）
- 逐道比对本地题库
  - 命中：显示题号与题库答案
  - 未命中：**自动**调用 AI 作答
- 未命中的题可一键「存入题库」，编号自动续写

### 题库 AI 索引（v0.3.0 新增）

在题库详情页点 ⭐ 图标，让模型为每道题提炼：

- 核心考点短语
- 易混关键词（3–6 个）
- 改写后的标准问法

结果存进本地 `question_index` 表。之后搜题时：

1. 先走文字相似度匹配
2. 再用索引做**二次校验**，两者取高分
3. 分数 ≥ 0.80 才判定命中题库

这样即使识别时认错字或换了说法，只要命中索引关键词，仍能正确判定为同一道题。

**这是一次性动作**，1007 题约需 41 次请求（每批 25 题）。建完后搜题在本地比对，不再重复消耗额度。

### AI 作答

- 用户自己填写 API Key，APP 不内置密钥
- 预设 DeepSeek、通义千问、智谱、硅基流动、OpenAI、Claude、Gemini
- 支持自定义 OpenAI 兼容接口
- 支持**直接看原图作答**（OpenAI 兼容 / Claude / Gemini 三种协议），避免 OCR 识别错误影响答案
- 题库答案与 AI 答案分开显示
- AI 历史本地保存，可单条删除、一键清空

### 分享与备份

- 不做链接、二维码分享
- 分享 APP 专用题库文件，对方直接导入
- 支持整库分享和选题目分享
- 一键备份 / 恢复，提醒定期导出
- 备份包含题库、AI 历史、设置
- **备份不包含 API Key**

## 已知限制

- 只支持 Android 64 位 `arm64-v8a`
- OCR 只识别打印体，手写题不支持
- 拍照搜题一次只处理一道题（整页多题请用「AI 查题」）
- 不支持公式、表格、图片题
- 老式 `.doc` 需先另存为 `.docx`
- 题库和历史本地普通存储，不加密
- **AI 查题的提取准确率不如 OCR 稳定**，视觉模型读长文本可能漏字；对单题精度要求高时建议用「拍照搜题」
- 需要图像输入的模型才能用「看图作答」，纯文本模型请关掉该开关

## 开发环境

- Flutter 3.47.8
- Dart 3.13.7
- JDK 17
- Android SDK 36
- NDK 28.2
- CMake 3.22.1

## 构建 release APK

```bash
flutter pub get
flutter build apk --release
```

产物：

```
build/app/outputs/flutter-apk/app-release.apk
```

### 构建注意事项

**1. 不要关闭 R8 压缩**

Flutter 3.44+ 默认对 release 开启 R8。`android/app/proguard-rules.pro` 里已经保留了 ONNX Runtime、OpenCV、PaddleOCR 的 JNI 反射类，**删掉这些规则会导致 OCR 首次识别即崩溃**（`java_class == null in call to GetMethodID`）。

**2. 内存较小时调低 Gradle 堆**

`android/gradle.properties` 默认 `-Xmx8G`。在 4G 内存以下的机器上请改小，例如：

```
org.gradle.jvmargs=-Xmx1100m -XX:MaxMetaspaceSize=512m
```

**3. 当前使用 debug 签名**

`android/app/build.gradle.kts` 里的 release 仍用 `signingConfigs.getConfig("debug")`，正式分发前请配置自己的 keystore。

**4. 国内网络可换镜像**

`PUB_HOSTED_URL` 和 `FLUTTER_STORAGE_BASE_URL` 可设为 `https://pub.flutter-io.cn` 与 `https://storage.flutter-io.cn`；Maven 可在 `settings.gradle.kts` 里加阿里云镜像。

## 测试

```bash
flutter test
dart analyze lib
```

真实 Excel 导入检查：

```bash
dart run tool/check_import.dart "<你的题库.xlsx>"
```

导出解析结果为 JSON（用于核对题号）：

```bash
dart run tool/export_drafts.dart "<你的题库.xlsx>"
```

## 许可证

MIT，详见 [LICENSE](LICENSE)。

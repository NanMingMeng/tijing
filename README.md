# 题镜

题镜是一个安卓端“私有题库 + 拍照搜题”应用。用户自己导入 Excel 或 Word 题库，拍照后离线识别题目，先在本地题库里找最像的原题；找不到时，再由用户主动调用自己配置的大模型作答。

第一版目标不是做公开题库，而是让每个人管理自己的题库，并能把题库副本分享给同学或老师。

## 当前版本

- 版本：0.1.2
- 平台：Android 10+，arm64-v8a
- 开源协议：MIT
- APK：通过 GitHub Releases 分发，本地构建产物不进仓库

## 已实现

- 首页：大按钮“拍照搜题”、题库入口、历史入口
- Excel 导入：
  - 自动识别表头
  - 支持手动调整列映射
  - 支持单选、多选、判断、填空、简答
  - 支持答案写选项原文或 A/B/C/D
  - 导入时保守查重，几乎完全重复才跳过
  - 导入过程显示进度条
- Word `.docx` 导入：
  - 本地规则拆题
  - 识别不到的题标问题，不硬猜
  - 老 `.doc` 提示用户先另存为 `.docx`
- 手机端题库编辑：改题、删题、加题
- 拍照搜题：
  - 相机和相册
  - 手动框选题目
  - PaddleOCR 离线识别
  - 前 3 道候选
  - 高置信度才自动显示答案
- AI 作答：
  - 用户自己填写 API Key
  - 内置 DeepSeek、通义千问、智谱、硅基流动、OpenAI、Claude、Gemini
  - 支持自定义 OpenAI 兼容接口
  - 题库答案和 AI 答案分开显示
  - AI 历史本地保存，可单条删除、一键清空
- 分享与备份：
  - APP 专用题库文件
  - 一键备份并分享
  - 从备份恢复
  - 备份不包含 API Key

## 当前限制

- 只支持 Android 64 位 `arm64-v8a`
- 第一版只识别打印体，手写题后续再加
- 第一版一次只处理一道题，整页多题后续再加
- 第一版不支持公式、表格、图片题
- 老式 `.doc` 不自动转换，需要用户另存为 `.docx`
- 不提供登录、班级管理、链接/二维码分享
- 题库和历史记录本地普通存储，不加密
- 超过 1 万题仍可导入，但可能变慢

## 开发环境

- Flutter 3.47.8
- Dart 3.13.7
- JDK 17（完整版，必须带 `jlink`）
- Android SDK 36
- NDK 28.2
- CMake 3.22.1

## 构建 release APK

```bash
flutter pub get
flutter build apk --release
```

产物：

`build/app/outputs/flutter-apk/app-release.apk`

### Windows 构建注意

Gradle/Kotlin 对中文路径支持不稳定。如果项目或 Flutter SDK 放在中文目录，建议先映射到英文路径，例如：

```powershell
New-Item -ItemType Junction -Path F:\tijing_work -Target <项目目录>
New-Item -ItemType Junction -Path F:\flutter_sdk -Target <Flutter SDK 目录>
New-Item -ItemType Junction -Path F:\jdk17 -Target <JDK 17 目录>
```

再从英文路径启动构建。

## 测试

```powershell
flutter test
dart analyze lib
```

真实 Excel 导入检查：

```powershell
dart run tool/check_import.dart "<你的题库.xlsx>"
```

## 许可证

MIT，详见 [LICENSE](LICENSE)。

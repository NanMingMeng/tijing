
import 'package:flutter/material.dart';
import 'package:image_cropper/image_cropper.dart';
import 'package:image_picker/image_picker.dart';

import '../models/question.dart';
import '../services/ocr_service.dart';
import '../theme.dart';
import 'search_result_page.dart';

class CameraPage extends StatefulWidget {
  const CameraPage({super.key, required this.banks});

  final List<QuestionBank> banks;

  @override
  State<CameraPage> createState() => _CameraPageState();
}

class _CameraPageState extends State<CameraPage> {
  final _picker = ImagePicker();
  late QuestionBank _bank;
  bool _working = false;
  String _status = '';

  @override
  void initState() {
    super.initState();
    _bank = widget.banks.first;
  }

  Future<void> _pick(ImageSource source) async {
    if (_working) return;
    try {
      final picked = await _picker.pickImage(source: source, imageQuality: 95);
      if (picked == null) return;
      setState(() {
        _working = true;
        _status = '正在框选题目…';
      });
      final cropped = await ImageCropper().cropImage(
        sourcePath: picked.path,
        compressFormat: ImageCompressFormat.jpg,
        compressQuality: 92,
        uiSettings: [
          AndroidUiSettings(
            toolbarTitle: '框选题目',
            toolbarColor: Colors.white,
            toolbarWidgetColor: AppTheme.ink,
            backgroundColor: Colors.black,
            lockAspectRatio: false,
            hideBottomControls: false,
            initAspectRatio: CropAspectRatioPreset.original,
          ),
          IOSUiSettings(title: '框选题目'),
        ],
      );
      if (cropped == null) {
        setState(() {
          _working = false;
          _status = '';
        });
        return;
      }
      setState(() => _status = '正在离线识别文字…');
      final text = await OcrService.recognize(cropped.path);
      if (!mounted) return;
      if (text.trim().isEmpty) {
        setState(() {
          _working = false;
          _status = '';
        });
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('没有识别到文字，请重新拍清楚一点')));
        return;
      }
      setState(() {
        _working = false;
        _status = '';
      });
      await Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => SearchResultPage(
          bank: _bank,
          recognizedText: text,
          imagePath: cropped.path,
        ),
      ));
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _working = false;
        _status = '';
      });
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('识别失败：$e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('拍照搜题')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 10, 20, 30),
        children: [
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: AppTheme.line),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('选择题库', style: TextStyle(fontWeight: FontWeight.w700)),
                const SizedBox(height: 10),
                DropdownButtonFormField<QuestionBank>(
                  initialValue: _bank,
                  isExpanded: true,
                  items: widget.banks.map((bank) => DropdownMenuItem(value: bank, child: Text('${bank.name}（${bank.questionCount} 题）', overflow: TextOverflow.ellipsis))).toList(),
                  onChanged: _working ? null : (value) {
                    if (value != null) setState(() => _bank = value);
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          Container(
            height: 300,
            decoration: BoxDecoration(
              color: const Color(0xFF0B1215),
              borderRadius: BorderRadius.circular(26),
            ),
            child: Center(
              child: _working
                  ? Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const CircularProgressIndicator(color: Colors.white),
                        const SizedBox(height: 16),
                        Text(_status, style: const TextStyle(color: Colors.white70)),
                      ],
                    )
                  : Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 92,
                          height: 92,
                          decoration: BoxDecoration(
                            border: Border.all(color: Colors.white24, width: 2),
                            borderRadius: BorderRadius.circular(26),
                          ),
                          child: const Icon(Icons.center_focus_strong_rounded, color: Colors.white, size: 50),
                        ),
                        const SizedBox(height: 20),
                        const Text('把题目放进框里', style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w700)),
                        const SizedBox(height: 8),
                        const Text('下一步可以手动调整框选区域', style: TextStyle(color: Colors.white54, fontSize: 13)),
                      ],
                    ),
            ),
          ),
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: _working ? null : () => _pick(ImageSource.camera),
            icon: const Icon(Icons.photo_camera_rounded),
            label: const Text('拍照'),
          ),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: _working ? null : () => _pick(ImageSource.gallery),
            icon: const Icon(Icons.photo_library_outlined),
            label: const Text('从相册选择'),
          ),
          const SizedBox(height: 18),
          const Text('第一版只识别打印体、单道题；手写题和整页多题后续支持。', style: TextStyle(fontSize: 12, color: AppTheme.muted)),
        ],
      ),
    );
  }
}



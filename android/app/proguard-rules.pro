# ONNX Runtime：native 层通过 JNI GetMethodID 反射访问 Java 类与方法名，
# 一旦被 R8 裁剪或重命名，就会在 OrtSession.run 里
# "JNI DETECTED ERROR: java_class == null in call to GetMethodID" 直接 SIGABRT。
-keep class ai.onnxruntime.** { *; }
-keepclassmembers class ai.onnxruntime.** { *; }
-keep class ai.onnxruntime.OrtSession$Result { *; }
-keep class ai.onnxruntime.OnnxTensor { *; }
-keep class ai.onnxruntime.OnnxValue { *; }
-keep class ai.onnxruntime.TensorInfo { *; }
-keep class ai.onnxruntime.OrtEnvironment { *; }
-keep class ai.onnxruntime.OrtSession$SessionOptions { *; }
-keep class ai.onnxruntime.OnnxJavaType { *; }
-dontwarn ai.onnxruntime.**

# OpenCV：paddle_ocr_native 内部通过类名直接引用
-keep class org.opencv.** { *; }
-dontwarn org.opencv.**

# PaddleOCR 插件本体与 vendored ppocr-sdk
-keep class com.flespark.paddle_ocr_native.** { *; }
-keep class com.baidu.paddle.** { *; }
-dontwarn com.baidu.paddle.**

# 保留 native 方法名（JNI 依赖符号名无法混淆）
-keepclasseswithmembernames,includedescriptorclasses class * {
    native <methods>;
}

// ignore_for_file: depend_on_referenced_packages, uri_does_not_exist, undefined_function, avoid_print

import 'dart:io';
import 'package:llamadart/llamadart.dart';

void main() async {
  print('=== llamadart 测试开始 ===');

  try {
    print('1. 创建 LlamaBackend...');
    final backend = LlamaBackend();

    print('2. 创建 LlamaEngine...');
    final engine = LlamaEngine(backend);

    print(
        '3. 输入模型路径 (例如: models\\qwen2.5-1.5b-q4km\\qwen2.5-1.5b-instruct-q4_k_m.gguf):');
    stdout.write('> ');
    String? modelPath = stdin.readLineSync();

    if (modelPath == null || modelPath.isEmpty) {
      print('错误: 模型路径为空');
      return;
    }

    final file = File(modelPath);
    if (!await file.exists()) {
      print('错误: 文件不存在: $modelPath');
      return;
    }

    print('4. 加载模型: $modelPath...');
    await engine.loadModel(modelPath);
    print('✅ 模型加载成功!');

    print('5. 创建 ChatSession...');
    final session = ChatSession(engine);

    print('6. 开始测试翻译...');
    final prompt = '翻译: Hello, world!';

    print('发送请求...');
    final buffer = StringBuffer();
    await for (final chunk in session.create([LlamaTextContent(prompt)])) {
      final content = chunk.choices.first.delta.content;
      if (content != null) {
        buffer.write(content);
        print('收到内容: $content');
      }
    }

    print('7. 翻译结果:');
    print(buffer.toString());

    print('8. 清理资源...');
    await engine.dispose();

    print('=== 测试完成 ===');
  } catch (e, stackTrace) {
    print('❌ 测试失败!');
    print('错误: $e');
    print('堆栈: $stackTrace');
  }
}

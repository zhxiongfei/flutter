// @dart = 2.8

import 'dart:io';

import 'package:flutter_tools/src/artifacts.dart';
import 'package:flutter_tools/src/base/common.dart';
import 'package:flutter_tools/src/base/file_system.dart';
import 'package:flutter_tools/src/build_info.dart';
import 'package:flutter_tools/src/globals.dart';

/// 创建时间：2020-03-28
/// 作者：liujingguang
/// 描述：Hook处理工厂
enum CommandType4Aop { Bundle, Aot, Snapshot }

// ignore: avoid_classes_with_only_static_members
class HookFactory {
  static Future<void> hook(String productDirPath, String executorPath,
      BuildMode buildMode, CommandType4Aop type) async {
    if (productDirPath == null ||
        executorPath == null ||
        !fs.file(executorPath).existsSync()) {
      return;
    }

    String inputPath;
    switch (type) {
      case CommandType4Aop.Bundle:
        inputPath = _getBundleInputPath(productDirPath);
        break;
      case CommandType4Aop.Aot:
        inputPath = _getAotInputPath(productDirPath);
        break;
      case CommandType4Aop.Snapshot:
        inputPath = _getSnapShotInputPath(productDirPath);
        break;
    }
    if (!inputPath.startsWith(fs.currentDirectory.path)) {
      inputPath = fs.path.join(fs.currentDirectory.path, inputPath);
    }
    if (!fs.file(inputPath).existsSync()) {
      return;
    }

    final String outputPath =
        inputPath + '.${type.toString().toLowerCase()}.result.dill';

    final String engineDartPath =
        artifacts.getHostArtifact(HostArtifact.engineDartBinary).path;

    /// 执行hook命令
    final List<String> command = <String>[
      engineDartPath,
      executorPath,
      '--input',
      inputPath,
      '--output',
      outputPath,
      if (buildMode != BuildMode.release) ...<String>[
        '--sdk-root',
        fs
                .file(artifacts.getArtifactPath(Artifact.platformKernelDill))
                .parent
                .path +
            fs.path.separator
      ],
    ];

    print(command.toString());
    final ProcessResult result = await processManager.run(command);
    if (result.exitCode != 0) {
      print(result.stderr);
      throwToolExit(
          'hook by aop terminated unexpectedly in ${type.toString()}.');
      return;
    }

    print('aop hook succeed');

    /// 删除input输入文件
    final File inputFile = fs.file(inputPath);
    if (inputFile.existsSync()) {
//      inputFile.copySync(inputPath + '.old'); //调试时可以打开查看信息
      inputFile.deleteSync();
    }

    /// 将Aop处理生成后的output文件重命名为input文件名
    fs.file(outputPath).renameSync(inputPath);
  }

  static String _getBundleInputPath(String assetsDir) =>
      fs.path.join(assetsDir, 'kernel_blob.bin');

  static String _getAotInputPath(String path) =>
      fs.path.join(path ?? getAotBuildDirectory(), 'app.dill');

  static String _getSnapShotInputPath(String path) => path;
}

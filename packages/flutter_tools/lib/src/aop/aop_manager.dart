// @dart = 2.8

import 'package:flutter_tools/src/aop/hook_factory.dart';
import 'package:flutter_tools/src/dart/package_map.dart';
import 'package:package_config/package_config.dart';
import 'package:yaml/yaml.dart';
import 'package:file/file.dart' as f;
import '../globals.dart' as globals;
import '../artifacts.dart';

import '../build_info.dart';
import '../globals.dart';

// ignore: avoid_classes_with_only_static_members
class AopManager {
  static const String sYamlConfigName = 'aop_config.yaml';
  static const String key_flutter_tools_hook = 'flutter_tools_hook';
  static const String key_project_name = 'project_name';
  static const String key_exec_path = 'exec_path';

  static Future<void> hookBuildBundleCommand(
    String productDirPath,
    BuildMode buildMode,
  ) async {
    await _handleHook(productDirPath, buildMode, CommandType4Aop.Bundle);
  }

  static Future<void> hookBuildAotCommand(
    String productDirPath,
    BuildMode buildMode,
  ) async {
    await _handleHook(productDirPath, buildMode, CommandType4Aop.Aot);
  }

  static Future<void> hookSnapshotCommand(
    String productDirPath,
    BuildMode buildMode,
  ) async {
    await _handleHook(productDirPath, buildMode, CommandType4Aop.Snapshot);
  }

  static Future<List<String>> aopArgs(BuildMode buildMode) async {
    final String dart_path = globals.artifacts
        .getArtifactPath(Artifact.frontendServerSnapshotForEngineDartSdk);

    final List proceduresList = await _aopProcedures();

    final List<String> args = [
      '--build-mode',
      buildMode.name,
      '--dart-path',
      dart_path
    ];

    if (proceduresList != null && proceduresList.isNotEmpty) {
      final String produces = proceduresList.join(',');
      args.add('--aop-packages');
      args.add(produces);
    }

    return args;
  }

  static Future<List<String>> _aopProcedures() async {
    List<String> procedures = List<String>();

    final String configYamlPath =
        fs.path.join(fs.currentDirectory.path, sYamlConfigName);

    if (fs.file(configYamlPath).existsSync()) {
      final dynamic yamlInfo =
          loadYaml(fs.file(configYamlPath).readAsStringSync());

      if (yamlInfo == null) {
        return null;
      }

      if (yamlInfo[key_flutter_tools_hook] is! YamlList) {
        return null;
      }

      final YamlList yamlNodes = yamlInfo[key_flutter_tools_hook] as YamlList;
      for (dynamic v in yamlNodes) {
        if (v == null) {
          continue;
        }

        final String projectName = v[key_project_name] as String;
        final String execPath = v[key_exec_path] as String;

        if (projectName == null || execPath == null) {
          continue;
        }

        final String packagePath = await _findAopPackagePath(projectName);
        if (packagePath == null) {
          continue;
        }

        procedures.add(fs.path.join(packagePath, execPath));
      }
    }

    return procedures;
  }

  static Future<void> _handleHook(
      String productDirPath, BuildMode buildMode, CommandType4Aop type) async {
//    return Future.value();
    try {
      final String configYamlPath =
          fs.path.join(fs.currentDirectory.path, sYamlConfigName);

      print(configYamlPath);

      if (fs.file(configYamlPath).existsSync()) {
        final dynamic yamlInfo =
            loadYaml(fs.file(configYamlPath).readAsStringSync());

        if (yamlInfo == null) {
          return;
        }

        if (yamlInfo[key_flutter_tools_hook] is! YamlList) {
          return;
        }

        final YamlList yamlNodes = yamlInfo[key_flutter_tools_hook] as YamlList;
        for (dynamic v in yamlNodes) {
          if (v == null) {
            return;
          }

          final String projectName = v[key_project_name] as String;
          final String execPath = v[key_exec_path] as String;

          if (projectName == null || execPath == null) {
            return;
          }
          final String packagePath = await _findAopPackagePath(projectName);
          if (packagePath == null) {
            return;
          }

          await HookFactory.hook(productDirPath,
              fs.path.join(packagePath, execPath), buildMode, type);
        }
      }
      // ignore: avoid_catches_without_on_clauses
    } catch (e) {
      printTrace('error in _handleHook of $type : ${e.toString()}');
    }
  }

  /// 获取项目中引用flutter_aop_data_parse的路径
  static Future<String> _findAopPackagePath(String projectName) async {
    Map<String, dynamic> packages;
    try {
      final String packagesFilePath =
          fs.path.join(fs.currentDirectory.path, '.packages');

      final f.File packageFile = fs.file(packagesFilePath);
      final PackageConfig packageConfig =
          await loadPackageConfigWithLogging(packageFile);
      packages = PackageConfig.toJson(packageConfig);

      for (Package package in packageConfig.packages) {
        if (package.name == projectName) {
          final Uri uri = package.packageUriRoot;
          final String uriString = uri.path;
          return uriString;
        }
      }
      // ignore: avoid_catches_without_on_clauses
    } catch (e) {
      printTrace('Invalid .packages file: $e');
      return null;
    }

    return null;
  }
}

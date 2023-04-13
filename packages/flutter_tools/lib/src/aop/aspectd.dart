// Copyright 2018 The Chromium Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

// @dart = 2.8

import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:yaml/yaml.dart';
import 'package:package_config/package_config.dart';

import '../artifacts.dart';
import '../base/file_system.dart';
import '../dart/package_map.dart';
import '../globals.dart' as globals;

const String aspectdImplPackageRelPath = '..';
const String frontendServerDartSnapshot = 'frontend_server.dart.snapshot';
const String sYamlConfigName = 'aop_config.yaml';
const String key_flutter_tools_hook = 'flutter_tools_hook';
const String key_project_name = 'project_name';
const String house_aspectd = 'house_aspectd';
const String inner_path = 'inner';
const String globalPackagesPath = '.packages';

// ignore: avoid_classes_with_only_static_members
class AspectdHook {
  static Future<Directory> getPackagePathFromConfig(
      String packageConfigPath, String packageName) async {
    final PackageConfig packageConfig = await loadPackageConfigWithLogging(
      globals.fs.file(packageConfigPath),
      logger: globals.logger,
    );
    if ((packageConfig?.packages?.length ?? 0) > 0) {
      final Package aspectdPackage = packageConfig.packages.toList().firstWhere(
          (Package element) => element.name == packageName,
          orElse: () => null);

      if (aspectdPackage == null) {
        return null;
      }
      return globals.fs.directory(aspectdPackage.root.toFilePath());
    }
    return null;
  }

  static Future<Directory> getFlutterFrontendServerDirectory(
      String packagesPath) async {
    final Directory directory =
        await getPackagePathFromConfig(packagesPath, house_aspectd);

    if (directory == null) {
      return null;
    }

    return globals.fs.directory(globals.fs.path
        .join(directory.absolute.path, inner_path, 'flutter_frontend_server'));
  }

  static bool configFileExists() {
    final String configYamlPath =
        globals.fs.path.join(globals.fs.currentDirectory.path, sYamlConfigName);

    print('[aop]: configYamlPath is $configYamlPath');

    final String exist = globals.fs.file(configYamlPath).existsSync().toString();
    print('[aop]: isExistConfigYaml is $exist');

    if (globals.fs.file(configYamlPath).existsSync()) {
      final dynamic yamlInfo =
          loadYaml(globals.fs.file(configYamlPath).readAsStringSync());

      final String yamlString = globals.fs.file(configYamlPath).readAsStringSync();
      print('[aop]: yamlString is $yamlString');

      if (yamlInfo == null) {
        return false;
      }

      print('[aop]: key_flutter_tools_hook is $yamlInfo[key_flutter_tools_hook]');

      if (yamlInfo[key_flutter_tools_hook] is! YamlList) {
        return false;
      }



      final YamlList yamlNodes = yamlInfo[key_flutter_tools_hook] as YamlList;

      final String cntStr = yamlNodes.nodes.length.toString();
      print('[aop]: yamlNodes.count is $cntStr');

      print('[aop] yamlNodes nodes is ${yamlNodes.nodes}');

      if (yamlNodes.nodes.isNotEmpty) {
        return true;
      }
    }

    return false;
  }

  static Directory getAspectdDirectory(Directory rootProjectDir) {
    return globals.fs.directory(globals.fs.path.normalize(globals.fs.path
        .join(rootProjectDir.path, aspectdImplPackageRelPath, house_aspectd)));
  }

  static Future<void> enableAspectd() async {
    final Directory currentDirectory = globals.fs.currentDirectory;

    final String packagesPath = globals.fs.path
        .join(currentDirectory.absolute.path, globalPackagesPath);

    final Directory houseAspectdDirectory =
        await getPackagePathFromConfig(packagesPath, house_aspectd);

    final Directory flutterFrontendServerDirectory =
        await getFlutterFrontendServerDirectory(packagesPath);

    print('[aop]: houseAspectdDirectory is $houseAspectdDirectory');
    print('[aop]: flutterFrontendServerDirectory is $flutterFrontendServerDirectory');

    if (houseAspectdDirectory == null ||
        flutterFrontendServerDirectory == null) {
      return;
    }

    final String aspectdPackagesPath = globals.fs.path.join(
        houseAspectdDirectory.absolute.path, inner_path, globalPackagesPath);

    print('[aop]: aspectdPackagesPath is $aspectdPackagesPath');

    await checkAspectdFlutterFrontendServerSnapshot(
        aspectdPackagesPath, flutterFrontendServerDirectory);
  }

  static Future<void> checkAspectdFlutterFrontendServerSnapshot(
      String packagesPath, Directory flutterFrontendServerDirectory) async {
    final String aspectdFlutterFrontendServerSnapshot = globals.fs.path.join(
        flutterFrontendServerDirectory.absolute.path,
        frontendServerDartSnapshot);

    final String defaultFlutterFrontendServerSnapshot = globals.artifacts
        .getArtifactPath(Artifact.frontendServerSnapshotForEngineDartSdk);
    final File defaultServerFile =
        globals.fs.file(defaultFlutterFrontendServerSnapshot);
    final File aspectdServerFile =
        globals.fs.file(aspectdFlutterFrontendServerSnapshot);

    print('[aop]: aspectdFlutterFrontendServerSnapshot $aspectdFlutterFrontendServerSnapshot');

    print('[aop]: aspectdServerFile $aspectdServerFile');
    print('[aop]: defaultServerFile $defaultServerFile');

    if (defaultServerFile.existsSync()) {

      print('[aop]: aspectdServerFile $aspectdServerFile');
      print('[aop]: defaultServerFile $defaultServerFile');

      String defString = md5.convert(defaultServerFile.readAsBytesSync()).toString();
      String aspString = md5.convert(aspectdServerFile.readAsBytesSync()).toString();

      print('[aop]: md5 defaultServerFile $defString');
      print('[aop]: md5 aspectdServerFile $aspString');

      if (md5.convert(defaultServerFile.readAsBytesSync()) ==
          md5.convert(aspectdServerFile.readAsBytesSync())) {

        print('[aop]: md5相同, 不需要替换 frontend_server.dart.snapshot');
        return true;
      }

      globals.fs.file(defaultFlutterFrontendServerSnapshot).deleteSync();
    }

    aspectdServerFile.copySync(defaultFlutterFrontendServerSnapshot);

    print('[aop]: New frontend server snapshot updated');
  }
}

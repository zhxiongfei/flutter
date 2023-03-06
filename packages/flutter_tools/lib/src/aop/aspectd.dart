// Copyright 2018 The Chromium Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

// @dart = 2.8

import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:yaml/yaml.dart';
import 'package:package_config/package_config.dart';

import '../artifacts.dart';
import '../base/common.dart';
import '../build_info.dart';
import '../base/file_system.dart';
import '../build_system/build_system.dart';
import '../build_system/targets/common.dart';
import '../cache.dart';
import '../compile.dart';
import '../dart/package_map.dart';
import '../globals.dart' as globals;

const String aspectdImplPackageRelPath = '..';
const String frontendServerDartSnapshot = 'frontend_server.dart.snapshot';
const String sYamlConfigName = 'aop_config.yaml';
const String key_flutter_tools_hook = 'flutter_tools_hook';
const String key_project_name = 'project_name';
const String key_exec_path = 'exec_path';
const String house_aspectd = 'house_aspectd';
const String inner_path = 'inner';
const String globalPackagesPath = '.packages';

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

    if (globals.fs.file(configYamlPath).existsSync()) {
      final dynamic yamlInfo =
          loadYaml(globals.fs.file(configYamlPath).readAsStringSync());

      if (yamlInfo == null) {
        return false;
      }

      if (yamlInfo[key_flutter_tools_hook] is! YamlList) {
        return false;
      }

      final YamlList yamlNodes = yamlInfo[key_flutter_tools_hook] as YamlList;

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

    if (houseAspectdDirectory == null ||
        flutterFrontendServerDirectory == null) {
      return;
    }

    final String aspectdPackagesPath = globals.fs.path.join(
        houseAspectdDirectory.absolute.path, inner_path, globalPackagesPath);

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

    if (defaultServerFile.existsSync()) {
      if (md5.convert(defaultServerFile.readAsBytesSync()) ==
          md5.convert(aspectdServerFile.readAsBytesSync())) {
        return true;
      }

      globals.fs.file(defaultFlutterFrontendServerSnapshot).deleteSync();
    }

    aspectdServerFile.copySync(defaultFlutterFrontendServerSnapshot);

    print('[aop]: New frontend server snapshot updated');
  }

  static Future<String> getDartSdkDependency(String aspectdDir) async {
    final ProcessResult processResult = await globals.processManager.run(
        <String>[
          globals.fs.path.join(
              globals.artifacts.getArtifactPath(
                  Artifact.frontendServerSnapshotForEngineDartSdk),
              'bin',
              'pub'),
          'get',
          '--verbosity=warning'
        ],
        workingDirectory: aspectdDir,
        environment: <String, String>{'FLUTTER_ROOT': Cache.flutterRoot});
    if (processResult.exitCode != 0) {
      throwToolExit(
          'Aspectd unexpected error: ${processResult.stderr.toString()}');
    }
    final Directory kernelDir = await getPackagePathFromConfig(
        globals.fs.path.join(aspectdDir, globalPackagesPath), 'kernel');
    return kernelDir.parent.parent.path;
  }

  Future<void> runBuildDillCommand(Environment environment) async {
    print('aop front end compiling');

    final Directory mainDirectory = globals.fs.currentDirectory;

    String relativeDir = environment.outputDir.absolute.path
        .substring(environment.projectDir.absolute.path.length + 1);
    final String outputDir =
        globals.fs.path.join(mainDirectory.path, relativeDir);

    final String buildDir =
        globals.fs.path.join(mainDirectory.path, '.dart_tool', 'flutter_build');

    final Map<String, String> defines = environment.defines;
    relativeDir = defines[kTargetFile]
        .substring(environment.projectDir.absolute.path.length + 1);

    String targetFile = environment.defines[kTargetFile];
    targetFile ??= globals.fs.path.join(mainDirectory.path, 'lib', 'main.dart');

    defines[kTargetFile] = targetFile;

    final Environment auxEnvironment = Environment(
        projectDir: mainDirectory,
        outputDir: globals.fs.directory(outputDir),
        cacheDir: environment.cacheDir,
        flutterRootDir: environment.flutterRootDir,
        fileSystem: environment.fileSystem,
        logger: environment.logger,
        artifacts: environment.artifacts,
        processManager: environment.processManager,
        engineVersion: environment.engineVersion,
        buildDir: globals.fs.directory(buildDir),
        defines: defines,
        inputs: environment.inputs);
    const KernelSnapshot auxKernelSnapshot = KernelSnapshot();
    final CompilerOutput compilerOutput =
        await auxKernelSnapshot.buildImpl(auxEnvironment);

    final String aspectdDill = compilerOutput.outputFilename;

    print('Aspectdill path : ' + aspectdDill);
    final File originalDillFile = globals.fs.file(
        globals.fs.path.join(environment.buildDir.absolute.path, 'app.dill'));

    print('originalDillFile path : ' + originalDillFile.path);
    if (originalDillFile.existsSync()) {
      await originalDillFile.copy(originalDillFile.absolute.path + '.bak');
    }
    globals.fs.file(aspectdDill).copySync(originalDillFile.absolute.path);
  }
}

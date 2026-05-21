import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:open_file/open_file.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

class UpdateService {
  static void Function()? _updateProgress;

  /// 检查更新
  static Future<void> check(BuildContext context) async {
    try {
      final res = await http.get(
        Uri.parse(
          "https://sunland.dev/update.json?t=${DateTime.now().millisecondsSinceEpoch}",
        ),
      );

      if (res.statusCode != 200) {
        print("❌ 更新接口状态异常: ${res.statusCode}");
        return;
      }

      print("📦 更新接口返回: ${res.body}");

      if (!res.body.trim().startsWith("{")) {
        print("❌ 更新接口返回异常: ${res.body}");
        return;
      }

      final data = jsonDecode(res.body);

      final latest = data["version"]?.toString();
      final apkUrl = (data["apk_url"] ?? data["url"])?.toString();
      final force = data["force"] ?? false;
      final desc = data["desc"]?.toString() ?? "";
      final appStoreUrl = data["app_store_url"]?.toString();

      if (latest == null) {
        print("❌ version 字段缺失");
        return;
      }

      final packageInfo = await PackageInfo.fromPlatform();
      final current = "${packageInfo.version}+${packageInfo.buildNumber}";

      print("📱 当前版本: $current, 最新版本: $latest");

      if (Platform.isIOS) {
        if (appStoreUrl != null && _isNewVersion(current, latest)) {
          _showIOSDialog(context, appStoreUrl, force, desc);
        }
        return;
      }

      if (apkUrl == null) {
        print("❌ apk_url/url 字段缺失");
        return;
      }

      if (_isNewVersion(current, latest)) {
        _showDialog(context, apkUrl, force, desc);
      }
    } catch (e) {
      print("❌ 更新检查失败: $e");
    }
  }

  /// 比较版本号
  static bool _isNewVersion(String current, String latest) {
    List<int> parseMain(String v) {
      final main = v.split('+').first.split('-').first;
      return main.split('.').map((e) => int.tryParse(e) ?? 0).toList();
    }

    int parseBuild(String v) {
      if (!v.contains('+')) return 0;
      return int.tryParse(v.split('+').last) ?? 0;
    }

    int parseBeta(String v) {
      if (!v.contains('-')) return 9999;
      final suffix = v.split('-').last;
      final num = RegExp(r'\d+').firstMatch(suffix);
      return num != null ? int.parse(num.group(0)!) : 0;
    }

    final cMain = parseMain(current);
    final lMain = parseMain(latest);

    final len = cMain.length > lMain.length ? cMain.length : lMain.length;
    for (int i = 0; i < len; i++) {
      final ci = i < cMain.length ? cMain[i] : 0;
      final li = i < lMain.length ? lMain[i] : 0;
      if (li > ci) return true;
      if (li < ci) return false;
    }

    // 主版本相同 → 比较 build number
    final cBuild = parseBuild(current);
    final lBuild = parseBuild(latest);

    if (lBuild > cBuild) return true;
    if (lBuild < cBuild) return false;

    // build 也相同 → 比较 beta
    final cBeta = parseBeta(current);
    final lBeta = parseBeta(latest);

    return lBeta > cBeta;
  }

  /// 弹窗
  static void _showDialog(
    BuildContext context,
    String url,
    bool force,
    String desc,
  ) {
    showDialog(
      context: context,
      barrierDismissible: !force,
      builder: (_) => AlertDialog(
        title: const Text("发现新版本 🚀"),
        content: Text(desc.isEmpty ? "建议更新以获得更好体验" : desc),
        actions: [
          if (!force)
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text("稍后"),
            ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _downloadAndInstall(context, url);
            },
            child: const Text("立即更新"),
          ),
        ],
      ),
    );
  }

  static void _showIOSDialog(
    BuildContext context,
    String url,
    bool force,
    String desc,
  ) {
    showDialog(
      context: context,
      barrierDismissible: !force,
      builder: (_) => AlertDialog(
        title: const Text("发现新版本 🚀"),
        content: Text(desc.isEmpty ? "请前往 App Store 更新" : desc),
        actions: [
          if (!force)
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text("稍后"),
            ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(context);
              final uri = Uri.parse(url);
              if (await canLaunchUrl(uri)) {
                await launchUrl(uri, mode: LaunchMode.externalApplication);
              }
            },
            child: const Text("前往更新"),
          ),
        ],
      ),
    );
  }

  /// 下载 + 安装
  static Future<void> _downloadAndInstall(
    BuildContext context,
    String url,
  ) async {
    final navigator = Navigator.of(context);
    final scaffoldMessenger = ScaffoldMessenger.of(context);

    final dir = await getApplicationDocumentsDirectory();
    final path = "${dir.path}/sunland_update.apk";

    final dio = Dio();

    double progress = 0;
    bool done = false;
    bool dialogOpen = true;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setState) {
          void update() {
            if (dialogOpen && dialogContext.mounted) {
              setState(() {});
            }
          }

          _updateProgress = update;

          return PopScope(
            canPop: false,
            onPopInvokedWithResult: (didPop, result) {
              if (!didPop) {
                dialogOpen = false;
                Navigator.of(dialogContext).pop();
              }
            },
            child: AlertDialog(
              title: Text(done ? "下载完成" : "正在下载更新"),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  LinearProgressIndicator(value: done ? 1 : progress),
                  const SizedBox(height: 10),
                  Text(
                    done
                        ? "安装包已准备完成"
                        : "${(progress * 100).toStringAsFixed(0)}%",
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );

    try {
      await dio.download(
        url,
        path,
        onReceiveProgress: (received, total) {
          if (total > 0) {
            progress = received / total;
          }
          _updateProgress?.call();
        },
      );

      done = true;

      if (navigator.canPop()) navigator.pop();
      dialogOpen = false;
      _updateProgress = null;

      await OpenFile.open(path);
    } catch (e) {
      print("❌ 下载失败: $e");
      if (navigator.canPop()) navigator.pop();
      dialogOpen = false;
      _updateProgress = null;
      scaffoldMessenger.showSnackBar(
        const SnackBar(content: Text("下载失败，请检查网络或稍后重试")),
      );
    } finally {
      dio.close();
    }
  }
}

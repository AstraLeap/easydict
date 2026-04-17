import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';
import '../core/logger.dart';
import '../core/utils/toast_utils.dart';
import '../services/font_loader_service.dart';
import '../services/app_update_service.dart';
import '../components/global_scale_wrapper.dart';
import '../i18n/strings.g.dart';

class HelpPage extends StatefulWidget {
  final VoidCallback? onBack;

  const HelpPage({super.key, this.onBack});

  @override
  State<HelpPage> createState() => _HelpPageState();
}

class _HelpPageState extends State<HelpPage> {
  final double _contentScale = FontLoaderService().getDictionaryContentScale();
  PackageInfo? _packageInfo;
  bool _isLoading = true;
  bool _showHiddenFeatures = false;

  @override
  void initState() {
    super.initState();
    _loadPackageInfo();
  }

  Future<void> _loadPackageInfo() async {
    try {
      final info = await PackageInfo.fromPlatform();
      setState(() {
        _packageInfo = info;
        _isLoading = false;
      });
    } catch (e) {
      debugPrint('获取包信息失败: $e');
      setState(() {
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final appUpdateService = context.watch<AppUpdateService>();

    // 显示隐藏功能页面
    if (_showHiddenFeatures) {
      return _buildHiddenFeaturesPage(context, colorScheme);
    }

    final content = Scaffold(
      appBar: AppBar(
        leading: widget.onBack != null
            ? IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: widget.onBack,
              )
            : null,
        title: Text(context.t.help.title),
        centerTitle: true,
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        surfaceTintColor: Colors.transparent,
      ),
      body: PageScaleWrapper(
        scale: _contentScale,
        child: CustomScrollView(
          slivers: [
            SliverList(
              delegate: SliverChildBuilderDelegate((context, index) {
                return Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 800),
                    child: _buildContent(
                      context,
                      colorScheme,
                      appUpdateService,
                    ),
                  ),
                );
              }, childCount: 1),
            ),
          ],
        ),
      ),
    );

    // 如果有 onBack 回调，使用 PopScope 拦截系统返回
    if (widget.onBack != null) {
      return PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, popResult) {
          if (!didPop) {
            widget.onBack!();
          }
        },
        child: content,
      );
    }

    return content;
  }

  /// 构建隐藏功能页面
  Widget _buildHiddenFeaturesPage(
    BuildContext context,
    ColorScheme colorScheme,
  ) {
    final content = Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            setState(() {
              _showHiddenFeatures = false;
            });
          },
        ),
        title: Text(context.t.help.hiddenFeaturesTitle),
        centerTitle: true,
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        surfaceTintColor: Colors.transparent,
      ),
      body: PageScaleWrapper(
        scale: _contentScale,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // 通配符搜索
            _buildFeatureCard(
              context,
              icon: Icons.search,
              iconColor: colorScheme.primary,
              title: context.t.help.wildcardSearch,
              description: context.t.help.wildcardSearchDesc,
            ),
            const SizedBox(height: 16),
            // 粘贴图片网址
            _buildFeatureCard(
              context,
              icon: Icons.link,
              iconColor: colorScheme.primary,
              title: context.t.help.pasteImageUrl,
              description: context.t.help.pasteImageUrlDesc,
            ),
            const SizedBox(height: 16),
            // 电脑端导航
            _buildFeatureCard(
              context,
              icon: Icons.computer,
              iconColor: colorScheme.secondary,
              title: context.t.help.desktopNavTitle,
              description: context.t.help.desktopNavDesc,
            ),
            const SizedBox(height: 16),
            // 手机端导航
            _buildFeatureCard(
              context,
              icon: Icons.phone_android,
              iconColor: colorScheme.tertiary,
              title: context.t.help.mobileNavTitle,
              description: context.t.help.mobileNavDesc,
            ),
          ],
        ),
      ),
    );

    // 使用 PopScope 拦截系统返回
    if (widget.onBack != null) {
      return PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, popResult) {
          if (!didPop) {
            setState(() {
              _showHiddenFeatures = false;
            });
          }
        },
        child: content,
      );
    }

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, popResult) {
        if (!didPop) {
          setState(() {
            _showHiddenFeatures = false;
          });
        }
      },
      child: content,
    );
  }

  Widget _buildContent(
    BuildContext context,
    ColorScheme colorScheme,
    AppUpdateService appUpdateService,
  ) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          const SizedBox(height: 24),
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(borderRadius: BorderRadius.circular(20)),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: Image.asset(
                'assets/icon/app_icon.png',
                width: 80,
                height: 80,
                fit: BoxFit.cover,
              ),
            ),
          ),
          const SizedBox(height: 20),
          ShaderMask(
            shaderCallback: (bounds) => LinearGradient(
              colors: [colorScheme.primary, colorScheme.secondary],
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
            ).createShader(bounds),
            child: Text(
              'EasyDict',
              style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                fontWeight: FontWeight.bold,
                color: Colors.white,
                letterSpacing: 2.0,
                fontFamily: 'SourceSerif4',
              ),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            context.t.help.tagline,
            style: TextStyle(
              fontSize: 16,
              color: colorScheme.onSurfaceVariant,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 28),

          // 隐藏功能
          _buildSettingsGroup(
            context,
            children: [
              _buildSettingsTile(
                context,
                title: context.t.help.hiddenFeatures,
                icon: Icons.tips_and_updates_outlined,
                iconColor: colorScheme.primary,
                onTap: () {
                  setState(() {
                    _showHiddenFeatures = true;
                  });
                },
              ),
            ],
          ),

          const SizedBox(height: 16),

          // GitHub 组（包含检查更新）
          _buildSettingsGroup(
            context,
            children: [
              _buildUpdateTile(context, appUpdateService),
              _buildSettingsTile(
                context,
                title: 'GitHub',
                subtitle: context.t.help.githubSubtitle,
                icon: Icons.code,
                iconColor: colorScheme.primary,
                isExternal: true,
                onTap: () async {
                  final url = Uri.parse(
                    'https://github.com/AstraLeap/easydict',
                  );
                  if (await canLaunchUrl(url)) {
                    await launchUrl(url, mode: LaunchMode.externalApplication);
                  }
                },
              ),
              _buildSettingsTile(
                context,
                title: context.t.help.forumTitle,
                subtitle: context.t.help.forumSubtitle,
                icon: Icons.forum_outlined,
                iconColor: colorScheme.primary,
                isExternal: true,
                onTap: () async {
                  final url = Uri.parse(
                    'https://forum.freemdict.com/t/topic/43251',
                  );
                  if (await canLaunchUrl(url)) {
                    await launchUrl(url, mode: LaunchMode.externalApplication);
                  }
                },
              ),
              _buildLogTile(context),
            ],
          ),

          const SizedBox(height: 16),

          Text(
            'Copyright © 2026 EasyDict Team',
            style: TextStyle(
              fontSize: 12,
              color: colorScheme.outline.withOpacity(0.5),
            ),
          ),
        ],
      ),
    );
  }

  String _getFlutterVersion() {
    return '3.19.0';
  }

  String _getDartVersion() {
    return '3.3.0';
  }

  Widget _buildSettingsGroup(
    BuildContext context, {
    required List<Widget> children,
  }) {
    final colorScheme = Theme.of(context).colorScheme;

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: colorScheme.outlineVariant.withOpacity(0.5),
          width: 1,
        ),
      ),
      child: Column(
        children: _addDividers(
          children,
          colorScheme.outlineVariant.withOpacity(0.3),
        ),
      ),
    );
  }

  List<Widget> _addDividers(List<Widget> children, Color dividerColor) {
    final result = <Widget>[];
    for (int i = 0; i < children.length; i++) {
      result.add(children[i]);
      if (i < children.length - 1) {
        result.add(Divider(height: 1, indent: 56, color: dividerColor));
      }
    }
    return result;
  }

  Widget _buildSettingsTile(
    BuildContext context, {
    required String title,
    String? subtitle,
    required IconData icon,
    Color? iconColor,
    bool isExternal = false,
    VoidCallback? onTap,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    final effectiveIconColor = iconColor ?? colorScheme.onSurfaceVariant;

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      leading: Icon(icon, color: effectiveIconColor, size: 24),
      title: Text(
        title,
        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
      ),
      subtitle: subtitle != null
          ? Text(
              subtitle,
              style: TextStyle(
                fontSize: 12,
                color: colorScheme.onSurfaceVariant,
              ),
            )
          : null,
      trailing: isExternal
          ? Icon(Icons.open_in_new, color: colorScheme.outline, size: 18)
          : Icon(Icons.chevron_right, color: colorScheme.outline, size: 18),
      onTap: onTap,
    );
  }

  Widget _buildInfoTile(BuildContext context, String title, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            title,
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }

  Widget _buildCopyableTile(
    BuildContext context, {
    required String title,
    required String subtitle,
    required IconData icon,
    Color? iconColor,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    final effectiveIconColor = iconColor ?? colorScheme.onSurfaceVariant;

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      leading: Icon(icon, color: effectiveIconColor, size: 24),
      title: Text(
        title,
        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
      ),
      subtitle: Text(
        subtitle,
        style: TextStyle(fontSize: 11, color: colorScheme.onSurfaceVariant),
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: Icon(Icons.copy, color: colorScheme.outline, size: 18),
      onTap: () {
        Clipboard.setData(ClipboardData(text: subtitle));
        showToast(context, '路径已复制到剪贴板');
      },
    );
  }

  Widget _buildOpenFolderTile(
    BuildContext context, {
    required String title,
    required String path,
    required IconData icon,
    Color? iconColor,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    final effectiveIconColor = iconColor ?? colorScheme.onSurfaceVariant;

    // Android 等平台无法直接打开私有目录，改为复制路径
    final bool canOpenFolder =
        Platform.isWindows || Platform.isMacOS || Platform.isLinux;

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      leading: Icon(icon, color: effectiveIconColor, size: 24),
      title: Text(
        title,
        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
      ),
      subtitle: Text(
        path,
        style: TextStyle(fontSize: 11, color: colorScheme.onSurfaceVariant),
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: Icon(
        canOpenFolder ? Icons.open_in_new : Icons.copy,
        color: colorScheme.outline,
        size: 18,
      ),
      onTap: () async {
        if (canOpenFolder) {
          // 桌面平台：使用系统命令打开文件夹
          try {
            if (Platform.isWindows) {
              await Process.run('explorer', [path]);
            } else if (Platform.isMacOS) {
              await Process.run('open', [path]);
            } else if (Platform.isLinux) {
              await Process.run('xdg-open', [path]);
            }
          } catch (e) {
            debugPrint('打开文件夹失败: $e');
            // 回退到 url_launcher
            final uri = Uri.file(path);
            if (await canLaunchUrl(uri)) {
              await launchUrl(uri);
            }
          }
        } else {
          // 移动平台：复制路径到剪贴板
          Clipboard.setData(ClipboardData(text: path));
          if (context.mounted) {
            showToast(context, '路径已复制到剪贴板');
          }
        }
      },
    );
  }

  Widget _buildUpdateTile(BuildContext context, AppUpdateService service) {
    final colorScheme = Theme.of(context).colorScheme;

    String subtitle;
    Widget? trailing;
    VoidCallback? onTap;

    if (service.isChecking) {
      subtitle = context.t.help.checking;
      trailing = const SizedBox(
        width: 18,
        height: 18,
        child: CircularProgressIndicator(strokeWidth: 2),
      );
    } else if (service.hasUpdate) {
      subtitle = context.t.help.updateAvailable(
        version: service.latestRelease?.version ?? '',
      );
      trailing = Icon(Icons.open_in_new, color: colorScheme.error, size: 18);
      onTap = () async {
        final url = Uri.tryParse(service.latestRelease?.htmlUrl ?? '');
        if (url != null && await canLaunchUrl(url)) {
          await launchUrl(url, mode: LaunchMode.externalApplication);
        }
      };
    } else if (service.latestRelease != null) {
      subtitle = context.t.help.upToDate(version: service.currentVersion ?? '');
      trailing = Icon(
        Icons.check_circle_outline,
        color: colorScheme.primary,
        size: 18,
      );
      onTap = () => service.checkForUpdates();
    } else if (service.errorMessage != null) {
      subtitle = service.errorMessage!;
      trailing = const Icon(Icons.refresh, size: 18);
      onTap = () => service.checkForUpdates();
    } else {
      subtitle = context.t.help.currentVersion(
        version: service.currentVersion ?? (_packageInfo?.version ?? ''),
      );
      trailing = const Icon(Icons.refresh, size: 18);
      onTap = () => service.checkForUpdates();
    }

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      leading: Stack(
        clipBehavior: Clip.none,
        children: [
          Icon(
            Icons.system_update_outlined,
            color: service.hasUpdate ? colorScheme.error : colorScheme.primary,
            size: 24,
          ),
          if (service.hasUpdate)
            Positioned(
              right: -4,
              top: -4,
              child: Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: colorScheme.error,
                  shape: BoxShape.circle,
                ),
              ),
            ),
        ],
      ),
      title: Text(
        context.t.help.checkUpdate,
        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
      ),
      subtitle: Text(
        subtitle,
        style: TextStyle(
          fontSize: 12,
          color: service.hasUpdate
              ? colorScheme.error
              : colorScheme.onSurfaceVariant,
        ),
      ),
      trailing: trailing,
      onTap: onTap,
    );
  }

  Widget _buildLogTile(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      leading: Icon(
        Icons.article_outlined,
        color: colorScheme.primary,
        size: 24,
      ),
      title: Text(
        context.t.help.debugLog,
        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
      ),
      subtitle: Text(
        context.t.help.debugLogDesc,
        style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant),
      ),
      trailing: Icon(Icons.chevron_right, color: colorScheme.outline, size: 18),
      onTap: () async {
        final logFile = await Logger.getLatestLogFile();
        if (!context.mounted) return;

        if (logFile == null) {
          showToast(context, context.t.help.noLogFile);
          return;
        }

        // 读取日志文件内容
        String logContent;
        try {
          logContent = await logFile.readAsString();
        } catch (e) {
          debugPrint('读取日志文件失败: $e');
          if (context.mounted) {
            showToast(context, context.t.help.logReadError);
          }
          return;
        }

        if (!context.mounted) return;

        // 弹窗显示日志内容
        _showLogDialog(context, logFile.path, logContent);
      },
    );
  }

  void _showLogDialog(BuildContext context, String logPath, String logContent) {
    final colorScheme = Theme.of(context).colorScheme;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(context.t.help.logDialogTitle),
        titlePadding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
        contentPadding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
        content: SizedBox(
          width: double.maxFinite,
          height: 400,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                logPath,
                style: TextStyle(
                  fontSize: 11,
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: SingleChildScrollView(
                    child: SelectableText(
                      logContent,
                      style: TextStyle(
                        fontSize: 12,
                        fontFamily: 'monospace',
                        color: colorScheme.onSurface,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(context.t.common.close),
          ),
        ],
      ),
    );
  }

  Widget _buildFeatureCard(
    BuildContext context, {
    required IconData icon,
    required Color iconColor,
    required String title,
    required String description,
  }) {
    final colorScheme = Theme.of(context).colorScheme;

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: colorScheme.outlineVariant.withOpacity(0.5),
          width: 1,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: iconColor, size: 24),
                const SizedBox(width: 12),
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              description,
              style: TextStyle(
                fontSize: 14,
                color: colorScheme.onSurfaceVariant,
                height: 1.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

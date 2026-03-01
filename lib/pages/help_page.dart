import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';
import '../services/font_loader_service.dart';
import '../services/app_update_service.dart';
import '../components/global_scale_wrapper.dart';

class HelpPage extends StatefulWidget {
  const HelpPage({super.key});

  @override
  State<HelpPage> createState() => _HelpPageState();
}

class _HelpPageState extends State<HelpPage> {
  final double _contentScale = FontLoaderService().getDictionaryContentScale();
  PackageInfo? _packageInfo;
  bool _isLoading = true;

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

    return Scaffold(
      appBar: AppBar(
        title: const Text('关于软件'),
        centerTitle: true,
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        surfaceTintColor: Colors.transparent,
      ),
      body: PageScaleWrapper(
        scale: _contentScale,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Center(
              child: Column(
                children: [
                  const SizedBox(height: 24),
                  Container(
                    width: 80,
                    height: 80,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(20),
                    ),
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
                      colors: [
                        colorScheme.primary,
                        colorScheme.secondary,
                      ],
                      begin: Alignment.centerLeft,
                      end: Alignment.centerRight,
                    ).createShader(bounds),
                    child: Text(
                      'EasyDict',
                      style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                        letterSpacing: 2.0,
                      ),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '查词，不折腾',
                    style: TextStyle(
                      fontSize: 16,
                      color: colorScheme.onSurfaceVariant,
                      letterSpacing: 0.5,
                    ),
                  ),
                  const SizedBox(height: 28),
                ],
              ),
            ),

            _buildSettingsGroup(
              context,
              children: [
                _buildSettingsTile(
                  context,
                  title: '词典反馈',
                  subtitle: '任何改进建议尽管提出',
                  icon: Icons.forum_outlined,
                  iconColor: colorScheme.primary,
                  isExternal: true,
                  onTap: () async {
                    final url = Uri.parse(
                      'https://forum.freemdict.com/t/topic/43251',
                    );
                    if (await canLaunchUrl(url)) {
                      await launchUrl(
                        url,
                        mode: LaunchMode.externalApplication,
                      );
                    }
                  },
                ),
                _buildSettingsTile(
                  context,
                  title: 'GitHub',
                  subtitle: '查看源码、提交 Issue',
                  icon: Icons.code,
                  iconColor: colorScheme.primary,
                  isExternal: true,
                  onTap: () async {
                    final url = Uri.parse(
                      'https://github.com/AstraLeap/easydict',
                    );
                    if (await canLaunchUrl(url)) {
                      await launchUrl(
                        url,
                        mode: LaunchMode.externalApplication,
                      );
                    }
                  },
                ),
                _buildSettingsTile(
                  context,
                  title: '爱发电',
                  subtitle: '支持开发者',
                  icon: Icons.favorite_border,
                  iconColor: colorScheme.primary,
                  isExternal: true,
                  onTap: () async {
                    final url = Uri.parse('https://afdian.com/a/karx_');
                    if (await canLaunchUrl(url)) {
                      await launchUrl(
                        url,
                        mode: LaunchMode.externalApplication,
                      );
                    }
                  },
                ),
              ],
            ),

            const SizedBox(height: 16),

            // 检查更新组
            _buildSettingsGroup(
              context,
              children: [_buildUpdateTile(context, appUpdateService)],
            ),

            const SizedBox(height: 16),

            Center(
              child: Text(
                'Copyright © 2026 EasyDict Team',
                style: TextStyle(
                  fontSize: 12,
                  color: colorScheme.outline.withOpacity(0.5),
                ),
              ),
            ),
          ],
        ),
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
          : const Icon(Icons.chevron_right),
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

  Widget _buildUpdateTile(BuildContext context, AppUpdateService service) {
    final colorScheme = Theme.of(context).colorScheme;

    String subtitle;
    Widget? trailing;
    VoidCallback? onTap;

    if (service.isChecking) {
      subtitle = '正在检查…';
      trailing = const SizedBox(
        width: 18,
        height: 18,
        child: CircularProgressIndicator(strokeWidth: 2),
      );
    } else if (service.hasUpdate) {
      subtitle =
          '发现新版本 ${service.latestRelease?.version ?? ''} · 点击前往 GitHub 下载';
      trailing = Icon(Icons.open_in_new, color: colorScheme.error, size: 18);
      onTap = () async {
        final url = Uri.tryParse(service.latestRelease?.htmlUrl ?? '');
        if (url != null && await canLaunchUrl(url)) {
          await launchUrl(url, mode: LaunchMode.externalApplication);
        }
      };
    } else if (service.latestRelease != null) {
      subtitle = '已是最新版本 ${service.currentVersion ?? ''}';
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
      subtitle =
          '当前版本 ${service.currentVersion ?? (_packageInfo?.version ?? '')}';
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
        '检查更新',
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
}

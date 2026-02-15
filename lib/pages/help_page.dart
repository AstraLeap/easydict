import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:package_info_plus/package_info_plus.dart';
import '../utils/dpi_utils.dart';

class HelpPage extends StatefulWidget {
  const HelpPage({super.key});

  @override
  State<HelpPage> createState() => _HelpPageState();
}

class _HelpPageState extends State<HelpPage> {
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

    return Scaffold(
      appBar: AppBar(title: const Text('帮助与反馈'), centerTitle: true),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // 顶部 Logo 和版本信息
          Center(
            child: Column(
              children: [
                const SizedBox(height: 24),
                Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    color: colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Icon(
                    Icons.book,
                    size: 48,
                    color: colorScheme.onPrimaryContainer,
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'EasyDict',
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: colorScheme.primary,
                  ),
                ),
                const SizedBox(height: 8),
                if (_isLoading)
                  const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                else
                  Text(
                    _packageInfo?.version ?? 'v1.0.0',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: colorScheme.outline,
                    ),
                  ),
                const SizedBox(height: 32),
              ],
            ),
          ),

          // 帮助与支持组
          _buildSettingsGroup(
            context,
            children: [
              _buildSettingsTile(
                context,
                title: '词典反馈',
                icon: Icons.feedback_outlined,
                iconColor: colorScheme.primary,
                onTap: () async {
                  // TODO: 实现反馈功能
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
                    await launchUrl(url, mode: LaunchMode.externalApplication);
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
                    await launchUrl(url, mode: LaunchMode.externalApplication);
                  }
                },
              ),
            ],
          ),

          const SizedBox(height: 24),

          // 编译信息
          _buildSettingsGroup(
            context,
            children: [
              if (_isLoading)
                const Padding(
                  padding: EdgeInsets.all(16),
                  child: Center(child: CircularProgressIndicator()),
                )
              else ...[
                _buildInfoTile(context, '应用版本', _packageInfo?.version ?? '未知'),
                _buildInfoTile(
                  context,
                  '构建版本',
                  _packageInfo?.buildNumber ?? '未知',
                ),
                _buildInfoTile(
                  context,
                  '包名',
                  _packageInfo?.packageName ?? '未知',
                ),
                _buildInfoTile(context, 'Flutter SDK', _getFlutterVersion()),
                _buildInfoTile(context, 'Dart SDK', _getDartVersion()),
              ],
            ],
          ),

          const SizedBox(height: 40),

          Center(
            child: Text(
              'Copyright © 2024 EasyDict Team',
              style: TextStyle(
                fontSize: 12,
                color: colorScheme.outline.withOpacity(0.5),
              ),
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
      contentPadding: EdgeInsets.symmetric(
        horizontal: DpiUtils.scale(context, 16),
        vertical: DpiUtils.scale(context, 4),
      ),
      leading: Icon(
        icon,
        color: effectiveIconColor,
        size: DpiUtils.scaleIconSize(context, 24),
      ),
      title: Text(
        title,
        style: TextStyle(
          fontSize: DpiUtils.scaleFontSize(context, 14),
          fontWeight: FontWeight.w500,
        ),
      ),
      subtitle: subtitle != null
          ? Text(
              subtitle,
              style: TextStyle(
                fontSize: DpiUtils.scaleFontSize(context, 12),
                color: colorScheme.onSurfaceVariant,
              ),
            )
          : null,
      trailing: isExternal
          ? Icon(
              Icons.open_in_new,
              color: colorScheme.outline,
              size: DpiUtils.scaleIconSize(context, 18),
            )
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
}

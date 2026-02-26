import 'package:flutter/material.dart';
import '../core/utils/language_utils.dart';

class LanguageDropdown extends StatelessWidget {
  final String? selectedLanguage;
  final List<String> availableLanguages;
  final bool showAllOption;
  final ValueChanged<String?> onSelected;

  const LanguageDropdown({
    super.key,
    required this.selectedLanguage,
    required this.availableLanguages,
    required this.onSelected,
    this.showAllOption = true,
  });

  String _getSelectedLabel() {
    if (selectedLanguage == null ||
        (showAllOption && selectedLanguage == 'ALL')) {
      return '';
    }
    return LanguageUtils.getLanguageDisplayName(selectedLanguage!);
  }

  @override
  Widget build(BuildContext context) {
    final bool isAllOrAuto =
        selectedLanguage == null ||
        (!showAllOption && selectedLanguage == 'auto') ||
        (showAllOption && selectedLanguage == 'ALL');

    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(8),
      child: PopupMenuButton<String?>(
        tooltip: '选择语言',
        offset: const Offset(-8, 45),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        elevation: 4,
        color: Theme.of(context).colorScheme.surface,
        initialValue: selectedLanguage,
        onSelected: onSelected,
        itemBuilder: (context) {
          final items = <PopupMenuEntry<String?>>[];

          if (showAllOption) {
            items.addAll([
              PopupMenuItem(
                value: 'ALL',
                child: Row(
                  children: [
                    Icon(
                      Icons.search,
                      size: 18,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 12),
                    const Text('全部'),
                  ],
                ),
              ),
              const PopupMenuDivider(height: 1),
            ]);
          }

          items.addAll(
            availableLanguages.map(
              (lang) => PopupMenuItem(
                value: lang,
                child: Row(
                  children: [
                    Icon(
                      Icons.language,
                      size: 18,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 12),
                    Text(LanguageUtils.getLanguageDisplayName(lang)),
                  ],
                ),
              ),
            ),
          );

          return items;
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: Theme.of(
              context,
            ).colorScheme.surfaceContainerHighest.withOpacity(0.7),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: Theme.of(
                context,
              ).colorScheme.outlineVariant.withOpacity(0.5),
              width: 1,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (isAllOrAuto)
                Icon(
                  Icons.search,
                  size: 18,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                )
              else
                Text(
                  _getSelectedLabel(),
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurface,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              const SizedBox(width: 4),
              Icon(
                Icons.expand_more,
                size: 16,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

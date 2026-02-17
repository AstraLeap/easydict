import 'package:flutter/material.dart';
import 'language_dropdown.dart';

class UnifiedSearchBar extends StatelessWidget {
  final TextEditingController controller;
  final String? hintText;
  final Widget? prefixIcon;
  final List<Widget> suffixIcons;
  final BoxConstraints? prefixIconConstraints;
  final BoxConstraints? suffixIconConstraints;
  final void Function(String)? onChanged;
  final void Function(String)? onSubmitted;
  final bool enabled;

  const UnifiedSearchBar({
    super.key,
    required this.controller,
    this.hintText,
    this.prefixIcon,
    this.suffixIcons = const [],
    this.prefixIconConstraints,
    this.suffixIconConstraints,
    this.onChanged,
    this.onSubmitted,
    this.enabled = true,
  });

  factory UnifiedSearchBar.withLanguageSelector({
    Key? key,
    required TextEditingController controller,
    required String selectedLanguage,
    required List<String> availableLanguages,
    required void Function(String?) onLanguageSelected,
    String? hintText,
    bool showAllOption = false,
    List<Widget> extraSuffixIcons = const [],
    void Function(String)? onChanged,
    void Function(String)? onSubmitted,
    bool enabled = true,
  }) {
    return UnifiedSearchBar(
      key: key,
      controller: controller,
      hintText: hintText,
      prefixIcon: Container(
        margin: const EdgeInsets.fromLTRB(8, 4, 4, 4),
        child: LanguageDropdown(
          selectedLanguage: selectedLanguage,
          availableLanguages: availableLanguages,
          showAllOption: showAllOption,
          onSelected: onLanguageSelected,
        ),
      ),
      prefixIconConstraints: const BoxConstraints(minWidth: 48, minHeight: 40),
      suffixIcons: extraSuffixIcons,
      onChanged: onChanged,
      onSubmitted: onSubmitted,
      enabled: enabled,
    );
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      enabled: enabled,
      decoration: InputDecoration(
        hintText: hintText,
        prefixIcon: prefixIcon,
        prefixIconConstraints: prefixIconConstraints,
        suffixIcon: Row(
          mainAxisSize: MainAxisSize.min,
          children: suffixIcons.map((icon) {
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 0),
              child: icon,
            );
          }).toList(),
        ),
        suffixIconConstraints:
            suffixIconConstraints ?? const BoxConstraints(minWidth: 90),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 12,
        ),
      ),
      onChanged: onChanged,
      onSubmitted: onSubmitted,
    );
  }
}

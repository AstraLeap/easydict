import 'package:flutter/material.dart';
import 'language_dropdown.dart';

class UnifiedSearchBar extends StatefulWidget {
  final TextEditingController controller;
  final FocusNode? focusNode;
  final String? hintText;
  final Widget? prefixIcon;
  final List<Widget> suffixIcons;
  final BoxConstraints? prefixIconConstraints;
  final BoxConstraints? suffixIconConstraints;
  final void Function(String)? onChanged;
  final void Function(String)? onSubmitted;
  final VoidCallback? onTap;
  final bool enabled;

  const UnifiedSearchBar({
    super.key,
    required this.controller,
    this.focusNode,
    this.hintText,
    this.prefixIcon,
    this.suffixIcons = const [],
    this.prefixIconConstraints,
    this.suffixIconConstraints,
    this.onChanged,
    this.onSubmitted,
    this.onTap,
    this.enabled = true,
  });

  @override
  State<UnifiedSearchBar> createState() => _UnifiedSearchBarState();
}

class _UnifiedSearchBarState extends State<UnifiedSearchBar> {
  bool _hasText = false;

  @override
  void initState() {
    super.initState();
    _hasText = widget.controller.text.isNotEmpty;
    widget.controller.addListener(_onTextChanged);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onTextChanged);
    super.dispose();
  }

  void _onTextChanged() {
    final hasText = widget.controller.text.isNotEmpty;
    if (hasText != _hasText) {
      setState(() {
        _hasText = hasText;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final availableWidth = constraints.maxWidth;
        final double dynamicIconWidth;
        if (availableWidth < 400) {
          dynamicIconWidth = 32;
        } else if (availableWidth < 600) {
          dynamicIconWidth = 40;
        } else {
          dynamicIconWidth = 48;
        }

        return TextField(
          controller: widget.controller,
          focusNode: widget.focusNode,
          enabled: widget.enabled,
          decoration: InputDecoration(
            hintText: widget.hintText,
            prefixIcon: widget.prefixIcon,
            prefixIconConstraints: widget.prefixIconConstraints,
            suffixIcon: widget.suffixIcons.isNotEmpty
                ? SizedBox(
                    width:
                        dynamicIconWidth *
                            widget.suffixIcons.length.toDouble() +
                        16,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        ...widget.suffixIcons.map((icon) {
                          return SizedBox(
                            width: dynamicIconWidth,
                            height: 40,
                            child: icon,
                          );
                        }),
                        const SizedBox(width: 8),
                      ],
                    ),
                  )
                : null,
            suffixIconConstraints:
                widget.suffixIconConstraints ??
                const BoxConstraints(minWidth: 40, minHeight: 40),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 12,
            ),
          ),
          onChanged: widget.onChanged,
          onSubmitted: widget.onSubmitted,
          onTap: widget.onTap,
        );
      },
    );
  }
}

class UnifiedSearchBarWithLanguageSelector extends StatefulWidget {
  final TextEditingController controller;
  final FocusNode? focusNode;
  final String selectedLanguage;
  final List<String> availableLanguages;
  final void Function(String?) onLanguageSelected;
  final String? hintText;
  final bool showAllOption;
  final List<Widget> extraSuffixIcons;
  final void Function(String)? onChanged;
  final void Function(String)? onSubmitted;
  final VoidCallback? onTap;
  final bool enabled;
  final bool showClearButton;

  const UnifiedSearchBarWithLanguageSelector({
    super.key,
    required this.controller,
    this.focusNode,
    required this.selectedLanguage,
    required this.availableLanguages,
    required this.onLanguageSelected,
    this.hintText,
    this.showAllOption = false,
    this.extraSuffixIcons = const [],
    this.onChanged,
    this.onSubmitted,
    this.onTap,
    this.enabled = true,
    this.showClearButton = true,
  });

  @override
  State<UnifiedSearchBarWithLanguageSelector> createState() =>
      _UnifiedSearchBarWithLanguageSelectorState();
}

class _UnifiedSearchBarWithLanguageSelectorState
    extends State<UnifiedSearchBarWithLanguageSelector> {
  bool _hasText = false;

  @override
  void initState() {
    super.initState();
    _hasText = widget.controller.text.isNotEmpty;
    widget.controller.addListener(_onTextChanged);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onTextChanged);
    super.dispose();
  }

  void _onTextChanged() {
    final hasText = widget.controller.text.isNotEmpty;
    if (hasText != _hasText) {
      setState(() {
        _hasText = hasText;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final availableWidth = constraints.maxWidth;
        final double dynamicIconWidth;
        if (availableWidth < 400) {
          dynamicIconWidth = 32;
        } else if (availableWidth < 600) {
          dynamicIconWidth = 40;
        } else {
          dynamicIconWidth = 48;
        }

        final allSuffixIcons = <Widget>[];
        if (widget.showClearButton && _hasText) {
          allSuffixIcons.add(
            IconButton(
              icon: const Icon(Icons.clear, size: 20),
              onPressed: () {
                widget.controller.clear();
              },
              visualDensity: VisualDensity.compact,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
            ),
          );
        }
        allSuffixIcons.addAll(widget.extraSuffixIcons);

        return TextField(
          controller: widget.controller,
          focusNode: widget.focusNode,
          enabled: widget.enabled,
          decoration: InputDecoration(
            hintText: widget.hintText,
            prefixIcon: Container(
              margin: const EdgeInsets.fromLTRB(8, 4, 4, 4),
              child: LanguageDropdown(
                selectedLanguage: widget.selectedLanguage,
                availableLanguages: widget.availableLanguages,
                showAllOption: widget.showAllOption,
                onSelected: widget.onLanguageSelected,
              ),
            ),
            prefixIconConstraints: const BoxConstraints(
              minWidth: 48,
              minHeight: 40,
            ),
            suffixIcon: allSuffixIcons.isNotEmpty
                ? SizedBox(
                    width:
                        dynamicIconWidth * allSuffixIcons.length.toDouble() +
                        16,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        ...allSuffixIcons.map((icon) {
                          return SizedBox(
                            width: dynamicIconWidth,
                            height: 40,
                            child: icon,
                          );
                        }),
                        const SizedBox(width: 8),
                      ],
                    ),
                  )
                : null,
            suffixIconConstraints: const BoxConstraints(
              minWidth: 40,
              minHeight: 40,
            ),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 12,
            ),
          ),
          onChanged: widget.onChanged,
          onSubmitted: widget.onSubmitted,
          onTap: widget.onTap,
        );
      },
    );
  }
}

class UnifiedSearchBarFactory {
  static Widget withLanguageSelector({
    Key? key,
    required TextEditingController controller,
    FocusNode? focusNode,
    required String selectedLanguage,
    required List<String> availableLanguages,
    required void Function(String?) onLanguageSelected,
    String? hintText,
    bool showAllOption = false,
    List<Widget> extraSuffixIcons = const [],
    void Function(String)? onChanged,
    void Function(String)? onSubmitted,
    VoidCallback? onTap,
    bool enabled = true,
    bool showClearButton = true,
  }) {
    return UnifiedSearchBarWithLanguageSelector(
      key: key,
      controller: controller,
      focusNode: focusNode,
      selectedLanguage: selectedLanguage,
      availableLanguages: availableLanguages,
      onLanguageSelected: onLanguageSelected,
      hintText: hintText,
      showAllOption: showAllOption,
      extraSuffixIcons: extraSuffixIcons,
      onChanged: onChanged,
      onSubmitted: onSubmitted,
      onTap: onTap,
      enabled: enabled,
      showClearButton: showClearButton,
    );
  }
}

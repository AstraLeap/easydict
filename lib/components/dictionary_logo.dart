import 'package:flutter/material.dart';
import 'dart:io';
import '../services/dictionary_manager.dart';

class DictionaryLogo extends StatefulWidget {
  final String dictionaryId;
  final String dictionaryName;
  final double size;

  const DictionaryLogo({
    super.key,
    required this.dictionaryId,
    required this.dictionaryName,
    this.size = 24,
  });

  @override
  State<DictionaryLogo> createState() => _DictionaryLogoState();
}

class _DictionaryLogoState extends State<DictionaryLogo> {
  static final Map<String, String?> _logoPathCache = {};
  String? _logoPath;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _loadLogoPath();
  }

  @override
  void didUpdateWidget(DictionaryLogo oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.dictionaryId != widget.dictionaryId) {
      _loadLogoPath();
    }
  }

  Future<void> _loadLogoPath() async {
    if (_logoPathCache.containsKey(widget.dictionaryId)) {
      if (mounted) {
        setState(() {
          _logoPath = _logoPathCache[widget.dictionaryId];
          _loaded = true;
        });
      }
      return;
    }

    final logoPath = await DictionaryManager().getLogoPath(widget.dictionaryId);
    _logoPathCache[widget.dictionaryId] = logoPath;

    if (mounted) {
      setState(() {
        _logoPath = logoPath;
        _loaded = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loaded && _logoPath != null) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(4),
        child: Image.file(
          File(_logoPath!),
          width: widget.size,
          height: widget.size,
          fit: BoxFit.cover,
          errorBuilder: (context, error, stackTrace) =>
              _buildFallback(context),
        ),
      );
    }
    return _buildFallback(context);
  }

  Widget _buildFallback(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      width: widget.size,
      height: widget.size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: colorScheme.primaryContainer,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        widget.dictionaryName.isNotEmpty
            ? widget.dictionaryName[0].toUpperCase()
            : '?',
        style: TextStyle(
          fontSize: widget.size * 0.6,
          fontWeight: FontWeight.bold,
          color: colorScheme.onPrimaryContainer,
        ),
      ),
    );
  }
}

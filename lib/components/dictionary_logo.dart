import 'package:flutter/material.dart';
import 'dart:io';
import '../services/dictionary_manager.dart';

class DictionaryLogo extends StatelessWidget {
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
  Widget build(BuildContext context) {
    return FutureBuilder<String?>(
      future: DictionaryManager().getLogoPath(dictionaryId),
      builder: (context, snapshot) {
        if (snapshot.hasData && snapshot.data != null) {
          return ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: Image.file(
              File(snapshot.data!),
              width: size,
              height: size,
              fit: BoxFit.cover,
              errorBuilder: (context, error, stackTrace) =>
                  _buildFallback(context),
            ),
          );
        }
        return _buildFallback(context);
      },
    );
  }

  Widget _buildFallback(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: colorScheme.primaryContainer,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        dictionaryName.isNotEmpty ? dictionaryName[0].toUpperCase() : '?',
        style: TextStyle(
          fontSize: size * 0.6,
          fontWeight: FontWeight.bold,
          color: colorScheme.onPrimaryContainer,
        ),
      ),
    );
  }
}

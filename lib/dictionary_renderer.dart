import 'package:flutter/material.dart';
import 'database_service.dart';
import 'component_renderer.dart';

abstract class DictionaryRenderer {
  Widget render(BuildContext context, DictionaryEntry entry);
}

class SimpleRenderer implements DictionaryRenderer {
  const SimpleRenderer();

  @override
  Widget render(BuildContext context, DictionaryEntry entry) {
    return ComponentRenderer(entry: entry);
  }
}

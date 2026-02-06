import 'package:flutter/material.dart';
import 'dictionary_manager_page.dart';
import 'llm_config_page.dart';

/// 词典类目页面 - 包含词典管理和大语言模型设置
class DictionaryCategoryPage extends StatefulWidget {
  const DictionaryCategoryPage({super.key});

  @override
  State<DictionaryCategoryPage> createState() => _DictionaryCategoryPageState();
}

class _DictionaryCategoryPageState extends State<DictionaryCategoryPage> {
  int _selectedIndex = 0;

  final List<Widget> _pages = const [DictionaryManagerPage(), LLMConfigPage()];

  final List<NavigationDestination> _destinations = const [
    NavigationDestination(
      icon: Icon(Icons.folder_outlined),
      selectedIcon: Icon(Icons.folder),
      label: '词典管理',
    ),
    NavigationDestination(
      icon: Icon(Icons.smart_toy_outlined),
      selectedIcon: Icon(Icons.smart_toy),
      label: '大语言模型',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _pages[_selectedIndex],
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedIndex,
        onDestinationSelected: (int index) {
          setState(() {
            _selectedIndex = index;
          });
        },
        destinations: _destinations,
      ),
    );
  }
}

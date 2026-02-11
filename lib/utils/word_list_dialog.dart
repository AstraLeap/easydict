import 'package:flutter/material.dart';
import '../word_bank_service.dart';

class WordListDialog {
  static Future<List<String>?> show(
    BuildContext context, {
    required String language,
    required String word,
    bool isNewWord = false,
    required WordBankService wordBankService,
  }) async {
    var wordLists = await wordBankService.getWordLists(language);
    final membership = await wordBankService.getWordMembership(word, language);

    final Set<String> selectedLists = {};
    if (membership != null) {
      membership.lists.forEach((listName, value) {
        if (value == 1) selectedLists.add(listName);
      });
    }

    return await showDialog<List<String>>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return Dialog(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 400),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        isNewWord ? '选择词表' : '调整 "$word" 的词表',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(height: 16),
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxHeight: 300),
                        child: ListView.builder(
                          shrinkWrap: true,
                          itemCount: wordLists.length,
                          itemBuilder: (context, index) {
                            final list = wordLists[index];
                            final isSelected = selectedLists.contains(
                              list.name,
                            );
                            return CheckboxListTile(
                              title: Text(list.displayName),
                              value: isSelected,
                              controlAffinity: ListTileControlAffinity.trailing,
                              contentPadding: const EdgeInsets.only(
                                left: 4,
                                right: 4,
                              ),
                              onChanged: (value) {
                                setState(() {
                                  if (value == true) {
                                    selectedLists.add(list.name);
                                  } else {
                                    selectedLists.remove(list.name);
                                  }
                                });
                              },
                            );
                          },
                        ),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              decoration: const InputDecoration(
                                hintText: '输入新词表名称',
                                contentPadding: EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 8,
                                ),
                              ),
                              onSubmitted: (value) async {
                                final newListName = value.trim();
                                if (newListName.isNotEmpty) {
                                  try {
                                    await wordBankService.addWordList(
                                      language,
                                      newListName,
                                    );
                                    // 重新获取词表列表
                                    final newLists = await wordBankService
                                        .getWordLists(language);
                                    setState(() {
                                      wordLists = newLists;
                                      selectedLists.add(newListName);
                                    });
                                  } catch (e) {
                                    // 词表已存在，直接添加
                                    if (e.toString().contains('已存在')) {
                                      setState(() {
                                        selectedLists.add(newListName);
                                      });
                                    }
                                  }
                                }
                              },
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 24),
                      Row(
                        children: [
                          if (!isNewWord)
                            TextButton.icon(
                              onPressed: () =>
                                  Navigator.pop(context, ['__REMOVE__']),
                              style: TextButton.styleFrom(
                                foregroundColor: Theme.of(
                                  context,
                                ).colorScheme.error,
                              ),
                              icon: const Icon(Icons.delete_outline),
                              label: const Text('移除单词'),
                            )
                          else
                            const SizedBox.shrink(),
                          const Spacer(),
                          TextButton(
                            onPressed: () => Navigator.pop(context, null),
                            child: const Text('取消'),
                          ),
                          const SizedBox(width: 8),
                          TextButton(
                            onPressed: selectedLists.isEmpty
                                ? null
                                : () => Navigator.pop(
                                    context,
                                    selectedLists.toList(),
                                  ),
                            child: const Text('确定'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  static Future<String?> _showAddNewListDialog(
    BuildContext context,
    String language,
    WordBankService wordBankService,
  ) async {
    final controller = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('新增词表'),
          content: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 300),
            child: TextField(
              controller: controller,
              decoration: const InputDecoration(
                labelText: '词表名称',
                hintText: '例如：GRE、雅思',
              ),
              autofocus: true,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('取消'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, controller.text.trim()),
              child: const Text('确定'),
            ),
          ],
        );
      },
    );
    controller.dispose();
    return result;
  }
}

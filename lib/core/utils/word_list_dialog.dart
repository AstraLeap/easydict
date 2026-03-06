import 'package:flutter/material.dart';
import '../../data/word_bank_service.dart';
import '../../i18n/strings.g.dart';

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
                        isNewWord ? context.t.wordBank.selectLists : context.t.wordBank.adjustLists(word: word),
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
                              decoration: InputDecoration(
                                hintText: context.t.wordBank.newListHint,
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
                              label: Text(context.t.wordBank.removeWord),
                            )
                          else
                            const SizedBox.shrink(),
                          const Spacer(),
                          TextButton(
                            onPressed: () => Navigator.pop(context, null),
                            child: Text(context.t.common.cancel),
                          ),
                          const SizedBox(width: 8),
                          TextButton(
                            onPressed: selectedLists.isEmpty
                                ? null
                                : () => Navigator.pop(
                                    context,
                                    selectedLists.toList(),
                                  ),
                            child: Text(context.t.common.ok),
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
}

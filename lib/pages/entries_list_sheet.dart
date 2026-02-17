import 'package:flutter/material.dart';
import 'entry_detail_page.dart';
import '../services/dictionary_manager.dart';
import '../services/font_loader_service.dart';
import '../data/models/dictionary_entry_group.dart';
import '../data/database_service.dart';
import '../components/scale_layout_wrapper.dart';
import '../components/global_scale_wrapper.dart';

class EntriesListSheet extends StatefulWidget {
  final String dictId;

  const EntriesListSheet({super.key, required this.dictId});

  @override
  State<EntriesListSheet> createState() => _EntriesListSheetState();
}

class _EntriesListSheetState extends State<EntriesListSheet> {
  final double _contentScale = FontLoaderService().getDictionaryContentScale();
  final TextEditingController searchController = TextEditingController();
  final ScrollController scrollController = ScrollController();
  final DictionaryManager dictManager = DictionaryManager();

  List<String> entries = [];
  List<String> filteredEntries = [];
  bool isLoading = true;
  int offset = 0;
  static const int limit = 50;
  bool hasMore = true;
  String searchQuery = '';

  @override
  void initState() {
    super.initState();
    loadEntries();
    scrollController.addListener(onScroll);
  }

  @override
  void dispose() {
    searchController.dispose();
    scrollController.dispose();
    super.dispose();
  }

  Future<void> loadEntries() async {
    if (isLoading && !hasMore) return;

    setState(() {
      isLoading = true;
    });

    try {
      final newEntries = await dictManager.getDictionaryEntries(
        widget.dictId,
        offset: offset,
        limit: limit,
      );

      if (newEntries.isEmpty) {
        setState(() {
          hasMore = false;
          isLoading = false;
        });
      } else {
        setState(() {
          entries = [...entries, ...newEntries];
          filteredEntries = filterEntries(searchQuery);
          offset += limit;
          isLoading = false;
        });
      }
    } catch (e) {
      setState(() {
        isLoading = false;
      });
    }
  }

  List<String> filterEntries(String query) {
    if (query.isEmpty) return entries;
    return entries
        .where((entry) => entry.toLowerCase().contains(query.toLowerCase()))
        .toList();
  }

  void onScroll() {
    if (scrollController.position.pixels >=
        scrollController.position.maxScrollExtent - 200) {
      if (!isLoading && hasMore) {
        loadEntries();
      }
    }
  }

  void onSearchChanged(String value) {
    setState(() {
      searchQuery = value;
      filteredEntries = filterEntries(value);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.8,
      decoration: BoxDecoration(
        color: Theme.of(context).scaffoldBackgroundColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
      ),
      child: PageScaleWrapper(
        scale: _contentScale,
        child: Column(
          children: [
            buildHeader(),
            Expanded(child: buildEntryList()),
          ],
        ),
      ),
    );
  }

  Widget buildHeader() {
    return Column(
      children: [
        const SizedBox(height: 12),
        Container(
          width: 40,
          height: 4,
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.outline,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(height: 16),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: TextField(
            controller: searchController,
            onChanged: onSearchChanged,
            decoration: InputDecoration(
              hintText: '搜索词条...',
              prefixIcon: const Icon(Icons.search),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
      ],
    );
  }

  Widget buildEntryList() {
    if (entries.isEmpty && !isLoading) {
      return const Center(child: Text('暂无词条'));
    }

    return ListView.builder(
      controller: scrollController,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      itemCount: filteredEntries.length + (hasMore ? 1 : 0),
      itemBuilder: (context, index) {
        if (index >= filteredEntries.length) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: CircularProgressIndicator(),
            ),
          );
        }

        final entry = filteredEntries[index];
        return ListTile(
          title: Text(entry),
          onTap: () {
            Navigator.of(context).pop();
            openEntryDetail(entry);
          },
        );
      },
    );
  }

  void openEntryDetail(String headword) async {
    final dbService = DatabaseService();
    final entry = await dbService.getEntry(headword);

    if (!mounted) return;

    if (entry != null) {
      final entryGroup = DictionaryEntryGroup.groupEntries([entry]);

      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (context) =>
              EntryDetailPage(entryGroup: entryGroup, initialWord: headword),
        ),
      );
    }
  }
}

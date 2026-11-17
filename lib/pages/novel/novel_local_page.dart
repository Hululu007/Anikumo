import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_modular/flutter_modular.dart';

import '../../bean/dialog/dialog.dart';
import '../../bean/widget/anikumo_icons.dart';
import 'package:anikumo/services/i18n/app_strings.dart';
import '../../models/novel_item.dart';
import '../../services/novel/local_books.dart';

/// Batch 158: the local bookshelf (feature repository's
/// 本地书籍）. Import EPUB / TXT files, open them through
/// the normal detail → reader flow, or remove them.
class NovelLocalPage extends StatefulWidget {
  const NovelLocalPage({super.key});

  @override
  State<NovelLocalPage> createState() => _NovelLocalPageState();
}

class _NovelLocalPageState extends State<NovelLocalPage> {
  List<LocalBook> _books = const [];
  Map<String, NovelItem> _items = const {};
  bool _importing = false;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    final books = LocalBookStore.books();
    const source = LocalNovelSource();
    final items = await source.explore(
      const NovelExploreCategory(title: '本地书架', url: LocalNovelSource.shelfUrl),
    );
    if (!mounted) return;
    setState(() {
      _books = books;
      _items = {
        for (final item in items)
          item.bookUrl.substring('local://book/'.length): item,
      };
    });
  }

  Future<void> _import() async {
    if (_importing) return;
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['epub', 'txt'],
      allowMultiple: true,
      withData: true,
    );
    if (result == null || result.files.isEmpty) return;
    setState(() => _importing = true);
    var added = 0;
    var duplicates = 0;
    final failures = <String>[];
    for (final file in result.files) {
      final bytes = file.bytes;
      if (bytes == null) {
        failures.add(S.f('{}：读不到文件内容', [file.name]));
        continue;
      }
      try {
        final book = await LocalBookStore.importBytes(file.name, bytes);
        if (book == null) {
          duplicates++;
        } else {
          added++;
        }
      } catch (e) {
        failures.add(S.f('{}：{}', [file.name, e]));
      }
    }
    if (!mounted) return;
    setState(() => _importing = false);
    await _reload();
    if (!mounted) return;
    final parts = <String>[
      if (added > 0) S.f('导入了 {} 本', [added]),
      if (duplicates > 0) S.f('{} 本已在书架中', [duplicates]),
      if (failures.isNotEmpty) S.f('{} 本失败', [failures.length]),
    ];
    AnikumoDialog.showToast(
      message: parts.isEmpty ? S.t('没有导入任何书籍') : parts.join(S.t('，')),
    );
    if (failures.isNotEmpty) {
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(S.t('部分文件导入失败')),
          content: Text(failures.join('\n')),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(S.t('知道了')),
            ),
          ],
        ),
      );
    }
  }

  Future<void> _remove(LocalBook book) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(S.f('删除《{}》？', [book.title])),
        content: Text(S.t('本地文件和阅读记录会一并删除。')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(S.t('取消')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(S.t('删除')),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await LocalBookStore.remove(book.id);
    await _reload();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(S.t('本地书架')),
        actions: [
          IconButton(
            onPressed: _importing ? null : _import,
            icon: const Icon(AnikumoIcons.upload_file_outlined),
            tooltip: S.t('导入书籍'),
          ),
        ],
      ),
      body: _books.isEmpty
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(AnikumoIcons.library_books_outlined, size: 44),
                  const SizedBox(height: 12),
                  Text(S.t('书架还是空的')),
                  const SizedBox(height: 4),
                  Text(
                    S.t('导入 EPUB / TXT 文件后，就能离线阅读'),
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.outline,
                        ),
                  ),
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    onPressed: _importing ? null : _import,
                    icon: const Icon(AnikumoIcons.upload_file_outlined, size: 18),
                    label: Text(S.t('导入书籍')),
                  ),
                ],
              ),
            )
          : ListView.builder(
              itemCount: _books.length,
              itemBuilder: (context, index) {
                final book = _books[index];
                final item = _items[book.id];
                return ListTile(
                  leading: const Icon(AnikumoIcons.library_books_rounded),
                  title: Text(
                    book.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: Text(
                    [
                      if (book.author.isNotEmpty) book.author,
                      book.format.toUpperCase(),
                      S.f('{} 章', [book.chapterCount]),
                    ].join(' · '),
                  ),
                  trailing: IconButton(
                    icon: const Icon(AnikumoIcons.delete_outline, size: 20),
                    onPressed: () => _remove(book),
                  ),
                  onTap: item == null
                      ? null
                      : () => context.pushNamed(
                            '/novel/detail',
                            arguments: item,
                          ),
                );
              },
            ),
    );
  }
}

import 'package:anikumo/services/i18n/app_strings.dart';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:anikumo/bean/dialog/dialog.dart';
import 'package:anikumo/bean/widget/github_file_picker.dart';
import 'package:anikumo/pages/manga/manga_widgets.dart';
import 'package:anikumo/pages/manga/manga_source_settings_panel.dart';
import 'package:anikumo/pages/manga/manga_source_update_prompt.dart';
import 'package:anikumo/services/manga/js/js_manga_source.dart';
import 'package:anikumo/services/manga/local_manga_source.dart';
import 'package:anikumo/services/manga/manga_sources.dart';
import 'package:anikumo/utils/constants.dart';
import 'package:anikumo/utils/error_message.dart';
import 'package:anikumo/utils/github_links.dart';
import 'package:anikumo/bean/widget/anikumo_icons.dart';

/// 漫画源管理 — every source the zone can read from: built-in
/// native sources and the user's downloaded Venera JS sources.
/// Picking a source switches all browsing (home / explore /
/// search) to it; favorites and progress stay per-source.
class MangaSourcesPage extends StatefulWidget {
  const MangaSourcesPage({super.key});

  @override
  State<MangaSourcesPage> createState() => _MangaSourcesPageState();
}

class _MangaSourcesPageState extends State<MangaSourcesPage> {
  bool _importing = false;

  // Batch 159: batch-delete selection mode.
  bool _selecting = false;

  /// Batch 191: the JS source whose settings panel is
  /// expanded under its row (tap toggles).
  String? _expandedId;
  final Set<String> _selected = {};

  @override
  void initState() {
    super.initState();
    // Batch 102: the local book list backs the 本地漫画
    // section below; load it once per process.
    LocalMangaLibrary.ensureLoaded().then((changed) {
      if (!mounted) return;
      if (changed) MangaSources.notifyRegistryChanged();
      setState(() {});
    });
  }

  /// Batch 102: import one CBZ / ZIP book into the local
  /// library (pages are extracted to app storage, so the
  /// book reads fully offline afterwards).
  Future<void> _importLocalBook() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['cbz', 'zip'],
    );
    final path = result?.files.single.path;
    if (path == null) return;
    setState(() => _importing = true);
    try {
      final book = await LocalMangaLibrary.importArchive(path);
      MangaSources.notifyRegistryChanged();
      AnikumoDialog.showToast(message: S.f('已导入《{}》（{} 页）', [book.title, book.pages]));
    } on FormatException catch (e) {
      AnikumoDialog.showToast(message: e.message);
    } catch (_) {
      AnikumoDialog.showToast(message: S.t('导入失败，文件可能已损坏'));
    } finally {
      if (mounted) setState(() => _importing = false);
    }
  }

  Future<void> _deleteLocalBook(LocalBook book) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(S.t('删除本地漫画')),
        content: Text(S.f('确定要删除《{}》吗？本地文件会被删掉；收藏与进度会保留，但无法再打开这本书。', [book.title])),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(S.t('取消')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(S.t('删除')),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await LocalMangaLibrary.deleteBook(book.id);
    MangaSources.notifyRegistryChanged();
    AnikumoDialog.showToast(message: S.f('已删除《{}》', [book.title]));
    if (mounted) setState(() {});
  }

  /// Batch 45: the three custom-import channels all end in
  /// MangaSources.installCustomJs — only the way the code
  /// text is obtained differs.
  Future<void> _installCode(
    String code, {
    String fileName = '',
    String? origin,
  }) async {
    setState(() => _importing = true);
    try {
      // Batch 88: a pasted/opened payload may be a source
      // *index* — it holds links, not source code, so it can
      // only be imported by URL. Say so instead of failing
      // with the single-source parser's error.
      if (MangaSources.parseVeneraIndex(code) != null) {
        throw FormatException(
          S.t('这是源索引文件（内含多个源的链接），请改用「从 URL 导入」粘贴它的链接导入'),
        );
      }
      // Batch 67: the payload may be a Legado book-source
      // pack (its manga entries are type-2 sources) rather
      // than a Venera JS source — route it to the Legado
      // registry, whose type-2 sources this zone adapts.
      final pack = await MangaSources.importLegadoPackIfAny(code);
      if (pack != null) {
        if (!mounted) return;
        AnikumoDialog.showToast(
          message: pack.added > 0
              ? S.f('已导入 {} 个书源', [pack.added]) +
                  (pack.mangaCount > 0
                      ? S.t('，已可在本区使用')
                      : S.t('（不含漫画类，可在小说区使用）'))
              : S.t('没有新的书源（都已存在）'),
        );
        setState(() {});
        return;
      }
      final meta = await MangaSources.installCustomJs(
        code,
        fileName: fileName,
        origin: origin,
      );
      if (!mounted) return;
      AnikumoDialog.showToast(message: S.f('已导入源「{}」v{}', [meta.name, meta.version]));
      setState(() {});
    } on FormatException catch (e) {
      if (!mounted) return;
      AnikumoDialog.showToast(message: S.f('导入失败：{}', [e.message]));
    } catch (e) {
      if (!mounted) return;
      AnikumoDialog.showToast(message: S.f('导入失败：{}', [friendlyError(e)]));
    } finally {
      if (mounted) setState(() => _importing = false);
    }
  }

  Future<void> _importFromUrl() async {
    final controller = TextEditingController();
    final url = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(S.t('从 URL 导入漫画源')),
        content: TextField(
          controller: controller,
          decoration: InputDecoration(
            hintText: S.t('https://…/source.js，或 GitHub 仓库/文件链接'),
          ),
          keyboardType: TextInputType.url,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text(S.t('取消')),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.pop(dialogContext, controller.text.trim()),
            child: Text(S.t('下载并导入')),
          ),
        ],
      ),
    );
    if (url == null || url.isEmpty || !mounted) return;
    // Batch 63: a GitHub *repository* address opens the
    // file picker (batch import of its .js sources); a
    // GitHub *file page* address is rewritten to raw.
    final repoRef = GithubLinks.parseRepo(url);
    if (repoRef != null) {
      await _importFromGithubRepo(repoRef);
      return;
    }
    await _downloadAndInstall(GithubLinks.rawFileUrl(url) ?? url);
  }

  Future<void> _downloadAndInstall(String url) async {
    setState(() => _importing = true);
    try {
      final response = await Dio().get<String>(
        url,
        options: Options(
          responseType: ResponseType.plain,
          connectTimeout: const Duration(seconds: 15),
          receiveTimeout: const Duration(seconds: 30),
        ),
      );
      final code = response.data ?? '';
      if (code.trim().isEmpty) {
        throw FormatException(S.t('下载到的文件是空的'));
      }
      // Batch 88: the URL may point at a source *index* (a
      // JSON list of .js files, e.g. a CDN mirror of the
      // community configs repo) rather than at one source
      // file — resolve and install every entry it lists.
      final index = MangaSources.parseVeneraIndex(code);
      if (index != null) {
        // Batch 190: remember this repository so the
        // update checker can watch it for new versions.
        await MangaSources.addSourceRepository(url);
        await _importFromVeneraIndex(url, index);
        return;
      }
      await _installCode(code, fileName: url.split('/').last, origin: url);
    } on FormatException catch (e) {
      if (mounted) {
        AnikumoDialog.showToast(message: S.f('导入失败：{}', [e.message]));
      }
    } catch (_) {
      if (mounted) {
        AnikumoDialog.showToast(message: S.t('导入失败：无法下载该文件，请检查链接'));
      }
    } finally {
      if (mounted) setState(() => _importing = false);
    }
  }

  /// Batch 88: install every source a Venera index lists.
  /// Each entry's fileName resolves against the index URL
  /// (an entry may also be an absolute URL). Downloads run
  /// four at a time; each file goes through the same
  /// validated installer as a single-source import, and
  /// the toast reports the real success/failure counts.
  Future<void> _importFromVeneraIndex(
    String indexUrl,
    List<VeneraIndexEntry> entries,
  ) async {
    final base = Uri.parse(indexUrl);
    var installed = 0;
    var failed = 0;
    for (var start = 0; start < entries.length; start += 4) {
      final chunk = entries.skip(start).take(4).toList();
      await Future.wait(chunk.map((entry) async {
        try {
          final fileUrl = base.resolve(entry.fileName).toString();
          final response = await Dio().get<String>(
            fileUrl,
            options: Options(
              responseType: ResponseType.plain,
              connectTimeout: const Duration(seconds: 15),
              receiveTimeout: const Duration(seconds: 30),
            ),
          );
          final code = response.data ?? '';
          if (code.trim().isEmpty) {
            throw FormatException(S.t('下载到的文件是空的'));
          }
          await MangaSources.installCustomJs(
            code,
            fileName: entry.fileName.split('/').last,
            origin: fileUrl,
          );
          installed++;
        } catch (_) {
          failed++;
        }
      }));
    }
    if (!mounted) return;
    setState(() {});
    AnikumoDialog.showToast(
      message: S.f('已从索引导入 {} 个漫画源', [installed]) +
          (failed > 0 ? S.f('，{} 个导入失败', [failed]) : ''),
    );
  }

  /// Batch 63: list the repo directory's .js files and
  /// install the ones the user checks.
  Future<void> _importFromGithubRepo(GithubRepoRef ref) async {
    setState(() => _importing = true);
    try {
      final files = await GithubLinks.listFiles(ref);
      final candidates = [
        for (final f in files)
          if (f.name.toLowerCase().endsWith('.js')) f,
      ];
      if (!mounted) return;
      setState(() => _importing = false);
      if (candidates.isEmpty) {
        AnikumoDialog.showToast(
          message: S.t('这个仓库目录里没有 .js 漫画源文件'),
        );
        return;
      }
      final picked = await showGithubFilePicker(
        context,
        title: S.t('从 GitHub 仓库导入漫画源'),
        files: candidates,
      );
      if (picked == null || picked.isEmpty || !mounted) return;
      setState(() => _importing = true);
      var installed = 0;
      var failed = 0;
      for (final file in picked) {
        try {
          final response = await Dio().get<String>(
            file.downloadUrl,
            options: Options(
              responseType: ResponseType.plain,
              connectTimeout: const Duration(seconds: 15),
              receiveTimeout: const Duration(seconds: 30),
            ),
          );
          final code = response.data ?? '';
          if (code.trim().isEmpty) {
            throw FormatException(S.t('下载到的文件是空的'));
          }
          await MangaSources.installCustomJs(
            code,
            fileName: file.name,
            origin: file.downloadUrl,
          );
          installed++;
        } catch (_) {
          failed++;
        }
      }
      if (!mounted) return;
      setState(() {});
      AnikumoDialog.showToast(
        message: S.f('已导入 {} 个漫画源', [installed]) +
            (failed > 0 ? S.f('，{} 个文件导入失败', [failed]) : ''),
      );
    } catch (e) {
      if (mounted) {
        AnikumoDialog.showToast(message: S.f('导入失败：{}', [friendlyError(e)]));
      }
    } finally {
      if (mounted) setState(() => _importing = false);
    }
  }

  Future<void> _importFromPaste() async {
    final controller = TextEditingController();
    final code = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(S.t('粘贴 JS 源代码')),
        content: SizedBox(
          width: double.maxFinite,
          child: TextField(
            controller: controller,
            maxLines: 12,
            decoration: InputDecoration(
              hintText: S.t('粘贴完整的 JS 源代码（class … extends ComicSource）'),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text(S.t('取消')),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.pop(dialogContext, controller.text),
            child: Text(S.t('导入')),
          ),
        ],
      ),
    );
    if (code == null || code.trim().isEmpty || !mounted) return;
    await _installCode(code);
  }

  Future<void> _importFromFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['js', 'txt'],
      withData: true,
    );
    if (result == null || result.files.isEmpty || !mounted) return;
    final file = result.files.first;
    final bytes = file.bytes;
    if (bytes == null) {
      AnikumoDialog.showToast(message: S.t('导入失败：读不到该文件'));
      return;
    }
    await _installCode(utf8.decode(bytes), fileName: file.name);
  }

  Future<void> _showImportSheet() async {
    final channel = await showModalBottomSheet<String>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(AnikumoIcons.link),
              title: Text(S.t('从 URL 导入')),
              subtitle: Text(S.t('粘贴 .js 直链或 GitHub 链接，下载后安装')),
              onTap: () => Navigator.pop(sheetContext, 'url'),
            ),
            ListTile(
              leading: const Icon(AnikumoIcons.content_paste),
              title: Text(S.t('粘贴 JS 代码')),
              subtitle: Text(S.t('把整段源代码粘进来')),
              onTap: () => Navigator.pop(sheetContext, 'paste'),
            ),
            ListTile(
              leading: const Icon(AnikumoIcons.folder_open_outlined),
              title: Text(S.t('从本地文件导入')),
              subtitle: Text(S.t('选择一个 .js 源文件')),
              onTap: () => Navigator.pop(sheetContext, 'file'),
            ),
          ],
        ),
      ),
    );
    if (!mounted) return;
    switch (channel) {
      case 'url':
        await _importFromUrl();
      case 'paste':
        await _importFromPaste();
      case 'file':
        await _importFromFile();
    }
  }

  Future<void> _activate(String id) async {
    await MangaSources.setActive(id);
    if (mounted) setState(() {});
  }

  void _toggleSelected(String id) {
    setState(() {
      if (!_selected.remove(id)) _selected.add(id);
    });
  }

  Future<void> _deleteSelected(Set<String> ids) async {
    if (ids.isEmpty) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(S.t('删除来源')),
        content: Text(S.f('确定要删除选中的 {} 个源吗？收藏与进度会保留，但无法再打开这些源的内容。', [ids.length])),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(S.t('取消')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(S.t('删除')),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    final removed = await MangaSources.removeInstalledBatch(ids);
    if (!mounted) return;
    setState(() {
      _selected.clear();
      _selecting = false;
    });
    AnikumoDialog.showToast(message: S.f('已删除 {} 个源', [removed]));
  }

  Future<void> _deleteAll(Set<String> ids) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(S.t('全部删除')),
        content: Text(S.f('确定要删除全部 {} 个已导入源吗？收藏与进度会保留，但无法再打开这些源的内容。', [ids.length])),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(S.t('取消')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(S.t('全部删除')),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    final removed = await MangaSources.removeInstalledBatch(ids);
    if (!mounted) return;
    setState(() {
      _selected.clear();
      _selecting = false;
    });
    AnikumoDialog.showToast(message: S.f('已删除 {} 个源', [removed]));
  }

  Future<void> _remove(String id, String name) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(S.t('删除来源')),
        content: Text(S.f('确定要删除下载源「{}」吗？它的收藏与进度会保留在本地，但无法再打开。', [name])),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(S.t('取消')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(S.t('删除')),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await MangaSources.removeInstalled(id);
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // Batch 47: pinned sources lead the list.
    final sources = MangaSources.sortForDisplay(MangaSources.all());
    // Batch 62: was MangaSources.active() — with zero
    // sources installed that throws inside build(), which
    // in release mode is the pure-grey screen users hit on
    // exactly this "add a source" page. Use the nullable
    // form; no active source just means nothing is checked.
    final activeId = MangaSources.activeOrNull()?.id;
    // Batch 159: everything except the local-library
    // facade can be batch-deleted.
    final deletableIds = {
      for (final s in sources)
        if (s.id != LocalMangaSource.sourceId) s.id,
    };
    final effectiveSelected = _selected.intersection(deletableIds);
    return Scaffold(
      appBar: AppBar(
        title: Text(_selecting ? S.f('已选 {} 个', [effectiveSelected.length]) : S.t('漫画源管理')),
        actions: [
          if (_selecting) ...[
            TextButton(
              onPressed: () =>
                  setState(() => _selected.addAll(deletableIds)),
              child: Text(S.t('全选')),
            ),
            TextButton(
              onPressed: effectiveSelected.isEmpty
                  ? null
                  : () => _deleteSelected(effectiveSelected),
              child: Text(
                S.t('删除'),
                style: TextStyle(color: theme.colorScheme.error),
              ),
            ),
            IconButton(
              tooltip: S.t('完成'),
              icon: const Icon(AnikumoIcons.close),
              onPressed: () => setState(() {
                _selecting = false;
                _selected.clear();
              }),
            ),
          ] else ...[
            if (deletableIds.isNotEmpty)
              IconButton(
                tooltip: S.t('批量删除'),
                icon: const Icon(AnikumoIcons.delete_sweep_outlined),
                onPressed: () => setState(() => _selecting = true),
              ),
            IconButton(
              tooltip: S.t('检查更新'),
              icon: const Icon(AnikumoIcons.cloud_sync_rounded),
              onPressed: () =>
                  MangaSourceUpdatePrompt.run(context, force: true),
            ),
            IconButton(
              tooltip: S.t('源诊断'),
              icon: const Icon(AnikumoIcons.fact_check_outlined),
              onPressed: () => context.pushNamed('/manga/diagnostics'),
            ),
          ],
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: StyleString.sectionSpace),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Text(
              S.t('当前源决定首页、探索与搜索的内容；详情与阅读始终回到每部漫画自己的源。'),
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          for (final source in sources) ...[
            ListTile(
              leading: _selecting &&
                      source.id != LocalMangaSource.sourceId
                  ? Checkbox(
                      value: _selected.contains(source.id),
                      onChanged: (_) => _toggleSelected(source.id),
                    )
                  : Icon(
                      source.id == activeId
                          ? AnikumoIcons.radio_button_checked
                          : AnikumoIcons.radio_button_unchecked,
                      color: source.id == activeId
                          ? theme.colorScheme.primary
                          : theme.colorScheme.onSurfaceVariant,
                    ),
              title: Row(
                children: [
                  Flexible(child: Text(source.name)),
                  if (MangaSources.isPinned(source.id)) ...[
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.primaryContainer,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        S.t('置顶'),
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: theme.colorScheme.onPrimaryContainer,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
              subtitle: Text(S.f('{} · 已导入', [source.description])),
              trailing: _selecting
                  ? null
                  : Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (source is JsBackedMangaSource)
                    IconButton(
                      tooltip: S.t('源账号登录'),
                      icon: const Icon(AnikumoIcons.account_circle_outlined),
                      onPressed: () => context.pushNamed(
                        '/manga/login',
                        arguments: source.id,
                      ),
                    ),
                  if (source is JsBackedMangaSource)
                    IconButton(
                      tooltip: S.t('源站网页登录'),
                      icon: const Icon(AnikumoIcons.language_rounded),
                      onPressed: () => context.pushNamed(
                        '/manga/web-login',
                        arguments: source.id,
                      ),
                    ),
                  IconButton(
                    tooltip: MangaSources.isPinned(source.id)
                        ? S.t('取消置顶')
                        : S.t('置顶这个源'),
                    icon: Icon(
                      MangaSources.isPinned(source.id)
                          ? AnikumoIcons.push_pin
                          : AnikumoIcons.push_pin_outlined,
                      color: MangaSources.isPinned(source.id)
                          ? theme.colorScheme.primary
                          : null,
                    ),
                    onPressed: () async {
                      await MangaSources.togglePin(source.id);
                      if (mounted) setState(() {});
                    },
                  ),
                  if (source.id == activeId)
                    Chip(label: Text(S.t('使用中')))
                  else if (source.id != LocalMangaSource.sourceId)
                    IconButton(
                      icon: const Icon(AnikumoIcons.delete_outline),
                      tooltip: S.t('删除'),
                      onPressed: () => _remove(source.id, source.name),
                    ),
                  if (source is JsBackedMangaSource)
                    Icon(
                      _expandedId == source.id
                          ? AnikumoIcons.expand_less_rounded
                          : AnikumoIcons.expand_more,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                ],
              ),
              onTap: _selecting
                  ? (source.id == LocalMangaSource.sourceId
                      ? null
                      : () => _toggleSelected(source.id))
                  : () {
                      // Batch 191: tapping a JS source
                      // expands its settings panel in
                      // place; other sources keep the
                      // tap-to-activate behavior.
                      if (source is JsBackedMangaSource) {
                        setState(() {
                          _expandedId = _expandedId == source.id
                              ? null
                              : source.id;
                        });
                      } else {
                        _activate(source.id);
                      }
                    },
            ),
            if (_expandedId == source.id &&
                source is JsBackedMangaSource &&
                !_selecting)
              MangaSourceSettingsPanel(
                key: ValueKey('source-settings:${source.id}'),
                source: source,
                isActive: source.id == activeId,
                onActivate: () => _activate(source.id),
              ),
          ],
          if (!_selecting && deletableIds.isNotEmpty)
            ListTile(
              leading: Icon(
                AnikumoIcons.delete_outline,
                color: theme.colorScheme.error,
              ),
              title: Text(
                S.t('全部删除'),
                style: TextStyle(color: theme.colorScheme.error),
              ),
              subtitle: Text(S.f('删除全部 {} 个已导入源', [deletableIds.length])),
              onTap: () => _deleteAll(deletableIds),
            ),
          const Divider(),
          ListTile(
            leading: const Icon(AnikumoIcons.file_download_outlined),
            title: Text(S.t('导入自定义源')),
            subtitle: Text(S.t('从 URL、粘贴代码或本地文件导入')),
            trailing: _importing
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(AnikumoIcons.chevron_right),
            onTap: _importing ? null : _showImportSheet,
          ),
          const Divider(),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: Text(
              S.t('本地漫画'),
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          ListTile(
            leading: const Icon(AnikumoIcons.folder_zip_outlined),
            title: Text(S.t('导入本地漫画')),
            subtitle: Text(S.t('从 CBZ / ZIP 文件导入，导入后离线可读')),
            trailing: _importing
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(AnikumoIcons.chevron_right),
            onTap: _importing ? null : _importLocalBook,
          ),
          for (final book in LocalMangaLibrary.cachedBooks)
            ListTile(
              leading: MangaCover(
                url: Uri.file(book.coverPath).toString(),
                width: 40,
                height: 56,
                radius: 6,
              ),
              title: Text(book.title, maxLines: 1, overflow: TextOverflow.ellipsis),
              subtitle: Text(S.f('{} 页', [book.pages])),
              trailing: IconButton(
                icon: const Icon(AnikumoIcons.delete_outline),
                tooltip: S.t('删除这本书'),
                onPressed: () => _deleteLocalBook(book),
              ),
            ),
        ],
      ),
    );
  }
}

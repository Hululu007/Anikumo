import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:anikumo/bean/appbar/sys_app_bar.dart';
import 'package:anikumo/bean/card/bangumi_card.dart';
import 'package:anikumo/bean/dialog/dialog.dart';
import 'package:anikumo/bean/glass/glass_surface.dart';
import 'package:anikumo/bean/widget/empty_state_widget.dart';
import 'package:anikumo/bean/widget/state_presentation.dart';
import 'package:anikumo/modules/bangumi/bangumi_item.dart';
import 'package:anikumo/pages/discover/bangumi_picker.dart';
import 'package:anikumo/services/library/user_library.dart';
import 'package:anikumo/services/share/share_builders.dart';
import 'package:anikumo/utils/constants.dart';
import 'package:anikumo/bean/widget/anikumo_icons.dart';
import 'package:anikumo/services/i18n/app_strings.dart';

/// 我的榜单 (hub 区二）: user-created lists over their own collections
/// and history — e.g. 「本季度神作」「补番计划」 — stored locally as
/// settings JSON (see [UserListsStore]).
class MyListsPage extends StatefulWidget {
  const MyListsPage({super.key});

  @override
  State<MyListsPage> createState() => _MyListsPageState();
}

class _MyListsPageState extends State<MyListsPage> {
  List<UserList> _lists = [];

  @override
  void initState() {
    super.initState();
    _lists = UserListsStore.load();
  }

  Future<void> _createList() async {
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(S.t('新建榜单')),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 20,
          decoration: InputDecoration(hintText: S.t('比如：本季度神作')),
          onSubmitted: (value) => Navigator.of(context).pop(value),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(S.t('取消')),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(controller.text),
            child: Text(S.t('创建')),
          ),
        ],
      ),
    );
    controller.dispose();
    final trimmed = name?.trim() ?? '';
    if (trimmed.isEmpty || !mounted) return;
    setState(() {
      _lists = [
        ..._lists,
        UserList(
          id: DateTime.now().microsecondsSinceEpoch.toString(),
          name: trimmed,
        ),
      ];
    });
    await UserListsStore.save(_lists);
  }

  Future<void> _deleteList(UserList list) async {
    setState(() => _lists = _lists.where((e) => e.id != list.id).toList());
    await UserListsStore.save(_lists);
    if (mounted) {
      AnikumoDialog.showToast(context: context, message: S.f('已删除榜单「{}」', [list.name]));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: SysAppBar(
        title: Text(S.t('我的榜单')),
        actions: [
          IconButton(
            tooltip: S.t('新建榜单'),
            onPressed: _createList,
            icon: const Icon(AnikumoIcons.add),
          ),
        ],
      ),
      body: _lists.isEmpty
          ? GeneralEmptyState(
              icon: AnikumoIcons.list_alt_outlined,
              title: S.t('还没有自建榜单'),
              actions: [
                StateActionButton.tonal(
                  onPressed: _createList,
                  icon: AnikumoIcons.add,
                  text: S.t('新建榜单'),
                ),
              ],
            )
          : ListView.separated(
              padding: const EdgeInsets.all(StyleString.pagePadding),
              itemCount: _lists.length,
              separatorBuilder: (context, index) => const SizedBox(height: 10),
              itemBuilder: (context, index) {
                final list = _lists[index];
                return GlassSurface(
                  onTap: () async {
                    await Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => _ListDetailPage(listId: list.id),
                      ),
                    );
                    if (mounted) {
                      setState(() => _lists = UserListsStore.load());
                    }
                  },
                  padding: const EdgeInsets.symmetric(
                    horizontal: StyleString.pagePadding,
                    vertical: 6,
                  ),
                  child: Row(
                    children: [
                      const Icon(AnikumoIcons.list_alt_rounded),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              list.name,
                              style: Theme.of(context)
                                  .textTheme
                                  .titleMedium
                                  ?.copyWith(fontWeight: FontWeight.w600),
                            ),
                            Text(
                              S.f('共 {} 部', [list.bangumiIds.length]),
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        tooltip: S.t('删除榜单'),
                        onPressed: () => _deleteList(list),
                        icon: const Icon(AnikumoIcons.delete_outline),
                      ),
                      const Icon(AnikumoIcons.chevron_right),
                    ],
                  ),
                );
              },
            ),
    );
  }
}

class _ListDetailPage extends StatefulWidget {
  const _ListDetailPage({required this.listId});

  final String listId;

  @override
  State<_ListDetailPage> createState() => _ListDetailPageState();
}

class _ListDetailPageState extends State<_ListDetailPage> {
  UserList? _list;
  Map<int, BangumiItem> _resolved = {};
  bool _editing = false;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() {
    final lists = UserListsStore.load();
    _list = lists.where((e) => e.id == widget.listId).firstOrNull;
    _resolved = {
      for (final item in loadBangumiCandidates()) item.id: item,
    };
  }

  Future<void> _persist() async {
    final lists = UserListsStore.load();
    final index = lists.indexWhere((e) => e.id == widget.listId);
    if (index < 0 || _list == null) return;
    lists[index] = _list!;
    await UserListsStore.save(lists);
  }

  Future<void> _addItem() async {
    final picked = await showBangumiPicker(context, title: S.t('添加到榜单'));
    if (picked == null || _list == null || !mounted) return;
    if (_list!.bangumiIds.contains(picked.id)) {
      AnikumoDialog.showToast(context: context, message: S.t('这部番已经在榜单里了'));
      return;
    }
    setState(() => _list!.bangumiIds.add(picked.id));
    await _persist();
  }

  Future<void> _removeItem(int bangumiId) async {
    setState(() => _list!.bangumiIds.remove(bangumiId));
    await _persist();
  }

  Future<void> _shareAsText() async {
    final list = _list;
    if (list == null) return;
    final items = list.bangumiIds
        .map((id) => _resolved[id])
        .whereType<BangumiItem>()
        .toList();
    if (items.isEmpty) {
      AnikumoDialog.showToast(context: context, message: S.t('榜单还是空的'));
      return;
    }
    await Clipboard.setData(
      ClipboardData(text: buildListShareText(list.name, items)),
    );
    if (!mounted) return;
    AnikumoDialog.showToast(context: context, message: S.t('片单文本已复制，去粘贴分享吧'));
  }

  @override
  Widget build(BuildContext context) {
    final list = _list;
    if (list == null) {
      return Scaffold(
        appBar: SysAppBar(title: Text(S.t('榜单'))),
        body: GeneralEmptyState(
          icon: AnikumoIcons.list_alt_outlined,
          title: S.t('这个榜单不存在了'),
        ),
      );
    }
    final items = list.bangumiIds
        .map((id) => _resolved[id])
        .whereType<BangumiItem>()
        .toList();
    return Scaffold(
      appBar: SysAppBar(
        title: Text(list.name),
        actions: [
          IconButton(
            tooltip: S.t('分享为文本'),
            onPressed: _shareAsText,
            icon: const Icon(AnikumoIcons.share_outlined),
          ),
          IconButton(
            tooltip: _editing ? S.t('完成') : S.t('编辑条目'),
            onPressed: () => setState(() => _editing = !_editing),
            icon: Icon(_editing ? AnikumoIcons.done : AnikumoIcons.edit_outlined),
          ),
          IconButton(
            tooltip: S.t('添加番剧'),
            onPressed: _addItem,
            icon: const Icon(AnikumoIcons.add),
          ),
        ],
      ),
      body: items.isEmpty
          ? GeneralEmptyState(
              icon: AnikumoIcons.playlist_add_outlined,
              title: S.t('榜单还是空的'),
              actions: [
                StateActionButton.tonal(
                  onPressed: _addItem,
                  icon: AnikumoIcons.add,
                  text: S.t('从追番/历史中添加'),
                ),
              ],
            )
          : GridView.builder(
              padding: const EdgeInsets.all(StyleString.cardSpace),
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount:
                    MediaQuery.sizeOf(context).width > 600 ? 5 : 3,
                mainAxisSpacing: StyleString.cardSpace - 2,
                crossAxisSpacing: StyleString.cardSpace,
                mainAxisExtent: MediaQuery.of(context).size.width /
                        (MediaQuery.sizeOf(context).width > 600 ? 5 : 3) /
                        0.65 +
                    MediaQuery.textScalerOf(context).scale(32.0),
              ),
              itemCount: items.length,
              itemBuilder: (context, index) {
                final item = items[index];
                return Stack(
                  children: [
                    BangumiCardV(bangumiItem: item),
                    if (_editing)
                      Positioned(
                        top: 2,
                        right: 2,
                        child: IconButton.filledTonal(
                          tooltip: S.t('从榜单移除'),
                          onPressed: () => _removeItem(item.id),
                          icon: const Icon(AnikumoIcons.close, size: 18),
                        ),
                      ),
                  ],
                );
              },
            ),
    );
  }
}

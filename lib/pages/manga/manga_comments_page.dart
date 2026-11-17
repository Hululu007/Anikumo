import 'package:flutter/material.dart';

import 'package:anikumo/services/i18n/app_strings.dart';
import '../../bean/card/network_img_layer.dart';
import '../../bean/dialog/dialog.dart';
import '../../modules/manga/manga_item.dart';
import '../../services/manga/manga_source.dart';
import '../../services/manga/manga_sources.dart';
import '../../utils/error_message.dart';
import 'package:anikumo/bean/widget/anikumo_icons.dart';

/// Batch 271: a source's comments for one comic.
///
/// Reads through the MangaSource comment surface (MangaKit
/// and the old engine both map it now); sources without
/// one land on the unsupported empty state. Replies open
/// as a threaded view of the parent comment; posting goes
/// through the source too, so its own login state and rate
/// limits apply and its errors surface verbatim.
class MangaCommentsPage extends StatefulWidget {
  const MangaCommentsPage({super.key, required this.manga});

  final MangaItem manga;

  @override
  State<MangaCommentsPage> createState() => _MangaCommentsPageState();
}

class _MangaCommentsPageState extends State<MangaCommentsPage> {
  final _inputController = TextEditingController();
  List<MangaComment> _comments = const [];
  int _page = 1;
  int _maxPage = 1;
  bool _loading = true;
  bool _loadingMore = false;
  bool _sending = false;
  bool _supported = true;
  MangaComment? _threadParent;
  MangaComment? _replyTarget;

  MangaSource? get _source => MangaSources.byId(widget.manga.source);

  @override
  void initState() {
    super.initState();
    _load(first: true);
  }

  @override
  void dispose() {
    _inputController.dispose();
    super.dispose();
  }

  Future<void> _load({required bool first}) async {
    final source = _source;
    if (source == null) {
      setState(() {
        _supported = false;
        _loading = false;
      });
      return;
    }
    if (first) {
      setState(() => _loading = true);
    } else {
      setState(() => _loadingMore = true);
    }
    final result = await source.loadComments(
      widget.manga,
      page: first ? 1 : _page + 1,
      replyTo: _threadParent?.id,
    );
    if (!mounted) return;
    setState(() {
      _loading = false;
      _loadingMore = false;
      if (result == null) {
        _supported = false;
        return;
      }
      _comments = first ? result.comments : [..._comments, ...result.comments];
      _page = first ? 1 : _page + 1;
      _maxPage = result.maxPage;
    });
  }

  Future<void> _send() async {
    final source = _source;
    final content = _inputController.text.trim();
    if (source == null || content.isEmpty || _sending) return;
    setState(() => _sending = true);
    try {
      await source.sendComment(
        widget.manga,
        content: content,
        replyTo: _replyTarget?.id ?? _threadParent?.id,
      );
      _inputController.clear();
      if (!mounted) return;
      setState(() => _replyTarget = null);
      AnikumoDialog.showToast(message: S.t('评论已发表'));
      await _load(first: true);
    } catch (error) {
      if (mounted) {
        AnikumoDialog.showToast(message: friendlyError(error));
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  void _openThread(MangaComment comment) {
    setState(() {
      _threadParent = comment;
      _replyTarget = null;
      _comments = const [];
    });
    _load(first: true);
  }

  void _closeThread() {
    setState(() {
      _threadParent = null;
      _replyTarget = null;
      _comments = const [];
    });
    _load(first: true);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(
          _threadParent == null
              ? S.t('评论')
              : S.f('{} 的回复', [_threadParent!.userName]),
        ),
        leading: _threadParent == null
            ? null
            : IconButton(
                icon: const Icon(AnikumoIcons.arrow_back_rounded),
                onPressed: _closeThread,
              ),
      ),
      body: Column(
        children: [
          if (_threadParent != null)
            Container(
              width: double.infinity,
              color: theme.colorScheme.surfaceContainerHighest,
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
              child: Text(
                _threadParent!.content,
                style: theme.textTheme.bodyMedium,
              ),
            ),
          Expanded(child: _buildList(theme)),
          if (_supported) _buildComposer(theme),
        ],
      ),
    );
  }

  Widget _buildList(ThemeData theme) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (!_supported) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            S.t('这个源没有评论功能'),
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium,
          ),
        ),
      );
    }
    if (_comments.isEmpty) {
      return Center(child: Text(S.t('还没有评论，来发第一条')));
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      itemCount: _comments.length + (_page < _maxPage ? 1 : 0),
      separatorBuilder: (context, index) => const Divider(height: 20),
      itemBuilder: (context, index) {
        if (index >= _comments.length) {
          return TextButton(
            onPressed: _loadingMore ? null : () => _load(first: false),
            child: Text(_loadingMore ? S.t('加载中…') : S.t('加载更多')),
          );
        }
        final comment = _comments[index];
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CircleAvatar(
              radius: 18,
              backgroundColor: theme.colorScheme.surfaceContainerHighest,
              child: comment.avatar.isEmpty
                  ? const Icon(AnikumoIcons.person_outline_rounded, size: 18)
                  : ClipOval(
                      child: NetworkImgLayer(
                        src: comment.avatar,
                        width: 36,
                        height: 36,
                      ),
                    ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    comment.userName,
                    style: theme.textTheme.bodyMedium
                        ?.copyWith(fontWeight: FontWeight.w600),
                  ),
                  if (comment.time.isNotEmpty)
                    Text(
                      comment.time,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.outline,
                      ),
                    ),
                  const SizedBox(height: 4),
                  Text(comment.content, style: theme.textTheme.bodyMedium),
                  Row(
                    children: [
                      TextButton(
                        onPressed: () =>
                            setState(() => _replyTarget = comment),
                        child: Text(S.t('回复')),
                      ),
                      if (_threadParent == null && comment.replyCount > 0)
                        TextButton(
                          onPressed: () => _openThread(comment),
                          child: Text(
                            S.f('查看 {} 条回复', [comment.replyCount]),
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildComposer(ThemeData theme) {
    return SafeArea(
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
        decoration: BoxDecoration(
          border: Border(
            top: BorderSide(color: theme.colorScheme.outlineVariant),
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_replyTarget != null)
              Row(
                children: [
                  Expanded(
                    child: Text(
                      S.f('回复 {}', [_replyTarget!.userName]),
                      style: theme.textTheme.bodySmall,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(AnikumoIcons.close_rounded, size: 18),
                    onPressed: () => setState(() => _replyTarget = null),
                  ),
                ],
              ),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _inputController,
                    minLines: 1,
                    maxLines: 4,
                    decoration: InputDecoration(
                      hintText: S.t('写评论…'),
                      isDense: true,
                      border: const OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: _sending ? null : _send,
                  child: Text(_sending ? S.t('发表中…') : S.t('发表')),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

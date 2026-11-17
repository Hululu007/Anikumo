import 'package:flutter/material.dart';
import 'package:anikumo/bean/appbar/sys_app_bar.dart';
import 'package:anikumo/services/i18n/app_strings.dart';
import 'package:anikumo/utils/constants.dart';

/// Batch 276 (#65): the built-in help page — short,
/// practical answers grouped by area. Static content
/// (localized through the string table); anything
/// deeper lives in the diagnostics bundle and the
/// community.
class HelpPage extends StatelessWidget {
  const HelpPage({super.key});

  static const _sections = <(String, String)>[
    (
      '四个专区怎么切换？',
      '点任意专区首页顶部的专区名标记（ANIME / 漫画 / 小说 / 影视），'
      '会拉起切换器。切换样式（上拉面板、滚轮、滑移、网格、分段）'
      '和专区顺序都可以在「设置 → 外观」里改。',
    ),
    (
      '内容从哪里来？',
      'Anikumo 本身不提供内容。动漫与影视需要你自己添加内容源，'
      '漫画与小说需要安装书源 / 漫画源；影视区也可以在片源仓库里'
      '一键导入配置。没有源的时候，对应专区是空的，这是正常现象。',
    ),
    (
      '换手机后数据怎么搬？',
      '两种方式：在「发现 → 本地备份与恢复」导出备份文件'
      '（可以加密），到新手机上导入；或者在「设置 → 同步」里'
      '配置 WebDAV，观看记录、收藏箱、三区收藏与进度都会同步，'
      '双边都改过同一区时会进冲突页让你选一份。',
    ),
    (
      '弹幕没有 / 不准怎么办？',
      '播放页的弹幕设置里可以手动搜索匹配；自动匹配走双线'
      '（官方线优先、备用线兜底）。发送的弹幕只保存在本机。'
      '也可以在弹幕设置里挂载本地弹幕文件（XML / JSON / ASS）。',
    ),
    (
      '下载的视频 / 漫画在哪？',
      '动漫下载在「下载」页管理；漫画下载在漫画区的下载页，'
      '完整备份会把已下载的漫画章节一并打包。影视下载在'
      '影视区的下载中心，加密的 HLS 分片也会自动解密合并。',
    ),
    (
      '更新与公告',
      'App 冷启动时会检查仓库里的公告，有新公告会弹窗一次。'
      '新版本在 GitHub 发布页与官网提供下载；发布说明会写清'
      '更新内容、优化与注意事项。',
    ),
    (
      '出问题了怎么反馈？',
      '先到「设置 → 日志」导出诊断包（日志尾段 + 已脱敏的'
      '设置摘要），再到 GitHub Issues 或官方 Discord 附上'
      '诊断包和复现步骤，这样定位最快。',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: SysAppBar(title: Text(S.t('帮助'))),
      body: ListView(
        padding: const EdgeInsets.all(StyleString.pagePadding),
        children: [
          for (final (title, body) in _sections)
            Padding(
              padding: const EdgeInsets.only(bottom: 18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    S.t(title),
                    style: theme.textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    S.t(body),
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                      height: 1.5,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

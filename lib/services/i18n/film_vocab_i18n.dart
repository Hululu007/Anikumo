import 'package:anikumo/services/i18n/app_strings.dart';

/// Batch 264: display labels for the film zone's FIXED
/// vocabulary (kFilmGenres / kFilmAreas in cms_api_source)
/// and its kind/chip words.
///
/// These words are data, not widget literals: filter logic,
/// browse matching and stored values always use the Chinese
/// source word; only the rendered chip/label goes through
/// here, following the UI language (S.languageCode). An
/// unmapped word (e.g. a legacy deep-link genre pinned at
/// the head of the chip row) renders as-is.
String _pick(String zh, Map<String, String> en, Map<String, String> ja,
    Map<String, String> zhHant) {
  switch (S.languageCode) {
    case 'en':
      return en[zh] ?? zh;
    case 'ja':
      return ja[zh] ?? zh;
    case 'zhHant':
      return zhHant[zh] ?? zh;
    default:
      return zh;
  }
}

String filmGenreLabel(String zh) =>
    _pick(zh, _kGenreEn, _kGenreJa, _kGenreZhHant);

String filmAreaLabel(String zh) =>
    _pick(zh, _kAreaEn, _kAreaJa, _kAreaZhHant);

String filmKindLabel(String zh) =>
    _pick(zh, _kKindEn, _kKindJa, _kKindZhHant);

const Map<String, String> _kKindEn = {
  '全部': 'All',
  '电视剧': 'TV Series',
  '电影': 'Movies',
  '综艺': 'Variety',
  '动漫': 'Anime',
  '短剧': 'Short Drama',
  '漫剧': 'Manju',
  '其他': 'Other',
  '直播': 'Live',
  '全部题材': 'All Genres',
  '全部年代': 'All Years',
  '全部地区': 'All Regions',
};

const Map<String, String> _kKindJa = {
  '全部': 'すべて',
  '电视剧': 'ドラマ',
  '电影': '映画',
  '综艺': 'バラエティ',
  '动漫': 'アニメ',
  '短剧': 'ショートドラマ',
  '漫剧': '漫劇',
  '其他': 'その他',
  '直播': 'ライブ',
  '全部题材': '全ジャンル',
  '全部年代': '全年代',
  '全部地区': '全地域',
};

const Map<String, String> _kKindZhHant = {
  '全部': '全部',
  '电视剧': '電視劇',
  '电影': '電影',
  '综艺': '綜藝',
  '动漫': '動漫',
  '短剧': '短劇',
  '漫剧': '漫劇',
  '其他': '其他',
  '直播': '直播',
  '全部题材': '全部題材',
  '全部年代': '全部年代',
  '全部地区': '全部地區',
};

const Map<String, String> _kGenreEn = {
  '爱情': 'Romance',
  '喜剧': 'Comedy',
  '动作': 'Action',
  '科幻': 'Sci-Fi',
  '悬疑': 'Mystery',
  '剧情': 'Drama',
  '惊悚': 'Thriller',
  '恐怖': 'Horror',
  '犯罪': 'Crime',
  '战争': 'War',
  '古装': 'Period',
  '武侠': 'Wuxia',
  '家庭': 'Family',
  '动画': 'Animation',
  '冒险': 'Adventure',
  '奇幻': 'Fantasy',
  '历史': 'History',
  '音乐': 'Music',
  '纪录': 'Documentary',
  '电视电影': 'TV Movie',
  '西部': 'Western',
  '动作冒险': 'Action & Adventure',
  '儿童': 'Kids',
  '真人秀': 'Reality',
  '肥皂剧': 'Soap Opera',
  '脱口秀': 'Talk Show',
  '新闻': 'News',
  '都市': 'Urban',
  '言情': 'Romance Drama',
  '校园': 'Campus',
  '青春': 'Youth',
  '年代': 'Era',
  '军事': 'Military',
  '谍战': 'Spy',
  '职场': 'Workplace',
  '仙侠': 'Xianxia',
  '玄幻': 'Xuanhuan',
  '穿越': 'Time Travel',
  '甜宠': 'Sweet Romance',
  '灾难': 'Disaster',
  '伦理': 'Melodrama',
  '歌舞': 'Musical',
  '体育': 'Sports',
  '宫廷': 'Palace',
  '民国': 'Republican Era',
  '励志': 'Inspirational',
  '传记': 'Biography',
  '其他': 'Other',
};

const Map<String, String> _kGenreJa = {
  '爱情': '恋愛',
  '喜剧': 'コメディ',
  '动作': 'アクション',
  '科幻': 'SF',
  '悬疑': 'ミステリー',
  '剧情': 'ドラマ',
  '惊悚': 'スリラー',
  '恐怖': 'ホラー',
  '犯罪': '犯罪',
  '战争': '戦争',
  '古装': '時代劇',
  '武侠': '武侠',
  '家庭': 'ファミリー',
  '动画': 'アニメ',
  '冒险': '冒険',
  '奇幻': 'ファンタジー',
  '历史': '歴史',
  '音乐': '音楽',
  '纪录': 'ドキュメンタリー',
  '电视电影': 'テレビ映画',
  '西部': '西部劇',
  '动作冒险': 'アクション・冒険',
  '儿童': '子供向け',
  '真人秀': 'リアリティ',
  '肥皂剧': 'ソープオペラ',
  '脱口秀': 'トークショー',
  '新闻': 'ニュース',
  '都市': '都市',
  '言情': '恋愛ドラマ',
  '校园': '学園',
  '青春': '青春',
  '年代': '年代',
  '军事': '軍事',
  '谍战': 'スパイ',
  '职场': 'お仕事',
  '仙侠': '仙侠',
  '玄幻': '玄幻',
  '穿越': 'タイムトラベル',
  '甜宠': '甘々ラブ',
  '灾难': '災害',
  '伦理': '倫理',
  '歌舞': 'ミュージカル',
  '体育': 'スポーツ',
  '宫廷': '宮廷',
  '民国': '民国',
  '励志': '感動',
  '传记': '伝記',
  '其他': 'その他',
};

const Map<String, String> _kGenreZhHant = {
  '爱情': '愛情',
  '喜剧': '喜劇',
  '动作': '動作',
  '科幻': '科幻',
  '悬疑': '懸疑',
  '剧情': '劇情',
  '惊悚': '驚悚',
  '恐怖': '恐怖',
  '犯罪': '犯罪',
  '战争': '戰爭',
  '古装': '古裝',
  '武侠': '武俠',
  '家庭': '家庭',
  '动画': '動畫',
  '冒险': '冒險',
  '奇幻': '奇幻',
  '历史': '歷史',
  '音乐': '音樂',
  '纪录': '紀錄',
  '电视电影': '電視電影',
  '西部': '西部',
  '动作冒险': '動作冒險',
  '儿童': '兒童',
  '真人秀': '真人秀',
  '肥皂剧': '肥皂劇',
  '脱口秀': '脫口秀',
  '新闻': '新聞',
  '都市': '都市',
  '言情': '言情',
  '校园': '校園',
  '青春': '青春',
  '年代': '年代',
  '军事': '軍事',
  '谍战': '諜戰',
  '职场': '職場',
  '仙侠': '仙俠',
  '玄幻': '玄幻',
  '穿越': '穿越',
  '甜宠': '甜寵',
  '灾难': '災難',
  '伦理': '倫理',
  '歌舞': '歌舞',
  '体育': '體育',
  '宫廷': '宮廷',
  '民国': '民國',
  '励志': '勵志',
  '传记': '傳記',
  '其他': '其他',
};

const Map<String, String> _kAreaEn = {
  '中国': 'China',
  '香港': 'Hong Kong',
  '台湾': 'Taiwan',
  '美国': 'USA',
  '日本': 'Japan',
  '韩国': 'South Korea',
  '英国': 'UK',
  '法国': 'France',
  '德国': 'Germany',
  '意大利': 'Italy',
  '西班牙': 'Spain',
  '俄罗斯': 'Russia',
  '泰国': 'Thailand',
  '印度': 'India',
  '加拿大': 'Canada',
  '澳大利亚': 'Australia',
  '新加坡': 'Singapore',
  '马来西亚': 'Malaysia',
  '其他': 'Other',
};

const Map<String, String> _kAreaJa = {
  '中国': '中国',
  '香港': '香港',
  '台湾': '台湾',
  '美国': 'アメリカ',
  '日本': '日本',
  '韩国': '韓国',
  '英国': 'イギリス',
  '法国': 'フランス',
  '德国': 'ドイツ',
  '意大利': 'イタリア',
  '西班牙': 'スペイン',
  '俄罗斯': 'ロシア',
  '泰国': 'タイ',
  '印度': 'インド',
  '加拿大': 'カナダ',
  '澳大利亚': 'オーストラリア',
  '新加坡': 'シンガポール',
  '马来西亚': 'マレーシア',
  '其他': 'その他',
};

const Map<String, String> _kAreaZhHant = {
  '中国': '中國',
  '香港': '香港',
  '台湾': '台灣',
  '美国': '美國',
  '日本': '日本',
  '韩国': '韓國',
  '英国': '英國',
  '法国': '法國',
  '德国': '德國',
  '意大利': '義大利',
  '西班牙': '西班牙',
  '俄罗斯': '俄羅斯',
  '泰国': '泰國',
  '印度': '印度',
  '加拿大': '加拿大',
  '澳大利亚': '澳洲',
  '新加坡': '新加坡',
  '马来西亚': '馬來西亞',
  '其他': '其他',
};

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:html/parser.dart' as html_parser;
import 'package:html/dom.dart' as dom;

class _AppHttpOverrides extends HttpOverrides {
  static const _trustedHosts = {
    'abibletool.net',
    'abibletool.com',
    'www.abibletool.net',
    'www.abibletool.com',
  };

  @override
  HttpClient createHttpClient(SecurityContext? context) {
    final client = super.createHttpClient(context);
    client.badCertificateCallback =
        (X509Certificate cert, String host, int port) =>
            _trustedHosts.contains(host);
    return client;
  }
}

void main() {
  HttpOverrides.global = _AppHttpOverrides();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    final lightAppBar = const AppBarTheme(
      backgroundColor: Colors.white,
      foregroundColor: Colors.black,
      elevation: 0,
      scrolledUnderElevation: 0,
      iconTheme: IconThemeData(color: Colors.black),
      titleTextStyle: TextStyle(
        color: Colors.black,
        fontSize: 18,
        fontWeight: FontWeight.w600,
      ),
      systemOverlayStyle: SystemUiOverlayStyle(
        statusBarColor: Colors.white,
        statusBarIconBrightness: Brightness.dark,
        statusBarBrightness: Brightness.light,
        systemNavigationBarColor: Colors.white,
        systemNavigationBarIconBrightness: Brightness.dark,
      ),
    );

    final darkAppBar = const AppBarTheme(
      backgroundColor: Colors.black,
      foregroundColor: Colors.white,
      elevation: 0,
      scrolledUnderElevation: 0,
      iconTheme: IconThemeData(color: Colors.white),
      titleTextStyle: TextStyle(
        color: Colors.white,
        fontSize: 18,
        fontWeight: FontWeight.w600,
      ),
      systemOverlayStyle: SystemUiOverlayStyle(
        statusBarColor: Colors.black,
        statusBarIconBrightness: Brightness.light,
        statusBarBrightness: Brightness.dark,
        systemNavigationBarColor: Colors.black,
        systemNavigationBarIconBrightness: Brightness.light,
      ),
    );

    return MaterialApp(
      title: '圣经搜索',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo),
        useMaterial3: true,
        scaffoldBackgroundColor: Colors.white,
        appBarTheme: lightAppBar,
      ),
      darkTheme: ThemeData(
        brightness: Brightness.dark,
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.indigo,
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
        scaffoldBackgroundColor: Colors.black,
        appBarTheme: darkAppBar,
      ),
      themeMode: ThemeMode.system,
      home: const SearchPage(),
    );
  }
}

class VerseResult {
  final String reference;
  final String text;
  final String href;

  VerseResult({
    required this.reference,
    required this.text,
    required this.href,
  });
}

class VerseLine {
  final int number;
  final String text;

  VerseLine({required this.number, required this.text});
}

class SearchFormState {
  final String viewState;
  final String viewStateGenerator;
  final String previousPage;
  final String eventValidation;
  final String query;

  const SearchFormState({
    required this.viewState,
    required this.viewStateGenerator,
    required this.previousPage,
    required this.eventValidation,
    required this.query,
  });
}

class PagerInfo {
  final int currentPage;
  final List<int> pages;
  final int? prevPage;
  final int? nextPage;
  final int? totalCount;

  const PagerInfo({
    required this.currentPage,
    required this.pages,
    this.prevPage,
    this.nextPage,
    this.totalCount,
  });
}

String _absoluteUrl(String href) {
  var url = href;
  final hashIndex = url.indexOf('#');
  if (hashIndex >= 0) url = url.substring(0, hashIndex);
  if (url.startsWith('//')) return 'https:$url';
  if (url.startsWith('http')) return url;
  return 'https://abibletool.com$url';
}

String _decodeBody(http.Response response) {
  final contentType = response.headers['content-type'] ?? '';
  final lower = contentType.toLowerCase();
  if (lower.contains('utf-8') || lower.contains('utf8')) {
    return utf8.decode(response.bodyBytes, allowMalformed: true);
  }
  try {
    final decoded = utf8.decode(response.bodyBytes, allowMalformed: false);
    return decoded;
  } catch (_) {
    return latin1.decode(response.bodyBytes);
  }
}

class SearchPage extends StatefulWidget {
  const SearchPage({super.key});

  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> {
  final TextEditingController _controller = TextEditingController();
  final ScrollController _listController = ScrollController();
  List<VerseResult> _results = [];
  bool _loading = false;
  String? _error;
  String _lastQuery = '';
  SearchFormState? _formState;
  PagerInfo? _pager;

  @override
  void dispose() {
    _controller.dispose();
    _listController.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    final query = _controller.text.trim();
    if (query.isEmpty) return;

    FocusScope.of(context).unfocus();
    setState(() {
      _loading = true;
      _error = null;
      _results = [];
      _pager = null;
      _formState = null;
      _lastQuery = query;
    });

    try {
      final uri = Uri.parse(
        'https://abibletool.net/search.aspx?q=${Uri.encodeQueryComponent(query)}&r=1',
      );
      final response = await http.get(uri).timeout(const Duration(seconds: 20));

      if (response.statusCode != 200) {
        throw Exception('请求失败：${response.statusCode}');
      }

      _consumeResponseHtml(_decodeBody(response), query);
    } catch (e) {
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _goToPage(int page) async {
    final form = _formState;
    if (form == null) return;

    FocusScope.of(context).unfocus();
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final uri = Uri.parse(
        'https://abibletool.net/search.aspx?q=${Uri.encodeQueryComponent(form.query)}&r=1',
      );
      final body = {
        '__EVENTTARGET': 'Pager1',
        '__EVENTARGUMENT': '$page',
        '__LASTFOCUS': '',
        '__VIEWSTATE': form.viewState,
        '__VIEWSTATEGENERATOR': form.viewStateGenerator,
        '__PREVIOUSPAGE': form.previousPage,
        '__EVENTVALIDATION': form.eventValidation,
        'txtText': form.query,
      };
      final response = await http
          .post(
            uri,
            headers: const {
              'Content-Type': 'application/x-www-form-urlencoded',
              'User-Agent':
                  'Mozilla/5.0 (Linux; Android 10) AppleWebKit/537.36 Mobile',
            },
            body: body,
          )
          .timeout(const Duration(seconds: 20));

      if (response.statusCode != 200) {
        throw Exception('请求失败：${response.statusCode}');
      }

      _consumeResponseHtml(_decodeBody(response), form.query);

      if (_listController.hasClients) {
        _listController.jumpTo(0);
      }
    } catch (e) {
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  void _consumeResponseHtml(String html, String query) {
    final document = html_parser.parse(html);
    final results = _parseResultsDoc(document);
    final formState = _parseFormState(document, query);
    final pager = _parsePager(document);

    setState(() {
      _results = results;
      _formState = formState;
      _pager = pager;
      _lastQuery = query;
      _loading = false;
    });
  }

  List<VerseResult> _parseResultsDoc(dom.Document document) {
    final rows = document.querySelectorAll('tr.verserow');
    final list = <VerseResult>[];

    for (final dom.Element row in rows) {
      final bookCell = row.querySelector('td.book a');
      final tds = row.querySelectorAll('td');
      dom.Element? textSpan;
      if (tds.length >= 2) {
        textSpan = tds[1].querySelector('span');
      }

      if (bookCell == null || textSpan == null) continue;

      final reference = bookCell.text.trim().replaceAll(RegExp(r'\s+'), '');
      final text = textSpan.text.trim();
      final href = bookCell.attributes['href'] ?? '';

      if (reference.isEmpty || text.isEmpty) continue;
      list.add(VerseResult(reference: reference, text: text, href: href));
    }

    return list;
  }

  SearchFormState? _parseFormState(dom.Document document, String query) {
    String input(String id) {
      final el = document.querySelector('input#$id');
      return el?.attributes['value'] ?? '';
    }

    final viewState = input('__VIEWSTATE');
    if (viewState.isEmpty) return null;

    return SearchFormState(
      viewState: viewState,
      viewStateGenerator: input('__VIEWSTATEGENERATOR'),
      previousPage: input('__PREVIOUSPAGE'),
      eventValidation: input('__EVENTVALIDATION'),
      query: query,
    );
  }

  PagerInfo? _parsePager(dom.Document document) {
    final pagerTable = document.querySelector('table.PagerContainerTable');
    if (pagerTable == null) return null;

    final pages = <int>[];
    int? currentPage;
    int? prev;
    int? next;
    int? total;

    final currentSpan = pagerTable.querySelector('.PagerCurrentPageCell span');
    if (currentSpan != null) {
      currentPage = int.tryParse(currentSpan.text.trim());
      final title = currentSpan.attributes['title'] ?? '';
      total = _parseTotalFromTitle(title);
    }

    final cells = pagerTable.querySelectorAll('td');
    for (final cell in cells) {
      final cls = cell.className;
      final a = cell.querySelector('a');
      if (a == null) {
        if (cls.contains('PagerCurrentPageCell') && currentPage != null) {
          pages.add(currentPage);
        }
        continue;
      }
      final title = a.attributes['title'] ?? '';
      final href = a.attributes['href'] ?? '';
      final num = _extractDoPostBackArg(href);

      if (title.contains('到') && title.contains('页')) {
        if (title.contains('上一页') || a.text.contains('上一页')) {
          prev = num;
        } else if (title.contains('下一页') || a.text.contains('下一页')) {
          next = num;
        }
      } else if (num != null) {
        pages.add(num);
      }
      total ??= _parseTotalFromTitle(title);
    }

    if (currentPage == null) return null;

    pages.sort();
    final dedupPages = <int>[];
    for (final p in pages) {
      if (dedupPages.isEmpty || dedupPages.last != p) dedupPages.add(p);
    }

    return PagerInfo(
      currentPage: currentPage,
      pages: dedupPages,
      prevPage: prev,
      nextPage: next,
      totalCount: total,
    );
  }

  int? _parseTotalFromTitle(String title) {
    final match = RegExp(r'共计(\d+)项').firstMatch(title);
    if (match == null) return null;
    return int.tryParse(match.group(1) ?? '');
  }

  int? _extractDoPostBackArg(String href) {
    final match = RegExp(r"__doPostBack\('Pager1','(\d+)'\)").firstMatch(href);
    if (match == null) return null;
    return int.tryParse(match.group(1) ?? '');
  }

  void _openDetail(VerseResult item) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => DetailPage(item: item, keyword: _lastQuery),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('圣经搜索'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _controller,
                    textInputAction: TextInputAction.search,
                    onSubmitted: (_) => _search(),
                    decoration: InputDecoration(
                      hintText: '请输入搜索内容，如：圣经',
                      prefixIcon: const Icon(Icons.search),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      isDense: true,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: _loading ? null : _search,
                  child: const Text('搜索'),
                ),
              ],
            ),
          ),
          Expanded(child: _buildBody()),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_loading && _results.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text('出错了：$_error', style: const TextStyle(color: Colors.red)),
        ),
      );
    }
    if (_results.isEmpty) {
      return Center(
        child: Text(
          _lastQuery.isEmpty ? '输入关键词开始搜索' : '未找到与 "$_lastQuery" 相关的经文',
          style: const TextStyle(color: Colors.grey),
        ),
      );
    }

    return Stack(
      children: [
        Column(
          children: [
            Expanded(
              child: ListView.separated(
                controller: _listController,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                itemCount: _results.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (context, index) {
                  final item = _results[index];
                  return ListTile(
                    onTap: () => _openDetail(item),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 6,
                    ),
                    title: Text(
                      item.reference,
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                    ),
                    subtitle: Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: _buildHighlightedText(item.text, _lastQuery),
                    ),
                    trailing: const Icon(Icons.chevron_right),
                  );
                },
              ),
            ),
            if (_pager != null) _buildPager(_pager!),
          ],
        ),
        if (_loading)
          const Positioned.fill(
            child: ColoredBox(
              color: Color(0x33000000),
              child: Center(child: CircularProgressIndicator()),
            ),
          ),
      ],
    );
  }

  Widget _buildPager(PagerInfo pager) {
    final theme = Theme.of(context);
    final borderColor = theme.colorScheme.outlineVariant;

    Widget pageButton({
      required String label,
      required bool enabled,
      required bool highlighted,
      required VoidCallback? onTap,
    }) {
      final bg = highlighted
          ? theme.colorScheme.primary
          : Colors.transparent;
      final fg = highlighted
          ? theme.colorScheme.onPrimary
          : (enabled ? theme.colorScheme.onSurface : theme.disabledColor);
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 3),
        child: InkWell(
          onTap: enabled ? onTap : null,
          borderRadius: BorderRadius.circular(6),
          child: Container(
            constraints: const BoxConstraints(minWidth: 36, minHeight: 32),
            alignment: Alignment.center,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: bg,
              border: Border.all(color: borderColor),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              label,
              style: TextStyle(
                color: fg,
                fontWeight: highlighted ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ),
        ),
      );
    }

    final children = <Widget>[];
    children.add(pageButton(
      label: '上一页',
      enabled: pager.prevPage != null && pager.currentPage > 1,
      highlighted: false,
      onTap: pager.prevPage == null
          ? null
          : () => _goToPage(pager.prevPage!),
    ));
    for (final p in pager.pages) {
      children.add(pageButton(
        label: '$p',
        enabled: true,
        highlighted: p == pager.currentPage,
        onTap: p == pager.currentPage ? null : () => _goToPage(p),
      ));
    }
    children.add(pageButton(
      label: '下一页',
      enabled: pager.nextPage != null,
      highlighted: false,
      onTap: pager.nextPage == null ? null : () => _goToPage(pager.nextPage!),
    ));

    return Container(
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: borderColor)),
        color: theme.scaffoldBackgroundColor,
      ),
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: children,
            ),
          ),
          if (pager.totalCount != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                '第 ${pager.currentPage} 页 / 共 ${pager.totalCount} 节',
                style: TextStyle(
                  fontSize: 12,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildHighlightedText(String text, String keyword) {
    final baseColor = Theme.of(context).colorScheme.onSurface;
    if (keyword.isEmpty) {
      return Text(
        text,
        style: TextStyle(fontSize: 15, height: 1.5, color: baseColor),
      );
    }
    final spans = <TextSpan>[];
    int start = 0;
    while (true) {
      final index = text.indexOf(keyword, start);
      if (index < 0) {
        spans.add(TextSpan(text: text.substring(start)));
        break;
      }
      if (index > start) {
        spans.add(TextSpan(text: text.substring(start, index)));
      }
      spans.add(
        TextSpan(
          text: keyword,
          style: const TextStyle(
            color: Colors.red,
            fontWeight: FontWeight.bold,
          ),
        ),
      );
      start = index + keyword.length;
    }
    return RichText(
      text: TextSpan(
        style: TextStyle(fontSize: 15, height: 1.5, color: baseColor),
        children: spans,
      ),
    );
  }
}

class DetailPage extends StatefulWidget {
  final VerseResult item;
  final String keyword;

  const DetailPage({super.key, required this.item, required this.keyword});

  @override
  State<DetailPage> createState() => _DetailPageState();
}

class _DetailPageState extends State<DetailPage> {
  final ScrollController _scrollController = ScrollController();
  final Map<int, GlobalKey> _verseKeys = {};
  List<VerseLine> _verses = [];
  bool _loading = true;
  String? _error;
  int? _targetVerse;

  @override
  void initState() {
    super.initState();
    _targetVerse = _extractTargetVerse(widget.item.href);
    _loadDetail();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  int? _extractTargetVerse(String href) {
    final hashIndex = href.indexOf('#');
    if (hashIndex < 0) return null;
    final fragment = href.substring(hashIndex + 1);
    return int.tryParse(fragment);
  }

  Future<void> _loadDetail() async {
    try {
      final url = _absoluteUrl(widget.item.href);
      final uri = Uri.parse(url);
      final response = await http.get(uri).timeout(const Duration(seconds: 20));

      if (response.statusCode != 200) {
        throw Exception('请求失败：${response.statusCode}');
      }

      final verses = _parseDetail(_decodeBody(response));
      if (!mounted) return;
      setState(() {
        _verses = verses;
        _loading = false;
      });

      if (_targetVerse != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToTarget());
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  List<VerseLine> _parseDetail(String body) {
    final document = html_parser.parse(body);
    var tables = document.querySelectorAll('table.table-hover');
    if (tables.isEmpty) {
      tables = document.querySelectorAll('table');
    }
    final list = <VerseLine>[];

    for (final table in tables) {
      final spans = table.querySelectorAll('span');
      for (final span in spans) {
        final idText = span.attributes['id'];
        if (idText == null) continue;
        final number = int.tryParse(idText);
        if (number == null) continue;

        final raw = span.text;
        final text = raw.replaceAll(RegExp(r'\s+'), '').trim();
        if (text.isEmpty) continue;

        list.add(VerseLine(number: number, text: text));
      }
      if (list.isNotEmpty) break;
    }

    return list;
  }

  void _scrollToTarget() {
    final target = _targetVerse;
    if (target == null) return;
    final key = _verseKeys[target];
    if (key == null) return;
    final ctx = key.currentContext;
    if (ctx == null) return;
    Scrollable.ensureVisible(
      ctx,
      duration: const Duration(milliseconds: 400),
      alignment: 0.1,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.item.reference),
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text('出错了：$_error', style: const TextStyle(color: Colors.red)),
        ),
      );
    }
    if (_verses.isEmpty) {
      return const Center(
        child: Text('未解析到经文内容', style: TextStyle(color: Colors.grey)),
      );
    }

    return ListView.separated(
      controller: _scrollController,
      padding: const EdgeInsets.all(12),
      itemCount: _verses.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (context, index) {
        final verse = _verses[index];
        final key = _verseKeys.putIfAbsent(verse.number, () => GlobalKey());
        final isTarget = verse.number == _targetVerse;
        return Container(
          key: key,
          color: isTarget
              ? Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.5)
              : null,
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 32,
                child: Text(
                  '${verse.number}',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
              ),
              Expanded(
                child: _buildVerseText(verse.text, widget.keyword),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildVerseText(String text, String keyword) {
    final baseColor = Theme.of(context).colorScheme.onSurface;
    if (keyword.isEmpty) {
      return Text(
        text,
        style: TextStyle(fontSize: 16, height: 1.7, color: baseColor),
      );
    }
    final spans = <TextSpan>[];
    int start = 0;
    while (true) {
      final index = text.indexOf(keyword, start);
      if (index < 0) {
        spans.add(TextSpan(text: text.substring(start)));
        break;
      }
      if (index > start) {
        spans.add(TextSpan(text: text.substring(start, index)));
      }
      spans.add(
        TextSpan(
          text: keyword,
          style: const TextStyle(
            color: Colors.red,
            fontWeight: FontWeight.bold,
          ),
        ),
      );
      start = index + keyword.length;
    }
    return RichText(
      text: TextSpan(
        style: TextStyle(fontSize: 16, height: 1.7, color: baseColor),
        children: spans,
      ),
    );
  }
}

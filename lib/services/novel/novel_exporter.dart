import 'dart:convert';

import 'package:archive/archive.dart';

/// Batch 270: whole-book export (TXT / EPUB) for source
/// novels. The builders are pure — they take plain chapter
/// texts — so the formats can be unit-tested without a
/// network or a source.
class ExportChapter {
  const ExportChapter({required this.title, required this.paragraphs});

  final String title;
  final List<String> paragraphs;
}

class NovelExporter {
  NovelExporter._();

  static String buildTxt({
    required String bookTitle,
    required String author,
    required List<ExportChapter> chapters,
  }) {
    final out = StringBuffer()
      ..writeln(bookTitle)
      ..writeln(author)
      ..writeln();
    for (final chapter in chapters) {
      out
        ..writeln(chapter.title)
        ..writeln();
      for (final paragraph in chapter.paragraphs) {
        out.writeln(paragraph);
      }
      out.writeln();
    }
    return out.toString();
  }

  static String _escape(String text) => text
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;');

  static String _chapterXhtml(ExportChapter chapter) {
    final out = StringBuffer()
      ..writeln('<?xml version="1.0" encoding="utf-8"?>')
      ..writeln(
        '<!DOCTYPE html PUBLIC "-//W3C//DTD XHTML 1.1//EN" '
        '"http://www.w3.org/TR/xhtml11/DTD/xhtml11.dtd">',
      )
      ..writeln(
        '<html xmlns="http://www.w3.org/1999/xhtml"><head>'
        '<title>${_escape(chapter.title)}</title></head><body>',
      )
      ..writeln('<h1>${_escape(chapter.title)}</h1>');
    for (final paragraph in chapter.paragraphs) {
      out.writeln('<p>${_escape(paragraph)}</p>');
    }
    out.writeln('</body></html>');
    return out.toString();
  }

  /// A minimal, valid EPUB 3 package: stored mimetype
  /// first, container, package document with one spine item
  /// per chapter, and a nav document.
  static List<int> buildEpub({
    required String bookTitle,
    required String author,
    required List<ExportChapter> chapters,
  }) {
    final archive = Archive();
    void add(String name, String content, {bool stored = false}) {
      final bytes = utf8.encode(content);
      final file = ArchiveFile(name, bytes.length, bytes);
      // EPUB requires the mimetype entry to be stored
      // (uncompressed) and first in the archive.
      if (stored) file.compression = CompressionType.none;
      archive.addFile(file);
    }

    add('mimetype', 'application/epub+zip', stored: true);
    add(
      'META-INF/container.xml',
      '<?xml version="1.0" encoding="utf-8"?>\n'
      '<container version="1.0" '
      'xmlns="urn:oasis:names:tc:opendocument:xmlns:container">'
      '<rootfiles><rootfile full-path="OEBPS/content.opf" '
      'media-type="application/oebps-package+xml"/></rootfiles>'
      '</container>',
    );

    final manifest = StringBuffer()
      ..writeln('<item id="nav" href="nav.xhtml" '
          'media-type="application/xhtml+xml" properties="nav"/>');
    final spine = StringBuffer();
    final navItems = StringBuffer();
    for (var i = 0; i < chapters.length; i++) {
      manifest.writeln('<item id="ch${i + 1}" href="ch${i + 1}.xhtml" '
          'media-type="application/xhtml+xml"/>');
      spine.writeln('<itemref idref="ch${i + 1}"/>');
      navItems.writeln(
        '<li><a href="ch${i + 1}.xhtml">'
        '${_escape(chapters[i].title)}</a></li>',
      );
    }
    add(
      'OEBPS/content.opf',
      '<?xml version="1.0" encoding="utf-8"?>\n'
      '<package xmlns="http://www.idpf.org/2007/opf" version="3.0" '
      'unique-identifier="bookid"><metadata '
      'xmlns:dc="http://purl.org/dc/elements/1.1/">'
      '<dc:identifier id="bookid">anikumo:${_escape(bookTitle)}</dc:identifier>'
      '<dc:title>${_escape(bookTitle)}</dc:title>'
      '<dc:creator>${_escape(author)}</dc:creator>'
      '<dc:language>zh</dc:language></metadata>'
      '<manifest>$manifest</manifest>'
      '<spine>$spine</spine></package>',
    );
    add(
      'OEBPS/nav.xhtml',
      '<?xml version="1.0" encoding="utf-8"?>\n'
      '<html xmlns="http://www.w3.org/1999/xhtml" '
      'xmlns:epub="http://www.idpf.org/2007/ops"><head>'
      '<title>${_escape(bookTitle)}</title></head><body>'
      '<nav epub:type="toc"><ol>$navItems</ol></nav></body></html>',
    );
    for (var i = 0; i < chapters.length; i++) {
      add('OEBPS/ch${i + 1}.xhtml', _chapterXhtml(chapters[i]));
    }
    return ZipEncoder().encode(archive);
  }
}

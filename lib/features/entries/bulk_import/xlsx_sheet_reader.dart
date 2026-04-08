import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:xml/xml.dart';

/// Reads the first worksheet in an `.xlsx` (OOXML) file into a sparse rectangular grid.
///
/// Used instead of the `excel` package because it conflicts with `flutter_native_splash` /
/// `image` via incompatible `archive` constraints.
///
/// Cell values are returned as strings (numbers and Excel serial dates converted where
/// detectable). Empty cells are `null`.
List<List<String?>> readFirstXlsxSheet(Uint8List bytes) {
  final archive = ZipDecoder().decodeBytes(bytes);
  String? readUtf8(String path) {
    final f = archive.findFile(path);
    if (f == null) return null;
    return String.fromCharCodes(f.content as List<int>);
  }

  final workbookXml = readUtf8('xl/workbook.xml');
  if (workbookXml == null) {
    throw FormatException('Invalid .xlsx: missing xl/workbook.xml');
  }
  final relsXml = readUtf8('xl/_rels/workbook.xml.rels');
  if (relsXml == null) {
    throw FormatException('Invalid .xlsx: missing xl/_rels/workbook.xml.rels');
  }

  final sheetPath = _firstWorksheetPath(workbookXml, relsXml);
  final sheetXml = readUtf8(sheetPath);
  if (sheetXml == null) {
    throw FormatException('Invalid .xlsx: missing worksheet at $sheetPath');
  }

  final sharedStrings = _readSharedStrings(readUtf8('xl/sharedStrings.xml'));

  final cellMap = <int, Map<int, String>>{};
  var maxRow = 0;
  var maxCol = 0;

  final sheetDoc = XmlDocument.parse(sheetXml);
  for (final c in sheetDoc.findAllElements('c')) {
    final ref = c.getAttribute('r');
    if (ref == null || ref.isEmpty) continue;
    final pos = _parseCellRef(ref);
    if (pos == null) continue;
    final (col, row) = pos;
    if (row > maxRow) maxRow = row;
    if (col > maxCol) maxCol = col;
    final text = _cellText(c, sharedStrings);
    if (text == null || text.isEmpty) continue;
    cellMap.putIfAbsent(row, () => {})[col] = text;
  }

  if (maxRow == 0 && maxCol == 0) {
    return [];
  }

  final grid = <List<String?>>[];
  for (var r = 0; r <= maxRow; r++) {
    final row = List<String?>.filled(maxCol + 1, null);
    final m = cellMap[r];
    if (m != null) {
      for (final e in m.entries) {
        row[e.key] = e.value;
      }
    }
    grid.add(row);
  }
  return grid;
}

String _firstWorksheetPath(String workbookXml, String relsXml) {
  final wb = XmlDocument.parse(workbookXml);
  final rels = XmlDocument.parse(relsXml);
  final targetsById = <String, String>{};
  for (final rel in rels.findAllElements('Relationship')) {
    final id = rel.getAttribute('Id');
    final t = rel.getAttribute('Target');
    if (id != null && t != null) {
      targetsById[id] = t;
    }
  }
  for (final sheet in wb.findAllElements('sheet')) {
    String? rid;
    for (final a in sheet.attributes) {
      if (a.name.local == 'id') {
        rid = a.value;
        break;
      }
    }
    if (rid == null) continue;
    final raw = targetsById[rid];
    if (raw == null) continue;
    var path = raw.replaceAll('\\', '/');
    if (path.startsWith('/')) path = path.substring(1);
    if (path.startsWith('xl/')) return path;
    if (path.startsWith('worksheets/')) return 'xl/$path';
    return 'xl/$path';
  }
  throw FormatException('No worksheet found in workbook');
}

List<String> _readSharedStrings(String? xml) {
  if (xml == null || xml.isEmpty) return const [];
  final doc = XmlDocument.parse(xml);
  final out = <String>[];
  for (final si in doc.findAllElements('si')) {
    final buf = StringBuffer();
    void walk(XmlNode n) {
      if (n is XmlText) {
        buf.write(n.value);
      } else if (n is XmlElement) {
        for (final ch in n.children) {
          walk(ch);
        }
      }
    }

    for (final ch in si.children) {
      walk(ch);
    }
    out.add(buf.toString());
  }
  return out;
}

String? _cellText(XmlElement c, List<String> sharedStrings) {
  final type = c.getAttribute('t');
  final v = c.getElement('v');
  final isEl = c.getElement('is');

  if (type == 'inlineStr' || type == 'str') {
    if (isEl != null) {
      final buf = StringBuffer();
      for (final t in isEl.findAllElements('t')) {
        buf.write(t.innerText);
      }
      final s = buf.toString();
      return s.isEmpty ? null : s;
    }
  }

  if (type == 's') {
    final raw = v?.innerText;
    if (raw == null) return null;
    final i = int.tryParse(raw.trim());
    if (i == null || i < 0 || i >= sharedStrings.length) return raw;
    return sharedStrings[i];
  }

  if (type == 'b') {
    final raw = v?.innerText;
    if (raw == '1') return 'TRUE';
    if (raw == '0') return 'FALSE';
  }

  final raw = v?.innerText.trim();
  if (raw == null || raw.isEmpty) {
    if (isEl != null) {
      final buf = StringBuffer();
      for (final t in isEl.findAllElements('t')) {
        buf.write(t.innerText);
      }
      final s = buf.toString();
      return s.isEmpty ? null : s;
    }
    return null;
  }

  final n = num.tryParse(raw);
  if (n != null) {
    final d = n.toDouble();
    if (_looksLikeExcelDateSerial(d)) {
      return _excelSerialToIsoDate(d);
    }
    if (d == d.roundToDouble() && d.abs() < 1e15) {
      return d.round().toString();
    }
    return raw;
  }
  return raw;
}

bool _looksLikeExcelDateSerial(double d) {
  if (d != d.roundToDouble()) return false;
  final i = d.round();
  return i >= 20000 && i <= 80000;
}

/// Excel 1900 date system (Windows), epoch Dec 30, 1899.
String _excelSerialToIsoDate(double serial) {
  final base = DateTime(1899, 12, 30);
  final dt = base.add(Duration(days: serial.round()));
  final y = dt.year.toString().padLeft(4, '0');
  final m = dt.month.toString().padLeft(2, '0');
  final day = dt.day.toString().padLeft(2, '0');
  return '$y-$m-$day';
}

(int col, int row)? _parseCellRef(String ref) {
  var i = 0;
  while (i < ref.length) {
    final code = ref.codeUnitAt(i);
    if (code >= 65 && code <= 90) {
      i++;
      continue;
    }
    if (code >= 97 && code <= 122) {
      i++;
      continue;
    }
    break;
  }
  if (i == 0) return null;
  final letters = ref.substring(0, i).toUpperCase();
  final rowPart = ref.substring(i);
  final rowNum = int.tryParse(rowPart);
  if (rowNum == null || rowNum < 1) return null;
  var col = 0;
  for (var k = 0; k < letters.length; k++) {
    col = col * 26 + (letters.codeUnitAt(k) - 64);
  }
  return (col - 1, rowNum - 1);
}

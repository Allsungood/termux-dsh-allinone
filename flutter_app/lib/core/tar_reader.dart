import 'dart:convert';
import 'dart:typed_data';

/// Size of a tar block, and of every tar header.
const int tarBlockSize = 512;

/// Header type flags, as defined by POSIX.1-1988 and the GNU extensions.
class TarType {
  const TarType._();

  static const String file = '0';
  static const String hardLink = '1';
  static const String symlink = '2';
  static const String charDevice = '3';
  static const String blockDevice = '4';
  static const String directory = '5';
  static const String fifo = '6';

  /// GNU long name / long link: the entry's *data* is the value for the next
  /// entry.
  static const String gnuLongName = 'L';
  static const String gnuLongLink = 'K';

  /// PAX extended header: the entry's data is a list of `key=value` records
  /// that override fields of the next entry.
  static const String paxHeader = 'x';

  /// PAX global header: archive-wide defaults, deliberately ignored.
  static const String paxGlobalHeader = 'g';
}

/// A single tar header, with the `prefix` field already joined onto the name.
class RawTarHeader {
  const RawTarHeader({
    required this.name,
    required this.mode,
    required this.size,
    required this.typeFlag,
    required this.linkName,
  });

  /// Archive-relative path: `prefix/name`, with `./` removed and any trailing
  /// slash stripped.
  final String name;

  /// Permission bits only; the file type bits are masked off.
  final int mode;

  final int size;
  final String typeFlag;
  final String linkName;

  bool get isDataCarrier =>
      typeFlag == TarType.file ||
      typeFlag == TarType.paxHeader ||
      typeFlag == TarType.gnuLongName ||
      typeFlag == TarType.gnuLongLink;
}

/// Fields a PAX extended header can override.
class PaxOverrides {
  const PaxOverrides({this.path, this.linkPath});

  final String? path;
  final String? linkPath;

  static const PaxOverrides empty = PaxOverrides();

  /// PAX records look like `LENGTH key=value\n`, where LENGTH counts the whole
  /// record including itself. Only `path` and `linkpath` matter here: they are
  /// the two that change how an entry is materialised. Other keys (timestamps,
  /// ownership) are intentionally dropped rather than half-applied.
  static PaxOverrides parse(String record, PaxOverrides previous) {
    String? path = previous.path;
    String? linkPath = previous.linkPath;

    for (final line in record.split('\n')) {
      if (line.isEmpty) continue;
      final space = line.indexOf(' ');
      if (space < 0) continue;
      final assignment = line.substring(space + 1);
      final equals = assignment.indexOf('=');
      if (equals < 0) continue;
      final key = assignment.substring(0, equals);
      final value = assignment.substring(equals + 1);
      switch (key) {
        case 'path':
          path = value;
        case 'linkpath':
          linkPath = value;
      }
    }
    return PaxOverrides(path: path, linkPath: linkPath);
  }
}

/// Raised when an archive cannot be understood.
///
/// The message always names the concrete problem, because the setup log is the
/// only diagnostic a user can send back.
class TarFormatException implements Exception {
  TarFormatException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Parses one 512-byte header block.
///
/// Returns `null` for the all-zero block that terminates an archive.
///
/// This is deliberately a hand-written reader rather than a general archive
/// package: rebuilding a root filesystem needs the raw `typeflag`, because a
/// symlink target is resolved relative to the link's own directory while a hard
/// link target is relative to the archive root. Decoders that surface both as
/// "a link name" make them indistinguishable, and confusing the two silently
/// corrupts the rootfs — a hard link stored as `usr/bin/perl` would become a
/// symlink resolving to `usr/bin/usr/bin/perl`.
RawTarHeader? parseTarHeader(Uint8List block, {int offset = 0}) {
  if (block.length < tarBlockSize) {
    throw TarFormatException(
      '归档已损坏：文件末尾出现了不完整的头部（偏移 $offset）。',
    );
  }
  if (_isZeroBlock(block)) return null;

  _verifyChecksum(block, offset);

  final rawType = String.fromCharCode(block[156]);
  // Old writers used NUL for a regular file.
  final typeFlag = rawType == '\u0000' ? TarType.file : rawType;

  return RawTarHeader(
    name: _readName(block),
    mode: _readNumber(block, 100, 8) & 0xFFF,
    size: _readNumber(block, 124, 12),
    typeFlag: typeFlag,
    linkName: _readCString(block, 157, 100),
  );
}

/// Fails unless [typeFlag] is one of the four kinds a distro rootfs contains.
void assertSupportedType(String typeFlag, String name) {
  switch (typeFlag) {
    case TarType.file:
    case TarType.directory:
    case TarType.symlink:
    case TarType.hardLink:
      return;
    case TarType.charDevice:
    case TarType.blockDevice:
      throw TarFormatException(
        '归档包含设备节点（"$name"），无法在未 root 的安卓上还原。',
      );
    case TarType.fifo:
      throw TarFormatException('归档包含 FIFO（"$name"），暂不支持。');
    default:
      throw TarFormatException(
        '归档包含未知条目类型 "$typeFlag"（"$name"），'
        '为避免生成损坏的系统，已停止安装。',
      );
  }
}

bool _isZeroBlock(Uint8List block) {
  for (var i = 0; i < tarBlockSize; i++) {
    if (block[i] != 0) return false;
  }
  return true;
}

/// The header checksum is the sum of every header byte with the checksum field
/// itself read as eight spaces.
///
/// Verifying it turns a truncated download into a precise message instead of a
/// strange failure much later. This was checked against the real Ubuntu base
/// archive before being relied on: every one of its headers matches.
void _verifyChecksum(Uint8List block, int offset) {
  final stored = _readNumber(block, 148, 8);
  if (stored == 0) return; // Some writers leave it unset.

  var sum = 0;
  for (var i = 0; i < tarBlockSize; i++) {
    sum += (i >= 148 && i < 156) ? 0x20 : block[i];
  }
  if (sum != stored) {
    throw TarFormatException(
      '归档校验和错误（偏移 $offset：期望 $stored，实际 $sum）。'
      '文件很可能下载不完整，请重新安装。',
    );
  }
}

String _readName(Uint8List block) {
  final name = _readCString(block, 0, 100);
  final prefix = _readCString(block, 345, 155);
  return normaliseTarPath(prefix.isEmpty ? name : '$prefix/$name');
}

/// Strips leading `./` and any trailing slash.
String normaliseTarPath(String path) {
  var value = path;
  while (value.startsWith('./')) {
    value = value.substring(2);
  }
  while (value.endsWith('/')) {
    value = value.substring(0, value.length - 1);
  }
  return value;
}

String _readCString(Uint8List block, int start, int length) {
  final end = (start + length).clamp(0, block.length);
  var stop = start;
  while (stop < end && block[stop] != 0) {
    stop++;
  }
  if (stop == start) return '';
  return utf8.decode(
    Uint8List.sublistView(block, start, stop),
    allowMalformed: true,
  );
}

/// Octal ASCII, or GNU base-256 when the high bit of the first byte is set.
int _readNumber(Uint8List block, int start, int length) {
  if (start >= block.length) return 0;
  if (block[start] & 0x80 != 0) {
    var value = block[start] & 0x7F;
    for (var i = start + 1; i < start + length && i < block.length; i++) {
      value = (value << 8) | block[i];
    }
    return value;
  }

  var value = 0;
  var seen = false;
  for (var i = start; i < start + length && i < block.length; i++) {
    final byte = block[i];
    if (byte == 0 || byte == 0x20) {
      if (seen) break;
      continue;
    }
    if (byte < 0x30 || byte > 0x37) break;
    value = value * 8 + (byte - 0x30);
    seen = true;
  }
  return value;
}

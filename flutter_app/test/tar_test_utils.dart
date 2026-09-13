import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

/// A tar member used by the tests.
class TarSpec {
  TarSpec({
    required this.name,
    this.type = '0',
    // 0644 and 0755 spelled in decimal: Dart has no octal literal syntax, and a
    // default parameter value must be a compile-time constant.
    this.mode = 420,
    this.linkName = '',
    this.data = '',
    this.prefix = '',
  });

  final String name;
  final String type;
  final int mode;
  final String linkName;
  final String data;

  /// ustar `prefix` field, used to verify long-path handling.
  final String prefix;
}

const int _block = 512;

/// Builds a tar archive by hand.
///
/// The bytes are written directly rather than through an encoder so the tests
/// can pin every field that matters — in particular `typeflag`, which is the
/// distinction the extractor depends on and which higher-level encoders tend to
/// normalise away.
Uint8List buildTar(List<TarSpec> specs, {bool twoZeroBlocks = true}) {
  final out = BytesBuilder();

  for (final spec in specs) {
    final data = utf8.encode(spec.data);
    out.add(_header(spec, data.length));
    if (data.isNotEmpty) {
      out.add(data);
      final padding = (_block - (data.length % _block)) % _block;
      if (padding > 0) out.add(Uint8List(padding));
    }
  }

  out.add(Uint8List(twoZeroBlocks ? _block * 2 : _block));
  return out.toBytes();
}

Uint8List _header(TarSpec spec, int size) {
  final header = Uint8List(_block);

  void writeString(int offset, int length, String value) {
    final bytes = utf8.encode(value);
    final count = bytes.length > length ? length : bytes.length;
    header.setRange(offset, offset + count, bytes);
  }

  void writeOctal(int offset, int length, int value) {
    final text = value.toRadixString(8).padLeft(length - 1, '0');
    writeString(offset, length - 1, text);
    header[offset + length - 1] = 0;
  }

  writeString(0, 100, spec.name);
  writeOctal(100, 8, spec.mode);
  writeOctal(108, 8, 0); // uid
  writeOctal(116, 8, 0); // gid
  writeOctal(124, 12, size);
  writeOctal(136, 12, 0); // mtime
  // The checksum field is read as eight spaces while the checksum is computed.
  for (var i = 148; i < 156; i++) {
    header[i] = 0x20;
  }
  header[156] = spec.type.codeUnitAt(0);
  writeString(157, 100, spec.linkName);
  writeString(257, 6, 'ustar');
  header[262] = 0;
  writeString(263, 2, '00');
  writeString(345, 155, spec.prefix);

  var sum = 0;
  for (final byte in header) {
    sum += byte;
  }
  writeString(148, 6, sum.toRadixString(8).padLeft(6, '0'));
  header[154] = 0;
  header[155] = 0x20;

  return header;
}

/// Builds a PAX extended-header payload.
///
/// GNU tar prefixes *every* line with its own length. The real Ubuntu base
/// archive stores e.g. `30 atime=1788826552.516239391\n29 ctime=...\n`, and
/// none of its records carry `path`; the builder reproduces that shape.
String buildPaxRecord(Map<String, String> fields) {
  final out = StringBuffer();
  fields.forEach((key, value) {
    final body = '$key=$value\n';
    var length = body.length + 2;
    while (true) {
      final total = '$length '.length + body.length;
      if (total == length) break;
      length = total;
    }
    out.write('$length $body');
  });
  return out.toString();
}

/// Recomputes a header block's checksum after the block has been mutated.
Uint8List resealHeader(Uint8List block) {
  final copy = Uint8List.fromList(block);
  for (var i = 148; i < 156; i++) {
    copy[i] = 0x20;
  }
  var sum = 0;
  for (final byte in copy) {
    sum += byte;
  }
  copy.setRange(148, 154, utf8.encode(sum.toRadixString(8).padLeft(6, '0')));
  copy[154] = 0;
  copy[155] = 0x20;
  return copy;
}

/// A spec plus a PAX header carrying the same name, mirroring how the Ubuntu
/// archive stores entries.
List<TarSpec> paxWrapped(TarSpec spec, {String? paxPath, String? paxLink}) {
  final fields = <String, String>{'path': paxPath ?? spec.name};
  if (paxLink != null) fields['linkpath'] = paxLink;

  return [
    TarSpec(
      name: 'PaxHeaders/${spec.name}',
      type: 'x',
      data: buildPaxRecord(fields),
    ),
    // The following header deliberately carries a truncated/placeholder name to
    // prove the PAX value is what wins.
    TarSpec(
      name: 'placeholder',
      type: spec.type,
      mode: spec.mode,
      linkName: paxLink ?? spec.linkName,
      data: spec.data,
    ),
  ];
}

/// Creates a throwaway directory that the caller is responsible for deleting.
Directory makeTempDir(String label) {
  return Directory.systemTemp.createTempSync('termux_allinone_$label');
}

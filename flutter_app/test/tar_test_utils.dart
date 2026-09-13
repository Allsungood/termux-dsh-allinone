import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

/// A tar member used by the tests.
class TarSpec {
  TarSpec({
    required this.name,
    this.type = '0',
    this.mode = 0o644,
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

/// Builds a PAX extended-header record (`LENGTH key=value\n`).
///
/// The real Ubuntu base archive writes one of these before *every* entry, so
/// the tests must cover that shape rather than only plain ustar.
String buildPaxRecord(Map<String, String> fields) {
  final body = StringBuffer();
  fields.forEach((key, value) => body.write('$key=$value\n'));
  final payload = body.toString();

  var length = payload.length + 2;
  while (true) {
    final total = '$length '.length + payload.length;
    if (total == length) return '$length $payload';
    length = total;
  }
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

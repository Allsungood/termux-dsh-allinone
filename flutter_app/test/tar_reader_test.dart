import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:termux_dsh_allinone/core/tar_reader.dart';

import 'tar_test_utils.dart';

Uint8List firstHeader(List<TarSpec> specs) {
  return Uint8List.sublistView(buildTar(specs), 0, tarBlockSize);
}

void main() {
  group('parseTarHeader', () {
    test('reads a regular file', () {
      final header = parseTarHeader(
        firstHeader([
          TarSpec(name: 'usr/bin/tool', type: '0', mode: octal(755), data: 'EXEC'),
        ]),
      )!;

      expect(header.name, 'usr/bin/tool');
      expect(header.typeFlag, TarType.file);
      expect(header.mode, octal(755));
      expect(header.size, 4);
    });

    test('reads a directory', () {
      final header = parseTarHeader(
        firstHeader([TarSpec(name: 'usr/bin', type: '5', mode: octal(755))]),
      )!;

      expect(header.typeFlag, TarType.directory);
      expect(header.name, 'usr/bin');
      expect(header.mode, octal(755));
    });

    test('distinguishes a symlink target from a hard link target', () {
      // This is the distinction the whole extractor hinges on: a symlink target
      // is relative to the link's own directory, a hard link target to the
      // archive root. Conflating them corrupts the rootfs.
      final symlink = parseTarHeader(
        firstHeader([TarSpec(name: 'bin', type: '2', linkName: 'usr/bin')]),
      )!;
      expect(symlink.typeFlag, TarType.symlink);
      expect(symlink.linkName, 'usr/bin');

      final hardLink = parseTarHeader(
        firstHeader([
          TarSpec(
            name: 'usr/bin/uncompress',
            type: '1',
            linkName: 'usr/bin/gunzip',
          ),
        ]),
      )!;
      expect(hardLink.typeFlag, TarType.hardLink);
      expect(hardLink.linkName, 'usr/bin/gunzip');
    });

    test('joins the ustar prefix to the name', () {
      final header = parseTarHeader(
        firstHeader([
          TarSpec(
            name: 'libpython3.12.so.1.0',
            prefix: 'usr/lib/aarch64-linux-gnu',
            data: 'x',
          ),
        ]),
      )!;

      expect(header.name, 'usr/lib/aarch64-linux-gnu/libpython3.12.so.1.0');
    });

    test('normalises leading ./ and trailing /', () {
      final header = parseTarHeader(
        firstHeader([TarSpec(name: './usr/bin/', type: '5')]),
      )!;

      expect(header.name, 'usr/bin');
    });

    test('treats a NUL type flag as a regular file', () {
      final block = Uint8List.fromList(
        firstHeader([TarSpec(name: 'old/style', data: 'x')]),
      );
      block[156] = 0;

      final header = parseTarHeader(block)!;
      expect(header.typeFlag, TarType.file);
      expect(header.name, 'old/style');
    });

    test('returns null for the terminating zero block', () {
      final block = Uint8List(tarBlockSize);
      expect(parseTarHeader(block), isNull);
    });

    test('rejects a corrupt checksum', () {
      final block = firstHeader([TarSpec(name: 'etc/os-release', data: 'x')]);
      final corrupt = Uint8List.fromList(block);
      corrupt.setRange(148, 154, '000000'.codeUnits);

      expect(
        () => parseTarHeader(corrupt),
        throwsA(
          isA<TarFormatException>().having(
            (error) => error.message,
            'message',
            contains('校验和'),
          ),
        ),
      );
    });

    test('rejects a header that is not a full block', () {
      expect(
        () => parseTarHeader(Uint8List(100)),
        throwsA(isA<TarFormatException>()),
      );
    });
  });

  group('assertSupportedType', () {
    test('accepts the four kinds a distro rootfs contains', () {
      for (final type in [
        TarType.file,
        TarType.directory,
        TarType.symlink,
        TarType.hardLink,
      ]) {
        expect(() => assertSupportedType(type, 'x'), returnsNormally);
      }
    });

    test('rejects device nodes', () {
      expect(
        () => assertSupportedType(TarType.charDevice, 'dev/null'),
        throwsA(
          isA<TarFormatException>().having(
            (error) => error.message,
            'message',
            contains('设备节点'),
          ),
        ),
      );
    });

    test('rejects FIFOs and unknown types', () {
      expect(
        () => assertSupportedType(TarType.fifo, 'var/run/x'),
        throwsA(isA<TarFormatException>()),
      );
      expect(
        () => assertSupportedType('Z', 'weird'),
        throwsA(
          isA<TarFormatException>().having(
            (error) => error.message,
            'message',
            contains('未知条目类型'),
          ),
        ),
      );
    });
  });

  group('PaxOverrides.parse', () {
    test('extracts path and linkpath', () {
      final record = buildPaxRecord({
        'path': 'usr/bin/uncompress',
        'linkpath': 'usr/bin/gunzip',
      });

      final overrides = PaxOverrides.parse(record, PaxOverrides.empty);
      expect(overrides.path, 'usr/bin/uncompress');
      expect(overrides.linkPath, 'usr/bin/gunzip');
    });

    test('keeps a previous value when the record omits the key', () {
      const previous = PaxOverrides(path: 'kept');
      final overrides = PaxOverrides.parse(
        buildPaxRecord({'mtime': '1700000000'}),
        previous,
      );

      expect(overrides.path, 'kept');
      expect(overrides.linkPath, isNull);
    });

    test('ignores records it cannot parse', () {
      expect(
        PaxOverrides.parse('garbage', PaxOverrides.empty).path,
        isNull,
      );
    });
  });

  group('normaliseTarPath', () {
    test('strips repeated ./ and trailing slashes', () {
      expect(normaliseTarPath('././usr//bin/'), 'usr//bin');
      expect(normaliseTarPath('usr/bin'), 'usr/bin');
      expect(normaliseTarPath('usr/bin/'), 'usr/bin');
    });
  });
}

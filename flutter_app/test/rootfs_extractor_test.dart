import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:termux_dsh_allinone/core/rootfs_extractor.dart';
import 'package:termux_dsh_allinone/core/tar_reader.dart';

import 'tar_test_utils.dart';

/// Mirrors the shape of the real Ubuntu base archive: a merged-/usr symlink, an
/// executable, a plain file, and a hard link.
///
/// Note that `bin` appears only as a symlink. In a merged-/usr rootfs `bin` is
/// never also a directory, which is exactly why the extractor must not create
/// it as one.
List<TarSpec> rootfsLikeSpecs() => [
  TarSpec(name: 'etc', type: '5', mode: 0o755),
  TarSpec(name: 'etc/alternatives', type: '5', mode: 0o755),
  TarSpec(name: 'usr', type: '5', mode: 0o755),
  TarSpec(name: 'usr/bin', type: '5', mode: 0o755),
  TarSpec(name: 'bin', type: '2', linkName: 'usr/bin'),
  TarSpec(name: 'lib', type: '2', linkName: 'usr/lib'),
  TarSpec(
    name: 'etc/alternatives/awk',
    type: '2',
    linkName: '/usr/bin/mawk',
  ),
  TarSpec(name: 'usr/bin/gunzip', type: '0', mode: 0o755, data: 'GUNZIP'),
  TarSpec(
    name: 'usr/bin/uncompress',
    type: '1',
    linkName: 'usr/bin/gunzip',
  ),
  TarSpec(name: 'usr/bin/tool', type: '0', mode: 0o755, data: 'EXEC'),
  TarSpec(name: 'etc/config', type: '0', mode: 0o644, data: 'CONF'),
  TarSpec(name: 'etc/secret', type: '0', mode: 0o600, data: 'SECRET'),
];

void main() {
  group('RootfsExtractor.extract', () {
    late Directory work;
    late Directory destination;

    setUp(() {
      work = makeTempDir('extract');
      destination = Directory('${work.path}/rootfs');
    });

    tearDown(() {
      if (work.existsSync()) work.deleteSync(recursive: true);
    });

    Future<ExtractionReport> extractSpecs(List<TarSpec> specs) async {
      final tarball = File('${work.path}/rootfs.tar.gz');
      await tarball.writeAsBytes(gzip.encode(buildTar(specs)));
      return RootfsExtractor.extract(
        tarball: tarball,
        destination: destination,
      );
    }

    test('recreates the merged-/usr symlink instead of a plain file', () async {
      await extractSpecs(rootfsLikeSpecs());

      final bin = Link('${destination.path}/bin');
      expect(
        FileSystemEntity.typeSync(bin.path, followLinks: false),
        FileSystemEntityType.link,
        reason: 'bin must be a symlink; as a regular file /bin/sh would vanish',
      );
      expect(bin.targetSync(), 'usr/bin');
    });

    test('keeps absolute symlink targets absolute for PRoot to resolve', () async {
      await extractSpecs(rootfsLikeSpecs());

      final alternatives = Link(
        '${destination.path}/etc/alternatives/awk',
      );
      expect(alternatives.targetSync(), '/usr/bin/mawk');
    });

    test('restores executable bits', () async {
      await extractSpecs(rootfsLikeSpecs());

      final exec = File('${destination.path}/usr/bin/tool').statSync();
      expect(exec.mode & 0o111, isNot(0), reason: 'binaries must be executable');
      expect(exec.mode & 0o777, 0o755);

      final plain = File('${destination.path}/etc/config').statSync();
      expect(plain.mode & 0o111, 0, reason: 'data files must not be executable');

      final restricted = File('${destination.path}/etc/secret').statSync();
      expect(restricted.mode & 0o777, 0o600);
    });

    test('restores file contents', () async {
      await extractSpecs(rootfsLikeSpecs());

      expect(
        await File('${destination.path}/usr/bin/gunzip').readAsString(),
        'GUNZIP',
      );
      expect(
        await File('${destination.path}/etc/config').readAsString(),
        'CONF',
      );
    });

    test('resolves a hard link to the same bytes as its target', () async {
      await extractSpecs(rootfsLikeSpecs());

      final linked = File('${destination.path}/usr/bin/uncompress');
      expect(await linked.exists(), isTrue);
      expect(await linked.readAsString(), 'GUNZIP');
    });

    test('reports what it created', () async {
      final report = await extractSpecs(rootfsLikeSpecs());

      expect(report.files, 4);
      expect(report.directories, 4);
      expect(report.symlinks, 3);
      expect(report.hardLinks, 1);
    });

    test('refuses to write outside the destination', () async {
      expect(
        () => extractSpecs([TarSpec(name: '../escape', data: 'x')]),
        throwsA(
          isA<TarFormatException>().having(
            (error) => error.message,
            'message',
            contains('不安全'),
          ),
        ),
      );
      expect(File('${work.path}/escape').existsSync(), isFalse);
    });

    test('surfaces a truncated download as a format error', () async {
      final tarball = File('${work.path}/broken.tar.gz');
      final full = buildTar([TarSpec(name: 'a/b', data: 'payload')]);
      // Cut inside the entry's payload, the way an interrupted download would.
      await tarball.writeAsBytes(gzip.encode(full.sublist(0, 515)));

      expect(
        () => RootfsExtractor.extract(
          tarball: tarball,
          destination: destination,
        ),
        throwsA(isA<TarFormatException>()),
      );
    });

    test('surfaces a file that is not gzip at all', () async {
      final tarball = File('${work.path}/not-gzip.tar.gz');
      await tarball.writeAsBytes(List<int>.filled(4096, 0x41));

      expect(
        () => RootfsExtractor.extract(
          tarball: tarball,
          destination: destination,
        ),
        throwsA(
          isA<TarFormatException>().having(
            (error) => error.message,
            'message',
            contains('解压归档失败'),
          ),
        ),
      );
    });

    test('honours PAX headers, which is how the real Ubuntu archive is stored', () async {
      // The Ubuntu base tarball writes a PAX extended header before every one of
      // its 3413 entries, so this path must work.
      final specs = [
        ...paxWrapped(TarSpec(name: 'usr', type: '5', mode: 0o755)),
        ...paxWrapped(TarSpec(name: 'usr/bin', type: '5', mode: 0o755)),
        ...paxWrapped(TarSpec(name: 'bin', type: '2', linkName: 'usr/bin')),
        ...paxWrapped(
          TarSpec(name: 'usr/bin/gunzip', type: '0', mode: 0o755, data: 'GZ'),
        ),
      ];

      final report = await extractSpecs(specs);

      expect(report.directories, 2);
      expect(report.symlinks, 1);
      expect(report.files, 1);
      expect(
        Directory('${destination.path}/usr/bin').existsSync(),
        isTrue,
        reason: 'the PAX path must win over the placeholder header name',
      );
      expect(
        Link('${destination.path}/bin').targetSync(),
        'usr/bin',
      );
      expect(
        await File('${destination.path}/usr/bin/gunzip').readAsString(),
        'GZ',
      );
      expect(
        Directory('${destination.path}/placeholder').existsSync(),
        isFalse,
        reason: 'the placeholder name must never be used',
      );
    });

    test('applies a PAX linkpath to a hard link', () async {
      final specs = [
        ...paxWrapped(
          TarSpec(name: 'usr/bin/gunzip', type: '0', mode: 0o755, data: 'GZ'),
        ),
        ...paxWrapped(
          TarSpec(name: 'usr/bin/uncompress', type: '1'),
          paxLink: 'usr/bin/gunzip',
        ),
      ];

      await extractSpecs(specs);

      expect(
        await File('${destination.path}/usr/bin/uncompress').readAsString(),
        'GZ',
      );
    });

    test('reports a missing archive clearly', () async {
      expect(
        () => RootfsExtractor.extract(
          tarball: File('${work.path}/absent.tar.gz'),
          destination: destination,
        ),
        throwsA(
          isA<TarFormatException>().having(
            (error) => error.message,
            'message',
            contains('找不到归档文件'),
          ),
        ),
      );
    });
  });
}

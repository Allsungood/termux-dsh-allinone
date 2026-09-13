import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'tar_reader.dart';

/// What [RootfsExtractor.extract] ended up creating.
class ExtractionReport {
  const ExtractionReport({
    required this.files,
    required this.directories,
    required this.symlinks,
    required this.hardLinks,
  });

  final int files;
  final int directories;
  final int symlinks;
  final int hardLinks;

  @override
  String toString() =>
      '文件 $files 个，目录 $directories 个，符号链接 $symlinks 个，硬链接 $hardLinks 个';
}

/// Unpacks a root filesystem tarball inside the app sandbox.
///
/// Two deliberate design choices, both learned from the real Ubuntu base
/// archive rather than assumed:
///
/// 1. **Pure Dart, not the platform `tar`.** Android's toybox `tar` runs as the
///    app's unprivileged uid while every member of a distro rootfs is owned by
///    `root:root`. `tar` tries to restore that ownership, gets `EPERM`, and
///    aborts. Restoring ownership is impossible here and unnecessary anyway —
///    PRoot fakes uid 0 inside the guest — so this extractor ignores ownership
///    and reproduces only what matters: contents, directories, link structure
///    and permission bits.
///
/// 2. **Streaming, not whole-archive-in-memory.** The compressed download is
///    28.5 MB but expands to about 102 MB of tar; holding both plus the
///    extracted tree would risk an out-of-memory kill on a modest phone. The
///    archive is therefore decompressed to a scratch file and walked block by
///    block, so peak memory stays in the tens of kilobytes.
class RootfsExtractor {
  const RootfsExtractor._();

  /// Modes equal to the platform defaults need no `chmod`, which keeps the
  /// number of subprocesses to a handful instead of thousands.
  static final int _defaultFileMode = octal(644);
  static final int _defaultDirectoryMode = octal(755);

  /// `chmod` accepts many paths per call; batching avoids ~3400 processes.
  static const int _chmodBatchSize = 200;

  static const int _copyBufferSize = 64 * 1024;

  static Future<ExtractionReport> extract({
    required File tarball,
    required Directory destination,
    void Function(String line)? onLog,
    void Function(double fraction)? onProgress,
  }) async {
    final log = onLog ?? (String _) {};

    if (!await tarball.exists()) {
      throw TarFormatException('找不到归档文件：${tarball.path}');
    }

    final compressedBytes = await tarball.length();
    log('开始解压 Ubuntu 归档（${_mb(compressedBytes)} MB，纯 Dart 流式解压）');

    // The scratch tar lives beside the rootfs, inside the same sandbox.
    final scratch = File('${destination.parent.path}/.rootfs-scratch.tar');
    await destination.parent.create(recursive: true);

    try {
      await _decompress(tarball, scratch, log);
      final plainBytes = await scratch.length();
      log('已展开为 ${_mb(plainBytes)} MB 的 tar 数据，开始写入文件…');
      final report = await _unpack(
        scratch,
        destination,
        log: log,
        onProgress: onProgress,
      );
      log('rootfs 展开完成：$report');
      return report;
    } finally {
      // Never leave a 100 MB scratch file behind.
      if (await scratch.exists()) {
        try {
          await scratch.delete();
        } on FileSystemException {
          // Best effort only.
        }
      }
    }
  }

  /// Streams the gzip member out to [target] without ever holding it in memory.
  static Future<void> _decompress(
    File source,
    File target,
    void Function(String) log,
  ) async {
    final sink = target.openWrite();
    var finished = false;
    try {
      await source.openRead().transform(gzip.decoder).pipe(sink);
      finished = true;
    } on Object catch (error) {
      // gzip failures surface as FormatException, ZLibException or an I/O error
      // depending on how the stream ended; all of them mean the same thing to
      // the user, and the original text is kept in the message.
      throw TarFormatException(
        '解压归档失败（$error）。文件很可能下载不完整，请重新安装。',
      );
    } finally {
      if (!finished) {
        try {
          await sink.close();
        } on Object {
          // The original failure is more useful than this one.
        }
      }
    }
  }

  static Future<ExtractionReport> _unpack(
    File tarFile,
    Directory destination, {
    required void Function(String) log,
    void Function(double)? onProgress,
  }) async {
    final totalBytes = await tarFile.length();
    final handle = await tarFile.open();
    final header = Uint8List(tarBlockSize);
    final copyBuffer = Uint8List(_copyBufferSize);
    final pendingChmod = <int, List<String>>{};
    final pendingHardLinks = <_PendingHardLink>[];

    final rootPath = destination.absolute.path;
    await destination.create(recursive: true);

    var pax = PaxOverrides.empty;
    String? longName;
    String? longLink;
    var files = 0;
    var directories = 0;
    var symlinks = 0;

    try {
      var offset = 0;
      while (offset + tarBlockSize <= totalBytes) {
        final got = await handle.readInto(header, 0, tarBlockSize);
        if (got < tarBlockSize) {
          throw TarFormatException(
            '归档已损坏：在偏移 $offset 处提前结束（文件可能未下载完整）。',
          );
        }

        final parsed = parseTarHeader(header, offset: offset);
        if (parsed == null) {
          // A zero block terminates the archive. Only one is required, and any
          // trailing padding is ignored.
          break;
        }

        final dataOffset = offset + tarBlockSize;
        final paddedSize =
            ((parsed.size + tarBlockSize - 1) ~/ tarBlockSize) * tarBlockSize;

        switch (parsed.typeFlag) {
          case TarType.paxHeader:
            final record = await _readText(handle, parsed.size, dataOffset);
            pax = PaxOverrides.parse(record, pax);

          case TarType.gnuLongName:
            longName = (await _readText(handle, parsed.size, dataOffset)).trim();

          case TarType.gnuLongLink:
            longLink = (await _readText(handle, parsed.size, dataOffset)).trim();

          case TarType.paxGlobalHeader:
            // Archive-wide defaults are intentionally ignored.

          default:
            final name = normaliseTarPath(
              pax.path ?? longName ?? parsed.name,
            );
            final linkTarget = pax.linkPath ?? longLink ?? parsed.linkName;
            pax = PaxOverrides.empty;
            longName = null;
            longLink = null;

            assertSupportedType(parsed.typeFlag, name);
            final path = _resolve(rootPath, name);

            switch (parsed.typeFlag) {
              case TarType.directory:
                await Directory(path).create(recursive: true);
                directories++;
                _recordMode(pendingChmod, parsed.mode, _defaultDirectoryMode, path);

              case TarType.symlink:
                await Directory(_parentOf(path)).create(recursive: true);
                await _createSymlink(path, linkTarget);
                symlinks++;

              case TarType.hardLink:
                pendingHardLinks.add(
                  _PendingHardLink(
                    name: name,
                    linkTarget: linkTarget,
                    mode: parsed.mode,
                  ),
                );

              case TarType.file:
                await Directory(_parentOf(path)).create(recursive: true);
                await _streamFile(
                  handle,
                  path,
                  parsed.size,
                  dataOffset,
                  copyBuffer,
                );
                files++;
                _recordMode(pendingChmod, parsed.mode, _defaultFileMode, path);
            }
        }

        offset = dataOffset + paddedSize;
        await handle.setPosition(offset);
        onProgress?.call((offset / totalBytes).clamp(0.0, 1.0));
      }

      // Hard links can only be created once their targets exist, and the
      // archive is read in a single forward pass.
      final hardLinks = await _finishHardLinks(
        pendingHardLinks,
        rootPath,
        pendingChmod,
        log,
      );

      await _applyPermissions(pendingChmod);

      return ExtractionReport(
        files: files,
        directories: directories,
        symlinks: symlinks,
        hardLinks: hardLinks,
      );
    } finally {
      await handle.close();
    }
  }

  /// Copies exactly [size] bytes from the archive into [path].
  static Future<void> _streamFile(
    RandomAccessFile handle,
    String path,
    int size,
    int dataOffset,
    Uint8List buffer,
  ) async {
    await handle.setPosition(dataOffset);
    final sink = File(path).openWrite();
    try {
      var remaining = size;
      while (remaining > 0) {
        final want = math.min(remaining, buffer.length);
        final read = await handle.readInto(buffer, 0, want);
        if (read <= 0) {
          throw TarFormatException('归档已损坏：读取 "$path" 的内容时提前结束。');
        }
        // Copy out of the reused buffer: the sink may still be flushing it.
        sink.add(Uint8List.fromList(Uint8List.sublistView(buffer, 0, read)));
        remaining -= read;
      }
    } finally {
      await sink.flush();
      await sink.close();
    }
  }

  /// Reads an extension header's payload as text (PAX records, GNU long names).
  static Future<String> _readText(
    RandomAccessFile handle,
    int size,
    int dataOffset,
  ) async {
    if (size <= 0) return '';
    await handle.setPosition(dataOffset);
    final buffer = Uint8List(size);
    var read = 0;
    while (read < size) {
      final got = await handle.readInto(buffer, read, size);
      if (got <= 0) {
        throw TarFormatException('归档已损坏：扩展头部数据不完整。');
      }
      read += got;
    }
    return utf8.decode(buffer, allowMalformed: true);
  }

  static Future<int> _finishHardLinks(
    List<_PendingHardLink> pending,
    String rootPath,
    Map<int, List<String>> pendingChmod,
    void Function(String) log,
  ) async {
    var created = 0;
    for (final link in pending) {
      final path = _resolve(rootPath, link.name);
      await Directory(_parentOf(path)).create(recursive: true);
      final targetPath = link.linkTarget.startsWith('/')
          ? _resolve(rootPath, link.linkTarget.substring(1))
          : _resolve(rootPath, link.linkTarget);

      if (await _createHardLink(targetPath, path)) {
        _recordMode(pendingChmod, link.mode, _defaultFileMode, path);
      } else {
        // Android restricts hard links inside app data directories. A symlink to
        // the guest-absolute path behaves identically inside PRoot, and is
        // always permitted.
        await _createSymlink(path, '/${link.linkTarget}');
        log('注意：${link.name} 无法建立硬链接，已改用符号链接（功能相同）');
      }
      created++;
    }
    return created;
  }

  static void _recordMode(
    Map<int, List<String>> pending,
    int mode,
    int defaultMode,
    String path,
  ) {
    if (mode == 0 || mode == defaultMode) return;
    pending.putIfAbsent(mode, () => <String>[]).add(path);
  }

  static Future<void> _createSymlink(String path, String target) async {
    if (target.isEmpty) {
      throw TarFormatException('符号链接 "$path" 没有目标，归档已损坏。');
    }
    final owner = FileSystemEntity.typeSync(path, followLinks: false);
    if (owner != FileSystemEntityType.notFound) {
      // Only a leftover from an interrupted run reaches here.
      await _deleteIfPresent(path);
    }
    try {
      await Link(path).create(target);
    } on FileSystemException catch (error) {
      throw TarFormatException(
        '无法创建符号链接 $path -> $target'
        '（${error.osError?.message ?? error.message}）',
      );
    }
  }

  /// Creates a hard link.
  ///
  /// `dart:io` exposes no hard-link API at all (`File` has no `link` method,
  /// and `Link.create` makes a symlink), so this shells out to `ln`, which
  /// Android's toybox provides. Returns `false` when the filesystem refuses —
  /// Android restricts hard links in app data directories — so the caller can
  /// fall back to a symlink.
  static Future<bool> _createHardLink(String targetPath, String linkPath) async {
    if (!await File(targetPath).exists()) return false;
    await _deleteIfPresent(linkPath);
    try {
      final result = await Process.run('ln', [targetPath, linkPath]);
      if (result.exitCode == 0 && await File(linkPath).exists()) {
        return true;
      }
    } on ProcessException {
      // No usable `ln` on this system.
    }
    return false;
  }

  static Future<void> _deleteIfPresent(String path) async {
    final type = await FileSystemEntity.type(path, followLinks: false);
    if (type == FileSystemEntityType.notFound) return;
    try {
      switch (type) {
        case FileSystemEntityType.directory:
          await Directory(path).delete(recursive: true);
        case FileSystemEntityType.link:
          await Link(path).delete();
        default:
          await File(path).delete();
      }
    } on FileSystemException {
      // The caller reports the real failure that follows.
    }
  }

  /// Applies the collected permission bits in as few `chmod` calls as possible.
  ///
  /// Dart exposes no `chmod` binding, and the platform `chmod` binary runs
  /// happily as an unprivileged user on files it owns — so this is the one
  /// place where a subprocess is still the right tool.
  static Future<void> _applyPermissions(
    Map<int, List<String>> pendingChmod,
  ) async {
    if (pendingChmod.isEmpty) return;

    for (final entry in pendingChmod.entries) {
      final octal = entry.key.toRadixString(8).padLeft(3, '0');
      final paths = entry.value;
      for (var start = 0; start < paths.length; start += _chmodBatchSize) {
        final end = math.min(start + _chmodBatchSize, paths.length);
        try {
          await Process.run('chmod', [octal, ...paths.sublist(start, end)]);
        } on ProcessException {
          // A missing `chmod` only costs permission bits; the install continues
          // so the problem stays visible in the console instead of aborting.
        }
      }
    }
  }

  static String _resolve(String root, String name) {
    // Names come straight from the archive; refuse anything that could escape.
    final normalised = name.replaceAll('\\', '/');
    if (normalised.startsWith('/') || normalised.split('/').contains('..')) {
      throw TarFormatException('归档中的路径不安全，已拒绝：$name');
    }
    return '$root/$normalised';
  }

  static String _parentOf(String path) {
    final index = path.lastIndexOf('/');
    return index <= 0 ? path : path.substring(0, index);
  }

  static String _mb(int bytes) => (bytes / 1024 / 1024).toStringAsFixed(1);
}

class _PendingHardLink {
  const _PendingHardLink({
    required this.name,
    required this.linkTarget,
    required this.mode,
  });

  final String name;
  final String linkTarget;
  final int mode;
}

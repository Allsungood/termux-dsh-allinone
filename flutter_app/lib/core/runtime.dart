import 'dart:async';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:path_provider/path_provider.dart';

import 'rootfs_extractor.dart';
import 'tar_reader.dart';

/// Progress callback: (0.0-1.0, human readable label)
typedef ProgressFn = void Function(double value, String label);

/// Log callback: one line of human readable output.
typedef LogFn = void Function(String line);

/// The device CPU architecture we can support.
enum DeviceArch {
  arm64,
  x86_64,
  unsupported;

  static Future<DeviceArch> detect() async {
    try {
      final result = await Process.run('uname', ['-m']);
      final machine = result.stdout.toString().trim().toLowerCase();
      if (machine.contains('aarch64') || machine.contains('arm64')) {
        return DeviceArch.arm64;
      }
      if (machine.contains('x86_64') || machine.contains('amd64')) {
        return DeviceArch.x86_64;
      }
    } catch (_) {
      // fall through to unsupported
    }
    return DeviceArch.unsupported;
  }

  String get prootAsset => switch (this) {
    DeviceArch.x86_64 => 'proot-x86_64.zip',
    _ => 'proot-aarch64.zip',
  };

  String get ubuntuAsset => switch (this) {
    DeviceArch.x86_64 => 'ubuntu-base-24.04.5-base-amd64.tar.gz',
    _ => 'ubuntu-base-24.04.5-base-arm64.tar.gz',
  };

  String get nodeDir => switch (this) {
    DeviceArch.x86_64 => 'node-v22.11.0-linux-x64',
    _ => 'node-v22.11.0-linux-arm64',
  };

  /// Ollama ships Linux builds as a ~1.5 GB `.tar.zst` tarball.
  String get ollamaAsset => switch (this) {
    DeviceArch.x86_64 => 'ollama-linux-amd64.tar.zst',
    _ => 'ollama-linux-arm64.tar.zst',
  };
}

/// All the upstream artifacts the runtime is assembled from.
///
/// Every URL here was verified reachable (HTTP 200) before being committed.
class RuntimeSources {
  const RuntimeSources._();

  static const String prootVersion = 'v26.08.25-7266fb3';
  static const String prootBase =
      'https://github.com/ahmed-alnassif/proot/releases/download/$prootVersion';

  static const String ubuntuBase =
      'https://cdimage.ubuntu.com/ubuntu-base/releases/24.04/release';

  static const String nodeVersion = '22.11.0';
  static const String nodeBase = 'https://nodejs.org/dist/v$nodeVersion';

  static const String ollamaVersion = 'v0.34.0';

  static String prootUrl(DeviceArch arch) => '$prootBase/${arch.prootAsset}';
  static String ubuntuUrl(DeviceArch arch) => '$ubuntuBase/${arch.ubuntuAsset}';
  static String nodeUrl(DeviceArch arch) =>
      '$nodeBase/${arch.nodeDir}.tar.xz';
  static String ollamaUrl(DeviceArch arch) =>
      'https://github.com/ollama/ollama/releases/download/$ollamaVersion/'
      '${arch.ollamaAsset}';

  /// Local cache filenames.
  ///
  /// Upstream names the PRoot and Ollama archives without a version
  /// (`proot-aarch64.zip`, `ollama-linux-arm64.tar.zst`), so caching under the
  /// upstream name would make a pinned-version bump silently reuse the stale
  /// file. Prefixing the version keeps the cache honest.
  static String cachedProot(DeviceArch arch) =>
      '$prootVersion-${arch.prootAsset}';
  static String cachedOllama(DeviceArch arch) =>
      '$ollamaVersion-${arch.ollamaAsset}';
}

/// Location of the self-contained Linux runtime inside the app sandbox.
///
/// Everything lives under the app's private support directory, which on Android
/// is `/data/data/<package>/files` — a location the app may execute from, as
/// long as it targets a pre-API-29 `targetSdk` (see the CI manifest patch).
class RuntimePaths {
  RuntimePaths(this.base);

  final Directory base;

  Directory get rootfs => Directory('${base.path}/rootfs');
  Directory get downloads => Directory('${base.path}/downloads');
  Directory get tmp => Directory('${base.path}/tmp');
  File get proot => File('${base.path}/proot');
  File get loader => File('${base.path}/loader');
  File get marker => File('${base.path}/bootstrap.complete');

  static Future<RuntimePaths> resolve() async {
    final support = await getApplicationSupportDirectory();
    return RuntimePaths(Directory('${support.path}/runtime'));
  }

  Future<void> ensureLayout() async {
    await base.create(recursive: true);
    await downloads.create(recursive: true);
    await tmp.create(recursive: true);
    await rootfs.create(recursive: true);
  }

  Future<bool> get isBootstrapped async => marker.exists();
}

/// Minimal HTTP downloader with progress reporting.
class Downloader {
  const Downloader();

  Future<void> fetch(String url, File destination, ProgressFn onProgress) async {
    await destination.parent.create(recursive: true);
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 45);
    try {
      final request = await client.getUrl(Uri.parse(url));
      request.followRedirects = true;
      final response = await request.close();
      if (response.statusCode != HttpStatus.ok) {
        throw HttpException(
          '下载失败：HTTP ${response.statusCode}（$url）',
        );
      }
      final total = response.contentLength;
      final sink = destination.openWrite();
      var received = 0;
      var lastTick = 0;
      try {
        await for (final chunk in response) {
          sink.add(chunk);
          received += chunk.length;
          if (total > 0) {
            final now = DateTime.now().millisecondsSinceEpoch;
            if (now - lastTick > 250) {
              lastTick = now;
              onProgress(
                received / total,
                '${_mb(received)} / ${_mb(total)} MB',
              );
            }
          }
        }
      } finally {
        await sink.flush();
        await sink.close();
      }
      onProgress(1, '${_mb(received)} MB');
    } finally {
      client.close(force: true);
    }
  }

  static String _mb(int bytes) => (bytes / 1024 / 1024).toStringAsFixed(1);
}

/// Runs commands inside the guest root filesystem through PRoot.
class ProotRuntime {
  ProotRuntime(this.paths);

  final RuntimePaths paths;

  Map<String, String> get environment => {
    'PROOT_LOADER': paths.loader.path,
    'PROOT_TMP_DIR': paths.tmp.path,
    'HOME': '/root',
    'PATH':
        '/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin',
    'TERM': 'xterm-256color',
    'LANG': 'C.UTF-8',
    'DEBIAN_FRONTEND': 'noninteractive',
  };

  /// PRoot argv for a guest command. `--link2symlink` is required because
  /// Android filesystems refuse hard links across some boundaries; the
  /// `/host-downloads` bind exposes files fetched on the Android side.
  List<String> guestArgs(List<String> command) => [
    '--link2symlink',
    '-0',
    '-r',
    paths.rootfs.path,
    '-b',
    '/dev',
    '-b',
    '/proc',
    '-b',
    '/sys',
    '-b',
    '${paths.downloads.path}:/host-downloads',
    '-w',
    '/root',
    ...command,
  ];

  Future<ProcessResult> run(
    List<String> command, {
    Duration timeout = const Duration(minutes: 20),
  }) {
    return Process.run(
      paths.proot.path,
      guestArgs(command),
      environment: environment,
      includeParentEnvironment: false,
    ).timeout(timeout);
  }

  /// Run a guest shell command and forward output to [log].
  Future<int> stream(
    String shellCommand, {
    required LogFn log,
    Duration timeout = const Duration(minutes: 20),
  }) async {
    final process = await Process.start(
      paths.proot.path,
      guestArgs(['/bin/sh', '-c', shellCommand]),
      environment: environment,
      includeParentEnvironment: false,
    );
    void forward(Stream<List<int>> stream) {
      stream
          .transform(const SystemEncoding().decoder)
          .listen((chunk) {
            for (final line in chunk.split('\n')) {
              if (line.trim().isNotEmpty) log(line.trimRight());
            }
          });
    }

    forward(process.stdout);
    forward(process.stderr);
    final code = await process.exitCode.timeout(timeout);
    return code;
  }

  Future<void> chmod(File file, String mode) async {
    final result = await Process.run('chmod', [mode, file.path]);
    if (result.exitCode != 0) {
      throw ProcessException(
        'chmod',
        [mode, file.path],
        result.stderr.toString(),
        result.exitCode,
      );
    }
  }

  /// Extract a `.zip` in pure Dart. Only used for the PRoot archive, which
  /// contains three regular files (`proot`, `loader`, `loader-m32`) and no
  /// symlinks.
  Future<void> extractZip(File archiveFile, Directory destination) async {
    final archive = ZipDecoder().decodeBytes(await archiveFile.readAsBytes());
    for (final entry in archive) {
      if (!entry.isFile) continue;
      final out = File('${destination.path}/${entry.name}');
      await out.parent.create(recursive: true);
      await out.writeAsBytes(entry.content as List<int>, flush: true);
    }
  }
}

/// Orchestrates first-run installation of the Linux runtime.
class RuntimeBootstrap {
  RuntimeBootstrap({required this.onLog, required this.onProgress});

  final LogFn onLog;
  final ProgressFn onProgress;

  final Downloader _downloader = const Downloader();

  /// Overall weight of each phase, used to build a single progress bar.
  static const List<double> _weights = [0.05, 0.15, 0.30, 0.20, 0.20, 0.10];

  void _phase(int index, double fraction, String label) {
    var total = 0.0;
    for (var i = 0; i < index; i++) {
      total += _weights[i];
    }
    total += _weights[index] * fraction.clamp(0.0, 1.0);
    onProgress(total.clamp(0.0, 1.0), label);
  }

  Future<void> run() async {
    final paths = await RuntimePaths.resolve();
    await paths.ensureLayout();

    final arch = await DeviceArch.detect();
    if (arch == DeviceArch.unsupported) {
      throw const FormatException(
        '不支持的 CPU 架构：本应用只能在 arm64（aarch64）或 x86_64 设备上运行。',
      );
    }
    onLog('检测到设备架构：${arch.name}');

    final proot = ProotRuntime(paths);

    // --- 1. PRoot + loader -------------------------------------------------
    _phase(0, 0.0, '正在获取 PRoot 运行器');
    final prootZip = File(
      '${paths.downloads.path}/${RuntimeSources.cachedProot(arch)}',
    );
    if (!await prootZip.exists()) {
      await _downloader.fetch(
        RuntimeSources.prootUrl(arch),
        prootZip,
        (f, l) => _phase(0, f * 0.8, '正在下载 PRoot（$l）'),
      );
    }
    _phase(0, 0.85, '正在解压 PRoot');
    await proot.extractZip(prootZip, paths.base);
    await proot.chmod(paths.proot, '700');
    await proot.chmod(paths.loader, '700');
    if (!await paths.proot.exists()) {
      throw const FileSystemException('解压后找不到 PRoot 可执行文件，安装包可能已损坏。');
    }
    onLog('PRoot 就绪：${paths.proot.path}');
    _phase(0, 1.0, 'PRoot 就绪');

    // --- 2. Ubuntu root filesystem ----------------------------------------
    // The rootfs is only re-extracted when the archive it came from changes.
    // Keying on `/etc/os-release` alone would silently keep an old release
    // after a version bump; the source marker records what was unpacked.
    final sourceMarker = File('${paths.base.path}/rootfs.source');
    final unpackedFrom = await sourceMarker.exists()
        ? (await sourceMarker.readAsString()).trim()
        : '';
    final osRelease = File('${paths.rootfs.path}/etc/os-release');
    if (unpackedFrom != arch.ubuntuAsset || !await osRelease.exists()) {
      final tarball = File('${paths.downloads.path}/${arch.ubuntuAsset}');
      if (!await tarball.exists()) {
        await _downloader.fetch(
          RuntimeSources.ubuntuUrl(arch),
          tarball,
          (f, l) => _phase(1, f * 0.85, '正在下载 Ubuntu 基础系统（$l）'),
        );
      }
      _phase(1, 0.9, '正在解压 Ubuntu 根文件系统');
      onLog('正在解压 Ubuntu 根文件系统（约 3400 个条目，需要一到两分钟）…');
      // Extracted by RootfsExtractor, not the platform `tar`: toybox tar runs as
      // the app's unprivileged uid and aborts when it cannot chown every member
      // back to root:root. See the class comment for the full reasoning.
      final report = await RootfsExtractor.extract(
        tarball: tarball,
        destination: paths.rootfs,
        onLog: onLog,
        onProgress: (fraction) =>
            _phase(1, 0.9 + fraction * 0.08, '正在解压 Ubuntu 根文件系统'),
      );
      onLog('解压完成：$report');
      await sourceMarker.writeAsString('${arch.ubuntuAsset}\n');
    }
    onLog('Ubuntu 根文件系统就绪');
    _phase(1, 1.0, '根文件系统就绪');

    // --- 3. Base packages -------------------------------------------------
    await _writeRootfsConfig(paths);
    _phase(2, 0.05, '正在配置软件源');
    onLog('正在安装基础工具（git、python3、curl 等，首次较慢）…');
    final aptCode = await proot.stream(
      'apt-get update -qq && '
      'apt-get install -y -qq --no-install-recommends '
      'git python3 curl ca-certificates xz-utils tar bash ripgrep procps '
      '&& rm -rf /var/lib/apt/lists/*',
      log: onLog,
    );
    if (aptCode != 0) {
      throw ProcessException(
        'apt-get',
        const ['install'],
        '基础工具安装失败（退出码 $aptCode）。请检查网络后重试；'
            '若持续失败，可在“终端”里手动执行 apt-get update 查看详细报错。',
        aptCode,
      );
    }
    _phase(2, 1.0, '基础工具安装完成');

    // --- 4. Node.js -------------------------------------------------------
    _phase(3, 0.1, '正在安装 Node.js ${RuntimeSources.nodeVersion}');
    final nodeTarball = File('${paths.downloads.path}/${arch.nodeDir}.tar.xz');
    if (!await nodeTarball.exists()) {
      await _downloader.fetch(
        RuntimeSources.nodeUrl(arch),
        nodeTarball,
        (f, l) => _phase(3, 0.1 + f * 0.5, '正在下载 Node.js（$l）'),
      );
    }
    _phase(3, 0.7, '正在解压 Node.js');
    final nodeCode = await proot.stream(
      'tar -xJf /host-downloads/${arch.nodeDir}.tar.xz '
      '-C /usr/local --strip-components=1',
      log: onLog,
    );
    if (nodeCode != 0) {
      throw ProcessException(
        'tar',
        const ['-xJf'],
        'Node.js 解压失败（退出码 $nodeCode）。',
        nodeCode,
      );
    }
    final nodeVersion = await proot.run(const ['/usr/local/bin/node', '--version']);
    onLog('Node.js 安装完成：${nodeVersion.stdout.toString().trim()}');
    _phase(3, 1.0, 'Node.js 就绪');

    // --- 5. dsh + OpenClaw ------------------------------------------------
    _phase(4, 0.1, '正在安装 dsh 与 OpenClaw');
    onLog('正在通过 npm 安装 dsh（DeepSeek Harness）与 OpenClaw…');
    final npmCode = await proot.stream(
      '/usr/local/bin/npm install -g --no-fund --no-audit '
      '@deepseek-ai/dsh openclaw',
      log: onLog,
    );
    if (npmCode != 0) {
      // Not fatal: the toolchain itself is usable, and the user can retry from
      // the console once they see the npm error.
      onLog(
        '警告：npm 全局安装失败（退出码 $npmCode）。系统本身仍然可用，'
        '可稍后在“终端”里手动重试：npm install -g @deepseek-ai/dsh openclaw',
      );
    }
    await _writeDshConfig(proot);
    _phase(4, 1.0, 'AI 工具安装完成');

    // --- 6. Finalise ------------------------------------------------------
    _phase(5, 0.5, '正在做最后检查');
    final check = await proot.run(const [
      '/bin/sh',
      '-c',
      'node --version; git --version; python3 --version',
    ]);
    final summary = check.stdout.toString().trim();
    if (summary.isNotEmpty) onLog(summary);
    await paths.marker.writeAsString(
      'bootstrapped ${DateTime.now().toIso8601String()}\n'
      'arch=${arch.name}\n'
      'node=${RuntimeSources.nodeVersion}\n',
    );
    _phase(5, 1.0, '安装完成');
    onLog('安装完成，可以开始使用了。');
  }

  Future<void> _writeRootfsConfig(RuntimePaths paths) async {
    final etc = Directory('${paths.rootfs.path}/etc');
    await etc.create(recursive: true);
    await File('${etc.path}/resolv.conf').writeAsString(
      'nameserver 1.1.1.1\nnameserver 8.8.8.8\n',
    );
    // Ubuntu 24.04 ships deb822 sources; a classic list is added as a fallback
    // for images that carry neither.
    await File('${etc.path}/apt/sources.list').create(recursive: true).then(
      (f) => f.writeAsString(
        'deb http://archive.ubuntu.com/ubuntu noble main restricted universe multiverse\n'
        'deb http://archive.ubuntu.com/ubuntu noble-updates main restricted universe multiverse\n'
        'deb http://archive.ubuntu.com/ubuntu noble-security main restricted universe multiverse\n',
      ),
    );
  }

  /// dsh runs commands on the user's behalf; the product requirement is a
  /// launcher that never stalls on an approval prompt, so the policy is
  /// pre-seeded to `never`.
  Future<void> _writeDshConfig(ProotRuntime proot) async {
    await proot.run(const [
      '/bin/sh',
      '-c',
      'mkdir -p /root/.dsh && '
          'printf %s '
          "'{\"approvalPolicy\":\"never\",\"webPort\":3080}' "
          '> /root/.dsh/config.json',
    ]);
    onLog('已将 dsh 的授权策略设为 never（不再逐条询问）');
  }

  /// Optional: Ollama ships as a ~1.5 GB `.tar.zst`, so it is never part of the
  /// default setup — the user triggers it explicitly from the dashboard.
  ///
  /// Extraction happens inside the guest because Android's bundled `tar` has no
  /// zstd support; `zstd` comes from the Ubuntu archive.
  Future<void> installOllama() async {
    final paths = await RuntimePaths.resolve();
    final arch = await DeviceArch.detect();
    final proot = ProotRuntime(paths);
    final localName = RuntimeSources.cachedOllama(arch);
    final tarball = File('${paths.downloads.path}/$localName');

    onLog(
      '正在下载 Ollama ${RuntimeSources.ollamaVersion}'
      '（约 1.5 GB，请保持联网并耐心等待）…',
    );
    if (!await tarball.exists()) {
      await _downloader.fetch(
        RuntimeSources.ollamaUrl(arch),
        tarball,
        (f, l) => onProgress(f, '正在下载 Ollama：$l'),
      );
    }

    onLog('正在安装 zstd 并在系统内解压 Ollama…');
    final code = await proot.stream(
      'apt-get install -y -qq --no-install-recommends zstd '
      '&& mkdir -p /usr/local '
      '&& tar --zstd -xf /host-downloads/$localName -C /usr/local '
      '&& chmod 755 /usr/local/bin/ollama '
      '&& /usr/local/bin/ollama --version',
      log: onLog,
      timeout: const Duration(minutes: 60),
    );
    if (code != 0) {
      throw ProcessException(
        'ollama',
        const ['--version'],
        'Ollama 安装失败（退出码 $code）。可能是下载不完整或存储空间不足。',
        code,
      );
    }
    onLog('Ollama 安装完成。下载模型：ollama pull llama3.2:1b');
  }
}

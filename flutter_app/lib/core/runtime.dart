import 'dart:async';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:path_provider/path_provider.dart';

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

  static const String ubuntuVersion = '24.04.5';
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
        throw HttpException('HTTP ${response.statusCode} while fetching $url');
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

  /// Extract a `.tar.gz` using the platform `tar`, which preserves symlinks
  /// (essential: an Ubuntu base rootfs is full of `/bin -> usr/bin` links).
  Future<void> extractTarGz(File tarball, Directory destination) async {
    await destination.create(recursive: true);
    final result = await Process.run('tar', [
      '-xzf',
      tarball.path,
      '-C',
      destination.path,
    ]);
    if (result.exitCode != 0) {
      throw ProcessException(
        'tar',
        ['-xzf', tarball.path],
        result.stderr.toString(),
        result.exitCode,
      );
    }
  }

  /// Extract a `.zip` in pure Dart. Only used for the PRoot archive, which
  /// contains three regular files and no symlinks.
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

  double _completed = 0;

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
        'Unsupported CPU architecture: only arm64 and x86_64 devices are '
        'supported.',
      );
    }
    onLog('Device architecture: ${arch.name}');

    final proot = ProotRuntime(paths);

    // --- 1. PRoot + loader -------------------------------------------------
    _phase(0, 0.0, 'Fetching PRoot');
    final prootZip = File('${paths.downloads.path}/${arch.prootAsset}');
    if (!await prootZip.exists()) {
      await _downloader.fetch(
        RuntimeSources.prootUrl(arch),
        prootZip,
        (f, l) => _phase(0, f * 0.8, 'Fetching PRoot ($l)'),
      );
    }
    _phase(0, 0.85, 'Extracting PRoot');
    await proot.extractZip(prootZip, paths.base);
    await proot.chmod(paths.proot, '700');
    await proot.chmod(paths.loader, '700');
    if (!await paths.proot.exists()) {
      throw const FileSystemException('PRoot binary missing after extraction');
    }
    onLog('PRoot ready: ${paths.proot.path}');
    _phase(0, 1.0, 'PRoot ready');

    // --- 2. Ubuntu root filesystem ----------------------------------------
    final rootfsMarker = File('${paths.rootfs.path}/etc/os-release');
    if (!await rootfsMarker.exists()) {
      final tarball = File('${paths.downloads.path}/${arch.ubuntuAsset}');
      if (!await tarball.exists()) {
        await _downloader.fetch(
          RuntimeSources.ubuntuUrl(arch),
          tarball,
          (f, l) => _phase(1, f * 0.85, 'Downloading Ubuntu base ($l)'),
        );
      }
      _phase(1, 0.9, 'Extracting Ubuntu base');
      onLog('Extracting Ubuntu root filesystem (this can take a minute)...');
      await proot.extractTarGz(tarball, paths.rootfs);
    }
    onLog('Ubuntu root filesystem ready');
    _phase(1, 1.0, 'Root filesystem ready');

    // --- 3. Base packages -------------------------------------------------
    await _writeRootfsConfig(paths);
    _phase(2, 0.05, 'Configuring package sources');
    onLog('Installing base packages (git, python3, curl, ...)');
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
        'base package installation failed with exit code $aptCode',
        aptCode,
      );
    }
    _phase(2, 1.0, 'Base packages installed');

    // --- 4. Node.js -------------------------------------------------------
    _phase(3, 0.1, 'Installing Node.js ${RuntimeSources.nodeVersion}');
    final nodeTarball = File('${paths.downloads.path}/${arch.nodeDir}.tar.xz');
    if (!await nodeTarball.exists()) {
      await _downloader.fetch(
        RuntimeSources.nodeUrl(arch),
        nodeTarball,
        (f, l) => _phase(3, 0.1 + f * 0.5, 'Downloading Node.js ($l)'),
      );
    }
    _phase(3, 0.7, 'Unpacking Node.js');
    final nodeCode = await proot.stream(
      'tar -xJf /host-downloads/${arch.nodeDir}.tar.xz '
      '-C /usr/local --strip-components=1',
      log: onLog,
    );
    if (nodeCode != 0) {
      throw ProcessException(
        'tar',
        const ['-xJf'],
        'Node.js extraction failed with exit code $nodeCode',
        nodeCode,
      );
    }
    final nodeVersion = await proot.run(const ['/usr/local/bin/node', '--version']);
    onLog('Node.js installed: ${nodeVersion.stdout.toString().trim()}');
    _phase(3, 1.0, 'Node.js ready');

    // --- 5. dsh + OpenClaw ------------------------------------------------
    _phase(4, 0.1, 'Installing dsh and OpenClaw (npm)');
    onLog('Installing dsh (DeepSeek Harness) and OpenClaw via npm...');
    final npmCode = await proot.stream(
      '/usr/local/bin/npm install -g --no-fund --no-audit '
      '@deepseek-ai/dsh openclaw',
      log: onLog,
    );
    if (npmCode != 0) {
      // Not fatal: the toolchain itself is usable, and the user can retry from
      // the terminal once they see the npm error.
      onLog(
        'WARNING: npm global install exited with code $npmCode. '
        'Retry later with: npm install -g @deepseek-ai/dsh openclaw',
      );
    }
    await _writeDshConfig(proot);
    _phase(4, 1.0, 'AI tools installed');

    // --- 6. Finalise ------------------------------------------------------
    _phase(5, 0.5, 'Finalising');
    final check = await proot.run(const ['/bin/sh', '-c', 'node --version; git --version']);
    onLog(check.stdout.toString().trim());
    await paths.marker.writeAsString(
      'bootstrapped ${DateTime.now().toIso8601String()}\n'
      'arch=${arch.name}\n'
      'node=${RuntimeSources.nodeVersion}\n',
    );
    _phase(5, 1.0, 'Setup complete');
    onLog('Setup complete.');
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
    onLog('dsh approval policy set to "never"');
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
    final tarball = File('${paths.downloads.path}/${arch.ollamaAsset}');

    onLog(
      'Downloading Ollama ${RuntimeSources.ollamaVersion} '
      '(~1.5 GB, this takes a while)...',
    );
    if (!await tarball.exists()) {
      await _downloader.fetch(
        RuntimeSources.ollamaUrl(arch),
        tarball,
        (f, l) => onProgress(f, 'Ollama: $l'),
      );
    }

    onLog('Installing zstd and unpacking Ollama inside the root filesystem...');
    final code = await proot.stream(
      'apt-get install -y -qq --no-install-recommends zstd '
      '&& mkdir -p /usr/local '
      '&& tar --zstd -xf /host-downloads/${arch.ollamaAsset} -C /usr/local '
      '&& chmod 755 /usr/local/bin/ollama '
      '&& /usr/local/bin/ollama --version',
      log: onLog,
      timeout: const Duration(minutes: 60),
    );
    if (code != 0) {
      throw ProcessException(
        'ollama',
        const ['--version'],
        'Ollama installation failed with exit code $code',
        code,
      );
    }
    onLog('Ollama installed. Pull a model with: ollama pull llama3.2:1b');
  }
}

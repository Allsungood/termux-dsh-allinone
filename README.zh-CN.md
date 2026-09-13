# Termux All-in-One

**一个自带 Linux 运行环境的 Flutter 安卓应用。**

首次启动时，App 会把静态编译的 PRoot 和一套 Ubuntu 24.04 根文件系统下载到自己的私有目录里，
解压后在"客户机"内装好一套小工具链：`git`、`python3`、`curl`、`bash`、`ripgrep`、
Node.js 22 LTS，以及 **dsh（DeepSeek Harness）** 和 **OpenClaw**；**Ollama** 属于可选组件，
需要你手动点一下才会装。

不需要 root，也不需要另外安装 Termux。所有东西都待在这一个 App 的沙箱里，通过 PRoot 执行。

[![License](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
![Android](https://img.shields.io/badge/Android-7.0%2B%20(API%2024)-brightgreen?logo=android)
![Flutter](https://img.shields.io/badge/Flutter-stable-02569B?logo=flutter)
![Arch](https://img.shields.io/badge/Arch-arm64%20%7C%20x86--64-orange)

[English](README.md) | 简体中文

---

## ⚠️ 先看这里：验证状态

**CI 能把 APK 构建出来，但作者还没有在真机上验证过运行时行为。** 组件测试覆盖到的 Dart 逻辑是通的，
所有上游下载地址在写进代码前也都确认过可以访问；但从首次下载、解压 rootfs、PRoot 执行，
到 `dsh web` 和 `openclaw gateway` 在 `127.0.0.1` 上真正起来——这条完整链路**尚未在真实设备上得到确认**。

所以请把当前版本当作预览版来用，遇到问题欢迎到
[Issues](https://github.com/Allsungood/termux-dsh-allinone/issues) 反馈。

另外两件事最好提前知道：

- 本应用**无法上架 Google Play**，因为它把 `targetSdk` 固定在了 28（[原因见下](#为什么必须锁定-targetsdk-28)）。
  安装方式是从 [GitHub Releases](https://github.com/Allsungood/termux-dsh-allinone/releases) 侧载 APK。
- 卸载 App 会**连带删掉整个环境**，包括你已经下载的 Ollama 模型。

---

## 运行要求

| 项目 | 要求 |
|---|---|
| Android 版本 | 7.0（API 24）及以上 |
| CPU 架构 | **仅支持 arm64（aarch64）和 x86_64**，32 位 ARM（`armeabi-v7a`）不支持 |
| 存储空间 | 首次运行约 55 MB 下载量，再加上解压后的 rootfs 与 apt 软件包（建议预留几个 GB）；装 Ollama 还要再加约 1.5 GB 和模型文件 |
| 网络 | 需要能访问 GitHub、`cdimage.ubuntu.com`、`nodejs.org`、Ubuntu 软件源和 npm 源 |
| Root | **不需要** |

App 会通过 `uname -m` 判断架构；如果既不是 `aarch64`/`arm64` 也不是 `x86_64`/`amd64`，
它会直接停下来并提示 *"Unsupported CPU architecture: only arm64 and x86_64 devices are supported."*

---

## 安装

1. 打开 [Releases](https://github.com/Allsungood/termux-dsh-allinone/releases/latest)。
2. 按机型下载对应的 APK：
   - `termux-allinone-arm64.apk` —— 2017 年之后几乎所有的安卓手机和平板
   - `termux-allinone-x86_64.apk` —— 安卓模拟器、x86 架构的 Chromebook、部分平板
3. 在系统里给你的浏览器或文件管理器打开"安装未知应用"权限，然后点开 APK 安装。
4. 启动 **Termux All-in-One**，跟着首屏走就行。

应用标识：

| 项目 | 值 |
|---|---|
| Application id / namespace | `com.allsungood.termux_dsh_allinone` |
| Flutter 包名 | `termux_dsh_allinone` |
| 显示名称 | Termux All-in-One |

---

## 首次运行

首屏（`SetupPage`）会先说明将要做什么，下面只有一个 **Install environment** 按钮。点下去之后，
进度条和实时日志会一路显示每个阶段：

1. 下载并解压 PRoot 和 loader
2. 下载并解压 Ubuntu 基础根文件系统
3. `apt-get install git python3 curl ca-certificates xz-utils tar bash ripgrep procps`
4. 下载 Node.js 22.11.0，解压到 `/usr/local`
5. 执行 `npm install -g @deepseek-ai/dsh openclaw`，并写入 `/root/.dsh/config.json`
6. 验证 `node` 和 `git`，最后写入 `bootstrap.complete` 标记文件

完成后点 **Open dashboard** 进入三标签主界面。中途出错的话，错误会打印在日志里，
按钮会变成 **Retry installation**；已经下载好的压缩包会被复用，所以重试并不费流量。

> 第 5 步的 npm 安装被刻意设计成"非致命"：即使失败也只是在日志里给一条 WARNING，
> 你之后仍然可以在 Console 里手动执行 `npm install -g @deepseek-ai/dsh openclaw` 补上。

---

## 下载内容一览

首次运行的全部下载量约 **55 MB**。

| 组件 | 版本 | 文件名 | 体积（约） | 来源 |
|---|---|---|---|---|
| PRoot（Android 静态编译） | `v26.08.25-7266fb3` | `proot-aarch64.zip` · `proot-x86_64.zip`（包内含 `proot`、`loader`、`loader-m32`） | 各约 0.1 MB | [ahmed-alnassif/proot releases](https://github.com/ahmed-alnassif/proot/releases) |
| Ubuntu 基础 rootfs | `24.04.5` | `ubuntu-base-24.04.5-base-arm64.tar.gz` · `ubuntu-base-24.04.5-base-amd64.tar.gz` | 28.5 MB · 28.6 MB | [cdimage.ubuntu.com/ubuntu-base/releases/24.04/release](https://cdimage.ubuntu.com/ubuntu-base/releases/24.04/release/) |
| Node.js | `22.11.0` | `node-v22.11.0-linux-arm64.tar.xz` · `node-v22.11.0-linux-x64.tar.xz` | 26.8 MB · 27.9 MB | [nodejs.org/dist/v22.11.0](https://nodejs.org/dist/v22.11.0/) |
| dsh + OpenClaw | 安装时的 npm 最新版 | — | （走 npm） | `npm install -g @deepseek-ai/dsh openclaw` |
| **Ollama（可选，需手动触发）** | `v0.34.0` | `ollama-linux-arm64.tar.zst` · `ollama-linux-amd64.tar.zst` | **约 1.5 GB** | [ollama/ollama releases](https://github.com/ollama/ollama/releases) |

以上全部通过 HTTPS 下载，并解压到
`/data/data/com.allsungood.termux_dsh_allinone/files/runtime/`。

客户机内安装的基础软件包是 `git`、`python3`、`curl`、`ca-certificates`、`xz-utils`、`tar`、
`bash`、`ripgrep`、`procps`；Node.js 22 LTS 解压进 `/usr/local`；最后用 npm 全局安装 `dsh` 和 `openclaw`。

**为什么用 Ubuntu 而不是 Alpine？** 因为 dsh 的原生模块提供的是 **glibc** 预编译产物，
musl 发行版（比如 Alpine）加载不了。所以客户机选用 Ubuntu 24.04（glibc）。

---

## 三个标签页

| 标签 | 说明 |
|---|---|
| **Tools** | 工具仪表盘。每个工具一张卡片（`dsh`、OpenClaw、Ollama、Node.js、Git、Python 3），卡片上显示 `running` / `installed` / `not installed` / `missing`，并提供 **Start**、**Stop**、**Open**。Ollama 因为是可选项，所以有独立的 **Install** 按钮。下拉即可重新检测。顶部汇总卡会显示"N of 6 tools ready inside the app sandbox"。 |
| **Console** | 客户机内的屏幕终端，上方有一排快捷命令标签（`dsh --version`、`dsh web --port 3080`、`openclaw gateway`、`ollama list`、`node --version`、`python3 --version`）。它是**管道式 shell，不是 PTY**——详见[已知限制](#已知限制)。 |
| **Settings** | dsh Web UI 端口、OpenClaw 网关端口、Ollama 端口、默认 Ollama 模型、保持唤醒开关，以及 **Repair / re-run installation**（修复 / 重跑安装）。 |

常驻服务（`dsh web`、`openclaw gateway`、`ollama serve`）都从 **Tools** 标签启动：App 会把它们
作为客户机后台进程拉起来，并保留它们的输出。点 **Open** 会用内置 WebView 打开本地面板
（dsh 是 `http://127.0.0.1:3080`，OpenClaw 是 `http://127.0.0.1:18789`），带刷新按钮和
"用外部浏览器打开"按钮。

---

## 为什么必须锁定 targetSdk 28

Android 10（API 29）引入了一项 **W^X 限制**：`targetSdk` ≥ 29 的应用，不能再 `execve`
自己写进应用数据目录里的文件。

而这个 App 的全部意义，恰恰就是执行 PRoot 和一套由它自己解压出来的 Linux 根文件系统——
这条限制会让它彻底跑不起来。因此构建时固定：

- `minSdk = 24`
- `targetSdk = 28`

Termux 出于完全相同的原因也把 `targetSdk` 压在低位。代价就是这个应用无法上架 Google Play，
只能通过 GitHub Releases 侧载。

---

## 仓库结构

```
termux-dsh-allinone/
├── .github/
│   ├── scripts/patch_android.py   # 给生成出来的 Android 工程打补丁（minSdk/targetSdk/名称/权限）
│   └── workflows/build.yml        # 唯一的工作流：脚手架 → 打补丁 → 检查 → 构建两个 APK → v* tag 时发 Release
├── docs/
│   ├── ARCHITECTURE.md            # PRoot 执行模型、数据流、为什么用 glibc、为什么 targetSdk 28、安全边界
│   ├── USER_GUIDE.md              # 安装、首次运行、各标签用法、逐工具说明、故障排查
│   └── BUILD.md                   # 本地构建、CI 脚手架与补丁、新增工具、版本锁定、发布清单
├── flutter_app/
│   ├── lib/core/runtime.dart      # PRoot/rootfs 路径、下载器、RuntimeSources 版本号、首次安装流程
│   ├── lib/models/                # EnvironmentConfig（设置项）、ToolStatus（仪表盘目录）
│   ├── lib/pages/                 # SetupPage、HomePage、TaskPage、WebDashboardPage
│   ├── lib/services/              # EnvironmentService（探测/启停）、TerminalService（Console 的 shell）
│   ├── lib/views/                 # DashboardView、ConsoleView、SettingsView
│   ├── lib/widgets/               # ToolCard、StatusCard
│   ├── test/widget_test.dart      # 组件/单元测试
│   └── pubspec.yaml
├── LICENSE
├── README.md
└── README.zh-CN.md
```

仓库里**刻意不提交 `android/` 目录**：CI 会先跑 `flutter create` 生成一份与当前 Flutter 版本
匹配的 Android 工程，再打补丁。详见 [docs/BUILD.md](docs/BUILD.md)。

Flutter 依赖：`shared_preferences`、`path_provider`、`webview_flutter`、`url_launcher`、`archive`。

---

## 已知限制

装之前请务必读完。这些是设计上的取舍，不是待修的临时 bug。

- **运行时尚未在真机上验证。** CI 能把 APK 构建出来，但完整的首次运行流程还没有人在真实设备上跑通。
- **Console 是管道式 shell，不是 PTY。** 普通命令没问题；全屏 curses 程序（`vi`、`nano`、
  `htop`、`top`）不行。`dsh web` 和 `openclaw gateway` 请从 **Tools** 标签以后台服务方式启动，
  不要在 Console 提示符里直接敲。
- **无法上架 Google Play。** `targetSdk = 28` 是这个方案的前提，所以只能从 GitHub Releases 侧载。
- **Ollama 要下约 1.5 GB**，而且是在客户机内部用 `tar --zstd` 解压的（Android 自带的 `tar`
  不支持 zstd）；另外模型有可能根本放不进你设备的内存。
- **一切都在单个 App 的私有存储里。** 卸载 App 就等于删掉整个环境——rootfs、工具链、
  npm 全局包、已下载模型全都没了。同时客户机没有共享存储的挂载点，所以它看不到 `/sdcard`。
- **不支持 32 位 ARM**，只支持 arm64 和 x86_64。
- **客户机里的 root 只是 PRoot 意义上的 root。** `-0` 让客户机看到 uid 0，但它拿不到任何超出
  App 自身 Android 沙箱的权限。

更多细节（包括安全边界）见 [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md)。

---

## 文档

- [docs/USER_GUIDE.md](docs/USER_GUIDE.md) —— 安装、首次运行、每个标签页、逐工具用法、故障排查
- [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) —— 组件图、首次运行数据流、PRoot 执行模型
- [docs/BUILD.md](docs/BUILD.md) —— 本地构建、CI 如何生成并打补丁、如何新增工具、发布清单
- [README.md](README.md) —— English

---

## 许可证

MIT，详见 [LICENSE](LICENSE)。

# Termux All-in-One — dsh + openclaw + git + ollama 一键启动器

> **小白友好的安卓终端环境**：Flutter 图形界面 + 内置 Termux 运行时，预装 dsh(DeepSeek Harness)、openclaw(Node.js)、git、ollama 等工具，支持图形化和控制台双模式。

![License](https://img.shields.io/badge/License-MIT-blue.svg)
![Android](https://img.shields.io/badge/Android-10%2B-brightgreen?logo=android)
![Flutter](https://img.shields.io/badge/Flutter-3.24-02569B?logo=flutter)

## 项目结构

```
termux-dsh-allinone/
├── flutter_app/           # Flutter 主应用
│   ├── lib/               # Dart 源码
│   │   ├── main.dart
│   │   ├── screens/       # 界面（启动器/终端/Web仪表盘/设置）
│   │   ├── widgets/       # UI 组件
│   │   ├── services/      # 终端/进程/网络服务
│   │   └── models/        # 数据模型
│   ├── android/           # Android 原生配置
│   ├── ios/               # iOS 配置
│   └── pubspec.yaml
├── bootstrap/             # Custom Termux Bootstrap
│   ├── bootstrap-aarch64/ # 预构建的 bootstrap zip
│   ├── scripts/           # 包定义与构建脚本
│   │   ├── make-bootstrap.sh     # 生成自定义 bootstrap
│   │   └── packages.txt          # 预装包列表（nodejs-lts, git, python3, dsh-termux, ollama 等）
│   └── overlays/          # 启动时自动执行的覆盖脚本
├── scripts/               # 集成与初始化脚本
│   ├── setup-dsh.sh       # dsh 环境配置
│   ├── setup-openclaw.sh  # openclaw 环境配置
│   ├── setup-ollama.sh    # ollama CLI 配置
│   └── setup-all.sh       # 一键全部配置
├── docs/
│   ├── ARCHITECTURE.md    # 架构设计
│   ├── USER_GUIDE.md      # 用户指南
│   └── BUILD.md           # 构建说明
├── .github/workflows/
│   ├── build.yml          # CI/CD：构建 APK + Bootstrap
│   └── test.yml           # 自动化测试
└── LICENSE
```

## 功能特性

### 🎨 图形界面（Flutter App）
- **启动器首页**：所有工具一键启动，状态实时显示
- **内置终端**：全功能终端模拟器（复制/粘贴/多选/URL 点击）
- **Web 仪表盘**：内置 WebView 显示 dsh Web UI 和 openclaw Dashboard
- **日志查看**：实时日志查看与搜索过滤
- **一键安装**：首次启动自动检测环境并引导安装
- **现代 UI**：Material 3 设计，支持深色/浅色模式

### 📦 内置环境（Custom Termux Bootstrap）
| 工具 | 说明 |
|------|------|
| **Node.js 24 LTS** | dsh/openclaw 运行环境 |
| **dsh (DeepSeek Harness)** | AI 助手 CLI + Web UI |
| **openclaw** | AI Gateway（Node.js 原生） |
| **Git** | 版本控制工具 |
| **Ollama CLI** | 本地 LLM 推理命令行 |
| **Python 3** | 脚本/构建依赖 |
| **OpenSSH** | 远程连接 |
| **curl / wget** | 网络工具 |
| **ripgrep / fd** | 现代搜索工具 |

### 🚀 使用方式

#### 方式一：安装 APK（推荐）
```
1. 从 Releases 下载最新 APK
2. 安装到 Android 设备
3. 打开 App → 点击"开始设置"
4. 等待环境初始化（约 2-5 分钟）
5. 选择你要使用的工具开始体验
```

#### 方式二：Termux CLI 安装
```bash
# 一键安装
curl -fsSL https://raw.githubusercontent.com/yourname/termux-dsh-allinone/main/install.sh | bash
```

#### 方式三：从源码构建
```bash
# Flutter App
git clone https://github.com/yourname/termux-dsh-allinone.git
cd termux-dsh-allinone/flutter_app
flutter build apk --release

# Custom Bootstrap（需要在 Linux arm64 上构建）
cd bootstrap/scripts
bash make-bootstrap.sh
```

## 架构设计

```
┌─────────────────────────────────────────────────────┐
│              Flutter App (Dart)                       │
│  ┌─────────┐ ┌──────────┐ ┌──────────────┐          │
│  │ 启动器  │ │ 终端     │ │ Web 仪表盘   │          │
│  │ (首页)  │ │ 模拟器   │ │ (dsh/openclaw│          │
│  │         │ │          │ │  Dashboard)  │          │
│  └────┬────┘ └─────┬────┘ └──────┬───────┘          │
│       │             │             │                   │
│  ┌────┴─────────────┴─────────────┴───────┐          │
│  │          Native Bridge (Kotlin)         │          │
│  └─────────────────┬───────────────────────┘          │
│                    │                                    │
└────────────────────┼──────────────────────────────────┘
                     │
┌────────────────────┼──────────────────────────────────┐
│         Termux Environment (Android)                   │
│  ┌─────────────────┴───────────────────────────┐      │
│  │      Custom Termux Bootstrap                  │      │
│  │  nodejs-lts · git · python3 · dsh · ollama   │      │
│  │  ssh · curl · ripgrep · fd · ...              │      │
│  └─────────────────┬───────────────────────────┘      │
│                    │                                    │
│  ┌─────────────────┴───────────────────────────┐      │
│  │  启动脚本 (overlay):                          │      │
│  │  - 配置 PATH、权限、环境变量                   │      │
│  │  - 检测并初始化 dsh/openclaw/ollama            │      │
│  │  - 设置 dsh 审批策略 (never/ask/manual)        │      │
│  └───────────────────────────────────────────────┘      │
└──────────────────────────────────────────────────────────┘
```

## 链接

- [用户指南](docs/USER_GUIDE.md) — 详细使用说明
- [架构设计](docs/ARCHITECTURE.md) — 技术方案与架构
- [构建说明](docs/BUILD.md) — 源码构建指南

---

Made with ❤️ for the Android developer community.

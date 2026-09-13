# Termux All-in-One — dsh + openclaw + git + ollama 一键启动器

> **小白友好的安卓终端环境**：Flutter 图形界面 + 内置 Termux 运行时，预装 dsh(DeepSeek Harness)、openclaw(Node.js)、git、ollama 等工具，支持图形化和控制台双模式。

![License](https://img.shields.io/badge/License-MIT-blue.svg)
![Android](https://img.shields.io/badge/Android-10%2B-brightgreen?logo=android)
![Flutter](https://img.shields.io/badge/Flutter-3.24-02569B?logo=flutter)
![Architecture](https://img.shields.io/badge/Arch-arm64%20%7C%20arm%20%7C%20x86_64-orange)

---

## 📱 效果预览

| 首页仪表盘 | 终端模拟器 | Web 仪表盘 | 设置页面 |
|------------|------------|------------|----------|
| ![Home](docs/assets/home.png) | ![Terminal](docs/assets/terminal.png) | ![Web](docs/assets/web.png) | ![Settings](docs/assets/settings.png) |

---

## 🚀 快速开始

### 方式一：下载 APK 安装（推荐，最简单）

1. 访问 [GitHub Releases](https://github.com/yourname/termux-dsh-allinone/releases)
2. 下载最新的 `app-release.apk` (约 50-80MB)
3. 安装到 Android 设备
4. 打开 App → 点击 **"开始一键设置"**
5. 等待 2-5 分钟自动配置完成
6. 点击 **"进入主界面"** 开始使用

### 方式二：Termux 命令行安装（进阶用户）

```bash
# 确保已安装 Termux (从 F-Droid，不要用 Play Store 版本)
# https://f-droid.org/packages/com.termux/

# 一键安装
curl -fsSL https://raw.githubusercontent.com/yourname/termux-dsh-allinone/main/scripts/setup-all.sh | bash -s -- -y
```

### 方式三：从源码构建（开发者）

```bash
# 1. 克隆仓库
git clone https://github.com/yourname/termux-dsh-allinone.git
cd termux-dsh-allinone

# 2. 构建自定义 Bootstrap (需要 Linux arm64 环境)
cd bootstrap/scripts
bash make-bootstrap.sh

# 3. 构建 Flutter APK
cd ../../flutter_app
flutter pub get
flutter build apk --release --target-platform android-arm64
# 输出: build/app/outputs/flutter-apk/app-release.apk
```

---

## ✨ 核心功能

### 🎨 现代化图形界面 (Flutter App)
- **首页仪表盘** - 所有工具一键启动，实时状态显示
- **完整终端** - 支持复制/粘贴/Tab补全/URL点击/额外按键工具栏
- **内嵌 WebView** - 无缝访问 dsh Web UI 和 OpenClaw Dashboard
- **设置中心** - 端口配置、审批策略、电池优化、权限管理
- **Material 3 设计** - 支持深色/浅色模式，流畅动画

### 📦 开箱即用的 Termux 环境 (Custom Bootstrap)
| 工具 | 版本 | 说明 |
|------|------|------|
| **Node.js** | 24 LTS | dsh/openclaw 运行时环境 |
| **dsh** | latest | DeepSeek Harness AI 助手 |
| **openclaw** | latest | AI Gateway + 设备能力 |
| **ollama** | CLI | 本地 LLM 推理命令行 |
| **Git** | latest | 版本控制 |
| **Python** | 3.12 | 脚本/构建依赖 |
| **SSH** | latest | 远程连接 |
| **ripgrep/fd** | latest | 现代搜索工具 |
| **make/clang** | latest | 原生模块编译支持 |

### ⚡ 零配置体验
- **审批策略默认 `never`** - 无需手动确认，自动执行命令
- **Bionic Bypass** - 修复 Android 上 `os.networkInterfaces()` 崩溃
- **电池优化豁免** - 后台服务持久运行
- **存储权限自动申请** - 首次运行自动配置

---

## 🏗️ 架构设计

```
┌─────────────────────────────────────────────────────────────────┐
│                      Flutter Application                         │
│  ┌─────────────┐  ┌──────────────┐  ┌────────────────────────┐  │
│  │  Home页      │  │  Terminal页   │  │  WebDashboard页         │  │
│  │  (工具卡片)  │  │  (完整Shell)  │  │  (dsh/openclaw WebView) │  │
│  └──────┬──────┘  └──────┬───────┘  └───────────┬────────────┘  │
│         │                │                      │                │
│  ┌──────▼────────────────▼──────────────────────▼────────────┐  │
│  │              Native Bridge (Kotlin)                        │  │
│  │  - Process Management (启动/停止/监控后台进程)               │  │
│  │  - Permission Handling (权限申请与管理)                     │  │
│  │  - File System Access (文件读写与存储)                      │  │
│  │  - Battery Optimization (电池优化豁免)                      │  │
│  └─────────────────────────┬──────────────────────────────────┘  │
│                            │                                      │
└────────────────────────────┼──────────────────────────────────────┘
                             │
┌────────────────────────────▼──────────────────────────────────────┐
│                    Termux Environment (Android)                    │
│  ┌──────────────────────────────────────────────────────────────┐ │
│  │              Custom Termux Bootstrap                          │ │
│  │  预装: nodejs-lts, git, python3, dsh-termux, ollama, ...     │ │
│  └──────────────────────────────────────────────────────────────┘ │
│  ┌──────────────────────────────────────────────────────────────┐ │
│  │  启动时自动执行: 配置 Node.js、生成 wrapper、设置审批策略      │ │
│  └──────────────────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────────────────┘
```

详见 [架构设计文档](docs/ARCHITECTURE.md)

---

## 📖 使用指南

### 主界面操作

| 页面 | 功能 |
|------|------|
| **首页** | 查看工具状态，点击卡片启动服务 |
| **终端** | 完整 Shell 体验，运行任意命令 |
| **Web仪表盘** | 访问 dsh Web UI (3080) / OpenClaw (18789) |
| **设置** | 修改端口、审批策略、系统选项 |

### 常用命令速查

```bash
# dsh (DeepSeek Harness)
dsh --version              # 查看版本
dsh web --port 3080        # 启动 Web UI
dsh update -t next -y      # 更新到最新版

# OpenClaw AI Gateway
openclawx setup            # 首次配置环境
openclawx onboarding       # 配置 API Key (Gemini/OpenAI/Claude)
openclawx start            # 启动网关
openclawx status           # 查看状态
openclawx shell            # 进入 Ubuntu 环境

# Ollama 本地推理
ollama serve               # 启动服务
ollama pull llama3.2:1b    # 下载小模型 (约 1.3GB)
ollama list                # 列出已下载模型
ollama run llama3.2:1b     # 交互式聊天
```

---

## ❓ 常见问题

<details>
<summary><b>Q: 首次设置卡住/失败怎么办？</b></summary>

- 确保网络正常（需访问 GitHub、npm、NodeSource）
- 尝试切换网络或开启代理
- 查看设置日志中的红色错误信息
- 点击"重新设置"再试一次
</details>

<details>
<summary><b>Q: dsh web 打不开 / 连接被拒绝？</b></summary>

1. 终端运行 `dsh --version` 确认已安装
2. 手动启动：`dsh web --port 3080`
3. 检查端口占用：`netstat -tlnp | grep 3080`
4. 确认审批策略：`cat ~/.dsh/config.json` 应显示 `"approvalPolicy": "never"`
</details>

<details>
<summary><b>Q: OpenClaw 报错 os.networkInterfaces？</b></summary>

这是 Android Bionic libc 问题，运行修复脚本：
```bash
bash scripts/setup-openclaw.sh
```
或手动添加 bypass（脚本已自动处理）。
</details>

<details>
<summary><b>Q: 后台服务被系统杀死？</b></summary>

1. App 设置中开启"禁用电池优化"
2. 系统设置 → 电池 → 应用管理 → Termux All-in-One → 允许后台运行
3. Termux 设置：设置 → 应用 → Termux → 电池 → 无限制
</details>

<details>
<summary><b>Q: Ollama 下载模型慢？</b></summary>

- 使用小模型：`llama3.2:1b` (1.3GB) 或 `qwen2:0.5b` (400MB)
- 手动下载放到 `~/.ollama/models/` 或 `/sdcard/ollama-models/`
- 设置镜像：`export OLLAMA_HOST=http://localhost:11434`
</details>

更多问题见 [用户指南](docs/USER_GUIDE.md)

---

## 🛠️ 开发者指南

### 添加新工具
1. 在 `bootstrap/scripts/packages.txt` 添加包名
2. 重新构建 bootstrap：`bash bootstrap/scripts/make-bootstrap.sh`
3. 在 `EnvironmentService` 添加检测方法
4. 在 `HomePage` 添加工具卡片

### 多架构支持
```bash
# 构建所有架构
for arch in aarch64 arm x86_64; do
    ARCH=$arch bash bootstrap/scripts/make-bootstrap.sh
done
```

### 本地测试
```bash
cd flutter_app
flutter analyze          # 静态分析
dart format --set-exit-if-changed lib/  # 格式检查
flutter test             # 单元测试
flutter build apk --release --target-platform android-arm64
```

---

## 📁 项目结构

```
termux-dsh-allinone/
├── flutter_app/              # Flutter 主应用
│   ├── lib/
│   │   ├── main.dart         # 入口
│   │   ├── models/           # 数据模型
│   │   ├── services/         # 核心服务
│   │   ├── pages/            # 页面
│   │   └── widgets/          # UI 组件
│   ├── android/              # Android 原生配置
│   └── pubspec.yaml
├── bootstrap/                # Custom Termux Bootstrap
│   ├── scripts/
│   │   ├── make-bootstrap.sh # 构建脚本
│   │   └── packages.txt      # 预装包列表
│   └── out/                  # 输出目录
├── scripts/                  # 环境初始化脚本
│   ├── setup-all.sh          # 一键全部配置
│   ├── setup-dsh.sh          # dsh 配置
│   ├── setup-openclaw.sh     # openclaw 配置
│   ├── setup-ollama.sh       # ollama 配置
│   └── install.sh            # Termux 安装入口
├── docs/                     # 文档
│   ├── ARCHITECTURE.md       # 架构设计
│   ├── USER_GUIDE.md         # 用户指南
│   └── BUILD.md              # 构建指南
├── .github/workflows/        # CI/CD
│   └── build.yml
└── LICENSE
```

---

## 🔧 CI/CD 自动化

GitHub Actions 自动化流程：

| 触发条件 | 动作 |
|----------|------|
| Push to main | 代码检查、单元测试 |
| Push tag `v*` | 构建 APK/AAB + 多架构 Bootstrap + 创建 Release |
| Pull Request | 代码检查、测试 |

查看 [构建指南](docs/BUILD.md) 了解详细配置。

---

## 🤝 贡献指南

欢迎提交 Issue 和 PR！

1. Fork 仓库
2. 创建特性分支: `git checkout -b feature/amazing-feature`
3. 提交更改: `git commit -m 'Add amazing feature'`
4. 推送分支: `git push origin feature/amazing-feature`
5. 创建 Pull Request

### 代码规范
- 运行 `flutter analyze` 确保无错误
- 运行 `dart format lib/` 格式化代码
- 编写测试覆盖新功能

---

## 📄 许可证

MIT License - 详见 [LICENSE](LICENSE)

---

## 🔗 相关项目

- [DeepSeek Harness (dsh)](https://github.com/deepseek-ai/deepseek-harness) - AI 编码助手
- [OpenClaw](https://github.com/anthropics/openclaw) - AI Gateway
- [Ollama](https://ollama.ai/) - 本地 LLM 推理
- [Termux](https://termux.dev/) - Android 终端模拟器
- [dsh-termux](https://github.com/ErEbusE/dsh-termux) - Termux 上的 dsh 运行时
- [openclaw-termux](https://github.com/mithun50/openclaw-termux) - Flutter + OpenClaw 集成

---

## 🙏 致谢

感谢所有上游项目的贡献者，以及 Android 开发者社区的支持。

---

<p align="center">
  Made with ❤️ for Android developers<br>
  <sub>如果这个项目对你有帮助，请给个 ⭐ Star 支持一下！</sub>
</p>
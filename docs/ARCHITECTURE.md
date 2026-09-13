# 架构设计文档

## 概述

Termux All-in-One 采用 **Flutter App + Custom Termux Bootstrap** 的混合架构，为 Android 设备提供零配置、一键启动的 AI 开发环境。

---

## 核心架构图

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
│  │  ┌─────────┐ ┌─────────┐ ┌─────────┐ ┌─────────┐ ┌────────┐  │ │
│  │  │ nodejs  │ │  git    │ │ python  │ │  dsh    │ │ ollama │  │ │
│  │  │ -lts    │ │         │ │ 3       │ │ termux  │ │  CLI   │  │ │
│  │  └─────────┘ └─────────┘ └─────────┘ └─────────┘ └────────┘  │ │
│  └──────────────────────────────────────────────────────────────┘ │
│                                                                     │
│  ┌──────────────────────────────────────────────────────────────┐ │
│  │              Startup Overlays (启动时自动执行)                │ │
│  │  1. configure_glibc_node.sh    - 配置 Node.js 直接执行        │ │
│  │  2. write_dsh_wrapper.sh       - 生成 dsh wrapper + $BROWSER  │ │
│  │  3. setup_openclaw.sh          - 配置 OpenClaw 环境           │ │
│  │  4. setup_ollama.sh            - 配置 Ollama 路径             │ │
│  │  5. set_approval_policy.sh     - 设置审批策略为 never         │ │
│  └──────────────────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────────────────┘
```

---

## 关键技术组件

### 1. Flutter 应用层

| 模块 | 职责 | 技术栈 |
|------|------|--------|
| **EnvironmentService** | 环境检测、配置管理、进程控制 | `package:shared_preferences`, `dart:io` |
| **TerminalService** | 完整的 Shell 终端交互 | `Process.start`, `Stream` |
| **WebViewService** | 内嵌 WebView 管理 (dsh/openclaw) | `webview_flutter` |
| **NativeBridge** | 与 Android 原生层通信 | `MethodChannel`, Kotlin |

### 2. Termux Bootstrap 层

**预装包列表 (packages.txt)**:
```text
# 核心运行时
nodejs-lts          # Node.js 24 LTS - dsh/openclaw 运行环境
python3             # Python 3.12 - node-gyp 构建依赖

# 开发工具
git                 # 版本控制
openssh             # SSH 客户端
curl / wget         # 网络下载
ripgrep / fd        # 现代搜索工具
jq                  # JSON 处理

# 构建工具 (可选，约 5MB)
make / clang        # 原生模块重新编译

# Android 特有
termux-tools        # termux-open, termux-open-url 等
```

**构建流程 (make-bootstrap.sh)**:
1. 下载官方 Termux bootstrap (Alpine-based)
2. 使用 `proot` 进入 chroot 环境
3. 通过 `apk` 安装预定义包
4. 清理缓存并打包为 zip
5. 供 Flutter App 内嵌或独立分发

### 3. 启动覆盖脚本

Flutter App 首次启动时，通过 Native Bridge 执行以下初始化：

```bash
# 1. 配置 Node.js 直接执行 (bypass grun)
patchelf --set-interpreter /data/data/com.termux/files/usr/glibc/lib/ld-linux-aarch64.so.1 node

# 2. 生成 dsh wrapper (包含 $BROWSER opener)
cat > ~/dsh-termux-open <<'EOF'
#!/data/data/com.termux/files/usr/bin/sh
case "$1" in
  http://*|https://*) tool=termux-open-url ;;
  *) tool=termux-open ;;
esac
exec "$tool" "$1"
EOF

# 3. 设置审批策略
mkdir -p ~/.dsh
echo '{"approvalPolicy":"never","webPort":3080}' > ~/.dsh/config.json
```

---

## 数据流

### 服务启动流程
```
用户点击"启动 dsh"
      ↓
EnvironmentService.startDshWeb()
      ↓
NativeBridge → Process.start("dsh web --port 3080")
      ↓
Termux 内部: grun node /path/to/dsh/bin.js web --port 3080
      ↓
dsh 启动 HTTP Server → 打印 "http://localhost:3080"
      ↓
Flutter App 通过 WebViewService 加载 URL
```

### 配置持久化
```
用户修改设置
      ↓
SettingsPage.saveConfig()
      ↓
SharedPreferences (Android) / UserDefaults (iOS)
      ↓
下次启动自动加载
      ↓
EnvironmentService.loadConfig() → 应用到启动参数
```

---

## 安全考量

| 风险点 | 缓解措施 |
|--------|----------|
| 任意代码执行 | 仅执行白名单内的预装工具 (dsh/openclaw/ollama) |
| 权限滥用 | 运行时动态申请权限，最小权限原则 |
| 数据泄露 | 本地存储加密，网络请求仅限 localhost |
| 后台进程被杀 | 前台服务 + 电池优化豁免 + Wake Lock |

---

## 扩展性设计

### 新增工具步骤
1. 在 `packages.txt` 添加包名
2. 重新构建 bootstrap
3. 在 `EnvironmentService` 添加检测方法
4. 在 `HomePage` 添加工具卡片
5. 如需 Web UI，在 `WebDashboardPage` 支持新 URL

### 多架构支持
- `aarch64` (arm64-v8a) - 主流手机
- `arm` (armeabi-v7a) - 旧设备
- `x86_64` - 模拟器/平板

---

## 版本策略

| 组件 | 版本源 | 更新方式 |
|------|--------|----------|
| Flutter App | pubspec.yaml | GitHub Release |
| Termux Bootstrap | packages.txt | CI 自动重建 |
| dsh | dsh-termux Release | `dsh update -t next -y` |
| openclaw | npm / proot | `openclawx setup` |
| ollama | ollama-termux Release | 手动更新 |

---

## 部署架构

```
GitHub Actions CI/CD
      │
      ├─► flutter build apk/aab ──► GitHub Release (APK + AAB)
      │
      ├─► make-bootstrap.sh (aarch64/arm/x86_64) ──► GitHub Release (bootstrap-*.zip)
      │
      └─► 自动化测试 (analyze, test, format)
```

用户只需下载 APK 安装，首次运行自动解压内嵌的 bootstrap 并配置环境，实现真正的"开箱即用"。
# 用户指南

## 快速开始

### 方式一：安装 APK（推荐，最简单）

1. **下载 APK**
   - 访问 [GitHub Releases](https://github.com/yourname/termux-dsh-allinone/releases)
   - 下载最新的 `app-release.apk` (约 50-80MB)

2. **安装**
   - 点击 APK 文件安装
   - 如果提示"未知来源应用"，请在设置中允许安装

3. **首次运行**
   - 打开 App
   - 点击 **"开始一键设置"**
   - 等待 2-5 分钟（取决于网速和设备性能）
   - 看到"环境已就绪"后点击"进入主界面"

### 方式二：Termux 命令行安装（进阶用户）

```bash
# 安装 Termux (从 F-Droid，不要用 Play Store 版本)
# https://f-droid.org/packages/com.termux/

# 在 Termux 中运行一键安装脚本
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

## 主界面功能

### 🏠 首页 (工具仪表盘)

| 区域 | 功能 |
|------|------|
| **状态卡片** | 显示 dsh / openclaw / ollama 安装和运行状态 |
| **工具卡片** | 点击启动对应服务，显示版本号 |
| **下拉刷新** | 重新检测服务状态 |
| **右上角设置** | 进入设置页面 |

### 💻 终端页面

完整的 Shell 终端体验：
- **复制/粘贴** - 长按文本选择，工具栏操作
- **命令历史** - 上下箭头键浏览
- **Tab 补全** - 支持路径/命令补全
- **URL 点击** - 自动识别链接可点击打开
- **额外按键** - Ctrl, Esc, Tab, 方向键工具栏

常用命令：
```bash
# dsh 相关
dsh --version          # 查看版本
dsh web --port 3080    # 启动 Web UI
dsh update -t next -y  # 更新到最新版

# openclaw 相关
openclawx setup        # 首次配置
openclawx onboarding   # 配置 API Key
openclawx start        # 启动网关
openclawx status       # 查看状态

# ollama 相关
ollama serve           # 启动服务
ollama pull llama3.2:1b # 下载模型
ollama list            # 列出模型
ollama run llama3.2:1b # 交互式运行
```

### 🌐 Web 仪表盘

内嵌 WebView，无缝访问：
- **dsh Web UI** - `http://localhost:3080`
- **OpenClaw Dashboard** - `http://localhost:18789`

功能：
- 刷新/前进/后退
- 缩放控制
- 外部浏览器打开
- 自动携带认证 Token

### ⚙️ 设置页面

| 设置项 | 说明 | 默认值 |
|--------|------|--------|
| dsh Web 端口 | dsh web 监听端口 | 3080 |
| dsh 审批策略 | never=自动执行, ask=每次询问, manual=手动 | never |
| OpenClaw 端口 | 网关监听端口 | 18789 |
| Ollama 端口 | Ollama 服务端口 | 11434 |
| 默认 Ollama 模型 | 首次下载的模型 | llama3.2:1b |
| 开机自动启动 | 设备启动时自动拉起服务 | 开启 |
| 禁用电池优化 | 防止后台被杀 | 开启 |
| 启动时请求权限 | 自动申请相机/定位等权限 | 开启 |

---

## 常见问题

### Q: 首次设置卡在某个步骤怎么办？
**A**: 
- 确保网络连接正常（需要访问 GitHub、npm、NodeSource）
- 尝试切换网络或使用代理
- 查看设置日志中的错误信息
- 可以点击"重新设置"再试一次

### Q: dsh web 打不开 / 显示连接被拒绝？
**A**:
1. 确认 dsh 已安装：终端运行 `dsh --version`
2. 手动启动：`dsh web --port 3080`
3. 检查端口是否被占用：`netstat -tlnp | grep 3080`
4. 确认审批策略为 `never`：`cat ~/.dsh/config.json`

### Q: OpenClaw 启动失败 / 报错 os.networkInterfaces？
**A**:
这是 Android Bionic libc 的已知问题。解决方案：
```bash
# 重新运行配置脚本
bash scripts/setup-openclaw.sh

# 或手动添加 bypass
mkdir -p ~/.openclaw
cat > ~/.openclaw/bionic-bypass.js << 'EOF'
const os = require('os');
const originalNetworkInterfaces = os.networkInterfaces;
os.networkInterfaces = function() {
  try {
    const interfaces = originalNetworkInterfaces.call(os);
    if (interfaces && Object.keys(interfaces).length > 0) return interfaces;
  } catch (e) {}
  return { lo: [{ address: '127.0.0.1', netmask: '255.0.0.0', family: 'IPv4', mac: '00:00:00:00:00:00', internal: true, cidr: '127.0.0.1/8' }] };
};
EOF
echo 'export NODE_OPTIONS="--require ~/.openclaw/bionic-bypass.js"' >> ~/.bashrc
source ~/.bashrc
```

### Q: Ollama 下载模型很慢 / 失败？
**A**:
- 使用国内镜像：`export OLLAMA_HOST=http://localhost:11434`
- 手动下载模型文件放到 `~/.ollama/models/` 或 `/sdcard/ollama-models/`
- 选择小模型：`llama3.2:1b` (约 1.3GB) 或 `qwen2:0.5b` (约 400MB)

### Q: 后台服务被系统杀死？
**A**:
1. **设置中开启"禁用电池优化"**
2. 手动设置：设置 → 电池 → 应用管理 → Termux All-in-One → 允许后台运行
3. Termux 设置：设置 → 应用 → Termux → 电池 → 无限制
4. 使用前台服务通知保持活跃

### Q: 权限被拒绝 (Permission denied)？
**A**:
```bash
# 授予存储权限
termux-setup-storage

# 检查文件权限
ls -la ~/.dsh/
ls -la ~/.openclaw/
```

---

## 进阶用法

### 自定义 Bootstrap

如果你想预装额外的包，修改 `bootstrap/scripts/packages.txt`：

```text
# 添加你需要的包
golang
rust
docker
# 等等...
```

然后重新构建：
```bash
cd bootstrap/scripts
ARCH=aarch64 bash make-bootstrap.sh
```

### 多设备同步配置

配置文件位置：
- `~/.dsh/config.json` - dsh 配置
- `~/.openclaw/openclaw.json` - OpenClaw 配置
- `~/.ollama/config` - Ollama 配置

可通过 Syncthing 或手动同步这些文件。

### 开发调试

查看 Flutter 日志：
```bash
# 连接手机 USB 调试
flutter logs

# 或使用 adb
adb logcat | grep -i flutter
```

查看 Termux 后台进程：
```bash
# 在 App 终端或独立 Termux 中
ps aux | grep -E 'dsh|openclaw|ollama'
netstat -tlnp
```

---

## 卸载清理

### 卸载 App
长按图标 → 卸载，或设置 → 应用 → 卸载

### 完全清理数据（可选）
```bash
# 在 Termux 中运行
rm -rf ~/.dsh
rm -rf ~/.openclaw
rm -rf ~/.ollama
rm -rf ~/.local/opt/dsh-termux-runtime
rm ~/.local/bin/dsh
rm ~/.local/bin/openclawx
rm ~/.local/bin/ollama-termux

# 从 .bashrc 移除相关行
sed -i '/dsh-termux/d' ~/.bashrc
sed -i '/bionic-bypass/d' ~/.bashrc
sed -i '/ollama-termux/d' ~/.bashrc
source ~/.bashrc
```

---

## 获取帮助

- **GitHub Issues**: [提交 Bug/功能请求](https://github.com/yourname/termux-dsh-allinone/issues)
- **dsh 文档**: https://github.com/deepseek-ai/deepseek-harness
- **OpenClaw 文档**: https://github.com/anthropics/openclaw
- **Ollama 文档**: https://ollama.ai/docs
- **Termux Wiki**: https://wiki.termux.com/

---

## 版本历史

| 版本 | 日期 | 变更 |
|------|------|------|
| 1.0.0 | 2025-01-XX | 首个正式版本 |

---

*Made with ❤️ for Android developers*
# 构建指南

本文档详细说明如何从源码构建 Termux All-in-One 的所有组件。

---

## 环境要求

### Flutter App 构建环境
| 组件 | 版本要求 |
|------|----------|
| Flutter SDK | 3.24.3+ (stable channel) |
| Dart SDK | 3.5.0+ (随 Flutter) |
| Android SDK | API 35 (Android 15) |
| Java/JDK | 17 (Temurin/OpenJDK) |
| Gradle | 8.2+ (随 Android Gradle Plugin) |
| Kotlin | 1.9.22+ |

### Bootstrap 构建环境
| 组件 | 版本要求 |
|------|----------|
| 操作系统 | Linux (推荐 Ubuntu 22.04+ / Debian 12+) |
| 架构 | aarch64 (arm64) - 必须在 arm64 上构建 |
| proot | 5.3.0+ |
| apk (Alpine) | 2.14+ |
| zip/unzip | 任意版本 |
| curl | 任意版本 |

---

## 快速开始

### 1. 克隆仓库
```bash
git clone https://github.com/yourname/termux-dsh-allinone.git
cd termux-dsh-allinone
```

### 2. 构建 Flutter APK (任意平台)
```bash
cd flutter_app

# 安装依赖
flutter pub get

# 代码生成 (如有 json_serializable 等)
dart run build_runner build --delete-conflicting-outputs

# 构建 Release APK (arm64)
flutter build apk --release --target-platform android-arm64

# 构建 Release AAB (Play Store)
flutter build appbundle --release

# 输出位置:
# build/app/outputs/flutter-apk/app-release.apk
# build/app/outputs/bundle/release/app-release.aab
```

### 3. 构建 Custom Bootstrap (必须在 Linux arm64 上)

#### 选项 A: GitHub Actions (推荐，免费 arm64 runner)
直接推送 tag 触发 CI，自动构建多架构 bootstrap。

#### 选项 B: 本地 arm64 机器 (树莓派 4/5, ARM 云服务器, Apple Silicon Mac 通过 UTM)
```bash
cd bootstrap/scripts

# 安装依赖
sudo apt-get update
sudo apt-get install -y proot zip unzip curl

# 构建 aarch64 (默认)
bash make-bootstrap.sh

# 构建 32-bit arm
ARCH=arm bash make-bootstrap.sh

# 构建 x86_64 (模拟器)
ARCH=x86_64 bash make-bootstrap.sh

# 自定义 bootstrap 源
BOOTSTRAP_BASE_URL=https://your-mirror.com/termux-bootstrap \
bash make-bootstrap.sh

# 输出位置:
# ../out/bootstrap-aarch64.zip
# ../out/bootstrap-arm.zip
# ../out/bootstrap-x86_64.zip
```

#### 选项 C: Docker (x86_64 主机交叉构建)
```dockerfile
# Dockerfile.bootstrap
FROM ubuntu:22.04

RUN apt-get update && apt-get install -y \
    proot zip unzip curl qemu-user-static \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /build
COPY bootstrap/scripts/ ./scripts/
RUN ARCH=aarch64 bash scripts/make-bootstrap.sh

# 然后 docker build -t bootstrap-builder . && docker run --rm -v $(pwd)/out:/build/out bootstrap-builder
```

---

## 详细构建步骤

### Flutter App 详细配置

#### Android 签名配置 (发布必需)
创建 `flutter_app/android/key.properties`：
```properties
storePassword=your_keystore_password
keyPassword=your_key_password
keyAlias=your_key_alias
storeFile=../release.keystore
```

在 `flutter_app/android/app/build.gradle` 中添加：
```gradle
def keystoreProperties = new Properties()
def keystorePropertiesFile = rootProject.file('key.properties')
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(new FileInputStream(keystorePropertiesFile))
}

android {
    ...
    signingConfigs {
        release {
            keyAlias keystoreProperties['keyAlias']
            keyPassword keystoreProperties['keyPassword']
            storeFile file(keystoreProperties['storeFile'])
            storePassword keystoreProperties['storePassword']
        }
    }
    buildTypes {
        release {
            signingConfig signingConfigs.release
            minifyEnabled true
            shrinkResources true
            proguardFiles getDefaultProguardFile('proguard-android-optimize.txt'), 'proguard-rules.pro'
        }
    }
}
```

#### 生成签名密钥
```bash
keytool -genkey -v \
  -keystore flutter_app/release.keystore \
  -alias termux-allinone \
  -keyalg RSA \
  -keysize 2048 \
  -validity 10000
```

#### Flutter 图标与启动画面
```bash
# 安装 flutter_launcher_icons
flutter pub add --dev flutter_launcher_icons

# 配置 pubspec.yaml
flutter_icons:
  android: true
  ios: true
  image_path: "assets/icons/app_icon.png"
  adaptive_icon_background: "assets/icons/adaptive_background.png"
  adaptive_icon_foreground: "assets/icons/adaptive_foreground.png"

# 生成
dart run flutter_launcher_icons
```

### Bootstrap 详细构建流程

#### make-bootstrap.sh 内部原理
```bash
# 1. 下载官方 bootstrap
curl -fL https://github.com/termux/termux-app/releases/download/bootstrap-20240907/bootstrap-aarch64.zip

# 2. 解压到工作目录
unzip -q bootstrap.zip -d rootfs

# 3. 进入 proot 环境安装包
proot \
  --rootfs=rootfs \
  --root-id \
  --kill-on-exit \
  --bind=/proc:/proc \
  --bind=/sys:/sys \
  --bind=/dev:/dev \
  --link2symlink \
  -b install-packages.sh:/install-packages.sh \
  -b packages.txt:/packages.txt \
  -w /data/data/com.termux/files/usr \
  /data/data/com.termux/files/usr/bin/bash /install-packages.sh

# 4. 打包
cd rootfs && zip -qr ../out/bootstrap-aarch64.zip .
```

#### 自定义包版本锁定
在 `packages.txt` 中指定版本：
```text
nodejs-lts:24.18.0
python3:3.12.3
git:2.45.1
```

查看可用版本：
```bash
# 在 proot 环境中
apk search nodejs-lts
apk policy nodejs-lts
```

---

## CI/CD 自动化

### GitHub Actions 工作流

项目包含 `.github/workflows/build.yml`，支持：

| 触发条件 | 动作 |
|----------|------|
| Push to main | 运行测试、代码检查 |
| Push tag `v*` | 构建 APK/AAB + 多架构 Bootstrap + 创建 Release |
| Pull Request | 运行测试、代码检查 |
| 手动触发 | 手动构建 |

### 本地模拟 CI
```bash
# 运行所有检查
cd flutter_app
flutter analyze
dart format --output=none --set-exit-if-changed lib/
flutter test

# 构建验证
flutter build apk --release --target-platform android-arm64
```

---

## 多架构支持

### 支持的架构
| 架构 | Android ABI | 用途 |
|------|-------------|------|
| aarch64 | arm64-v8a | 现代手机 (默认) |
| arm | armeabi-v7a | 旧设备 (2019年前) |
| x86_64 | x86_64 | 模拟器、部分平板 |

### 构建所有架构
```bash
# 本地构建 (需要对应架构机器或 qemu-user-static)
for arch in aarch64 arm x86_64; do
    ARCH=$arch bash bootstrap/scripts/make-bootstrap.sh
done
```

### Flutter 多架构 APK
```bash
# 单个 APK 包含多架构 (体积较大)
flutter build apk --release

# 分架构 APK (推荐，体积小)
flutter build apk --release --target-platform android-arm64
flutter build apk --release --target-platform android-arm
flutter build apk --release --target-platform android-x64
```

---

## 故障排查

### Flutter 常见问题

**Q: `flutter: command not found`**
```bash
# 添加到 PATH
export PATH="$PATH:`pwd`/flutter/bin"
# 或使用 FVM
fvm use 3.24.3
```

**Q: Gradle 内存不足**
```bash
# flutter_app/android/gradle.properties
org.gradle.jvmargs=-Xmx4096m -Dkotlin.daemon.jvm.options="-Xmx2048m"
```

**Q: 签名错误**
```bash
# 清理并重新构建
flutter clean
flutter pub get
flutter build apk --release
```

**Q: 依赖冲突**
```bash
# 查看依赖树
flutter pub deps

# 强制版本
dependency_overrides:
  some_package: ^1.2.3
```

### Bootstrap 常见问题

**Q: `proot: command not found`**
```bash
sudo apt-get install proot
# 或
# 下载静态编译版本
curl -fL https://github.com/proot-me/proot-static-build/releases/download/v5.3.0/proot-x86_64 -o /usr/local/bin/proot
chmod +x /usr/local/bin/proot
```

**Q: `apk: not found` (在 proot 内)**
```bash
# 确保 bootstrap 基础镜像完整
# 官方 bootstrap 已包含 apk
# 如果缺失，手动安装 alpine-base
```

**Q: 网络下载失败**
```bash
# 使用国内镜像
BOOTSTRAP_BASE_URL=https://mirrors.tuna.tsinghua.edu.cn/termux/bootstrap \
bash make-bootstrap.sh

# 或设置代理
export HTTP_PROXY=http://proxy:port
export HTTPS_PROXY=http://proxy:port
```

**Q: 构建产物过大**
```bash
# 清理 apk 缓存
# make-bootstrap.sh 已包含: apk clean

# 移除文档和 man pages
# 在 install-packages.sh 中添加:
# apk add --no-cache --no-docs <packages>
```

---

## 发布清单

发布新版本前检查：

- [ ] 更新 `flutter_app/pubspec.yaml` 版本号
- [ ] 更新 `bootstrap/scripts/packages.txt` (如有包更新)
- [ ] 运行完整测试套件 `flutter test`
- [ ] 代码格式检查 `dart format --set-exit-if-changed lib/`
- [ ] 静态分析 `flutter analyze` 无错误
- [ ] 本地构建 APK 验证安装运行
- [ ] 本地构建 Bootstrap 验证包含所有包
- [ ] 创建 Git tag: `git tag v1.0.0 && git push origin v1.0.0`
- [ ] GitHub Actions 自动构建并创建 Release
- [ ] 验证 Release 页面包含: APK, AAB, bootstrap-*.zip
- [ ] 更新文档 (CHANGELOG.md 等)

---

## 性能优化

### APK 体积优化
```gradle
// flutter_app/android/app/build.gradle
android {
    buildTypes {
        release {
            minifyEnabled true
            shrinkResources true
            proguardFiles getDefaultProguardFile('proguard-android-optimize.txt'), 'proguard-rules.pro'
        }
    }
    // 移除不需要的架构
    defaultConfig {
        ndk {
            abiFilters 'arm64-v8a' // 只保留 arm64
        }
    }
}
```

### Bootstrap 体积优化
```bash
# 在 install-packages.sh 中
apk add --no-cache --no-docs <packages>
# 移除: /usr/share/doc, /usr/share/man, /var/cache/apk/*
```

### 启动速度优化
- 使用 Flutter 的 `deferred components` 延迟加载非首页页面
- Bootstrap 预编译 Node.js 原生模块
- 启用 Flutter 的 `--split-debug-info` 减少调试符号

---

## 跨平台构建矩阵

| 目标平台 | 构建机器 | 交叉编译 | 备注 |
|----------|----------|----------|------|
| Android arm64 | Linux arm64 / GitHub Actions | 否 | 原生构建 |
| Android arm | Linux arm / qemu | 是 | 需要 qemu-user |
| Android x86_64 | Linux x86_64 | 否 | 原生构建 |
| iOS | macOS | 否 | 需要 Xcode |
| Web | 任意 | N/A | `flutter build web` |

---

## 资源链接

- [Flutter 官方构建文档](https://docs.flutter.dev/deployment/android)
- [Termux Bootstrap 官方仓库](https://github.com/termux/termux-app)
- [proot 文档](https://github.com/proot-me/proot)
- [GitHub Actions arm64 runners](https://github.com/actions/runner-images)
- [Android 签名指南](https://developer.android.com/studio/publish/app-signing)
# HarmonyOS NEXT 开发教程

更新：2026-11-16。面向在 `LKM-desktop` 上继续做鸿蒙适配的开发者。

本文是操作手册；插件取舍的完整依据见 [插件审计](HARMONYOS_PLUGIN_AUDIT.md)、
[替换进度](HARMONYOS_PLUGIN_REPLACEMENTS.md) 和 [剩余处理清单](HARMONYOS_REMAINING_MATRIX.md)，
逐阶段构建记录与哈希见 [Linux 构建记录](HARMONYOS_LINUX_BUILD.md)。

## 1. 目标与边界

- **同一份应用**：所有平台共用根 `pubspec.yaml`、锁文件和 `lib/`；
  不建立鸿蒙专用业务副本，也不维护第二套界面。
- **产物是 HAP**：宿主在 `ohos/`，通过 FlutterAbility 加载现有 `lib/main.dart`，
  不是 WebView 套壳。
- **当前唯一验证过的构建宿主是 Linux x64**。Windows/macOS 宿主未验证。
- **构建成功不等于可用**：无签名证书、无 HDC 设备时，只能宣称
  「源码接入、依赖求解、Dart/ArkTS 编译、HAP 打包与静态校验通过」。

## 2. 工程结构

| 路径 | 作用 |
| --- | --- |
| `.flutter-version` | 固定 `3.47.9-ohos-1.0.0`，对应 Dart 3.13.4 |
| `ohos/` | OHOS 宿主：EntryAbility、深链桥、权限、图标、版本号 |
| `ohos/AppScope/app.json5` | bundleName、versionCode/versionName |
| `ohos/entry/src/main/module.json5` | 权限、scheme、NFC/推送/快捷方式入口 |
| `packages/` | 本地 vendored 包与 OHOS 后端（每个包附 `UPSTREAM.md`） |
| `buildtools/env-ohos.sh` | SDK/NDK/JDK/Node/HDC/Rust 环境变量 |
| `buildtools/build-ohos.sh` | Linux 一键构建 + HAP 校验 |
| `buildtools/prepare-ohos-media.py` | 按固定哈希准备 libmpv / WebRTC |
| `buildtools/verify-ohos-*.mjs` | 直接用 Node 跑真实 ArkTS 后端逻辑（SDK 打桩） |
| `test/core/ohos_*.dart` | OHOS 相关 Dart 回归 |

宿主中 `entry/src/main/resources/rawfile/flutter_assets/`、`entry/build/`、`.hvigor/`、
`node_modules/`、`oh_modules/` 都是生成物，已由 `.gitignore` 排除，**不要手改或提交**。
`entry/libs/` 默认忽略 `*.so`，但当前有两个历史跟踪文件
（`libopenmls_frb.so`、`libsqlite3.so`）；替换它们时必须与 native-assets 输出和
`verify-ohos-hap.py` 的检查一起确认。`GeneratedPluginRegistrant` 由 Flutter 生成。

### 关键入口

- `EntryAbility.ets`：初始化 Huawei Push、分发快捷方式、接收 `lkm://`/`solian://`
  深链，注册插件。
- `DeepLinkBridge.ets`：复用 Apple 宿主的 `consumePendingDeepLink` / `onDeepLink`
  契约，Dart 侧不需要第二套路由。
- `module.json5`：新增权限必须同时写 `reason` 与 `usedScene`，并补
  `resources/base|en_US|zh_CN/element/string.json` 的文案。

## 3. 环境准备

### 3.1 版本组合

| 组件 | 版本 |
| --- | --- |
| 宿主系统 | Linux x64 |
| Command Line Tools | 26.0.0.865 |
| HarmonyOS SDK / NDK | 26.0.0.105，API 26 |
| JDK | Temurin 21 |
| Node.js（SDK 内置） | 24.x |
| OHPM / Hvigor / HDC | 26.0.0.630 / 6.26.9 / 3.2.0f |
| Rust | 安装 `aarch64-unknown-linux-ohos` target |
| OH-Flutter | `3.47.9-ohos-1.0.0` |
| Dart | 3.13.4（定制 Linux 构建，已装入 Flutter 缓存） |

安装目录默认是 `~/harmonyos/command-line-tools`；可用
`LKM_HARMONYOS_HOME`、`LKM_OHOS_JAVA_HOME` 覆盖。

### 3.2 加载环境

```bash
source buildtools/env-ohos.sh
flutter --version          # 必须是 3.47.9-ohos-1.0.0
ohpm -v
hvigorw -v
hdc list targets           # 无设备时输出 [Empty]
rustup target list --installed | grep ohos
```

`env-ohos.sh` 必须是 **source**，不能 `bash` 执行，否则变量不会留在当前终端。
它还会把 `flutter`、`ohpm`、`hvigorw`、`hdc` 和 NDK 工具加入 `PATH`。

### 3.3 两个不能随意动的缓存

- **不要 `flutter precache`**：当前 OH-Flutter 缓存中 `flutter_tester`、Dart 3.13.4、
  `gen_snapshot` 是手工校准的，precache 会覆盖它们。
- **不要 `flutter precache --web`**：会把 Web 调试用的官方 3.47.5 SDK 换回
  engine.ohos 的旧包。Web 调试的适配步骤见构建记录。

## 4. 首次拉起

```bash
# 1. 环境
source buildtools/env-ohos.sh

# 2. 给 OH-Flutter 应用 native-assets 补丁（保留真实 OS.ohos）
bash buildtools/patch-ohos-sdk.sh

# 3. 依赖
flutter pub get

# 4. 原生媒体库（按固定提交与 SHA-256 下载，生成物不入 Git）
python3 buildtools/prepare-ohos-media.py

# 5. 编译与测试
PATH="/usr/bin:$PATH" flutter test --no-pub
flutter analyze --no-pub

# 6. 首次 HAP
./buildtools/build-ohos.sh --debug
```

`buildtools/setup-dev.sh` 也会执行第 2 步；如果你重装/切换了 Flutter SDK，
重新执行 `patch-ohos-sdk.sh` 即可，重复执行是幂等的。

### 4.1 GitCode 返回 418

本机访问 GitCode 时普通 Git User-Agent 会被拒绝：

```bash
git config --global http.https://gitcode.com/.userAgent Mozilla/5.0
git config --global http.https://atomgit.com/.userAgent Mozilla/5.0
```

只匹配这两个域名，不要设置成全局 User-Agent。

### 4.2 WebF 仓库断流

WebF 固定提交的完整克隆可能报 `curl 18 / early EOF`。按构建记录中的步骤，
为 `~/.pub-cache/git/cache/fluttertpc_webf-d20964bca5b6fee17fe1e9363e818d5199752aa3`
做一次浅获取并 `fsck`，再执行 `flutter pub get`。升级 WebF pin 时同步更新该缓存的
refspec，或移开缓存让 Pub 重新克隆。

## 5. 日常开发命令

| 目的 | 命令 |
| --- | --- |
| 静态检查 | `flutter analyze --no-pub` |
| 全量 Dart 测试 | `PATH="/usr/bin:$PATH" flutter test --no-pub` |
| 定向 OHOS 回归 | `PATH="/usr/bin:$PATH" flutter test --no-pub test/core/ohos_*.dart test/shared/ohos_ui_compatibility_test.dart` |
| ArkTS 后端逻辑 | `for s in buildtools/verify-ohos-*.mjs; do node "$s" || exit 1; done` |
| native-assets 探针 | `PATH="/usr/bin:$PATH" dart run buildtools/verify-ohos-native-assets.dart` |
| debug HAP | `./buildtools/build-ohos.sh --debug` |
| release HAP | `./buildtools/build-ohos.sh --release` |
| 单独构建 | `flutter build hap --release --no-pub --no-codesign --target-platform ohos-arm64` |
| 校验 HAP | `python3 buildtools/verify-ohos-hap.py --require-aot` |

为什么测试要带 `PATH="/usr/bin:$PATH"`：本机 Lean 的 clang 排在 PATH 前面，
会让 native-assets 选中错误编译器。

为什么用 `--no-pub`：避免每次测试重新解析 Git 依赖；依赖变更后才显式
`flutter pub get`。

**当前基线**：全量 `892 passed / 0 failed / 3 skipped`（2026-11-15 修复测试后）。
低于此数或出现新失败文件时，先对照 [Linux 构建记录](HARMONYOS_LINUX_BUILD.md)
的失败集合，再单跑确认是否为计时类噪声。

### 5.1 HAP 校验器检查什么

`verify-ohos-hap.py` 会检查：

- ZIP CRC 完整；
- 动态库是 ARM64 OHOS ELF，拒绝 GNU/Linux 依赖；
- `DT_NEEDED` 指向的库都在包内；
- release 包含 AOT `libapp.so`；
- 关键 N-API / FFI 导出存在；
- 业务需要的运行库名单齐全。

它**不检查**签名、设备兼容、权限弹窗、相机/麦克风/NFC 的真实能力。

### 5.2 真机调试（拿到设备后）

```bash
hdc list targets
flutter devices
flutter run -d <device-id>          # 设备需已授权；安装包必须已签名
hdc hilog | grep -i flutter
```

签名步骤见 §8。`build-ohos.sh` 固定带 `--no-codesign`，签名后应直接用
`flutter build hap` 或调整脚本参数。没有签名证书时不要用未签名产物冒充可安装包。

## 6. 接入或升级一个插件

### 6.1 先判断属于哪一类

1. **OHOS 官方/社区有同版实现**：在 `pubspec.yaml` 的 `dependency_overrides`
   固定到 40 位 commit。
2. **只有旧版适配源**：把 OHOS 后端移植到当前版本，**不要降级主包或平台接口**。
3. **纯 Flutter 包但含平台 switch**：补 `TargetPlatform.ohos` 分支，优先保留
   现有 Android 行为。
4. **桌面/Apple 专属能力**：用平台白名单保护，不向 OHOS 暴露；不伪造原生能力。
5. **没有可用实现**：明确失败（`UnsupportedError`/能力不可用），
   不要静默成功或假装支持。

### 6.2 标准接入流程

```text
审计当前版本
  → 选择同版适配源或本地移植
  → 固定 40 位 commit / 本地包 + UPSTREAM.md
  → 插件 pubspec 声明 ohos 平台
  → ArkTS 后端 + Dart 注册
  → module.json5 权限/入口
  → test/core/ohos_*.dart + buildtools/verify-ohos-*.mjs
  → flutter analyze + 全量测试
  → build-ohos.sh + verify-ohos-hap.py
  → 更新三份鸿蒙文档
```

### 6.3 依赖覆盖示例

```yaml
dependency_overrides:
  foo:
    git:
      url: https://gitcode.com/oh-flutter/foo.git
      ref: 0123456789abcdef0123456789abcdef01234567
      path: packages/foo/foo
```

规则：

- 只用固定 commit，不用 `main`/开发分支名。
- 主包、平台接口、各平台实现尽量来自同一仓库同一提交。
- 本地修改收进 `packages/<name>_ohos/`，保留上游 LICENSE，
  在 `UPSTREAM.md` 写清来源、固定提交、改了什么、**没做什么**。
- 不引入鸿蒙专用 `pubspec_ohos.yaml` 或业务分支。

### 6.4 插件平台声明

```yaml
flutter:
  plugin:
    platforms:
      ohos:
        pluginClass: FooPlugin
```

federated 插件则实现 `FooOhos.registerWith()`，并确保生成的
`GeneratedPluginRegistrant.ets` 包含该注册。

### 6.5 ArkTS 后端与权限

- 通道必须等待真实 SDK 结果再回复；失败回传错误，不提前返回成功。
- 资源（FD、Uri、相机、录音、NFC 会话）在成功、取消、异常三条路径都要释放。
- 新增系统权限同步写 `module.json5`：

```json5
{
  "name": "ohos.permission.CAMERA",
  "reason": "$string:camera_reason",
  "usedScene": { "abilities": ["EntryAbility"], "when": "inuse" }
}
```

`reason` 的字符串要同时补 `base`、`en_US`、`zh_CN` 三份资源。

### 6.6 ArkTS 严格模式常见拒绝项

浏览器的 TypeScript 能过，不代表 ArkTS 能过。当前构建实际踩过的错误：

| 写法 | ArkTS 错误 | 改法 |
| --- | --- | --- |
| `constructor(private x: T)` | `arkts-no-ctor-prop-decls` | 先声明字段，再在构造器里赋值 |
| `{ ...base, extra }` | `arkts-no-spread` | 逐字段显式构造目标类型 |
| `const r: Record<string, Object> = {...}` | `arkts-no-untyped-obj-literals` | 用 `Record<string, ESObject>`、显式接口或类 |
| `.map(x => ({ id, title }))` | `arkts-no-untyped-obj-literals` | 回调显式标注返回类型，或先赋值给具名类型 |
| `throw error`（`error` 为 unknown） | `arkts-limited-throw` | `throw new Error(String(error))` |
| `fs.OpenMode.EXCL` | 属性不存在 | 先 `fs.accessSync(path)` 判存在，再 `CREATE｜TRUNC` |
| 声明了 `pluginClass` 却没有对应 `.ets` | `Cannot find module` | 先实现原生插件；未实现的平台只保留 `dartPluginClass` |

原则：**平台声明必须和真实实现一致**。没有原生后端就不要声明 `pluginClass`，
否则 Hvigor 会在编译期直接失败。

### 6.7 必须留下的验证

- Dart 侧：`test/core/ohos_<能力>_test.dart`，用 fake 通道验证参数、错误与清理。
- ArkTS 侧：`buildtools/verify-ohos-<能力>.mjs`，直接加载真实 `.ets` 后端，
  对 SDK 边界打桩。
- 构建侧：`verify-ohos-hap.py` 的库名单/导出一旦新增就补进去。
- 文档侧：更新本教程、替换进度和剩余处理清单。

以上都是「源码/编译级」证据；硬件能力仍需真机验收。

## 7. 业务层平台分支约定

### 7.1 判断 OHOS 的写法

业务 `lib/` 统一用系统字符串，避免依赖 OH-Flutter 才有的 API：

```dart
final isOhos = Platform.operatingSystem == 'ohos';
```

`TargetPlatform.ohos` 只在确实需要 UI 行为分支、且该文件由 OH-Flutter 编译时使用
（现有例子见 `material_ui`、`settings_auth_factors.dart`）。

### 7.2 触摸设备判定

鸿蒙手机应和 Android/iOS 一样走触摸交互，而不是桌面 hover/右键/悬浮控件：

```dart
final isMobile = !kIsWeb &&
    (Platform.isAndroid ||
        Platform.isIOS ||
        Platform.operatingSystem == 'ohos');
```

已经覆盖：

- 帖子/消息的更多操作入口与滑动手势；
- 消息文本选择与头像动画；
- 视频播放器控件；
- 个人页/设置中的 NFC 护照扫描入口；
- 应用评价、相机入口、深链、推送、快捷方式。

审计命令：

```bash
grep -rn "Platform.isAndroid || Platform.isIOS" lib/
```

逐条判断：触摸交互 → 加 OHOS；Apple/Android 专属原生能力 → 保持排除并写清原因。

### 7.3 有意排除的能力

以下保持平台白名单，不要为了“看起来完整”强行打开：

| 能力 | 原因 |
| --- | --- |
| Firebase 初始化/分析 | OHOS 不初始化 Firebase 原生服务 |
| Apple IAP / StoreKit | 华为内购需要 AGC 商品与服务端验单，未接入 |
| Apple 图标切换、CallKit 专属路径、iOS 分享建议/通信通知 | Apple 原生能力 |
| 桌面多窗口、托盘、窗口管理、桌面 presence | 仅桌面目标 |
| 系统级拖放 | 手机继续用文件/图片选择器 |
| Android/iOS 分享“接收”入口 | 宿主尚未配置 want 接收；Dart 侧保持关闭 |
| 系统桌面卡片/Widget 同步 | OHOS 卡片需独立原生实现 |

## 8. 版本号与签名

### 8.1 版本号必须同步

`pubspec.yaml` 的 `version: 4.2.0+316` 对应
`ohos/AppScope/app.json5` 的 `versionName` / `versionCode`。
发版前两者一起改，否则设备与商店看到的是旧版本。

### 8.2 签名

当前 `ohos/build-profile.json5` 的 `signingConfigs` 为空，所有 HAP 都是
`--no-codesign`。拿到证书后：

1. 在 DevEco Studio 或 AGC 生成签名材料（证书、Profile、密钥库）。
2. 在 `build-profile.json5` 填 `signingConfigs`：

```json5
{
  "name": "default",
  "type": "HarmonyOS",
  "material": {
    "certpath": "/secure/path/app.cer",
    "storePassword": "******",
    "keyAlias": "lkm",
    "keyPassword": "******",
    "profile": "/secure/path/app.p7b",
    "signAlg": "SHA256withECDSA",
    "storeFile": "/secure/path/app.p12"
  }
}
```

3. 签名材料与密码**不得提交**；CI 用 Secret 注入或使用本地未跟踪配置。
4. 用签名配置重新构建（不带 `--no-codesign`），再按 §9 做真机验收。

### 8.3 推送与内购

- 远程推送：客户端 token 注册与服务端 PS256 v3 发送已接入 compose/k8s；
  仍需 AGC Push Kit 应用、服务账号密钥、签名真机才能实发。见 [推送说明](HARMONYOS_PUSH.md)。
- 华为内购：当前没有商户、商品与服务端验单，`supportsIap` 只在 Apple 目标为真；
  不要复用 Apple 流程冒充可用。

## 9. 验收边界与清单

### 9.1 构建/静态验证可以证明

- 依赖在 OH-Flutter 下可求解；
- Dart/ArkTS 可编译，release 含 ARM64 AOT；
- 打包后的运行库架构、依赖和 FFI/N-API 导出正确；
- Dart 回归、ArkTS 边界回归通过。

### 9.2 真机验收清单

- [ ] 冷/暖启动、深链 `lkm://` / `solian://`
- [ ] 登录、找回、2FA、Passkey（真实 RP/签名关联）
- [ ] 相机、图片选择、录音、相册保存、文件选择/保存
- [ ] NFC 标签读写与护照扫描
- [ ] 通知权限、前台展示、点击跳转、后台/杀进程接收
- [ ] 远程推送（AGC 配置后）
- [ ] 音视频播放、通话、扬声器路由
- [ ] 应用评价弹窗、快捷方式、地图跳转
- [ ] 升级安装、版本号显示、卸载重装后的本地数据行为

### 9.3 当前已知缺口

| 缺口 | 状态 |
| --- | --- |
| HAP 签名 | 无证书，全部未签名 |
| 真机运行 | 无 HDC 设备，未验收 |
| 华为远程推送实发 | 代码与部署已通，缺 AGC/签名真机 |
| 华为内购 | 未实现（无消费方） |
| Passkeys 生产验收 | 缺 RP/域名/签名关联 |
| 媒体 E2EE、WebRTC 原生录制/截图/指定输入 | 当前原生库不支持，明确失败 |
| 扫码前摄/USB/远端相机、反色分析 | 仅后摄 ScanKit 路径 |
| 后台连续录音、自动中断恢复 | 未实现 |
| 分享接收、桌面卡片、OK 托盘 | OHOS 无原生日志/入口 |

## 10. 排障速查

| 现象 | 原因 | 处理 |
| --- | --- | --- |
| `pub get` 418 | GitCode 拒绝默认 UA | 设置上述 `http.<host>.userAgent` |
| WebF `curl 18` / `early EOF` | 大仓库断流 | 按 §4.2 准备固定提交缓存 |
| native-assets 选了 Linux/GTK 库 | SDK 把 `OS.ohos` 映射成 `linux` | 跑 `patch-ohos-sdk.sh` |
| native-assets 选错 clang | Lean clang 在 PATH 前 | 命令前加 `PATH="/usr/bin:$PATH"` |
| `Invalid SDK hash` | 测试引擎与 Dart 3.13.4 不匹配 | 换回校准的 Linux `flutter_tester` |
| Web 调试 kernel 版本不匹配 | OH-Flutter 的 Web SDK 是旧批次 | 按构建记录换官方 3.47.5 Web SDK |
| ArkTS 编译报非 Error 抛出 | ArkTS 只允许抛确定 Error 类型 | 包成 `new Error(...)` |
| 合并上游后报 `Unsupported OS: ohos` | 上游覆盖了 vendored 包的 OHOS hook | 按 git 历史恢复 `packages/*/hook/ohos.dart` 与 `build.dart` 的 OHOS 分支 |
| 合并上游后报找不到插件模块 | 上游覆盖了插件平台声明或实现文件 | 对照合并前后的 `pubspec.yaml` / `ohos/` 目录补齐 |
| HAP 校验缺 AOT | release 参数没生效 | 用 `--release`，校验加 `--require-aot` |
| 金图测试差异 | 字体/渲染批次变化 | 确认差异合理后 `--update-goldens` |
| `hdc list targets` 为 `[Empty]` | 无设备/未授权 | 接设备、开调试、确认签名 |

## 11. 文档索引

- [插件审计](HARMONYOS_PLUGIN_AUDIT.md)：替换前的完整快照与候选来源。
- [替换进度](HARMONYOS_PLUGIN_REPLACEMENTS.md)：固定提交、本地移植、接口边界。
- [剩余处理清单](HARMONYOS_REMAINING_MATRIX.md)：26 个剩余插件与能力边界。
- [Linux 构建记录](HARMONYOS_LINUX_BUILD.md)：工具链校准、HAP 哈希、逐阶段验证。
- [推送说明](HARMONYOS_PUSH.md)：AGC 配置、服务端变量、部署接线。

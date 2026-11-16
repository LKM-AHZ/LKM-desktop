# 鸿蒙剩余插件统一处理清单

更新：2026-11-15。所有平台共用 `pubspec.yaml`、锁文件和业务 `lib/`；不维护鸿蒙应用副本。环境与接入流程见 [开发教程](HARMONYOS_DEVELOPMENT.md)。下表针对第六阶段结束时剩余的 26 个主插件声明，以及播放器配套依赖。源码接入与构建检查不等于硬件或云服务验收。

## 本轮新增的实际后端

| 依赖（保留当前版本） | 已处理的业务能力 | 明确边界 |
| --- | --- | --- |
| geocoding 5.0.1 | 当前工厂 API、地址/坐标转换、每请求语言隔离；共享天气入口开放 OHOS | 系统服务覆盖、网络和真实结果待设备确认 |
| flutter_nfc_kit 3.7.0 | 前台 readerMode、当前 poll/tag/NDEF 通道与异常清理 | NFC_TAG 权限；实际标签/芯片能力待验，后台派发不作承诺 |
| mobile_scanner 7.5.0 | 当前协议、后摄ScanKit、前摄/USB/远端摄像头CameraKit选择与NV21解码、旋转坐标/图像、缩放/暂停/资源释放 | 所选相机须提供双路NV21预览；无设备/flash/focus/zoom能力明确报错；前摄/外摄反色分析、具体镜头枚举不支持，实际外摄/朝向待验 |
| quick_actions 1.1.1 | 4 个静态快捷入口真实显隐、冷暖启动分发 | 使用系统声明的 compose_post/explore/chats/notifications；不伪造动态新增任意入口 |
| map_launcher 7.0.0 | 当前 launch/probe 协议，URL 经系统打开、地图 scheme 查询 | OHOS 走模型中的通用链接，不冒充 Android/iOS；无通用链接的地图不假报可用 |
| flutter_local_notifications 23.0.0 | 当前 initialize/show/cancel/launchDetails、权限、图片/2个前台action、系统单次/日历/周期调度、pending查询和取消、点击payload/actionId | Reminder权限；周期至少1天且整秒；日历重复仅设备IANA时区；调度图片/action、后台isolate/action、任意附件不支持，明确错误；后台投递/系统交互待验 |
| passkeys 2.24.1 / interface 2.11.0 | API 20+ 系统 FIDO2 注册/认证/可用性，当前二进制与请求模型 | 仍需真实 RP/域名/签名关联；无 SDK 取消接口时不假装取消，conditional/silent/PRF 不支持 |
| flutter_webrtc 1.6.3 | 当前通道、原生设备/媒体/PeerConnection、纹理；权限、错误、路由和资源修复 | 当前原生库不含 FrameCryptor；原生录制/截图/空流/指定输入等未实现项明确失败；真机互通未验 |
| livekit_client 2.13.2 | 复用当前 WebRTC；OHOS mobile/ClientInfo、实际扬声器路由 | 媒体 E2EE 不支持；独立 native 可视化/音频帧采集等扩展未实现，不宣称全 SDK API 兼容 |
| media_kit_video 2.0.1、media_kit 1.2.6、libs_video 1.0.7 | 实际 ARM64 libmpv、Flutter 资源提取、纹理/窗口尺寸与释放 | 解码/声音/视频输出、设备路由需硬件验收；已核验所解析OH-Flutter HAR：只有未接线的OnFrameConsumedListener声明，没有注册或回调入口；首帧getter明确不支持 |

OHOS libmpv/WebRTC 运行库由 `buildtools/prepare-ohos-media.py` 从固定来源准备并校验 SHA-256，生成文件不进 Git。`buildtools/build-ohos.sh` 统一执行 SDK 补丁、依赖解析、原生库准备、HAP 构建及校验。运行库来源、具体修改与许可证见各包 `UPSTREAM.md`。

## 无需伪造鸿蒙插件声明的 16 项

| 依赖 | 统一处理方式 |
| --- | --- |
| desktop_drop | DropTarget 的通道监听不会主动调用不存在的原生后端；手机仍用当前文件/图片选择器，不声称已有跨应用原生拖放 |
| desktop_multi_window、window_manager | 只在 Windows/macOS/Linux 创建窗口；设置窗口透明度和桌面 RPC 的遗漏分支已改为同样白名单 |
| island_desktop_presence | 桌面 presence/RPC 保留在桌面目标，不向 OHOS 暴露桌面 native 能力 |
| windows_notification | Windows 专用；OHOS 使用本轮统一通知后端 |
| native_glass_navbar | 仅 iOS 原生玻璃导航；OHOS 继续使用共享 Flutter 导航 |
| snow_fall_animation | 纯 Flutter 动画，未发现需 OHOS 原生注册的调用；随同应用编译/测试 |
| flutter_native_splash | Android/iOS 插件入口保留；OHOS 使用已有原生启动窗口/FlutterAbility 生命周期 |
| image_picker_android | Android 实现只在 Android 注册；OHOS 已使用统一 image_picker_ohos |
| protocol_handler | 桌面入口保留；OHOS 复用现有 Apple 宿主 consumePendingDeepLink/onDeepLink 契约，处理 lkm/solian 冷暖启动，无第二套路由业务 |
| sign_in_with_apple | Apple 原生入口保留；OHOS 复用现有服务端 OAuth 浏览器授权入口，不使用旧 Solarpass 客户端硬编码配置 |
| in_app_purchase、in_app_purchase_storekit | 当前 Apple IAP UI/调用保持 iOS/macOS 白名单；不会将 Apple SKU 当作华为商品 |
| firebase_core、firebase_analytics、firebase_messaging | 不在 OHOS 初始化不支持的 Firebase 原生服务；已有业务功能继续使用共享 API/WebSocket，不伪造 FCM/Huawei token 兼容性 |

## 尚不能宣称完成的服务和运行验收

用户已确认暂时没有 AGC/Push Kit、华为商品/验单及 Apple OAuth 外部配置。

- 鸿蒙远程推送：客户端 token 注册与服务端 PS256 v3 发送已实现并接入 compose/k8s（见 [推送说明](HARMONYOS_PUSH.md)），账号切换会迁移 token 归属；仍需当前 bundle 的 AGC Push Kit 应用、服务账号密钥与签名真机才能实发验收。本轮不把本地通知或在线 WebSocket 当成系统离线推送。
- 华为内购：需要商户应用、商品 ID 和服务端验单；当前 Apple IAP 继续只服务 Apple 目标，没有可凭空生成的 OHOS 商品。
- Apple 网页授权：客户端可走当前服务端入口；成功登录仍取决于服务端 Apple provider/clientId/回调与域名配置。
- Passkeys：代码调用真实 FIDO2 API；生产签名、应用 origin/RP 关联与真实设备认证仍需验收。
- 媒体 E2EE、WebRTC 原生录制/截图/指定输入、LiveKit native 扩展、扫码所选相机能力/反色等上表限制，不能因 HAP 构建成功改标“全部支持”。

所有 HAP 仍未签名。当前无 HDC 设备，音视频通话、播放器、相机/NFC/通知、快捷入口及认证等硬件/系统交互尚未验收。最终测试、HAP 哈希与构建日志见 [Linux 构建记录](HARMONYOS_LINUX_BUILD.md)。

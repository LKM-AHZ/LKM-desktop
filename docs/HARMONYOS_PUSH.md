# HarmonyOS NEXT 系统远程推送

客户端使用 `@kit.PushKit` 的真实设备 token，通过与其它 LKM 通知相同的
`POST /api/v1/notification/me/tokens` 注册，字段为 `token` 和
`platform: "huawei"`。此 token 不进入 Firebase 或旧 Solian 的 provider 枚举。
同一 Huawei token 注册到新账号时，服务端在事务锁下移除旧账号绑定，避免账号切换后仍收到旧账号通知。
现有 token 字段足以存储 Push Kit 的 112 字符 token，无数据库迁移。

服务端 notification worker 在业务通知提交后发送系统远程通知，沿用用户通知偏好。
发送失败不会撤回站内信；日志保留 Huawei 结果码，不记录 token、JWT 或私钥。
通知点击打开应用首页，用户在通知列表查看完整内容。当前覆盖 notification worker
产生的点赞、评论、回复和问答采纳通知；管理员审核摘要原有路径仍为站内信与 bot。

## 外部开通与配置

1. 在 AppGallery Connect 为 `ltd.lkmahz.desktop` 创建真实 HarmonyOS 应用，配置签名证书、
   应用标识与 Push Kit 能力。将实际应用标识写入宿主配置，不能用 bundleName 代替 appId。
2. 在华为开发者 API Console 对同一个项目创建服务帐号密钥，安全保管下载 JSON。
3. 将 JSON 中的真实字段映射到以下服务端环境变量（通过部署平台 Secret 注入，不提交代码库）：

| 环境变量 | 值 |
| --- | --- |
| `LKM_HUAWEI_PUSH_ENABLED` | `true` |
| `LKM_HUAWEI_PUSH_PROJECT_ID` | JSON 的 `project_id` |
| `LKM_HUAWEI_PUSH_KEY_ID` | JSON 的 `key_id` |
| `LKM_HUAWEI_PUSH_SUB_ACCOUNT` | JSON 的 `sub_account` |
| `LKM_HUAWEI_PUSH_PRIVATE_KEY` | JSON 的完整 `private_key` PEM，保留实际换行 |
| `LKM_HUAWEI_PUSH_CATEGORY` | 默认 `SUBSCRIPTION`；须与实际通知场景及已获权益一致 |
| `LKM_HUAWEI_PUSH_TEST_MESSAGE` | 默认 `false`；按官方测试限制调试时可设 `true` |

HarmonyOS NEXT/5+ 使用 v3 接口和 PS256 服务帐号 JWT，不能用 Android HMS 的
OAuth2 appId/clientSecret 发送方式替代。启用时缺字段或非 RSA 私钥会拒绝启动；
默认关闭，客户端注册返回明确不可用。没有以上外部开通、凭据和签名真机，不能声称已送达。

## 验证

不依赖数据库的签名与 HTTP 契约测试：

```sh
cd ../LKM-service
uv run pytest --noconftest tests/test_huawei_push.py -q
```

接入后还需签名真机验收：授权通知、登录注册、切后台/杀进程接收、点击打开、token 更新、
退出登录使旧 token 失效，以及关闭某类通知偏好后不下发。真实发送是否成功以 Huawei
响应与设备实际接收共同确认。

## API 依据

- [服务帐号 JWT](https://developer.huawei.com/consumer/en/doc/doccenter-capabilities/push-jwt-token/)
- [通知消息发送](https://developer.huawei.com/consumer/en/doc/harmonyos-guides/push-send-alert/)
- [v3 响应码与认证要求](https://developer.huawei.com/consumer/en/doc/harmonyos-references/push-scenariozed-api-response/)
- [消息分类与权益](https://developer.huawei.com/consumer/en/doc/doccenter-capabilities/push-apply-right/)

客户端 `getToken`、`deleteToken`、`receiveMessage('DEFAULT')`、`on/off('tokenUpdate')`
另以本机 HarmonyOS SDK `@hms.core.push.pushService.d.ts` 为编译依据；tokenUpdate 自 API 18
可用，更早系统在启动和恢复前台时重新读取 token。

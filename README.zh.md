# Immich + 内嵌 Tailscale

<p>
  <a href="LICENSE"><img alt="License" src="https://img.shields.io/badge/license-AGPL--3.0-3F51B5?style=flat-square"></a>
  <img alt="Platform" src="https://img.shields.io/badge/platform-Android-3DDC84?style=flat-square&logo=android&logoColor=white">
  <img alt="Upstream" src="https://img.shields.io/badge/upstream-immich--app%2Fimmich-555?style=flat-square">
</p>

[English](README.md) · **简体中文**

把 **Tailscale 节点直接编进 Immich 安卓客户端**的修改版。

装好 APK 后，手机在任何网络下都能连回家里那台 Immich——不需要公网 IP、不用端口映射、也不开系统 VPN。隧道只承载本应用的流量。

基于 [immich-app/immich](https://github.com/immich-app/immich)（AGPL-3.0）。**服务端零改动**，直接部署官方版本即可。

> 本文件为中文版，英文版见 [README.md](README.md)。上游原始 README 仍保留在 git 历史中（`git show 2acfe9e^:README.md`）。

---

## 为什么有这个 fork

| | 上游 Immich | 本仓库 |
|---|---|---|
| 远程访问 | 需要公网暴露，或手机上另装 Tailscale App | 节点在应用内，只有 Immich 的流量走隧道 |
| 系统 VPN | 第三方 Tailscale App 会占用 VPN 槽 | 槽位保持空闲，其他应用不受影响 |
| 家里 Wi-Fi | — | 自动绕过隧道走局域网，更快 |
| 构建 | 生成代码被 gitignore，必须跑 codegen | 生成代码已 vendor，clone 完直接 `flutter build apk` |
| 签名 | CI 用组织密钥 | 仓库自带固定 keystore，构建之间可增量覆盖 |

分支：`main` 是合并后的主线；`tailnet` / `release` 是特性分支。推 `tailnet` 出 debug 包，推 `release` 出签名 release 包。

---

## 功能

- **一个开关** — 设置 → 网络 → Tailscale 远程访问，在应用进程内启动用户态节点。
- **两种登录** — 浏览器跳转授权，或粘贴 `tskey-auth-…` 密钥。
- **精确分流** — 只有 `*.ts.net`、`100.64.0.0/10`、`fd7a:115c:a1e0::/48`、`100.100.100.100` 走节点；localhost、局域网、公网地址保持直连。
- **诊断** — 节点状态、tailnet 名、本机 IP / MagicDNS 名、登录账号；「测试延迟」实测一次到服务器的连接，并报告走的是**直连、DERP 中继还是对等中继**。
- **后台同样生效** — 前台请求、后台备份、上传队列共用同一条隧道。
- **干净退出** — 关开关即停节点、释放端口；退出登录会把设备移出 tailnet；Wi-Fi ↔ 蜂窝切换会主动通知节点立即重探路径。

---

## 使用场景

1. **家里 NAS 跑 Immich，人在外面备份。** 家庭宽带基本没有公网 IPv4，运营商 NAT 后的服务外网连不上。开了开关就通，回家又自动走局域网。
2. **不想为一个应用开全局 VPN。** 系统级隧道会接管其他所有应用的流量，部分银行类 App 还会报警。这里只影响 Immich 自己发往 tailnet 的请求。
3. **和家人共用一台 Immich。** 拉进同一个 tailnet，各装一个 APK，都填同一个 `https://<host>.<tailnet>.ts.net`。
4. **弱网下判断链路质量。** 面板能看出是 P2P 直连还是被踢到 DERP 中继，以及为此多付了多少延迟。
5. **自建私有版本。** 签名密钥和完整 CI 都在仓库里——fork、改名、持续出包。

---

## 上手

**安装**（Releases 页）
- `apk-latest-release` — 包名 `app.alextran.immich`，**会覆盖商店版**
- `apk-latest` — debug 包，包名 `…immich.debug`，可与商店版共存

**服务端**：装 Tailscale 加入 tailnet，开启 MagicDNS。Immich 默认监听 `0.0.0.0:2283` 即可。

**客户端**：服务器地址填 `https://<host>.<tailnet>.ts.net`（必须完整域名，短名有意不走隧道）→ 打开开关 → 登录 → 点「测试延迟」确认链路。

---

## 构建

生成代码已 vendor，无需 bootstrap：

```bash
bash mobile/tooling/build-apk.sh            # debug
bash mobile/tooling/build-apk.sh --release
```

工具链：Flutter 3.47.9、JDK 21、NDK 28.2.13676358、Rust 1.99.1。

改了 Go 桥接层（`mobile/android/tsbridge/`）需要重编 AAR：

```bash
bash mobile/android/tsbridge/build.sh       # -> app/libs/tsbridge.aar
```

改了 pigeon 或 drift schema：`bash mobile/tooling/bootstrap.sh`。

CI（`.github/workflows/build-tailnet-apk.yml`）自带全套环境——不需要组织密钥，也不需要自托管 runner——构建失败时会把日志附到对应提交上。

---

## 原理

```
Dart/Flutter ──pigeon──▶ Kotlin TailnetManager
                           ├─ ProxySelector ──▶ 127.0.0.1:48113 (本地 HTTP 代理)
                           └─ OkHttp/Cronet/          │
                              HttpURLConnection       ▼
                                                 Go tsnet 节点 ──▶ tailnet
```

- **用户态节点，不是 VPN。** `tsnet` 在进程内运行节点，gomobile 把它 bind 成 AAR。它从不碰 `VpnService`，系统 VPN 槽始终为空。
- **回环代理承载流量。** Go 侧在 `127.0.0.1:48113`（能占住就固定）提供 HTTP 代理，支持 `CONNECT` 与普通转发，所有出站连接都经 `tsnet.Server.Dial`。代理要求 Basic Auth，密码是每进程随机 token——回环端口设备上任何应用都能访问。
- **Java 只决定“哪些走隧道”。** `ProxySelector` 对 tailnet 目标返回本地代理，其余返回 `NO_PROXY`。
- **三套 HTTP 栈要照顾。** OkHttp 走 ProxySelector，另加拦截器在冷启动时等节点就绪；Cronet 不支持代理，媒体加载退回 OkHttp；`background_downloader` 跑在 HttpURLConnection 上，忽略 ProxySelector，需要显式配代理并由 JVM 全局 `Authenticator` 应答 407。
- **两个 Android 坑。** 应用拿不到 netlink socket，接口表改由 `java.net.NetworkInterface` 生成后喂给 `netmon`，网络变化时 `InjectEvent()`；另外应用没有 `HOME`/`TMPDIR`，两者都指向私有目录。

---

## 限制

- **仅 Android。** iOS 侧只有空的 pigeon 绑定。
- **只出 arm64 包。** AAR 含 arm64 与 amd64，APK 构建目标是 arm64。
- **MagicDNS 短名不走隧道** —— 请用完整 `<host>.<tailnet>.ts.net`。
- **签名密钥已提交**（口令在 `build.gradle` 里）。这保证了覆盖安装可用，但也意味着任何人都能签出同包名 APK。自用侧载没问题，别用于分发。
- **生成代码 vendor 进仓库**，体积明显大于上游。

---

## 目录

```
mobile/android/app/src/main/kotlin/.../tailnet/   节点生命周期、分流、pigeon 实现
mobile/android/tsbridge/bridge.go                 tsnet + 回环代理（Go）
mobile/android/app/libs/tsbridge.aar              预编译 AAR（8 MB）
mobile/lib/providers/tailnet.provider.dart        状态轮询与动作
mobile/lib/widgets/settings/.../tailnet_preference.dart   设置卡片
mobile/pigeon/tailnet_api.dart                    原生接口定义
.github/workflows/build-tailnet-apk.yml           APK CI
```

---

## 许可

[AGPL-3.0](LICENSE)，继承自上游。本 fork 的改动以相同条款发布。

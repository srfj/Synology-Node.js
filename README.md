# Node.js for Synology DSM 6.2.x（群晖套件）

> 在群晖 DSM 6.2.x 上运行的 Node.js 最新版套件。可直接**覆盖安装官方 Node.js v12**，
> 并保证依赖 Node.js 的群晖/第三方套件继续正常工作。

## 这是什么

群晖官方套件中心提供的 Node.js 版本较旧（v12 之后基本不再更新 DSM 6 分支），而
[nodejs.org](https://nodejs.org/) 的官方 Linux 二进制又**无法在 DSM 6.2.x 上运行**。
本仓库提供一个可在 DSM 6.2.x 上直接安装的 Node.js 最新版 SPK 套件，并提供完整的构建脚本。

当前构建版本：**Node.js v24.21.0**（含 npm / npx / corepack），架构 `x86_64`，支持 DSM 6.2.x。

## 为什么需要自己构建

| 项目 | glibc 要求 |
| --- | --- |
| DSM 6.2.3 系统自带 | **2.20** |
| nodejs.org 官方 `linux-x64` 二进制 | 2.28 |
| 本套件所使用的构建 | **2.17**（`glibc-217`，最低需求） |

官方二进制在 DSM 6.2.3 上会直接因为找不到高版本 glibc 符号而无法执行。因此本套件使用
[unofficial-builds.nodejs.org](https://unofficial-builds.nodejs.org/) 提供的
`linux-x64-glibc-217` 构建，它在 glibc 2.20 的 DSM 6.2.x 上可以正常运行。

## 特性

- Node.js **v24.21.0**（`linux-x64-glibc-217` 构建），自带 npm、npx、corepack
- **package id 与官方一致**（`Node.js_v12`），因此会作为官方 Node.js v12 的**升级/覆盖**安装，
  而不是并存出第二个 Node
- **目录布局与官方套件完全一致**（`usr/local/bin/node`），依赖 Node.js 的套件不会找不到可执行文件
- 提供 `start-stop-status`，DSM 不会再把该套件标记为 `unknown status` / `Package is broken`
- 纯 shell + Python 图标脚本，构建过程可复现

## 安装

1. 到本仓库的 [Releases](../../releases) 页面下载最新的 `.spk` 文件；
2. DSM → **套件中心 → 手动安装**，选择该 `.spk`；
3. 因为是非官方签名套件，会提示“未知发行者/未签名”，确认继续即可；
4. 安装完成后在 SSH 中验证：

```sh
ls -l /var/packages/Node.js_v12/target/usr/local/bin/node   # 官方约定路径，必须存在
ls -l /usr/local/bin/node                                   # 应指向上面的路径
/usr/local/bin/node -v                                      # v24.21.0
npm -v                                                      # 24.21.0 自带的 npm
synopkg status Node.js_v12                                  # 不应再是 broken
```

## 构建

```sh
# 默认会自动下载当前版本对应的 glibc-217 二进制并校验 SHA256
sh build.sh

# 可用的环境变量：
#   NODE_TARBALL  复用本地已下载的 node-vX-linux-x64-glibc-217.tar.gz（跳过下载）
#   SPK_REV       套件修订号，默认 0001；覆盖安装时请递增（如 0002）
NODE_TARBALL=/path/to/node-v24.21.0-linux-x64-glibc-217.tar.gz SPK_REV=0002 sh build.sh
```

产物：`synology-nodejs-spk/out/Node.js_v12_x64-dsm6_<version>-<rev>.spk`

构建流程：下载 → 校验 SHA256 → 按官方布局整理运行时 → 打包 `package.tgz` →
生成 `INFO`（含 `package.tgz` 的 MD5 作为 `checksum`）→ 生成图标 → 组装 `.spk`。

## 目录结构

```
synology-nodejs-spk/
├── build.sh            # 构建入口：下载 / 校验 / 布局 / 打包 / 组装 SPK
├── mk-icon.py          # 生成套件图标 PACKAGE_ICON.PNG / PACKAGE_ICON_256.PNG
└── spk/
    ├── conf/
    │   └── privilege   # 指定 run-as: root
    └── scripts/
        ├── common              # 共享函数：DO_LINK / DO_REMOVE / GET_STATUS
        ├── preinst             # 安装前
        ├── postinst            # 安装后：建立 /usr/local/bin 软链
        ├── preuninst           # 卸载前：清理软链
        ├── postuninst          # 卸载后
        ├── preupgrade          # 升级前
        ├── postupgrade         # 升级后：重新指向新版本的软链
        └── start-stop-status   # 状态上报（DSM 依赖它判断套件是否健康）
```

## 编译 / 打包经验（踩过的坑）

### 1. glibc 版本是第一道门槛

DSM 6.2.3 的 glibc 只有 2.20，必须用 `glibc-217` 构建，否则二进制根本起不来。

### 2. 目录布局必须和官方套件完全一致（最大的坑）

官方 `Node.js_v12` 套件把可执行文件放在 **`<target>/usr/local/bin/node`**，
而不是上游 Node.js 发行包的 `bin/node`。群晖自家和第三方套件会**硬编码**这个路径，例如
`SynologyApplicationService` 启动 “Vapid Send Server” 的 upstart 任务：

```sh
NODE_PACKAGE=Node.js_v12
NODE_BIN="/var/packages/$NODE_PACKAGE/target/usr/local/bin/node"
exec $NODE_BIN /var/packages/SynologyApplicationService/target/node_libs/VapidSendServer.js
```

如果套件把 node 放在 `target/bin/node`，上述 `exec` 找不到可执行文件，进程立刻退出，
upstart 反复重试后放弃：

```
init: pkg-SynologyApplicationService-VapidSendServer main process (28143) terminated with status 1
init: pkg-SynologyApplicationService-VapidSendServer respawning too fast, stopped
```

套件中心就会提示 `Failed to start service [Vapid Send Server]`，并且**所有依赖 Node.js 的套件一起启动失败**。
所以本套件的负载结构完全照搬官方：

```
target/usr/local/bin/node                    # 真实二进制
target/usr/local/bin/npm  -> ../lib/node_modules/npm/bin/npm-cli.js
target/usr/local/bin/npx  -> ../lib/node_modules/npm/bin/npx-cli.js
target/usr/local/bin/corepack -> ../lib/node_modules/corepack/dist/corepack.js
target/usr/local/lib/node_modules/{npm,corepack}
```

### 3. 必须提供 `start-stop-status`

官方套件带这个脚本，DSM 靠它判断套件状态。缺失时日志会出现：

```
pkgtool.cpp:3195 unknown status: [Node.js_v12]
Package is broken, Node.js_v12, [150]
```

进而影响依赖套件的健康判定。本套件的 `common` 里实现了与官方一致的 `GET_STATUS`
（同时检查 `/usr/local/bin/node` 与包内 `usr/local/bin/node` 可执行），
`start-stop-status` 调用它。

### 4. 覆盖安装的三个条件

想覆盖官方 Node.js v12，必须同时满足：

- `package="Node.js_v12"` —— 与官方 package id 完全一致；
- `arch="x86_64"` —— 与官方 SPK 的架构字段一致（不要用 `apollolake avoton ...` 这类平台码列表）；
- `version` 高于已安装版本，例如 `24.21.0-0002` > `12.22.12-0024`，DSM 才会按“升级”处理。

### 5. SPK 打包细节

- `INFO` 中的 `checksum` 必须是 `package.tgz` 的 **MD5**（不是外层的 `.spk`）；
- `package.tgz` 是 `tar + gzip` 的负载；
- 外层 `.spk` 用**无压缩 tar** 打包（内含 `INFO`、`package.tgz`、`scripts/`、`conf/`、图标）；
- `conf/privilege` 指定运行身份，本套件为 `run-as: root`。

### 6. Node 版本不是“万能背锅侠”

覆盖安装后依赖套件启动失败，第一反应容易怀疑“Node 24 太新、API 不兼容”。实测
`VapidSendServer.js` 用到的 `new Buffer()`、以及它依赖的 `web-push@3.1.0` 在 Node 24 上都能正常加载运行
（`new Buffer()` 只是告警）。**先核对路径与布局，再怀疑 API 兼容性**，能少走很多弯路。

## 兼容性与影响范围

- 本套件替换的是官方 `Node.js_v12`，属于**就地覆盖**：系统里不会出现第二个 Node.js。
- 依赖 Node.js 的套件（如 Synology Application Service、Synology Drive 等）会改用本套件的运行时。
  经测试，至少 `SynologyApplicationService` 的 Vapid Send Server 可正常启动。
- 如果你需要保留官方 Node.js v12，请改用**不同的 package id**（例如 `nodejs24`）并排安装，
  而不是覆盖安装。
- 建议在生产环境安装前先做快照/备份。

## 免责声明

本项目为个人构建，非群晖官方、非 Node.js 官方发布物，仅供学习与自用。使用前请自行评估风险。
本仓库 fork 自 [nodejs/node](https://github.com/nodejs/node)，仅在上面附带了群晖套件的构建脚本与文档。
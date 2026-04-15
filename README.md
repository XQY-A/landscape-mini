# Landscape Mini

[![Latest Release](https://img.shields.io/github/v/release/Cloud370/landscape-mini)](https://github.com/Cloud370/landscape-mini/releases/latest)

[English](README_EN.md) | 中文 | [贡献流程](CONTRIBUTING.md) | [**下载最新镜像**](https://github.com/Cloud370/landscape-mini/releases/latest)

Landscape Router 的最小化 x86 镜像构建器。支持 **Debian Trixie** 和 **Alpine Linux** 两种基础系统，生成精简磁盘镜像（最小 ~76MB 压缩），支持 BIOS + UEFI 双启动。

上游项目：[Landscape Router](https://github.com/ThisSeanZhang/landscape)

## 特性

- 双基础系统：Debian Trixie / Alpine Linux（内核 6.12+，原生 BTF/BPF 支持）
- GPT 分区，BIOS + UEFI 双引导（兼容 Proxmox/SeaBIOS）
- 激进裁剪：移除未使用的内核模块（声卡、GPU、无线等）、文档、locale
- 可选内置 Docker CE（含 compose 插件）
- CI/CD：GitHub Actions 4 变体并行构建+测试 + Release 发布
- 自动化测试：QEMU 无人值守启动 + 健康检查 + E2E 网络测试（DHCP/DNS/NAT）

## 快速开始

### 构建

```bash
# 安装构建依赖（首次）
make deps

# 构建 Debian 镜像
make build

# 构建 Alpine 镜像（更小）
make build-alpine

# 构建含 Docker 的镜像
make build-docker
make build-alpine-docker
```

### 测试

```bash
# 自动化 readiness 检查（无需交互）
make deps-test      # 首次需安装测试依赖
make test           # Debian readiness
make test-alpine    # Alpine readiness

# 数据面测试（双 VM：路由器 + 客户端）
make test-dataplane        # Debian dataplane
make test-dataplane-alpine # Alpine dataplane

# 交互式启动（串口控制台）
make test-serial
```

### 部署

#### 物理机 / U 盘

```bash
dd if=output/landscape-mini-x86.img of=/dev/sdX bs=4M status=progress
```

#### Proxmox VE (PVE)

1. 上传镜像到 PVE 服务器
2. 创建虚拟机（不添加磁盘）
3. 导入磁盘：`qm importdisk <vmid> landscape-mini-x86.img local-lvm`
4. 在 VM 硬件设置中挂载导入的磁盘
5. 设置启动顺序，启动虚拟机

#### 云服务器（dd 脚本）

使用 [reinstall](https://github.com/bin456789/reinstall) 脚本将自定义镜像写入云服务器：

```bash
bash <(curl -sL https://raw.githubusercontent.com/bin456789/reinstall/main/reinstall.sh) \
    dd --img='https://github.com/Cloud370/landscape-mini/releases/latest/download/landscape-mini-x86.img.gz'
```

> 根分区会在首次启动时自动扩展以填满整个磁盘，无需手动操作。

## 换源（国内镜像）

部署后如需将软件源切换到国内镜像以加速 `apt` / `apk` 操作，镜像内置了 `setup-mirror.sh` 工具：

```bash
# 查看当前源配置
setup-mirror.sh show

# 一键切换到国内镜像
setup-mirror.sh tuna       # 清华 TUNA
setup-mirror.sh aliyun     # 阿里云
setup-mirror.sh ustc       # 中科大
setup-mirror.sh huawei     # 华为云

# 恢复官方源
setup-mirror.sh reset

# 交互式选择
setup-mirror.sh
```

自动检测 Debian / Alpine 系统，切换后自动执行 `apt update` 或 `apk update`。

## 默认凭据

| 场景 | 用户 | 密码 |
|------|------|------|
| SSH / 系统登录 | `root` | `landscape` |
| SSH / 系统登录 | `ld` | `landscape` |
| 管理网页 | `root` | `root` |

> `custom-build.yml` 支持通过 workflow inputs 或 GitHub Secrets 覆盖 Linux/Web 管理凭据。明文 inputs 有泄露风险，优先使用 `CUSTOM_ROOT_PASSWORD`、`CUSTOM_API_USERNAME`、`CUSTOM_API_PASSWORD`。

## 构建配置

编辑 `build.env` 或通过环境变量覆盖：

| 变量 | 默认值 | 说明 |
|------|--------|------|
| `APT_MIRROR` | `http://deb.debian.org/debian` | Debian 软件源地址 |
| `ALPINE_MIRROR` | `https://dl-cdn.alpinelinux.org/alpine` | Alpine 软件源地址 |
| `LANDSCAPE_VERSION` | `v0.18.2` | 上游 Landscape 版本号（或指定 tag） |
| `LANDSCAPE_REPO` | `https://github.com/ThisSeanZhang/landscape` | 上游 Landscape 发布仓库 |
| `OUTPUT_FORMAT` | `img` | 输出格式：`img`、`vmdk`、`both` |
| `COMPRESS_OUTPUT` | `yes` | 是否压缩输出镜像 |
| `IMAGE_SIZE_MB` | `2048` | 初始镜像大小（最终会自动缩小） |
| `ROOT_PASSWORD` | `landscape` | root / ld 登录密码 |
| `TIMEZONE` | `Asia/Shanghai` | 时区 |
| `LOCALE` | `en_US.UTF-8` | 系统 locale |

### 自定义构建（GitHub Actions）

仓库新增 `custom-build.yml`，面向 fork 用户提供单变体构建入口，支持：

- `variant`：`default` / `docker` / `alpine` / `alpine-docker`
- `landscape_version`
- `lan_server_ip` / `lan_range_start` / `lan_range_end` / `lan_netmask`
- `root_password`
- `api_username` / `api_password`
- `ack_plaintext_credentials`：当使用上述明文凭据 inputs 时，必须显式设为 `true`

当前优先级：**direct inputs > secrets > defaults**。

推荐把密码类信息放在 GitHub Secrets：
- `CUSTOM_ROOT_PASSWORD`
- `CUSTOM_API_USERNAME`
- `CUSTOM_API_PASSWORD`

如果使用 GitHub Secrets，则不需要设置 `ack_plaintext_credentials`；只有在使用明文 inputs 时，未确认会导致 workflow 直接失败。

workflow 会把**凭据来源信息**按字段写入 `build-metadata.txt`（例如 `api_username_source` / `api_password_source`），同时会记录 `api_username` 的实际值，但不会把密码明文写入 artifact。网络拓扑的有效配置会随 artifact 一起携带为 `effective-landscape_init.toml`，供 `test.yml` 和 release promotion 校验使用。


`build.sh` 采用 **编排器 + 后端** 架构，按 8 个阶段顺序执行：

- `build.sh` — 编排器：解析参数、加载配置和后端、执行阶段
- `lib/common.sh` — 共享函数（阶段 1、2、5、7、8 及工具函数）
- `lib/debian.sh` — Debian 后端（debootstrap、apt、systemd）
- `lib/alpine.sh` — Alpine 后端（apk、OpenRC、mkinitfs、gcompat）

```
1. Download     下载 Landscape 二进制文件和 Web 前端资源
2. Disk Image   创建 GPT 磁盘镜像（BIOS boot + EFI + root 三分区）
3. Bootstrap    Debian: debootstrap / Alpine: apk.static
4. Configure    安装内核、GRUB 双引导、网络工具、SSH
5. Landscape    安装 Landscape 二进制、创建 init 服务（systemd/OpenRC）
6. Docker       （可选）安装 Docker CE / apk docker
7. Cleanup      裁剪内核模块、清理缓存、缩小镜像
8. Report       输出构建结果
```

## 磁盘分区布局

```
┌──────────────┬────────────┬────────────┬──────────────────────────┐
│ BIOS boot    │ EFI System │ Root (/)   │                          │
│ 1 MiB        │ 200 MiB    │ 剩余空间    │  ← 构建后自动缩小        │
│ (无文件系统)   │ FAT32      │ ext4       │                          │
├──────────────┼────────────┼────────────┤                          │
│ GPT: EF02    │ GPT: EF00  │ GPT: 8300  │                          │
└──────────────┴────────────┴────────────┴──────────────────────────┘
```

## 自动化测试

### Readiness 检查

`make test` / `make test-alpine` 执行统一的 router readiness 契约验证：

1. 复制镜像到临时文件（保护构建产物）
2. 后台启动 QEMU（自动检测 KVM）
3. 等待 SSH、API listener、API login、layout 检测完成
4. 验证 `eth0` / `eth1` 以及核心服务进入 running
5. 输出 readiness / service / diagnostics 快照并清理 QEMU

自动适配 systemd（Debian）和 OpenRC（Alpine）两种 init 系统。

### Dataplane 测试

`make test-dataplane` / `make test-dataplane-alpine` 使用双 VM 拓扑验证真实 client-visible dataplane：

```
Router VM (eth0=WAN/SLIRP, eth1=LAN/mcast) ←→ Client VM (CirrOS, eth0=mcast)
```

测试项：DHCP 分配、Router API 中 lease 可见、Router ↔ Client LAN 连通。

测试日志输出到 `output/test-logs/`。

## QEMU 测试端口

| 服务 | 宿主机端口 | 说明 |
|------|-----------|------|
| SSH | 2222 | `ssh -p 2222 root@localhost` |
| Web UI | 9800 | `http://localhost:9800` |

## 项目结构

```
├── build.sh              # 构建编排器（参数解析、加载后端、执行阶段）
├── build.env             # 构建配置
├── Makefile              # 开发便捷命令
├── lib/
│   ├── common.sh         # 共享构建函数（下载、磁盘、安装、裁剪）
│   ├── debian.sh         # Debian 后端（debootstrap、apt、systemd）
│   └── alpine.sh         # Alpine 后端（apk、OpenRC、mkinitfs）
├── configs/
│   └── landscape_init.toml  # 路由器初始配置（WAN/LAN/DHCP/NAT）
├── rootfs/               # 写入镜像的配置文件
│   ├── usr/local/bin/
│   │   ├── expand-rootfs.sh         # 首次启动自动扩展根分区
│   │   └── setup-mirror.sh          # 换源工具（国内镜像）
│   └── etc/
│       ├── network/interfaces
│       ├── sysctl.d/99-landscape.conf
│       ├── systemd/system/          # systemd 服务（Debian）
│       │   ├── landscape-router.service
│       │   └── expand-rootfs.service
│       └── init.d/                  # OpenRC 脚本（Alpine）
│           ├── landscape-router
│           └── expand-rootfs
├── tests/
│   ├── test-readiness.sh  # Router readiness 测试（共享 SSH/API ready 契约）
│   └── test-dataplane.sh  # Dataplane 测试（双 VM：DHCP + LAN 连通）
└── .github/workflows/
    ├── ci.yml                  # CI：调用可复用单变体构建验证 workflow
    ├── _build-and-validate.yml # 可复用的单变体 build + validate workflow
    ├── custom-build.yml        # fork 用户手动自定义构建入口
    ├── release.yml             # Release：promote 已验证 CI artifact 并发布
    └── test.yml                # 独立复测（手动触发，可重传凭据）
```

## CI/CD

- **CI**：手动触发始终可用；对 push 到 `main` / PR，仅在构建相关文件、`.github/` 下相关文件或 `CHANGELOG.md` 变更时自动运行，4 个 variant 通过可复用 workflow 独立构建验证
- **Readiness / E2E 覆盖**：`default`、`alpine` 运行 readiness + dataplane；`docker`、`alpine-docker` 运行 readiness，并显式记录 E2E skipped
- **Artifact contract**：每个 image artifact 都包含 `.img`、`build-metadata.txt`、`effective-landscape_init.toml`
- **Custom Build**：`custom-build.yml` 支持 fork 用户按单 variant 构建，并支持 LAN/DHCP、Linux 密码、Web 管理账号密码输入
- **Manual Retest**：`test.yml` 当前支持按 `run_id` 复测一整组 CI artifacts，并重新传入 SSH / API 凭据；`artifact_suffix` 更适合作为已知 artifact 标识的高级输入，而不是文档承诺的单 artifact 精确复测入口
- **Release**：推送 `v*` tag 时，`release.yml` 仅 promote 同一 commit 上已通过 CI 的 artifact，校验后压缩并创建 GitHub Release

## 许可证

本项目是 [Landscape Router](https://github.com/ThisSeanZhang/landscape) 的社区镜像构建器。

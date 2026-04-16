# Landscape Mini

[![Latest Release](https://img.shields.io/github/v/release/Cloud370/landscape-mini)](https://github.com/Cloud370/landscape-mini/releases/latest)

[English](./docs/en/README.md) | 中文 | [贡献流程](./CONTRIBUTING.md) | [**下载最新镜像**](https://github.com/Cloud370/landscape-mini/releases/latest)

Landscape Router 的最小化 x86 镜像构建器。支持 **Debian Trixie** 和 **Alpine Linux** 两种基础系统，可生成精简磁盘镜像，并支持 BIOS + UEFI 双启动。

上游项目：[Landscape Router](https://github.com/ThisSeanZhang/landscape)

## 先看这里

如果你只是想**快速体验 Landscape**：

- 直接去 [Release 页面下载预编译镜像](https://github.com/Cloud370/landscape-mini/releases/latest)

如果你想**做一份自己的镜像**，例如修改：

- LAN / DHCP 网段
- Linux 登录密码
- Web 管理用户名和密码

推荐优先使用：

- [Custom Build 使用说明](./docs/zh/custom-build.md)
- [PVE 安装引导](./docs/zh/pve-install.md)

如果你要开发或调试构建系统本身，再看下面的本地构建说明。

## 特性

- 同时支持 Debian 和 Alpine 两种基础系统
- 镜像身份由显式组合定义：`base_system + include_docker + output_formats`
- 输出格式支持 `img`、`vmdk`、`ova`
- 支持 BIOS + UEFI，常见虚拟化环境都比较友好
- fork 用户也可以直接在 GitHub 上跑自定义构建
- GitHub Actions 已经接好，支持自动构建、测试和发布

## 文档导航

- 中文主文档：[`docs/zh/README.md`](./docs/zh/README.md)
- 英文主文档：[`docs/en/README.md`](./docs/en/README.md)
- Custom Build：[`docs/zh/custom-build.md`](./docs/zh/custom-build.md)
- PVE 安装：[`docs/zh/pve-install.md`](./docs/zh/pve-install.md)

# Landscape Mini

[![Latest Release](https://img.shields.io/github/v/release/Cloud370/landscape-mini)](https://github.com/Cloud370/landscape-mini/releases/latest)

[中文](README.md) | English | [Contributing](CONTRIBUTING.md) | [**Download Latest**](https://github.com/Cloud370/landscape-mini/releases/latest)

Minimal x86 image builder for Landscape Router. Supports both **Debian Trixie** and **Alpine Linux** as base systems, producing small, optimized disk images (as small as ~76MB compressed) with dual BIOS+UEFI boot.

Upstream: [Landscape Router](https://github.com/ThisSeanZhang/landscape)

## Features

- Dual base systems: Debian Trixie / Alpine Linux (kernel 6.12+ with native BTF/BPF)
- GPT partitioned, dual BIOS+UEFI boot (Proxmox/SeaBIOS compatible)
- Aggressive trimming: removes unused kernel modules, docs, locales
- Optional Docker CE (with compose plugin)
- CI/CD: GitHub Actions with 4-variant parallel build+test + Release
- Automated testing: headless QEMU health checks + E2E network tests (DHCP/DNS/NAT)

## Quick Start

### Build

```bash
# Install build dependencies (once)
make deps

# Build Debian image
make build

# Build Alpine image (smaller)
make build-alpine

# Build with Docker included
make build-docker
make build-alpine-docker
```

### Test

```bash
# Automated readiness checks (non-interactive)
make deps-test          # Install test dependencies (once)
make test               # Debian readiness
make test-alpine        # Alpine readiness

# Dataplane tests (dual VM: router + client)
make test-dataplane         # Debian dataplane
make test-dataplane-alpine  # Alpine dataplane

# Interactive boot (serial console)
make test-serial
```

### Deploy

#### Physical Disk / USB

```bash
dd if=output/landscape-mini-x86.img of=/dev/sdX bs=4M status=progress
```

#### Proxmox VE (PVE)

1. Upload image to PVE server
2. Create a VM (without adding a disk)
3. Import disk: `qm importdisk <vmid> landscape-mini-x86.img local-lvm`
4. Attach the imported disk in VM hardware settings
5. Set boot order and start the VM

#### Cloud Server (dd script)

Use the [reinstall](https://github.com/bin456789/reinstall) script to write custom images to cloud servers:

```bash
bash <(curl -sL https://raw.githubusercontent.com/bin456789/reinstall/main/reinstall.sh) \
    dd --img='https://github.com/Cloud370/landscape-mini/releases/latest/download/landscape-mini-x86.img.gz'
```

> The root partition automatically expands to fill the entire disk on first boot — no manual action needed.

## Mirror Setup (China)

To switch package mirrors to Chinese mirrors after deployment for faster `apt` / `apk` operations, use the built-in `setup-mirror.sh` tool:

```bash
# Show current mirror config
setup-mirror.sh show

# Switch to a Chinese mirror
setup-mirror.sh tuna       # Tsinghua TUNA
setup-mirror.sh aliyun     # Alibaba Cloud
setup-mirror.sh ustc       # USTC
setup-mirror.sh huawei     # Huawei Cloud

# Restore official mirrors
setup-mirror.sh reset

# Interactive selection
setup-mirror.sh
```

Auto-detects Debian / Alpine and runs `apt update` or `apk update` after switching.

## Default Credentials

| Scope | User | Password |
|------|------|----------|
| SSH / system login | `root` | `landscape` |
| SSH / system login | `ld` | `landscape` |
| Web admin | `root` | `root` |

> `custom-build.yml` can override Linux and web admin credentials via workflow inputs or GitHub Secrets. Plaintext inputs are less safe; prefer `CUSTOM_ROOT_PASSWORD`, `CUSTOM_API_USERNAME`, and `CUSTOM_API_PASSWORD`.

## Build Configuration

Edit `build.env` or override via environment variables:

| Variable | Default | Description |
|----------|---------|-------------|
| `APT_MIRROR` | `http://deb.debian.org/debian` | Debian mirror URL |
| `ALPINE_MIRROR` | `https://dl-cdn.alpinelinux.org/alpine` | Alpine mirror URL |
| `LANDSCAPE_VERSION` | `v0.18.2` | Upstream Landscape release version |
| `LANDSCAPE_REPO` | `https://github.com/ThisSeanZhang/landscape` | Upstream Landscape release repository |
| `OUTPUT_FORMAT` | `img` | Output format: `img`, `vmdk`, `both` |
| `COMPRESS_OUTPUT` | `yes` | Compress output image |
| `IMAGE_SIZE_MB` | `2048` | Initial image size (auto-shrunk) |
| `ROOT_PASSWORD` | `landscape` | Root / ld login password |
| `TIMEZONE` | `Asia/Shanghai` | System timezone |
| `LOCALE` | `en_US.UTF-8` | System locale |

### Custom Build via GitHub Actions

The repository now includes `custom-build.yml`, a fork-user-oriented single-variant build entrypoint. It supports:

- `variant`: `default` / `docker` / `alpine` / `alpine-docker`
- `landscape_version`
- `lan_server_ip` / `lan_range_start` / `lan_range_end` / `lan_netmask`
- `root_password`
- `api_username` / `api_password`
- `ack_plaintext_credentials`: must be set to `true` when the plaintext credential inputs above are used

Current precedence is **direct inputs > secrets > defaults**.

For passwords, prefer GitHub Secrets:
- `CUSTOM_ROOT_PASSWORD`
- `CUSTOM_API_USERNAME`
- `CUSTOM_API_PASSWORD`

If you use GitHub Secrets, `ack_plaintext_credentials` is not needed; the workflow only requires it for plaintext credential inputs and will fail fast otherwise.

The workflow records **credential source information per field** in `build-metadata.txt` (for example `api_username_source` / `api_password_source`), and it also records the effective `api_username`, but it never stores plaintext passwords in artifacts. The effective network topology is carried inside each artifact as `effective-landscape_init.toml`, which is then reused by `test.yml` and release promotion validation.


`build.sh` uses an **orchestrator + backend** architecture:

- `build.sh` — Orchestrator: parses args, sources config and backend, runs phases
- `lib/common.sh` — Shared functions (phases 1, 2, 5, 7, 8 and helpers)
- `lib/debian.sh` — Debian backend (debootstrap, apt, systemd)
- `lib/alpine.sh` — Alpine backend (apk, OpenRC, mkinitfs, gcompat)

```
1. Download     Fetch Landscape binary and web assets from GitHub
2. Disk Image   Create GPT image (BIOS boot + EFI + root partitions)
3. Bootstrap    Debian: debootstrap / Alpine: apk.static
4. Configure    Install kernel, dual GRUB, networking tools, SSH
5. Landscape    Install binary, create init services (systemd/OpenRC), apply sysctl
6. Docker       (optional) Install Docker CE / apk docker
7. Cleanup      Strip kernel modules, caches, docs; shrink image
8. Report       List outputs and sizes
```

## Disk Partition Layout

```
┌──────────────┬────────────┬────────────┬──────────────────────────┐
│ BIOS boot    │ EFI System │ Root (/)   │                          │
│ 1 MiB        │ 200 MiB    │ Remaining  │  ← Auto-shrunk after    │
│ (no fs)      │ FAT32      │ ext4       │    build                 │
├──────────────┼────────────┼────────────┤                          │
│ GPT: EF02    │ GPT: EF00  │ GPT: 8300  │                          │
└──────────────┴────────────┴────────────┴──────────────────────────┘
```

## Automated Testing

### Readiness Checks

`make test` / `make test-alpine` runs the unified router readiness contract:

1. Copy the image to a temp file (protect build artifacts)
2. Start QEMU daemonized (auto-detects KVM)
3. Wait for SSH, API listener, API login, and layout detection
4. Verify `eth0` / `eth1` plus the core services reach `running`
5. Write readiness / service / diagnostics snapshots and clean up

Auto-detects systemd (Debian) and OpenRC (Alpine) init systems.

### Dataplane Tests

`make test-dataplane` / `make test-dataplane-alpine` runs a two-VM topology to validate real client-visible dataplane behavior:

```
Router VM (eth0=WAN/SLIRP, eth1=LAN/mcast) ←→ Client VM (CirrOS, eth0=mcast)
```

Tests: DHCP assignment, lease visibility in the router API, and Router ↔ Client LAN connectivity.

Logs saved to `output/test-logs/`.

## QEMU Test Ports

| Service | Host Port | Access |
|---------|-----------|--------|
| SSH | 2222 | `ssh -p 2222 root@localhost` |
| Web UI | 9800 | `http://localhost:9800` |

## Project Structure

```
├── build.sh              # Build orchestrator (arg parsing, backend loading, phases)
├── build.env             # Build configuration
├── Makefile              # Dev convenience targets
├── lib/
│   ├── common.sh         # Shared build functions (download, disk, install, shrink)
│   ├── debian.sh         # Debian backend (debootstrap, apt, systemd)
│   └── alpine.sh         # Alpine backend (apk, OpenRC, mkinitfs)
├── configs/
│   └── landscape_init.toml  # Router init config (WAN/LAN/DHCP/NAT)
├── rootfs/               # Files copied into image
│   ├── usr/local/bin/
│   │   ├── expand-rootfs.sh         # Auto-expand root partition on first boot
│   │   └── setup-mirror.sh          # Mirror setup tool (Chinese mirrors)
│   └── etc/
│       ├── network/interfaces
│       ├── sysctl.d/99-landscape.conf
│       ├── systemd/system/          # systemd services (Debian)
│       │   ├── landscape-router.service
│       │   └── expand-rootfs.service
│       └── init.d/                  # OpenRC scripts (Alpine)
│           ├── landscape-router
│           └── expand-rootfs
├── tests/
│   ├── test-readiness.sh  # Router readiness tests (shared SSH/API ready contract)
│   └── test-dataplane.sh  # Dataplane tests (dual VM: DHCP + LAN connectivity)
└── .github/workflows/
    ├── ci.yml                  # CI: calls the reusable single-variant build+validate workflow
    ├── _build-and-validate.yml # Reusable single-variant build + validate workflow
    ├── custom-build.yml        # Manual fork-user custom build entrypoint
    ├── release.yml             # Release: promote validated CI artifacts and publish
    └── test.yml                # Manual retest workflow with credential re-entry
```

## CI/CD

- **CI**: manual dispatch is always available; automatic runs on pushes to `main` and PRs happen only when build-related files, files under `.github/`, or `CHANGELOG.md` change, and each of the 4 variants uses the reusable workflow independently
- **Readiness / E2E coverage**: `default` and `alpine` run readiness + dataplane; `docker` and `alpine-docker` run readiness and explicitly record E2E as skipped
- **Artifact contract**: each image artifact contains the `.img`, `build-metadata.txt`, and `effective-landscape_init.toml`
- **Custom Build**: `custom-build.yml` lets fork users build one selected variant with LAN/DHCP, Linux password, and web admin credential inputs
- **Manual Retest**: `test.yml` currently supports retesting a full CI artifact set by `run_id` and re-supplying SSH / API credentials; `artifact_suffix` is better treated as an advanced known-artifact input than as a documented single-artifact precision retest entrypoint
- **Release**: pushing a `v*` tag now promotes already-validated artifacts from the matching CI run, then compresses and publishes them

## License

This project is a community image builder for [Landscape Router](https://github.com/ThisSeanZhang/landscape).

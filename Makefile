# =============================================================================
# Landscape Mini - Local Development & Debugging Makefile
# =============================================================================
#
# Builds a minimal x86 UEFI image for the Landscape Router.
# Supports Debian and Alpine base systems, optional Docker, and multiple
# output formats.
# The main build script (build.sh) requires root/sudo.
#
# Usage:
#   make              - Show all available targets
#   make build        - Full build with current variables
#   make test         - Run automated readiness checks (non-interactive)
#   make test-serial  - Boot image in QEMU (interactive serial console)
#
# Example:
#   make build BASE_SYSTEM=alpine INCLUDE_DOCKER=true OUTPUT_FORMATS=img,pve-ova
#
# Default credentials:  root / landscape  |  ld / landscape
# =============================================================================

.PHONY: help deps deps-test \
	build test test-dataplane test-serial test-gui ssh clean distclean status

# --------------------------------------------------------------------------
# Configuration
# --------------------------------------------------------------------------

empty :=
space := $(empty) $(empty)
comma := ,
BUILD_ENV_VARS := BUILD_ENV_PROFILE BASE_SYSTEM INCLUDE_DOCKER OUTPUT_FORMATS LANDSCAPE_VERSION ROOT_PASSWORD LANDSCAPE_ADMIN_USER LANDSCAPE_ADMIN_PASS LANDSCAPE_LAN_SERVER_IP LANDSCAPE_LAN_RANGE_START LANDSCAPE_LAN_RANGE_END LANDSCAPE_LAN_NETMASK RUN_TEST EFFECTIVE_CONFIG_PATH EFFECTIVE_CONFIG_PROFILE EFFECTIVE_TOPOLOGY_SOURCE APT_MIRROR ALPINE_MIRROR DOCKER_APT_MIRROR DOCKER_APT_GPG_URL SOURCE_PROBE_TIMEOUT COMPRESS_OUTPUT LANDSCAPE_REPO IMAGE_SIZE_MB DEBIAN_RELEASE ALPINE_RELEASE TIMEZONE LOCALE
BUILD_PRESERVE_ENV := $(subst $(space),$(comma),$(strip $(BUILD_ENV_VARS)))
OVMF := /usr/share/ovmf/OVMF.fd
SSH_PORT := 2222
WEB_PORT := 9800
LANDSCAPE_CONTROL_PORT := 6443
QEMU_MEM := 1024
QEMU_SMP := 2

IMAGE_BASENAME := landscape-mini-x86-$(if $(BASE_SYSTEM),$(BASE_SYSTEM),debian)$(if $(filter true,$(INCLUDE_DOCKER)),-docker,)
IMAGE := output/$(IMAGE_BASENAME).img

resolve_image_path = $${IMAGE_PATH:-$$( \
	if [ -f output/metadata/build-metadata.txt ]; then \
		awk -F'=' '/^image_file=/{print "output/" $$2; exit}' output/metadata/build-metadata.txt; \
	else \
		printf '%s' "$(IMAGE)"; \
	fi \
)}

$(foreach var,$(BUILD_ENV_VARS),$(if $(filter undefined,$(origin $(var))),,$(eval export $(var))))

# --------------------------------------------------------------------------
# Default target
# --------------------------------------------------------------------------

help: ## Show all available targets with descriptions
	@echo ""
	@echo "Landscape Mini - Development Makefile"
	@echo "======================================"
	@echo ""
	@grep -E '^[a-zA-Z_-]+:.*##' $(MAKEFILE_LIST) \
		| awk 'BEGIN {FS = ":.*## "}; {printf "  \033[36m%-22s\033[0m %s\n", $$1, $$2}'
	@echo ""
	@echo "Current build identity:"
	@echo "  BASE_SYSTEM=$(if $(BASE_SYSTEM),$(BASE_SYSTEM),<from layered env files>)"
	@echo "  INCLUDE_DOCKER=$(if $(INCLUDE_DOCKER),$(INCLUDE_DOCKER),<from layered env files>)"
	@echo "  OUTPUT_FORMATS=$(if $(OUTPUT_FORMATS),$(OUTPUT_FORMATS),<from layered env files>)"
	@echo "  IMAGE=$(IMAGE)"
	@echo "  SSH:  ssh -p $(SSH_PORT) root@localhost"
	@echo "  Web:  http://localhost:$(WEB_PORT)"
	@echo ""

# --------------------------------------------------------------------------
# Dependencies
# --------------------------------------------------------------------------

deps: ## Install all host dependencies needed for building
	sudo apt-get update
	sudo apt-get install -y debootstrap parted dosfstools e2fsprogs \
		grub-efi-amd64-bin grub-pc-bin qemu-utils qemu-system-x86 ovmf \
		rsync curl gdisk unzip

deps-test: ## Install test dependencies (sshpass, socat, curl, jq)
	sudo apt-get update
	sudo apt-get install -y sshpass socat curl jq qemu-system-x86 ovmf

# --------------------------------------------------------------------------
# Build and test targets
# --------------------------------------------------------------------------

build: ## Build image with layered env files plus explicit overrides
	sudo --preserve-env=$(BUILD_PRESERVE_ENV) ./build.sh

test: ## Run readiness checks on the current raw image
	@image_path="$(resolve_image_path)"; \
	./tests/test-readiness.sh "$$image_path"

test-dataplane: ## Run dataplane checks on the current raw image
	@image_path="$(resolve_image_path)"; \
	./tests/test-dataplane.sh "$$image_path"

# --------------------------------------------------------------------------
# Interactive QEMU targets
# --------------------------------------------------------------------------

test-serial: ## Boot current image in QEMU (interactive serial console)
	@image_path="$(resolve_image_path)"; \
	qemu-system-x86_64 \
		-enable-kvm \
		-m $(QEMU_MEM) \
		-smp $(QEMU_SMP) \
		-bios $(OVMF) \
		-drive file="$$image_path",format=raw,if=virtio \
		-device virtio-net-pci,netdev=wan \
		-netdev user,id=wan,hostfwd=tcp::$(SSH_PORT)-:22,hostfwd=tcp::$(WEB_PORT)-:$(LANDSCAPE_CONTROL_PORT) \
		-device virtio-net-pci,netdev=lan \
		-netdev user,id=lan \
		-display none \
		-serial mon:stdio

test-gui: ## Boot current image in QEMU (with VGA display window)
	@image_path="$(resolve_image_path)"; \
	qemu-system-x86_64 \
		-enable-kvm \
		-m $(QEMU_MEM) \
		-smp $(QEMU_SMP) \
		-bios $(OVMF) \
		-drive file="$$image_path",format=raw,if=virtio \
		-device virtio-net-pci,netdev=wan \
		-netdev user,id=wan,hostfwd=tcp::$(SSH_PORT)-:22,hostfwd=tcp::$(WEB_PORT)-:$(LANDSCAPE_CONTROL_PORT) \
		-device virtio-net-pci,netdev=lan \
		-netdev user,id=lan

# --------------------------------------------------------------------------
# Remote access
# --------------------------------------------------------------------------

ssh: ## SSH into the running QEMU instance
	ssh -o StrictHostKeyChecking=no -p $(SSH_PORT) root@localhost

# --------------------------------------------------------------------------
# Cleanup targets
# --------------------------------------------------------------------------

clean: ## Remove work/ directory (requires sudo)
	sudo rm -rf work/

distclean: ## Remove work/ and output/ directories (requires sudo)
	sudo rm -rf work/ output/

# --------------------------------------------------------------------------
# Status / Info
# --------------------------------------------------------------------------

status: ## Show disk usage of work/ and output/ directories
	@echo ""
	@echo "Landscape Mini - Build Status"
	@echo "=============================="
	@echo ""
	@if [ -d work ]; then \
		echo "work/ directory:"; \
		du -sh work/ 2>/dev/null || echo "  (empty)"; \
		echo ""; \
	else \
		echo "work/ directory:  does not exist"; \
		echo ""; \
	fi
	@if [ -d output ]; then \
		echo "output/ directory:"; \
		du -sh output/ 2>/dev/null || echo "  (empty)"; \
		echo ""; \
		echo "Output files:"; \
		ls -lh output/ 2>/dev/null || echo "  (none)"; \
	else \
		echo "output/ directory: does not exist"; \
	fi
	@echo ""

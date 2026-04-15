#!/bin/bash
set -euo pipefail

# =============================================================================
# Landscape Mini - Minimal x86 UEFI Image Builder
# =============================================================================
# Orchestrator: sources lib/common.sh + backend (lib/debian.sh or lib/alpine.sh)
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source configuration
if [ -f "${SCRIPT_DIR}/build.env" ]; then
    source "${SCRIPT_DIR}/build.env"
else
    echo "ERROR: build.env not found in ${SCRIPT_DIR}"
    exit 1
fi

# ---------------------------------------------------------------------------
# Parse command line arguments
# ---------------------------------------------------------------------------
SKIP_TO_PHASE=0
EFFECTIVE_CONFIG_PATH="${EFFECTIVE_CONFIG_PATH:-}"
EFFECTIVE_CONFIG_PROFILE="${EFFECTIVE_CONFIG_PROFILE:-default}"
EFFECTIVE_TOPOLOGY_SOURCE="${EFFECTIVE_TOPOLOGY_SOURCE:-default}"
ROOT_PASSWORD_SOURCE="${ROOT_PASSWORD_SOURCE:-default}"
LANDSCAPE_ADMIN_USER="${LANDSCAPE_ADMIN_USER:-root}"
LANDSCAPE_ADMIN_USER_SOURCE="${LANDSCAPE_ADMIN_USER_SOURCE:-default}"
LANDSCAPE_ADMIN_PASS="${LANDSCAPE_ADMIN_PASS:-root}"
LANDSCAPE_ADMIN_PASS_SOURCE="${LANDSCAPE_ADMIN_PASS_SOURCE:-default}"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --base)
            if [[ -n "${2:-}" && ( "$2" == "debian" || "$2" == "alpine" ) ]]; then
                BASE_SYSTEM="$2"
                shift 2
            else
                echo "ERROR: --base requires 'debian' or 'alpine'"
                exit 1
            fi
            ;;
        --with-docker)
            INCLUDE_DOCKER="yes"
            shift
            ;;
        --version)
            if [[ -n "${2:-}" ]]; then
                LANDSCAPE_VERSION="$2"
                shift 2
            else
                echo "ERROR: --version requires a value (e.g. --version v0.12.4)"
                exit 1
            fi
            ;;
        --skip-to)
            if [[ -n "${2:-}" && "${2:-}" =~ ^[1-8]$ ]]; then
                SKIP_TO_PHASE="$2"
                shift 2
            else
                echo "ERROR: --skip-to requires a phase number (1-8)"
                exit 1
            fi
            ;;
        *)
            echo "Unknown argument: $1"
            echo "Usage: $0 [--base debian|alpine] [--with-docker] [--version VERSION] [--skip-to PHASE]"
            exit 1
            ;;
    esac
done

# ---------------------------------------------------------------------------
# Must run as root
# ---------------------------------------------------------------------------
if [[ $EUID -ne 0 ]]; then
    echo "ERROR: This script must be run as root (use sudo)."
    exit 1
fi

# ---------------------------------------------------------------------------
# Source shared library and backend
# ---------------------------------------------------------------------------
source "${SCRIPT_DIR}/lib/common.sh"

case "${BASE_SYSTEM}" in
    debian)
        source "${SCRIPT_DIR}/lib/debian.sh"
        ;;
    alpine)
        source "${SCRIPT_DIR}/lib/alpine.sh"
        ;;
    *)
        echo "ERROR: Unknown base system '${BASE_SYSTEM}'. Use 'debian' or 'alpine'."
        exit 1
        ;;
esac

# ---------------------------------------------------------------------------
# Variables
# ---------------------------------------------------------------------------
WORK_DIR="$(pwd)/work"
OUTPUT_DIR="$(pwd)/output"
ROOTFS_DIR="${WORK_DIR}/rootfs"
DOWNLOAD_DIR="${WORK_DIR}/downloads/${LANDSCAPE_VERSION}"
LOOP_DEV=""
SOURCE_PROBE_TIMEOUT="${SOURCE_PROBE_TIMEOUT:-5}"

# Docker suffix
IMAGE_SUFFIX=""
if [[ "${INCLUDE_DOCKER}" == "yes" ]]; then
    IMAGE_SUFFIX="-docker"
fi

# Base system suffix (alpine gets a suffix, debian is the default with no suffix)
BASE_SUFFIX=""
if [[ "${BASE_SYSTEM}" == "alpine" ]]; then
    BASE_SUFFIX="-alpine"
fi

IMAGE_FILE="${OUTPUT_DIR}/landscape-mini-x86${BASE_SUFFIX}${IMAGE_SUFFIX}.img"
RESOLVED_SOURCES_FILE="${OUTPUT_DIR}/metadata/resolved-sources.env"

resolve_build_sources() {
    echo ""
    echo "==== Source Resolution ===="

    if [[ "${BASE_SYSTEM}" == "debian" ]]; then
        resolve_source \
            "Debian APT mirror" \
            "${APT_MIRROR}" \
            "${APT_MIRROR_CANDIDATES}" \
            "debian-package" \
            "/dists/${DEBIAN_RELEASE}/main/binary-amd64/Packages.xz" \
            "RESOLVED_APT_MIRROR" \
            "RESOLVED_APT_MIRROR_SOURCE" \
            "${SOURCE_PROBE_TIMEOUT}"
        RESOLVED_ALPINE_MIRROR=""
        RESOLVED_ALPINE_MIRROR_SOURCE="unused"
    else
        resolve_source \
            "Alpine mirror" \
            "${ALPINE_MIRROR}" \
            "${ALPINE_MIRROR_CANDIDATES}" \
            "alpine-package" \
            "/${ALPINE_RELEASE}/main/x86_64" \
            "RESOLVED_ALPINE_MIRROR" \
            "RESOLVED_ALPINE_MIRROR_SOURCE" \
            "${SOURCE_PROBE_TIMEOUT}"
        RESOLVED_APT_MIRROR=""
        RESOLVED_APT_MIRROR_SOURCE="unused"
    fi

    if [[ "${INCLUDE_DOCKER}" == "yes" && "${BASE_SYSTEM}" == "debian" ]]; then
        resolve_source \
            "Docker APT mirror" \
            "${DOCKER_APT_MIRROR}" \
            "${DOCKER_APT_MIRROR_CANDIDATES}" \
            "plain-debian-package" \
            "/dists/${DEBIAN_RELEASE}/stable/binary-amd64/Packages" \
            "RESOLVED_DOCKER_APT_MIRROR" \
            "RESOLVED_DOCKER_APT_MIRROR_SOURCE" \
            "${SOURCE_PROBE_TIMEOUT}"

        resolve_source \
            "Docker APT GPG URL" \
            "${DOCKER_APT_GPG_URL}" \
            "${DOCKER_APT_GPG_URL_CANDIDATES}" \
            "direct" \
            "" \
            "RESOLVED_DOCKER_APT_GPG_URL" \
            "RESOLVED_DOCKER_APT_GPG_URL_SOURCE" \
            "${SOURCE_PROBE_TIMEOUT}"
    else
        RESOLVED_DOCKER_APT_MIRROR=""
        RESOLVED_DOCKER_APT_MIRROR_SOURCE="unused"
        RESOLVED_DOCKER_APT_GPG_URL=""
        RESOLVED_DOCKER_APT_GPG_URL_SOURCE="unused"
    fi

    if [[ "${BASE_SYSTEM}" == "alpine" ]]; then
        MIRROR="${RESOLVED_ALPINE_MIRROR}"
    else
        MIRROR="${RESOLVED_APT_MIRROR}"
    fi

    DOCKER_MIRROR_DISPLAY="${RESOLVED_DOCKER_APT_MIRROR:-}"
    DOCKER_GPG_DISPLAY="${RESOLVED_DOCKER_APT_GPG_URL:-}"

    mkdir -p "${OUTPUT_DIR}/metadata"
    printf '%s\n' \
        "resolved_apt_mirror=${RESOLVED_APT_MIRROR}" \
        "resolved_apt_mirror_source=${RESOLVED_APT_MIRROR_SOURCE}" \
        "resolved_alpine_mirror=${RESOLVED_ALPINE_MIRROR}" \
        "resolved_alpine_mirror_source=${RESOLVED_ALPINE_MIRROR_SOURCE}" \
        "resolved_docker_apt_mirror=${RESOLVED_DOCKER_APT_MIRROR}" \
        "resolved_docker_apt_mirror_source=${RESOLVED_DOCKER_APT_MIRROR_SOURCE}" \
        "resolved_docker_apt_gpg_url=${RESOLVED_DOCKER_APT_GPG_URL}" \
        "resolved_docker_apt_gpg_url_source=${RESOLVED_DOCKER_APT_GPG_URL_SOURCE}" \
        > "${RESOLVED_SOURCES_FILE}"

    echo "  Source resolution complete."
}

load_resolved_sources() {
    if [[ ! -f "${RESOLVED_SOURCES_FILE}" ]]; then
        echo "ERROR: Missing ${RESOLVED_SOURCES_FILE} for resumed build." >&2
        return 1
    fi

    # shellcheck disable=SC1090
    source "${RESOLVED_SOURCES_FILE}"

    RESOLVED_APT_MIRROR="${resolved_apt_mirror:-}"
    RESOLVED_APT_MIRROR_SOURCE="${resolved_apt_mirror_source:-unknown}"
    RESOLVED_ALPINE_MIRROR="${resolved_alpine_mirror:-}"
    RESOLVED_ALPINE_MIRROR_SOURCE="${resolved_alpine_mirror_source:-unknown}"
    RESOLVED_DOCKER_APT_MIRROR="${resolved_docker_apt_mirror:-}"
    RESOLVED_DOCKER_APT_MIRROR_SOURCE="${resolved_docker_apt_mirror_source:-unknown}"
    RESOLVED_DOCKER_APT_GPG_URL="${resolved_docker_apt_gpg_url:-}"
    RESOLVED_DOCKER_APT_GPG_URL_SOURCE="${resolved_docker_apt_gpg_url_source:-unknown}"

    if [[ "${BASE_SYSTEM}" == "alpine" ]]; then
        MIRROR="${RESOLVED_ALPINE_MIRROR}"
    else
        MIRROR="${RESOLVED_APT_MIRROR}"
    fi

    DOCKER_MIRROR_DISPLAY="${RESOLVED_DOCKER_APT_MIRROR:-}"
    DOCKER_GPG_DISPLAY="${RESOLVED_DOCKER_APT_GPG_URL:-}"

    echo "  Reusing resolved sources from ${RESOLVED_SOURCES_FILE}."
}

should_resolve_sources() {
    if [[ ${SKIP_TO_PHASE} -le 4 ]]; then
        return 0
    fi

    if [[ "${INCLUDE_DOCKER}" == "yes" && ${SKIP_TO_PHASE} -le 6 ]]; then
        return 0
    fi

    return 1
}

# Determine download base URL
if [ "${LANDSCAPE_VERSION}" == "latest" ]; then
    DOWNLOAD_BASE="${LANDSCAPE_REPO}/releases/latest/download"
else
    DOWNLOAD_BASE="${LANDSCAPE_REPO}/releases/download/${LANDSCAPE_VERSION}"
fi

# ---------------------------------------------------------------------------
# Setup trap
# ---------------------------------------------------------------------------
trap cleanup EXIT ERR

main() {
    # Check backend-specific host dependencies
    backend_check_deps

    if should_resolve_sources; then
        resolve_build_sources
    elif [[ ${SKIP_TO_PHASE} -gt 0 ]]; then
        load_resolved_sources
    fi

    echo "============================================================"
    echo "  Landscape Mini - x86 UEFI Image Builder"
    echo "============================================================"
    echo "  Base System       : ${BASE_SYSTEM}"
    echo "  Landscape Version : ${LANDSCAPE_VERSION}"
    echo "  Download Source    : ${DOWNLOAD_BASE}"
    if [[ "${BASE_SYSTEM}" == "debian" ]]; then
        echo "  Debian Release    : ${DEBIAN_RELEASE}"
        echo "  APT Mirror        : ${MIRROR} (${RESOLVED_APT_MIRROR_SOURCE})"
    else
        echo "  Alpine Release    : ${ALPINE_RELEASE}"
        echo "  Alpine Mirror     : ${MIRROR} (${RESOLVED_ALPINE_MIRROR_SOURCE})"
    fi
    echo "  Image Size        : ${IMAGE_SIZE_MB} MB"
    echo "  Include Docker    : ${INCLUDE_DOCKER}"
    if [[ "${INCLUDE_DOCKER}" == "yes" && "${BASE_SYSTEM}" == "debian" ]]; then
        echo "  Docker APT Mirror : ${DOCKER_MIRROR_DISPLAY} (${RESOLVED_DOCKER_APT_MIRROR_SOURCE})"
        echo "  Docker GPG URL    : ${DOCKER_GPG_DISPLAY} (${RESOLVED_DOCKER_APT_GPG_URL_SOURCE})"
    elif [[ "${INCLUDE_DOCKER}" == "yes" && "${BASE_SYSTEM}" == "alpine" ]]; then
        echo "  Docker Source     : Alpine packages via ${MIRROR} (${RESOLVED_ALPINE_MIRROR_SOURCE})"
    fi
    echo "  Output Format     : ${OUTPUT_FORMAT}"
    echo "  Compress Output   : ${COMPRESS_OUTPUT}"
    echo "  Config Profile    : ${EFFECTIVE_CONFIG_PROFILE}"
    echo "  Topology Source   : ${EFFECTIVE_TOPOLOGY_SOURCE}"
    echo "  Admin User        : ${LANDSCAPE_ADMIN_USER}"
    echo "============================================================"

    if [[ ${SKIP_TO_PHASE} -gt 0 ]]; then
        echo ""
        echo "==== Resuming from Phase ${SKIP_TO_PHASE} ===="
        echo "  Phase 1: Download      | Phase 5: Install Landscape"
        echo "  Phase 2: Create Image  | Phase 6: Install Docker"
        echo "  Phase 3: Bootstrap     | Phase 7: Cleanup & Shrink"
        echo "  Phase 4: Configure     | Phase 8: Report"
    fi

    # Phase 1: Download (always run unless skipping past it)
    [[ ${SKIP_TO_PHASE} -le 1 ]] && phase_download

    # Phase 2: Create image
    if [[ ${SKIP_TO_PHASE} -le 2 ]]; then
        phase_create_image
    elif [[ ${SKIP_TO_PHASE} -le 7 ]]; then
        # Need to re-attach image for phases 3-7
        resume_from_image
    fi

    [[ ${SKIP_TO_PHASE} -le 3 ]] && backend_bootstrap
    [[ ${SKIP_TO_PHASE} -le 4 ]] && backend_configure
    [[ ${SKIP_TO_PHASE} -le 5 ]] && phase_install_landscape
    [[ ${SKIP_TO_PHASE} -le 6 ]] && backend_install_docker
    [[ ${SKIP_TO_PHASE} -le 7 ]] && phase_cleanup_and_shrink
    phase_report
}

main

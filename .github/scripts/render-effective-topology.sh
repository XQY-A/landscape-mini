#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"
DEFAULT_TEMPLATE="${PROJECT_DIR}/configs/landscape_init.toml"
OUTPUT_PATH="${1:-${PROJECT_DIR}/output/metadata/effective-landscape_init.toml}"

LAN_SERVER_IP="${LANDSCAPE_LAN_SERVER_IP:-}"
LAN_RANGE_START="${LANDSCAPE_LAN_RANGE_START:-}"
LAN_RANGE_END="${LANDSCAPE_LAN_RANGE_END:-}"
LAN_NETMASK="${LANDSCAPE_LAN_NETMASK:-}"

mkdir -p "$(dirname "${OUTPUT_PATH}")"
cp "${DEFAULT_TEMPLATE}" "${OUTPUT_PATH}"

replace_line() {
    local key="$1"
    local value="$2"
    local is_string="${3:-true}"

    if [[ -z "${value}" ]]; then
        return 0
    fi

    if [[ "${is_string}" == "true" ]]; then
        python3 - "$OUTPUT_PATH" "$key" "$value" <<'PY'
from pathlib import Path
import re
import sys
path = Path(sys.argv[1])
key = sys.argv[2]
value = sys.argv[3]
text = path.read_text()
pattern = rf'(^\s*{re.escape(key)}\s*=\s*").*("\s*$)'
new_text, count = re.subn(
    pattern,
    lambda m: f"{m.group(1)}{value}{m.group(2)}",
    text,
    flags=re.MULTILINE,
)
if count != 1:
    raise SystemExit(f"Failed to replace {key}, matches={count}")
path.write_text(new_text)
PY
    else
        python3 - "$OUTPUT_PATH" "$key" "$value" <<'PY'
from pathlib import Path
import re
import sys
path = Path(sys.argv[1])
key = sys.argv[2]
value = sys.argv[3]
text = path.read_text()
pattern = rf'(^\s*{re.escape(key)}\s*=\s*).*(\s*$)'
new_text, count = re.subn(
    pattern,
    lambda m: f"{m.group(1)}{value}{m.group(2)}",
    text,
    flags=re.MULTILINE,
)
if count != 1:
    raise SystemExit(f"Failed to replace {key}, matches={count}")
path.write_text(new_text)
PY
    fi
}

replace_line "server_ip_addr" "${LAN_SERVER_IP}" true
replace_line "ip_range_start" "${LAN_RANGE_START}" true
replace_line "ip_range_end" "${LAN_RANGE_END}" true
replace_line "network_mask" "${LAN_NETMASK}" false

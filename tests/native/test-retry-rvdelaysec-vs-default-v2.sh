#!/usr/bin/env bash
# RVDelaysec configured vs default with V2 API

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)/test-retry-rvdelaysec-vs-default.sh"
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)/../../utils/mgmt-api-v2.sh"

# Override rv_info to use V2 format (array of arrays with integer ports)
rv_info="[[{\"dev_only\": true}, {\"ip\": \"192.0.2.1\"}, {\"device_port\": 8041}, {\"protocol\": \"http\"}, {\"delay_seconds\": 5}],
          [{\"dev_only\": true}, {\"ip\": \"192.0.2.2\"}, {\"device_port\": 8041}, {\"protocol\": \"http\"}]]"

# Allow running directly
[[ "${BASH_SOURCE[0]}" != "$0" ]] || {
  run_test
  cleanup
}

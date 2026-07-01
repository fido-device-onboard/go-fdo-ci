#!/usr/bin/env bash
# RV bypass + TO1 coexistence with V2 API

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)/test-retry-rv-bypass-to1-coexistence.sh"
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)/../../utils/mgmt-api-v2.sh"

# Override rv_info to use V2 format (array of arrays with integer ports)
rv_info="[[{\"ip\": \"192.0.2.1\"}, {\"device_port\": 8041}, {\"owner_port\": 8043}, {\"protocol\": \"http\"}, {\"delay_seconds\": 2}, {\"rv_bypass\": true}],
          [{\"ip\": \"${rendezvous_ip}\"}, {\"device_port\": ${rendezvous_port}}, {\"owner_port\": ${rendezvous_port}}, {\"protocol\": \"${rendezvous_protocol}\"}]]"

unreachable_rvto2addr="[{\"ip\": \"192.0.2.1\", \"port\": ${owner_port}, \"protocol\": \"${owner_protocol}\"},
                        {\"ip\": \"192.0.2.2\", \"port\": ${owner_port}, \"protocol\": \"${owner_protocol}\"}]"

# Allow running directly
[[ "${BASH_SOURCE[0]}" != "$0" ]] || {
  run_test
  cleanup
}

#!/usr/bin/env bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)/../native/test-retry-rv-bypass-to1-coexistence-v2.sh"
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)/../../utils/container.sh"

rv_info="[[{\"ip\": \"192.0.2.1\"}, {\"device_port\": 8041}, {\"owner_port\": 8043}, {\"protocol\": \"http\"}, {\"delay_seconds\": 2}, {\"rv_bypass\": true}],
          [{\"dns\": \"${rendezvous_dns}\"}, {\"device_port\": ${rendezvous_port}}, {\"owner_port\": ${rendezvous_port}}, {\"protocol\": \"${rendezvous_protocol}\"}]]"

# Allow running directly
[[ "${BASH_SOURCE[0]}" != "$0" ]] || {
  run_test
  cleanup
}

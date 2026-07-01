#!/usr/bin/env bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)/../native/test-retry-rv-bypass-to1-coexistence.sh"
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)/../../utils/container.sh"

# Two directives: bypass with unreachable owner + normal TO1
rv_info="[{\"ip\": \"192.0.2.1\", \"device_port\": \"8041\", \"owner_port\": \"8043\", \"protocol\": \"http\", \"rv_bypass\": true, \"delay_seconds\": 3},
          {\"dns\": \"${rendezvous_dns}\", \"device_port\": \"${rendezvous_port}\", \"owner_port\": \"${rendezvous_port}\", \"protocol\": \"${rendezvous_protocol}\"}]"

# Allow running directly
[[ "${BASH_SOURCE[0]}" != "$0" ]] || {
  run_test
  cleanup
}

#!/usr/bin/env bash
# TO2 retry delay configured with V2 API

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)/test-retry-to2-delay-configured.sh"
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)/../../utils/mgmt-api-v2.sh"

unreachable_rvto2addr="[{\"ip\": \"192.0.2.1\", \"port\": ${owner_port}, \"protocol\": \"${owner_protocol}\"},
                        {\"ip\": \"192.0.2.2\", \"port\": ${owner_port}, \"protocol\": \"${owner_protocol}\"}]"

# Allow running directly
[[ "${BASH_SOURCE[0]}" != "$0" ]] || {
  run_test
  cleanup
}

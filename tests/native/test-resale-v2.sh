#!/usr/bin/env bash
# Resale test: Verify voucher extension and transfer to a new owner (V2 API)

set -euo pipefail

# Source base test script
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)/test-resale.sh"
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)/../../utils/mgmt-api-v2.sh"

new_owner_rvto2addr="[{\"ip\": \"${new_owner_ip}\", \"dns\": \"${new_owner_dns}\", \"port\": ${new_owner_port}, \"protocol\": \"${new_owner_protocol}\"}]"

# Allow running directly
[[ "${BASH_SOURCE[0]}" != "$0" ]] || {
  run_test
  cleanup
}

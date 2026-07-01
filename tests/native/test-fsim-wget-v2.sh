#!/usr/bin/env bash
#
# This test verifies the fdo.wget FSIM
#
# Step 1: the test generates files to be served by the httpd server
# Step 2: configure the wget service module to download the files to
#         different locations on the device's filesystem
# Step 3: verify the device has downloaded files properly

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)/test-fsim-wget.sh"
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)/../../utils/mgmt-api-v2.sh"

# Allow running directly
[[ "${BASH_SOURCE[0]}" != "$0" ]] || {
  run_test
  cleanup
}

#! /usr/bin/env bash
#
# This test verifies that a sequence of FSIMs is performed in the proper order.
#
# Step 1: download a bash script to the device
# Step 2: have the device run the bash script with command line
#         arguments, the script generates output
# Step 3: upload the generated output
#
# The test passes if the output is generated as expected

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)/test-fsim-config.sh"
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)/../../utils/mgmt-api-v2.sh"

# Allow running directly
[[ "${BASH_SOURCE[0]}" != "$0" ]] || {
  run_test
  cleanup
}

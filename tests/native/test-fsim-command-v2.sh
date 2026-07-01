#!/usr/bin/env bash
#
# This test verifies the fdo.command FSIM
#
# Step 1: run "touch" on the device to create an empty test file
# Step 2: run a command that renames the test file
#
# Verify that the file exists in the working directory of the
# go-fdo-client and has the expected name.

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)/test-fsim-command.sh"
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)/../../utils/mgmt-api-v2.sh"

# Allow running directly
[[ "${BASH_SOURCE[0]}" != "$0" ]] || {
  run_test
  cleanup
}

#!/usr/bin/env bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)/test-fsim-upload.sh"
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)/../../utils/mgmt-api-v2.sh"

get_device_guid() {
  local owner_url=$1
  local guid=$2
  local device_guid
  device_guid=$(curl --silent --fail --insecure "${owner_url}/api/v2/devices?old_guid=${guid}" | jq -r '.devices.[0].guid')
  echo "${device_guid}"
}

# Allow running directly
[[ "${BASH_SOURCE[0]}" != "$0" ]] || {
  run_test
  cleanup
}

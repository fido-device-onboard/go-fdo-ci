#! /usr/bin/env bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)/../ci/test-fsim-wget.sh"
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)/utils.sh"

servers_compose_file="${compose_dir}/server/test-fsim-wget.yaml"

# Allow running directly
[[ "${BASH_SOURCE[0]}" != "$0" ]] || {
  run_test
  cleanup
}

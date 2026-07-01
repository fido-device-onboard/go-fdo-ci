#!/usr/bin/env bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)/../native/test-retry-rvdelaysec-vs-default.sh"
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)/../../utils/container.sh"

run_go_fdo_client() {
  # Translate host paths to container paths in arguments
  local args=()
  for arg in "$@"; do
    # Replace base_dir with container_working_dir in paths
    args+=("${arg//$base_dir/$container_working_dir}")
  done
  local exit_code=0
  timeout --signal=INT --kill-after=5s "${client_timeout}" \
    docker run --init --rm \
    --hostname go-fdo-client \
    --workdir "${container_working_dir}/device-credentials" \
    --user "${container_user}" \
    --network fdo \
    --volume "${base_dir}:${container_working_dir}" \
    go-fdo-client "${args[@]}" || exit_code=$?
  if [[ ${exit_code} -ne 0 ]]; then
    log_warn "Command timed out (${exit_code}): 'go-fdo-client $*'"
    [ "${exit_code}" != "137" ] ||
      log_error "Command returned '${exit_code}' maybe the 'go-fdo-client' didn't respond to SIGINT and was killed with SIGKILL."
  fi
  return ${exit_code}
}

# Allow running directly
[[ "${BASH_SOURCE[0]}" != "$0" ]] || {
  run_test
  cleanup
}

#!/usr/bin/env bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)/test-onboarding.sh"

configs_dir="${base_dir}/configs"
manufacturer_config_file="${configs_dir}/manufacturing.yaml"
rendezvous_config_file="${configs_dir}/rendezvous.yaml"
owner_config_file="${configs_dir}/owner.yaml"

directories+=("${configs_dir}")

configure_service_manufacturer() {
  cat >"${manufacturer_config_file}" <<EOF
log:
  level: "${manufacturer_log_level}"
db:
  type: "${manufacturer_db_type}"
  dsn: "${manufacturer_db_dsn}"
http:
  ip: "${manufacturer_dns}"
  port: ${manufacturer_port}
manufacturing:
  key: "${manufacturer_key}"
device_ca:
  cert: "${device_ca_crt}"
  key: "${device_ca_key}"
owner:
  cert: "${owner_crt}"
EOF
}

configure_service_rendezvous() {
  cat >"${rendezvous_config_file}" <<EOF
log:
  level: "${rendezvous_log_level}"
db:
  type: "${rendezvous_db_type}"
  dsn: "${rendezvous_db_dsn}"
http:
  ip: "${rendezvous_dns}"
  port: ${rendezvous_port}
EOF
}

configure_service_owner() {
  cat >"${owner_config_file}" <<EOF
log:
  level: "${owner_log_level}"
db:
  type: "${owner_db_type}"
  dsn: "${owner_db_dsn}"
http:
  ip: "${owner_dns}"
  port: ${owner_port}
device_ca:
  cert: "${device_ca_crt}"
owner:
  key: "${owner_key}"
  to0_insecure_tls: true
EOF
}

# override to remove use of CLI flags
run_go_fdo_server() {
  local role=$1
  local pid_file=$2
  local log=$3
  shift 3
  mkdir -p "$(dirname "${log}")"
  mkdir -p "$(dirname "${pid_file}")"
  nohup "${bin_dir}/go-fdo-server" "${role}" "${@}" &>"${log}" &
  echo -n $! >"${pid_file}"
}

start_service_manufacturer() {
  run_go_fdo_server manufacturing "${manufacturer_pid_file}" "${manufacturer_log_file}" \
    --config="${manufacturer_config_file}"
}

start_service_rendezvous() {
  run_go_fdo_server rendezvous "${rendezvous_pid_file}" "${rendezvous_log_file}" \
    --config="${rendezvous_config_file}"
}

start_service_owner() {
  run_go_fdo_server owner "${owner_pid_file}" "${owner_log_file}" \
    --config="${owner_config_file}"
}

# Allow running directly
[[ "${BASH_SOURCE[0]}" != "$0" ]] || {
  run_test
  cleanup
}

#!/usr/bin/env bash
# RV bypass + TO1 coexistence: first directive uses bypass with unreachable
# owners (TO2 fails multiple times with default 0s delay), then falls back
# to normal TO1 on the second directive which succeeds.

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)/../../utils/native.sh"
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)/../../utils/mgmt-api-v1.sh"

# Two directives: bypass with unreachable owner + normal TO1
rv_info="[{\"ip\": \"192.0.2.1\", \"device_port\": \"8041\", \"owner_port\": \"8043\", \"protocol\": \"http\", \"rv_bypass\": true, \"delay_seconds\": 3},
          {\"ip\": \"${rendezvous_ip}\", \"device_port\": \"${rendezvous_port}\", \"owner_port\": \"${rendezvous_port}\", \"protocol\": \"${rendezvous_protocol}\"}]"

unreachable_rvto2addr="[{\"ip\": \"192.0.2.1\", \"port\": \"${owner_port}\", \"protocol\": \"${owner_protocol}\"},
                        {\"ip\": \"192.0.2.2\", \"port\": \"${owner_port}\", \"protocol\": \"${owner_protocol}\"}]"

run_test() {
  log_info "Setting the error trap handler"
  trap on_failure EXIT

  log_info "Creating directories"
  create_directories

  log_info "Generating service certificates"
  generate_service_certs

  log_info "Build and install 'go-fdo-client' binary"
  install_client

  log_info "Build and install 'go-fdo-server' binary"
  install_server

  log_info "Configuring services"
  configure_services

  log_info "Configure DNS and start services"
  start_services

  log_info "Wait for the services to be ready:"
  wait_for_services_ready

  log_info "Resolving real owner IP for RVTO2Addr"
  rvto2addr=$(resolve_rvto2addr "${owner_service_name}" "${rvto2addr}")

  # Prepend unreachable owner addresses to trigger TO2 failures before the real owner
  rvto2addr=$(echo "${rvto2addr}" | jq "${unreachable_rvto2addr} + .")

  log_info "Setting Rendezvous Info with RV BYPASS + TO1 coexistence"
  set_or_update_rendezvous_info "${manufacturer_url}" "${rv_info}"

  log_info "Adding Device CA certificate to rendezvous"
  add_device_ca_cert "${rendezvous_url}" "${device_ca_crt}" | jq -r -M .

  log_info "Run Device Initialization"
  guid=$(run_device_initialization)
  log_info "Device initialized with GUID: ${guid}"

  log_info "Setting RVTO2Addr with multiple owner addresses (2 unreachable + 1 real)"
  set_or_update_rvto2addr "${owner_url}" "${rvto2addr}"

  log_info "Sending Ownership Voucher to the Owner"
  send_manufacturer_ov_to_owner "${manufacturer_url}" "${guid}" "${owner_url}"

  log_info "Running FIDO Device Onboard (bypass fails, then TO1 succeeds)"
  run_fido_device_onboard "${guid}" --debug || log_error "Onboarding failed!"

  local log_file
  log_file="$(get_device_onboard_log_file_path "${guid}")"

  log_info "Validating retry behavior in client log"
  find_in_log "${log_file}" "RV bypass enabled" || log_error "Expected 'RV bypass enabled' in log"
  find_in_log "${log_file}" "Using Owner URL from bypass directive" || log_error "Expected bypass owner URL usage in log"
  find_in_log "${log_file}" "Applying directive delay" || log_error "Expected directive delay in log"
  find_in_log "${log_file}" "Attempting TO1 protocol" || log_error "Expected TO1 attempt in log"
  find_in_log "${log_file}" "TO1 succeeded" || log_error "Expected TO1 success in log"
  find_in_log "${log_file}" "TO2 succeeded" || log_error "Expected TO2 success in log"
  ! find_in_log "${log_file}" "Applying TO2 retry delay" || log_error "TO2 retry delay should not be applied (default is 0s)"

  local to2_failures
  to2_failures=$(count_in_log "${log_file}" "TO2 failed")
  [ "${to2_failures}" -ge 2 ] || log_error "Expected at least 2 TO2 failures, got ${to2_failures}"

  log_info "Unsetting the error trap handler"
  trap - EXIT
  test_pass
}

# Allow running directly
[[ "${BASH_SOURCE[0]}" != "$0" ]] || {
  run_test
  cleanup
}

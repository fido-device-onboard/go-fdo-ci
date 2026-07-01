#!/usr/bin/env bash
# TO2 retry delay configured: uses --to2-retry-delay 3s flag to add a delay
# between TO2 owner attempts. Multiple unreachable owners cause TO2 failures
# with delays before the real owner succeeds.

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)/../../utils/native.sh"
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)/../../utils/mgmt-api-v1.sh"

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

  # Prepend unreachable owner addresses to trigger TO2 failures with retry delay
  rvto2addr=$(echo "${rvto2addr}" | jq "${unreachable_rvto2addr} + .")

  log_info "Setting or updating Rendezvous Info (RendezvousInfo)"
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

  log_info "Running FIDO Device Onboard with --to2-retry-delay 3s"
  run_fido_device_onboard "${guid}" --debug --to2-retry-delay 3s || log_error "Onboarding failed!"

  local log_file
  log_file="$(get_device_onboard_log_file_path "${guid}")"

  log_info "Validating TO2 retry delay behavior in client log"
  find_in_log "${log_file}" "Applying TO2 retry delay" || log_error "Expected TO2 retry delay in log"

  local to2_delays
  to2_delays=$(count_in_log "${log_file}" "Applying TO2 retry delay")
  [ "${to2_delays}" -ge 2 ] || log_error "Expected at least 2 TO2 retry delays, got ${to2_delays}"

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

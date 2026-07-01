#!/usr/bin/env bash
# RVDelaysec configured vs default: first directive fails TO1 with a
# configured 5s delay, second (last) directive fails TO1 triggering the
# default 120s delay. Then SIGINT is sent to verify graceful cancellation.

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)/../../utils/native.sh"
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)/../../utils/mgmt-api-v1.sh"

# Two directives with dev_only pointing to unreachable IPs:
# first has delay_seconds=5, second has no delay (triggers 120s default)
rv_info="[{\"dev_only\": true, \"ip\": \"192.0.2.1\", \"device_port\": \"8041\", \"protocol\": \"http\", \"delay_seconds\": 5},
          {\"dev_only\": true, \"ip\": \"192.0.2.2\", \"device_port\": \"8041\", \"protocol\": \"http\"}]"

run_go_fdo_client() {
  # If the command times out, the return code is 124 (see: man timeout)
  # If the command finishes before the timeout, the return code comes from 'go-fdo-client'
  local exit_code=0
  timeout --signal=INT --kill-after=5s "${client_timeout}" "${bin_dir}/go-fdo-client" "$@" || exit_code=$?
  if [[ ${exit_code} -ne 0 ]]; then
    log_warn "'go-fdo-client' exited with '${exit_code}' (124 -> timeout):\n  - go-fdo-client $*"
    [ "${exit_code}" != "137" ] ||
      log_error "Command returned '${exit_code}' maybe the 'go-fdo-client' didn't respond to SIGINT and was killed with SIGKILL."
  fi
  return ${exit_code}
}

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

  log_info "Setting Rendezvous Info with unreachable endpoints and delay_seconds"
  set_or_update_rendezvous_info "${manufacturer_url}" "${rv_info}"

  log_info "Adding Device CA certificate to rendezvous"
  add_device_ca_cert "${rendezvous_url}" "${device_ca_crt}" | jq -r -M .

  log_info "Run Device Initialization"
  guid=$(run_device_initialization)
  log_info "Device initialized with GUID: ${guid}"

  log_info "Sending Ownership Voucher to the Owner"
  send_manufacturer_ov_to_owner "${manufacturer_url}" "${guid}" "${owner_url}"

  local log_file
  log_file="$(get_device_onboard_log_file_path "${guid}")"

  # Send SIGINT after 300s (enough time to reach the default 120s delay on the
  # last directive), then SIGKILL after 5s if the process doesn't exit
  client_timeout=300s
  log_info "Running FIDO Device Onboard with timeout (SIGINT after ${client_timeout})"
  ! run_fido_device_onboard "${guid}" --debug || log_error "Onboarding must have failed!"

  log_info "Validating retry behavior in client log"
  find_in_log "${log_file}" "Applying directive delay" || log_error "Expected configured directive delay in log"
  find_in_log "${log_file}" "Applying default delay for last directive" || log_error "Expected default delay for last directive in log"
  find_in_log "${log_file}" "All TO1 attempts failed for this directive" || log_error "Expected TO1 failure message in log"
  find_in_log "${log_file}" "Onboarding canceled by user" || log_error "Expected cancellation message in log"

  local to1_attempts
  to1_attempts=$(count_in_log "${log_file}" "Attempting TO1 protocol")
  [ "${to1_attempts}" -ge 2 ] || log_error "Expected at least 2 TO1 attempts, got ${to1_attempts}"

  log_info "Unsetting the error trap handler"
  trap - EXIT
  test_pass
}

# Allow running directly
[[ "${BASH_SOURCE[0]}" != "$0" ]] || {
  run_test
  cleanup
}

#! /usr/bin/env bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)/utils.sh"
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)/../utils/mgmt-api-v1.sh"

run_test() {

  log_info "Setting the error trap handler"
  trap on_failure EXIT

  log_info "Environment variables"
  show_env

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

  log_info "Setting or updating Rendezvous Info (RendezvousInfo)"
  set_or_update_rendezvous_info "${manufacturer_url}" "${rv_info}"

  log_info "Adding Device CA certificate to rendezvous"
  add_device_ca_cert "${rendezvous_url}" "${device_ca_crt}" | jq -r -M .

  log_info "=== Test 1: FDO 1.1 client with FDO 2.0-capable server ==="
  log_info "Run Device Initialization"
  guid1=$(run_device_initialization)
  log_info "Device initialized with GUID: ${guid1}"

  log_info "Setting or updating Owner Redirect Info (RVTO2Addr)"
  set_or_update_rvto2addr "${owner_url}" "${owner_service_name}" "${owner_dns}" "${owner_port}" "${owner_protocol}"

  log_info "Sending Ownership Voucher to the Owner"
  send_manufacturer_ov_to_owner "${manufacturer_url}" "${guid1}" "${owner_url}"

  log_info "Run FDO 1.1 onboarding"
  run_fido_device_onboard "${guid1}" --fdo-version 101 --debug || log_error "FDO 1.1 onboarding failed!"

  log_info "Verifying FDO 1.1 protocol was used"
  verify_fdo_version "1.1" "${guid1}"

  log_success "Test 1 passed: FDO 1.1 client works with FDO 2.0-capable server"

  log_info "=== Test 2: FDO 2.0 client with FDO 2.0-capable server ==="

  log_info "=== Test 2: FDO 2.0 client with FDO 2.0-capable server ==="

  # Reset for second test
  log_info "Resetting device for FDO 2.0 test"
  rm -f "${fdo_conf_root}/device_credential.bin"

  log_info "Run Device Initialization for second device"
  guid2=$(run_device_initialization)
  log_info "Device initialized with GUID: ${guid2}"

  log_info "Sending second Ownership Voucher to the Owner"
  send_manufacturer_ov_to_owner "${manufacturer_url}" "${guid2}" "${owner_url}"

  log_info "Run FDO 2.0 onboarding"
  run_fido_device_onboard "${guid2}" --fdo-version 200 --debug || log_error "FDO 2.0 onboarding failed!"

  log_info "Verifying FDO 2.0 protocol was used"
  verify_fdo_version "2.0" "${guid2}"

  log_success "Test 2 passed: FDO 2.0 client works with FDO 2.0-capable server"

  log_info "Unsetting the error trap handler"
  trap - EXIT
  test_pass
}

verify_fdo_version() {
  local expected_version=$1
  local guid=$2
  local log_file=$(get_device_onboard_log_file_path "${guid}")
  log_info "Verifying FDO protocol version ${expected_version} was used"

  case "${expected_version}" in
    "1.1")
      # Check for FDO 1.1 - no specific message, just verify it worked
      if [ -f "${log_file}" ]; then
        log_info "Confirmed: FDO ${expected_version} onboarding completed"
      else
        log_error "FDO ${expected_version} log file not found"
        return 1
      fi
      ;;
    "2.0")
      # Check for FDO 2.0 specific patterns
      if grep -q "Using FDO 2.0 protocol (message types 80-91)" "${log_file}"; then
        log_info "Confirmed: FDO ${expected_version} protocol was used (message types 80-91)"
      else
        log_error "FDO ${expected_version} protocol markers not found in logs"
        return 1
      fi
      ;;
    *)
      log_error "Unknown FDO version: ${expected_version}"
      return 1
      ;;
  esac
}

# Allow running directly
[[ "${BASH_SOURCE[0]}" != "$0" ]] || {
  run_test
  cleanup
}

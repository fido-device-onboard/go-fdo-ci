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
  send_ownership_voucher_to_owner "${owner_url}" "${guid1}"

  log_info "Registering Ownership Voucher to Rendezvous"
  register_ownership_voucher "${owner_url}" "${guid1}"

  log_info "Run FDO 1.1 onboarding"
  run_device_onboarding_v11 "${guid1}"

  log_info "Verifying FDO 1.1 onboarding results"
  verify_onboarding_success

  log_info "Verifying FDO 1.1 protocol was used"
  verify_fdo_version "1.1" "${test_dir}/onboard-v11.log"

  log_success "Test 1 passed: FDO 1.1 client works with FDO 2.0-capable server"

  log_info "=== Test 2: FDO 2.0 client with FDO 2.0-capable server ==="

  # Reset for second test
  log_info "Resetting device for FDO 2.0 test"
  reset_device_credential

  log_info "Run Device Initialization for second device"
  guid2=$(run_device_initialization)
  log_info "Device initialized with GUID: ${guid2}"

  log_info "Sending second Ownership Voucher to the Owner"
  send_ownership_voucher_to_owner "${owner_url}" "${guid2}"

  log_info "Registering second Ownership Voucher to Rendezvous"
  register_ownership_voucher "${owner_url}" "${guid2}"

  log_info "Run FDO 2.0 onboarding"
  run_device_onboarding_v2 "${guid2}"

  log_info "Verifying FDO 2.0 onboarding results"
  verify_onboarding_success

  log_info "Verifying FDO 2.0 protocol was used"
  verify_fdo_version "2.0" "${test_dir}/onboard-v2.log"

  log_success "Test 2 passed: FDO 2.0 client works with FDO 2.0-capable server"

  log_success "Cross-version compatibility tests completed successfully!"
}

# Run FDO 1.1 onboarding
run_device_onboarding_v11() {
  local guid=$1
  log_info "Starting FDO 1.1 onboarding for device: ${guid}"

  sudo -u fdo /usr/local/bin/go-fdo-client onboard \
    --fdo-version 101 \
    --blob "${fdo_conf_root}/device_credential.bin" \
    --key ec256 \
    --kex ECDH256 \
    --cipher A128GCM \
    --insecure-tls \
    --debug 2>&1 | tee "${test_dir}/onboard-v11.log"

  log_info "FDO 1.1 onboarding completed"
}

# Run FDO 2.0 onboarding
run_device_onboarding_v2() {
  local guid=$1
  log_info "Starting FDO 2.0 onboarding for device: ${guid}"

  sudo -u fdo /usr/local/bin/go-fdo-client onboard \
    --fdo-version 200 \
    --blob "${fdo_conf_root}/device_credential.bin" \
    --key ec256 \
    --kex ECDH256 \
    --cipher A128GCM \
    --insecure-tls \
    --debug 2>&1 | tee "${test_dir}/onboard-v2.log"

  log_info "FDO 2.0 onboarding completed"
}

verify_fdo_version() {
  local expected_version=$1
  local log_file=$2
  log_info "Verifying FDO protocol version ${expected_version} was used"

  case "${expected_version}" in
    "1.1")
      # Check for FDO 1.1 specific patterns
      if grep -qE "message type (6[0-9]|7[01])" "${log_file}"; then
        log_info "Confirmed: FDO ${expected_version} protocol was used (message types 60-71)"
      else
        log_error "FDO ${expected_version} protocol markers not found in logs"
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

reset_device_credential() {
  log_info "Resetting device credential for next test"
  rm -f "${fdo_conf_root}/device_credential.bin"
}

# Run the test
run_test

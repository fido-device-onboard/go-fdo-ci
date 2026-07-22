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

  log_info "Run Device Initialization"
  guid=$(run_device_initialization)
  log_info "Device initialized with GUID: ${guid}"

  log_info "Setting or updating Owner Redirect Info (RVTO2Addr)"
  set_or_update_rvto2addr "${owner_url}" "${owner_service_name}" "${owner_dns}" "${owner_port}" "${owner_protocol}"

  log_info "Sending Ownership Voucher to the Owner"
  send_ownership_voucher_to_owner "${owner_url}" "${guid}"

  log_info "Registering Ownership Voucher to Rendezvous"
  register_ownership_voucher "${owner_url}" "${guid}"

  log_info "Run FDO 2.0 onboarding (protocol version 200)"
  run_device_onboarding_v2 "${guid}"

  log_info "Verifying onboarding results"
  verify_onboarding_success

  log_info "Verifying FDO 2.0 protocol was used"
  verify_fdo_version "2.0"

  log_success "FDO 2.0 onboarding completed successfully!"
}

# Override onboarding function to use FDO 2.0
run_device_onboarding_v2() {
  local guid=$1
  log_info "Starting FDO 2.0 onboarding for device: ${guid}"

  # Run onboard with explicit FDO version 200
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
  log_info "Verifying FDO protocol version ${expected_version} was used"

  # Check log for FDO 2.0 specific messages
  if grep -q "Using FDO 2.0 protocol (message types 80-91)" "${test_dir}/onboard-v2.log"; then
    log_info "Confirmed: FDO ${expected_version} protocol was used"
  else
    log_error "FDO ${expected_version} protocol markers not found in logs"
    return 1
  fi
}

# Run the test
run_test

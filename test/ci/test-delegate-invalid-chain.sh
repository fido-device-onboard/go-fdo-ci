#! /usr/bin/env bash
# Delegate invalid chain test: Verify that TO2 fails when the delegate
# certificate chain is signed by a different key than the owner key.
# This is a security-critical test: an attacker should NOT be able to
# forge a delegate chain with a key they control.

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)/test-delegate-onboarding.sh"

# FDO delegate permission OIDs (re-declare for clarity)
OID_PERMIT_ONBOARD_NEW_CRED="1.3.6.1.4.1.45724.3.1.2"

# Paths for the "wrong" key that will sign the delegate cert
wrong_signer_key="${certs_dir}/wrong_signer.key"
wrong_signer_crt="${certs_dir}/wrong_signer.crt"

run_test() {

  log_info "Setting the error trap handler"
  trap on_failure EXIT

  log_info "Environment variables"
  show_env

  log_info "Creating directories"
  create_directories

  log_info "Generating service certificates"
  generate_service_certs

  log_info "Generating a WRONG signer key (not the owner key)"
  openssl ecparam -name prime256v1 -genkey -outform der -out "${wrong_signer_key}" 2>/dev/null
  openssl req -x509 -key "${wrong_signer_key}" -keyform der -subj "/C=US/O=Attacker/CN=Wrong Signer" -days 365 -out "${wrong_signer_crt}" 2>/dev/null

  log_info "Generating delegate certificate signed by the WRONG key"
  generate_delegate_cert "${wrong_signer_key}" "${wrong_signer_crt}" "${delegate_key}" "${delegate_crt}" "${OID_PERMIT_ONBOARD_NEW_CRED}"

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
  send_manufacturer_ov_to_owner "${manufacturer_url}" "${guid}" "${owner_url}"

  log_info "Running FIDO Device Onboard with FDO 2.0 (expected to FAIL due to invalid delegate chain)"
  client_timeout=30s
  ! run_fido_device_onboard "${guid}" --debug --fdo-version 200 || log_error "SECURITY FAILURE: Onboarding should have failed with invalid delegate chain"

  log_info "Verifying the owner server rejected the invalid delegate chain"
  get_service_logs "owner" | grep -q "delegate chain validation error\|not signed by" || log_error "Owner server did not detect invalid delegate chain"
  log_success "Owner server correctly rejected the invalid delegate chain"

  log_info "Unsetting the error trap handler"
  trap - EXIT
  test_pass
}

# Allow running directly
[[ "${BASH_SOURCE[0]}" != "$0" ]] || {
  run_test
  cleanup
}

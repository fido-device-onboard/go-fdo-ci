#! /usr/bin/env bash
# Delegate permissions test: Verify that a delegate with only the
# OIDPermitRedirect permission (and NO onboard permissions) is rejected
# during TO2. Per FDO spec, a delegate MUST have one of the three
# fdo-ekt-permit-onboard-* permissions to perform TO2 onboarding.

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)/test-delegate-onboarding.sh"

run_test() {

  log_info "Setting the error trap handler"
  trap on_failure EXIT

  log_info "Environment variables"
  show_env

  check_fdo_20_support

  log_info "Creating directories"
  create_directories

  log_info "Generating service certificates"
  generate_service_certs

  log_info "Generating delegate certificate with REDIRECT-ONLY permission (no onboard)"
  generate_delegate_cert "${owner_key}" "${owner_crt}" "${delegate_key}" "${delegate_crt}" "${OID_PERMIT_REDIRECT}"

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

  log_info "Running FIDO Device Onboard with FDO 2.0 (expected to FAIL due to missing onboard permission)"
  client_timeout=30s
  ! run_fido_device_onboard "${guid}" --debug || log_error "SECURITY FAILURE: Onboarding should have failed with redirect-only delegate"

  log_info "Verifying the owner server rejected the delegate due to missing permission"
  get_service_logs "owner" | grep -q "missing required permission\|delegate.*cannot onboard\|permit-onboard\|does not have onboarding permission" || log_error "Owner server did not detect missing onboard permission"
  log_success "Owner server correctly rejected delegate without onboard permission"

  log_info "Unsetting the error trap handler"
  trap - EXIT
  test_pass
}

# Allow running directly
[[ "${BASH_SOURCE[0]}" != "$0" ]] || {
  run_test
  cleanup
}

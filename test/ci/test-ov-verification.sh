#! /bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)/test-resale.sh"

ovs_dir="${base_dir}/ovs"

# Add the new owner service for wrong owner test
services+=("${new_owner_service_name}")
directories+=("${ovs_dir}")

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

  log_info "Get valid voucher from manufacturer"
  valid_ov="${base_dir}/ov_valid.pem"
  get_ov_from_manufacturer "${manufacturer_url}" "${guid}" "${valid_ov}"

  log_info "Valid voucher should be accepted"
  send_ov_to_owner "${owner_url}" "${valid_ov}" 2>&1 || log_error "This test was supposed to succeed"
  log_success "Valid voucher accepted"

  # NOTE: We use approximate offset-based corruption (not precise field-level corruption).
  # Precise field-level corruption is tested in unit tests.
  # This approach is sufficient for E2E validation.
  #
  log_info "Create voucher with corrupted signature"
  corrupted_sig_ov="${ovs_dir}/ov_corrupted_sig.pem"
  corrupted_sig_ov_cbor="${corrupted_sig_ov/pem/cbor}"
  sed 's/^-----.*//' "${valid_ov}" | base64 -d >"${corrupted_sig_ov_cbor}"
  printf '\xFF\xFF\xFF\xFF\xFF\xFF\xFF\xFF\xFF\xFF' | dd of="${corrupted_sig_ov_cbor}" bs=1 seek=200 count=10 conv=notrunc 2>/dev/null
  tee "${corrupted_sig_ov}" <<EOF
-----BEGIN OWNERSHIP VOUCHER-----
$(base64 <"${corrupted_sig_ov_cbor}")
-----END OWNERSHIP VOUCHER-----
EOF
  ! send_ov_to_owner "${owner_url}" "${corrupted_sig_ov}" 2>&1 || log_error "This test was supposed to fail"
  log_success "Corrupted voucher rejected"

  log_info "Create voucher with invalid cert chain"
  invalid_hash_ov="${ovs_dir}/ov_invalid_hash.pem"
  invalid_hash_ov_cbor="${invalid_hash_ov/pem/cbor}"
  sed 's/^-----.*//' "${valid_ov}" | base64 -d >"${invalid_hash_ov_cbor}"
  printf '\xAA\xBB\xCC\xDD\xEE\xFF' | dd of="${invalid_hash_ov_cbor}" bs=1 seek=120 count=6 conv=notrunc 2>/dev/null
  tee "${invalid_hash_ov}" <<EOF
-----BEGIN OWNERSHIP VOUCHER-----
$(base64 <"${invalid_hash_ov_cbor}")
-----END OWNERSHIP VOUCHER-----
EOF
  ! send_ov_to_owner "${owner_url}" "${invalid_hash_ov}" 2>&1 || log_error "This test was supposed to fail"
  log_success "Voucher with invalid cert chain hash rejected"

  log_info "Voucher sent to wrong owner should be rejected"
  ! send_manufacturer_ov_to_owner "${manufacturer_url}" "${guid}" "${new_owner_url}" 2>&1 || log_error "This test was supposed to fail"
  log_success "New owner correctly rejected voucher (owner key doesn't match)"

  log_info "Unsetting the error trap handler"
  trap - EXIT
  test_pass
}

# Allow running directly
[[ "${BASH_SOURCE[0]}" != "$0" ]] || {
  run_test
  cleanup
}

#!/usr/bin/env bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)/test-resale-v2.sh"

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
  valid_ov="${ovs_dir}/ov_valid.pem"
  get_ov_from_manufacturer "${manufacturer_url}" "${guid}" "${valid_ov}"

  # Corrupt bytes at an offset within the CBOR-encoded voucher to break the
  # signature. The server should reject the voucher with a hash mismatch error.
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
  log_info "Corrupted voucher signature should be rejected"
  result=$(send_ov_to_owner "${owner_url}" "${corrupted_sig_ov}" | jq -r -M '.')
  echo "${result}"
  imported=$(echo "${result}" | jq -r -M '.imported')
  [ "${imported}" = "0" ] || log_error "Voucher should not be imported!"
  failed=$(echo "${result}" | jq -r -M '.failed')
  [ "${failed}" = "1" ] || log_error "Voucher import didn't fail!"
  echo "${result}" | jq -r -M '.messages[0]' | grep -q "voucher entry payload -1 previous hash did not match" || log_error "Corrupted signature was not detected by the server!"

  # Corrupt bytes at an early offset to damage the manufacturer public key
  # embedded in the cert chain. The server should reject with a curve error.
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
  log_info "Voucher with invalid cert chain hash should be rejected"
  result=$(send_ov_to_owner "${owner_url}" "${invalid_hash_ov}" | jq -r -M '.')
  echo "${result}"
  imported=$(echo "${result}" | jq -r -M '.imported')
  [ "${imported}" = "0" ] || log_error "Voucher should not be imported!"
  failed=$(echo "${result}" | jq -r -M '.failed')
  [ "${failed}" = "1" ] || log_error "Voucher import didn't fail!"
  echo "${result}" | jq -r -M '.messages[0]' | grep -q "error parsing manufacturer public key: P256 point not on curve" || log_error "Invalid cert chain was not detected by the server!"

  # PEM with valid base64 that decodes to invalid CBOR (0xff break codes).
  # The server should classify this as a failed voucher at the parsing stage.
  log_info "Create voucher with invalid CBOR"
  garbage_ov="${ovs_dir}/ov_invalid_cbor.pem"
  tee "${garbage_ov}" <<EOF
-----BEGIN OWNERSHIP VOUCHER-----
$(printf '\xff\xff\xff\xff' | base64)
-----END OWNERSHIP VOUCHER-----
EOF
  log_info "Voucher with invalid CBOR should fail"
  result=$(send_ov_to_owner "${owner_url}" "${garbage_ov}" | jq -r -M '.')
  echo "${result}"
  imported=$(echo "${result}" | jq -r -M '.imported')
  [ "${imported}" = "0" ] || log_error "Voucher should not be imported!"
  failed=$(echo "${result}" | jq -r -M '.failed')
  [ "${failed}" = "1" ] || log_error "Voucher import didn't fail!"
  echo "${result}" | jq -r -M '.messages[0]' | grep -q "unsupported type: decoding reserved simple value" || log_error "Invalid CBOR was not detected by the server!"

  # PEM block with content that isn't valid base64. Go's pem.Decode() silently
  # skips unparseable blocks, so the server sees zero vouchers and returns 400.
  log_info "Create voucher with invalid base64"
  invalid_b64_ov="${ovs_dir}/ov_invalid_base64.pem"
  tee "${invalid_b64_ov}" <<EOF
-----BEGIN OWNERSHIP VOUCHER-----
!!!not~valid~base64!!!
-----END OWNERSHIP VOUCHER-----
EOF
  log_info "Voucher with invalid base64 should fail"
  ! send_ov_to_owner "${owner_url}" "${invalid_b64_ov}" || log_error "Vouchers with invalid base64 content should fail with 400 response code"

  log_info "Valid voucher should be accepted"
  result=$(send_ov_to_owner "${owner_url}" "${valid_ov}" | jq -r -M '.')
  imported=$(echo "${result}" | jq -r -M '.imported')
  [ "${imported}" = "1" ] || log_error "Expected 1 voucher imported, got ${imported}"

  # Import a PEM file containing multiple vouchers: one already imported (should
  # be skipped), one new valid voucher (should be imported), and the corrupted/
  # invalid vouchers from above (should fail). Verifies the server processes each
  # voucher independently and reports per-voucher results.
  log_info "Run Device Initialization again"
  guid=$(run_device_initialization)
  log_info "Device initialized with GUID: ${guid}"

  log_info "Get the new valid voucher from manufacturer"
  new_valid_ov="${ovs_dir}/new_valid_ov.pem"
  get_ov_from_manufacturer "${manufacturer_url}" "${guid}" "${new_valid_ov}"
  log_info "Create a file with multiple vouchers in it"
  cat "${valid_ov}" "${invalid_hash_ov}" "${invalid_b64_ov}" "${corrupted_sig_ov}" "${garbage_ov}" >>"${new_valid_ov}"
  result=$(send_ov_to_owner "${owner_url}" "${new_valid_ov}" | jq -r -M '.')
  echo "${result}"
  skipped=$(echo "${result}" | jq -r -M '.skipped')
  [ "${skipped}" = "1" ] || log_error "The existing voucher was not skipped!"
  imported=$(echo "${result}" | jq -r -M '.imported')
  [ "${imported}" = "1" ] || log_error "There must be an imported voucher at least!"
  imported_guid=$(echo "${result}" | jq -r -M '.vouchers[0].voucher.guid')
  [ "${imported_guid}" = "${guid}" ] || log_error "The new voucher should be imported!"
  failed=$(echo "${result}" | jq -r -M '.failed')
  [ "${failed}" = "3" ] || log_error "Some vouchers didn't fail!"
  detected=$(echo "${result}" | jq -r -M '.detected')
  [ "${detected}" = "5" ] || log_error "Incorrect number of detected OVs!"
  echo "${result}" | jq -r -M '.messages' | grep -q "error parsing manufacturer public key: P256 point not on curve" || log_error "Invalid cert chain was not detected in multi-voucher import!"
  echo "${result}" | jq -r -M '.messages' | grep -q "voucher entry payload -1 previous hash did not match" || log_error "Corrupted signature was not detected in multi-voucher import!"
  echo "${result}" | jq -r -M '.messages' | grep -q "unsupported type: decoding reserved simple value" || log_error "Invalid CBOR was not detected in multi-voucher import!"

  log_info "Unsetting the error trap handler"
  trap - EXIT
  test_pass
}

# Allow running directly
[[ "${BASH_SOURCE[0]}" != "$0" ]] || {
  run_test
  cleanup
}

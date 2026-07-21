#! /usr/bin/env bash
# Delegate onboarding test: Verify that TO2 succeeds when the owner server is
# configured with a valid delegate certificate chain. The delegate cert is
# signed by the owner key and carries the OIDPermitOnboardNewCred permission.

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)/utils.sh"
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)/../utils/mgmt-api-v1.sh"

# FDO delegate permission OIDs
OID_PERMIT_ONBOARD_NEW_CRED="1.3.6.1.4.1.45724.3.1.2"

# Delegate and config paths
delegate_key="${certs_dir}/delegate.key"
delegate_crt="${certs_dir}/delegate.crt"
delegate_cnf="${certs_dir}/delegate.cnf"
delegate_csr="${certs_dir}/delegate.csr"
configs_dir="${base_dir}/configs"
owner_config_file="${configs_dir}/owner.yaml"

directories+=("${configs_dir}")

generate_delegate_cert() {
  local owner_key_path=$1
  local owner_crt_path=$2
  local delegate_key_path=$3
  local delegate_crt_path=$4
  local permissions_oid=$5

  local delegate_cnf_path="${delegate_key_path%.key}.cnf"
  local delegate_csr_path="${delegate_key_path%.key}.csr"

  log_info "Generating delegate EC key in DER format (same as other service keys)"
  openssl ecparam -name prime256v1 -genkey -outform der -out "${delegate_key_path}" 2>/dev/null

  log_info "Creating delegate openssl config with FDO permission OID ${permissions_oid}"
  cat >"${delegate_cnf_path}" <<EOF
[ext]
basicConstraints = critical, CA:FALSE
keyUsage = critical, digitalSignature
extendedKeyUsage = ${permissions_oid}
EOF

  log_info "Generating delegate CSR"
  openssl req -new -key "${delegate_key_path}" -keyform der -out "${delegate_csr_path}" -subj "/CN=FDO Delegate" 2>/dev/null

  log_info "Signing delegate cert with owner key"
  openssl x509 -req \
    -in "${delegate_csr_path}" \
    -CA "${owner_crt_path}" \
    -CAkey "${owner_key_path}" \
    -CAkeyform der \
    -CAcreateserial \
    -out "${delegate_crt_path}" \
    -days 30 \
    -extfile "${delegate_cnf_path}" \
    -extensions ext 2>/dev/null

  log_info "Delegate certificate generated:"
  openssl x509 -in "${delegate_crt_path}" -noout -subject -issuer -dates >&2
}

start_service_owner() {
  log_info "Writing owner config with delegate settings"
  cat >"${owner_config_file}" <<EOF
log:
  level: "debug"
db:
  type: "${owner_db_type}"
  dsn: "${owner_db_dsn}"
http:
  ip: "${owner_dns}"
  port: ${owner_port}
device_ca:
  cert: "${device_ca_crt}"
owner:
  key: "${owner_key}"
  delegate:
    name: "test-delegate"
    key: "${delegate_key}"
    cert: "${delegate_crt}"
EOF

  mkdir -p "$(dirname "${owner_log}")"
  mkdir -p "$(dirname "${owner_pid_file}")"
  nohup "${bin_dir}/go-fdo-server" owner --config="${owner_config_file}" &>"${owner_log}" &
  echo -n $! >"${owner_pid_file}"
}

run_test() {

  log_info "Setting the error trap handler"
  trap on_failure EXIT

  log_info "Environment variables"
  show_env

  log_info "Checking if client supports FDO 2.0"
  if ! "${bin_dir}/go-fdo-client" onboard --help 2>&1 | grep -q "fdo-version"; then
    log_warn "Client does not support --fdo-version flag, skipping FDO 2.0 delegate test"
    test_pass
    exit 0
  fi

  log_info "Creating directories"
  create_directories

  log_info "Generating service certificates"
  generate_service_certs

  log_info "Generating delegate certificate"
  generate_delegate_cert "${owner_key}" "${owner_crt}" "${delegate_key}" "${delegate_crt}" "${OID_PERMIT_ONBOARD_NEW_CRED}"

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

  log_info "Verifying delegation is enabled in owner logs"
  sleep 2
  find_in_log "${owner_log}" "FDO 2.0 delegation enabled" || log_error "Delegation was not enabled on the owner server"
  log_success "Delegation is enabled"

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

  log_info "Running FIDO Device Onboard with delegated owner (FDO 2.0 protocol, default)"
  run_fido_device_onboard "${guid}" --debug || log_error "Onboarding with delegate failed!"

  log_info "Verifying FDO 2.0 protocol was used (message types 80-91)"
  find_in_log "${owner_log}" "msg/80" || log_error "FDO 2.0 message type 80 (HelloDeviceProbe) not found in owner logs"
  log_success "FDO 2.0 protocol confirmed"

  log_info "Unsetting the error trap handler"
  trap - EXIT
  test_pass
}

# Allow running directly
[[ "${BASH_SOURCE[0]}" != "$0" ]] || {
  run_test
  cleanup
}

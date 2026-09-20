#! /usr/bin/env bash
# Cross-version API compatibility test: Verify that the V1 and V2 management
# APIs are interoperable. Configures the server using one API version and
# verifies the data is correctly accessible via the other API version.
# Then runs full onboarding to confirm the server works regardless of
# which API version was used for setup.

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)/utils.sh"

# We do NOT source mgmt-api-v1.sh or mgmt-api-v2.sh here because we need
# both API versions simultaneously. Instead we define prefixed wrappers that
# call the specific API endpoints directly.

# ── V1 API helpers ──────────────────────────────────────────────────────────

v1_set_rendezvous_info() {
  local manufacturer_url=$1
  local rendezvous_info_json=$2
  curl --fail --verbose --silent --insecure \
    --request POST \
    --header 'Content-Type: application/json' \
    --data-raw "${rendezvous_info_json}" \
    "${manufacturer_url}/api/v1/rvinfo"
}

v1_get_rendezvous_info() {
  local manufacturer_url=$1
  curl --fail --verbose --silent --insecure \
    --request GET \
    --header 'Content-Type: text/plain' \
    "${manufacturer_url}/api/v1/rvinfo"
}

v1_set_rvto2addr() {
  local owner_url=$1
  local ip=$2
  local dns=$3
  local port=$4
  local protocol=$5
  local rvto2addr="[{\"ip\": \"${ip}\", \"dns\": \"${dns}\", \"port\": \"${port}\", \"protocol\": \"${protocol}\"}]"
  curl --fail --verbose --silent --insecure \
    --request POST \
    --header 'Content-Type: text/plain' \
    --data-raw "${rvto2addr}" \
    "${owner_url}/api/v1/owner/redirect"
}

v1_get_rvto2addr() {
  local owner_url=$1
  curl --fail --verbose --silent --insecure \
    --header 'Content-Type: text/plain' \
    "${owner_url}/api/v1/owner/redirect"
}

v1_get_ov_from_manufacturer() {
  local manufacturer_url=$1
  local guid=$2
  local output=$3
  curl --fail --verbose --silent --insecure \
    "${manufacturer_url}/api/v1/vouchers/${guid}" -o "${output}"
}

v1_send_ov_to_owner() {
  local owner_url=$1
  local output=$2
  curl --fail --verbose --silent --insecure \
    --request POST \
    --data-binary "@${output}" \
    "${owner_url}/api/v1/owner/vouchers"
}

v1_add_device_ca_cert() {
  local url=$1
  local crt=$2
  curl --fail --verbose --silent --insecure \
    --request POST \
    --header 'Content-Type: application/x-pem-file' \
    --data-binary @"${crt}" \
    "${url}/api/v1/device-ca"
}

# ── V2 API helpers ──────────────────────────────────────────────────────────

v2_set_rendezvous_info() {
  local manufacturer_url=$1
  local rendezvous_info_json=$2
  curl --fail --verbose --silent --insecure \
    --request PUT \
    --header 'Content-Type: application/json' \
    --data-raw "${rendezvous_info_json}" \
    "${manufacturer_url}/api/v2/rvinfo"
}

v2_get_rendezvous_info() {
  local manufacturer_url=$1
  curl --fail --verbose --silent --insecure \
    --header 'Accept: application/json' \
    --request GET \
    "${manufacturer_url}/api/v2/rvinfo"
}

v2_set_rvto2addr() {
  local owner_url=$1
  local ip=$2
  local dns=$3
  local port=$4
  local protocol=$5
  local rvto2addr="[{\"ip\": \"${ip}\", \"dns\": \"${dns}\", \"port\": ${port}, \"protocol\": \"${protocol}\"}]"
  curl --fail --verbose --silent --insecure \
    --request PUT \
    --header 'Accept: application/json' \
    --header 'Content-Type: application/json' \
    --data-raw "${rvto2addr}" \
    "${owner_url}/api/v2/rvto2addr"
}

v2_get_rvto2addr() {
  local owner_url=$1
  curl --fail --verbose --silent --insecure \
    --header 'Accept: application/json' \
    "${owner_url}/api/v2/rvto2addr"
}

v2_get_ov_from_manufacturer() {
  local manufacturer_url=$1
  local guid=$2
  local output=$3
  curl --fail --verbose --silent --insecure \
    --header 'Accept: application/x-pem-file' \
    "${manufacturer_url}/api/v2/vouchers/${guid}" -o "${output}"
}

v2_send_ov_to_owner() {
  local owner_url=$1
  local output=$2
  curl --fail --verbose --silent --insecure \
    --request POST \
    --header 'Content-Type: application/x-pem-file' \
    --data-binary "@${output}" \
    "${owner_url}/api/v2/vouchers"
}

v2_add_device_ca_cert() {
  local url=$1
  local crt=$2
  curl --fail --verbose --silent --insecure \
    --header 'Content-Type: application/x-pem-file' \
    --data-binary @"${crt}" \
    "${url}/api/v2/device-ca"
}

# ── RV info in both API formats ────────────────────────────────────────────

rv_info_v1="[{\"dns\": \"${rendezvous_dns}\", \"device_port\": \"${rendezvous_port}\", \"protocol\": \"${rendezvous_protocol}\", \"ip\": \"${rendezvous_ip}\", \"owner_port\": \"${rendezvous_port}\"}]"
rv_info_v2="[[{\"dns\": \"${rendezvous_dns}\"}, {\"device_port\": ${rendezvous_port}}, {\"protocol\": \"${rendezvous_protocol}\"}, {\"ip\": \"${rendezvous_ip}\"}, {\"owner_port\": ${rendezvous_port}}]]"

# ── Test helpers ────────────────────────────────────────────────────────────

send_manufacturer_ov_to_owner_v1() {
  local manufacturer_url=$1
  local guid=$2
  local owner_url=$3
  local ov_dir="${base_dir}/ovs"
  mkdir -p "${ov_dir}"
  local ov_file="${ov_dir}/${guid}.ov"
  v1_get_ov_from_manufacturer "${manufacturer_url}" "${guid}" "${ov_file}"
  v1_send_ov_to_owner "${owner_url}" "${ov_file}"
  log_info "Waiting '${to0_wait_seconds}' seconds for TO0"
  sleep "${to0_wait_seconds}"
}

send_manufacturer_ov_to_owner_v2() {
  local manufacturer_url=$1
  local guid=$2
  local owner_url=$3
  local ov_dir="${base_dir}/ovs"
  mkdir -p "${ov_dir}"
  local ov_file="${ov_dir}/${guid}.ov"
  v2_get_ov_from_manufacturer "${manufacturer_url}" "${guid}" "${ov_file}"
  v2_send_ov_to_owner "${owner_url}" "${ov_file}"
  log_info "Waiting '${to0_wait_seconds}' seconds for TO0"
  sleep "${to0_wait_seconds}"
}

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

  # ── Phase 1: Configure with V1 API, verify with V2 API ──────────────────

  log_info "=== Phase 1: Configure via V1 API, verify via V2 API ==="

  log_info "Setting RendezvousInfo via V1 API"
  v1_set_rendezvous_info "${manufacturer_url}" "${rv_info_v1}"

  log_info "Reading back RendezvousInfo via V2 API"
  v2_rv_result=$(v2_get_rendezvous_info "${manufacturer_url}")
  log_info "V2 API returned: ${v2_rv_result}"
  [ -n "${v2_rv_result}" ] || log_error "V2 API returned empty RendezvousInfo"
  [ "${v2_rv_result}" != "null" ] || log_error "V2 API returned null RendezvousInfo"
  log_success "V1->V2 RendezvousInfo cross-read succeeded"

  log_info "Adding Device CA certificate via V1 API to rendezvous"
  v1_add_device_ca_cert "${rendezvous_url}" "${device_ca_crt}" | jq -r -M .

  log_info "Setting RVTO2Addr via V1 API"
  real_owner_ip="$(get_real_ip "${owner_service_name}")"
  v1_set_rvto2addr "${owner_url}" "${real_owner_ip}" "${owner_dns}" "${owner_port}" "${owner_protocol}"

  log_info "Reading back RVTO2Addr via V2 API"
  v2_redirect=$(v2_get_rvto2addr "${owner_url}")
  log_info "V2 API returned: ${v2_redirect}"
  [ -n "${v2_redirect}" ] || log_error "V2 API returned empty RVTO2Addr"
  [ "${v2_redirect}" != "null" ] || log_error "V2 API returned null RVTO2Addr"
  log_success "V1->V2 RVTO2Addr cross-read succeeded"

  log_info "Run Device Initialization (Phase 1)"
  guid1=$(run_device_initialization)
  log_info "Device initialized with GUID: ${guid1}"

  log_info "Sending Ownership Voucher to Owner via V1 API"
  send_manufacturer_ov_to_owner_v1 "${manufacturer_url}" "${guid1}" "${owner_url}"

  log_info "Running FIDO Device Onboard (V1 setup)"
  run_fido_device_onboard "${guid1}" --debug || log_error "Onboarding after V1 setup failed!"
  log_success "Phase 1 (V1 setup) onboarding succeeded"

  # ── Phase 2: Configure with V2 API, verify with V1 API ──────────────────

  log_info "=== Phase 2: Configure via V2 API, verify via V1 API ==="

  log_info "Setting RendezvousInfo via V2 API"
  v2_set_rendezvous_info "${manufacturer_url}" "${rv_info_v2}"

  log_info "Reading back RendezvousInfo via V1 API"
  v1_rv_result=$(v1_get_rendezvous_info "${manufacturer_url}")
  log_info "V1 API returned: ${v1_rv_result}"
  [ -n "${v1_rv_result}" ] || log_error "V1 API returned empty RendezvousInfo"
  [ "${v1_rv_result}" != "null" ] || log_error "V1 API returned null RendezvousInfo"
  log_success "V2->V1 RendezvousInfo cross-read succeeded"

  log_info "Setting RVTO2Addr via V2 API"
  v2_set_rvto2addr "${owner_url}" "${real_owner_ip}" "${owner_dns}" "${owner_port}" "${owner_protocol}"

  log_info "Reading back RVTO2Addr via V1 API"
  v1_redirect=$(v1_get_rvto2addr "${owner_url}")
  log_info "V1 API returned: ${v1_redirect}"
  [ -n "${v1_redirect}" ] || log_error "V1 API returned empty RVTO2Addr"
  [ "${v1_redirect}" != "null" ] || log_error "V1 API returned null RVTO2Addr"
  log_success "V2->V1 RVTO2Addr cross-read succeeded"

  log_info "Run Device Initialization (Phase 2)"
  guid2=$(run_device_initialization)
  log_info "Device initialized with GUID: ${guid2}"

  log_info "Sending Ownership Voucher to Owner via V2 API"
  send_manufacturer_ov_to_owner_v2 "${manufacturer_url}" "${guid2}" "${owner_url}"

  log_info "Running FIDO Device Onboard (V2 setup)"
  run_fido_device_onboard "${guid2}" --debug || log_error "Onboarding after V2 setup failed!"
  log_success "Phase 2 (V2 setup) onboarding succeeded"

  # ── Phase 3: Mixed V1/V2 setup ──────────────────────────────────────────

  log_info "=== Phase 3: Mixed API setup (V2 rvinfo, V1 voucher) ==="

  log_info "Setting RendezvousInfo via V2 API"
  v2_set_rendezvous_info "${manufacturer_url}" "${rv_info_v2}"

  log_info "Run Device Initialization (Phase 3)"
  guid3=$(run_device_initialization)
  log_info "Device initialized with GUID: ${guid3}"

  log_info "Sending Ownership Voucher to Owner via V1 API (mixed)"
  send_manufacturer_ov_to_owner_v1 "${manufacturer_url}" "${guid3}" "${owner_url}"

  log_info "Running FIDO Device Onboard (mixed V1/V2 setup)"
  run_fido_device_onboard "${guid3}" --debug || log_error "Onboarding after mixed V1/V2 setup failed!"
  log_success "Phase 3 (mixed V1/V2) onboarding succeeded"

  log_info "Unsetting the error trap handler"
  trap - EXIT
  test_pass
}

# Allow running directly
[[ "${BASH_SOURCE[0]}" != "$0" ]] || {
  run_test
  cleanup
}

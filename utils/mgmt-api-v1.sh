#!/usr/bin/env bash

set -euo pipefail

# Default RV info JSON for standard tests (can be overridden per test)
rv_info="[{\"dns\": \"${rendezvous_dns}\", \"device_port\": \"${rendezvous_port}\", \"protocol\": \"${rendezvous_protocol}\", \"ip\": \"${rendezvous_ip}\", \"owner_port\": \"${rendezvous_port}\"}]"

# Default RVTO2Addr JSON for standard tests (can be overridden per test)
rvto2addr="[{\"ip\": \"${owner_ip}\", \"dns\": \"${owner_dns}\", \"port\": \"${owner_port}\", \"protocol\": \"${owner_protocol}\"}]"

get_rendezvous_info() {
  local manufacturer_url=$1
  curl --fail --verbose --silent --insecure \
    --request GET \
    --header 'Content-Type: text/plain' \
    "${manufacturer_url}/api/v1/rvinfo"
}

set_rendezvous_info() {
  local manufacturer_url=$1
  local rendezvous_info_json=$2
  curl --fail --verbose --silent --insecure \
    --request POST \
    --header 'Content-Type: application/json' \
    --data-raw "${rendezvous_info_json}" \
    "${manufacturer_url}/api/v1/rvinfo"
}

update_rendezvous_info() {
  local manufacturer_url=$1
  local rendezvous_info_json=$2
  curl --fail --verbose --silent --insecure \
    --request PUT \
    --header 'Content-Type: application/json' \
    --data-raw "${rendezvous_info_json}" \
    "${manufacturer_url}/api/v1/rvinfo"
}

get_rvto2addr() {
  local owner_url=$1
  curl --fail --verbose --silent --insecure \
    --header 'Content-Type: text/plain' \
    "${owner_url}/api/v1/owner/redirect"
}

set_rvto2addr() {
  local owner_url=$1
  local rvto2addr_json=$2
  curl --fail --verbose --silent --insecure \
    --request POST \
    --header 'Content-Type: text/plain' \
    --data-raw "${rvto2addr_json}" \
    "${owner_url}/api/v1/owner/redirect"
}

update_rvto2addr() {
  local owner_url=$1
  local rvto2addr_json=$2
  curl --fail --verbose --silent --insecure \
    --request PUT \
    --header 'Content-Type: text/plain' \
    --data-raw "${rvto2addr_json}" \
    "${owner_url}/api/v1/owner/redirect"
}

get_ov_from_manufacturer() {
  local manufacturer_url=$1
  local guid=$2
  local output=$3
  curl --fail --verbose --silent --insecure \
    "${manufacturer_url}/api/v1/vouchers/${guid}" -o "${output}"
}

send_ov_to_owner() {
  local owner_url=$1
  local output=$2
  [ -s "${output}" ] || {
    echo "❌ Voucher file not found or empty: ${output}" >&2
    return 1
  }
  curl --fail --verbose --silent --insecure \
    --request POST \
    --data-binary "@${output}" \
    "${owner_url}/api/v1/owner/vouchers"
}

resell() {
  local owner_url=$1
  local guid=$2
  local new_owner_pubkey=$3
  local output=$4
  [ -s "${new_owner_pubkey}" ] || {
    echo "❌ Public key file not found or empty: ${new_owner_pubkey}" >&2
    return 1
  }
  curl --fail --verbose --silent --insecure "${owner_url}/api/v1/owner/resell/${guid}" --data-binary @"${new_owner_pubkey}" -o "${output}"
}

get_device_ca_certs() {
  local url=$1
  curl --fail --verbose --silent --insecure \
    --request GET \
    "${url}/api/v1/device-ca"
}

add_device_ca_cert() {
  local url=$1
  local crt=$2
  curl --fail --verbose --silent --insecure \
    --request POST \
    --header 'Content-Type: application/x-pem-file' \
    --data-binary @"${crt}" \
    "${url}/api/v1/device-ca"
}

delete_device_ca_cert() {
  local url=$1
  local fingerprint=$2
  curl --fail --verbose --silent --insecure \
    --request DELETE --header 'Content-Type: application/x-pem-file' \
    "${url}/api/v1/device-ca/${fingerprint}"
}

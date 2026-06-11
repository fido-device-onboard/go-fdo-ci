#! /usr/bin/env bash

set -euo pipefail

# Default RV info JSON for standard tests (can be overridden per test)
rv_info="[[{\"dns\": \"${rendezvous_dns}\"}, {\"device_port\": ${rendezvous_port}}, {\"protocol\": \"${rendezvous_protocol}\"}, {\"ip\": \"${rendezvous_ip}\"}, {\"owner_port\": ${rendezvous_port}}]]"

# V2 API functions (local overrides)
get_rendezvous_info() {
  local manufacturer_url=$1
  curl --fail --verbose --silent --insecure \
    --header 'Accept: application/json' \
    --request GET \
    "${manufacturer_url}/api/v2/rvinfo"
}

set_rendezvous_info() {
  local manufacturer_url=$1
  local rendezvous_info_json=$2
  curl --fail --verbose --silent --insecure \
    --request PUT \
    --header 'Content-Type: application/json' \
    --data-raw "${rendezvous_info_json}" \
    "${manufacturer_url}/api/v2/rvinfo"
}

update_rendezvous_info() {
  set_rendezvous_info "$@"
}

delete_rendezvous_info() {
  local manufacturer_url=$1
  curl --fail --verbose --silent --insecure \
    --request DELETE \
    "${manufacturer_url}/api/v2/rvinfo"
}

get_rvto2addr() {
  local owner_url=$1
  curl --fail --verbose --silent --insecure \
    --header 'Accept: application/json' \
    "${owner_url}/api/v2/rvto2addr"
}

set_rvto2addr() {
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

update_rvto2addr() {
  set_rvto2addr "$@"
}

get_ov_from_manufacturer() {
  local manufacturer_url=$1
  local guid=$2
  local output=$3
  curl --fail --verbose --silent --insecure \
    --header 'Accept: application/x-pem-file' \
    "${manufacturer_url}/api/v2/vouchers/${guid}" -o "${output}"
}

get_ov_from_manufacturer_as_json() {
  local manufacturer_url=$1
  local guid=$2
  local output=$3
  curl --fail --verbose --silent --insecure \
    --header 'Accept: application/json' \
    "${manufacturer_url}/api/v2/vouchers/${guid}" -o "${output}"
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
    --header 'Content-Type: application/x-pem-file' \
    --data-binary "@${output}" \
    "${owner_url}/api/v2/vouchers"
}

send_ov_as_json_to_owner() {
  local owner_url=$1
  local output=$2
  [ -s "${output}" ] || {
    echo "❌ Voucher file not found or empty: ${output}" >&2
    return 1
  }
  curl --fail --verbose --silent --insecure \
    --request POST \
    --header 'Content-Type: application/json' \
    --data-binary "@${output}" \
    "${owner_url}/api/v2/vouchers"
}

list_manufacturer_vouchers() {
  local manufacturer_url=$1
  curl --fail --verbose --silent --insecure \
    "${manufacturer_url}/api/v2/vouchers"
}

get_voucher_guid() {
  local guid
  guid=$(curl --fail --silent --insecure "${manufacturer_url}/api/v2/vouchers" | jq -r '.vouchers[0].guid')
  echo "${guid}"
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
  curl --fail --verbose --silent --insecure \
    --header 'Content-Type: application/x-pem-file' \
    "${owner_url}/api/v2/vouchers/${guid}/extend" \
    --data-binary @"${new_owner_pubkey}" \
    -o "${output}"
}

get_device_ca_certs() {
  local url=$1
  curl --fail --verbose --silent --insecure \
    --request GET \
    "${url}/api/v2/device-ca"
}

add_device_ca_cert() {
  local url=$1
  local crt=$2
  curl --fail --verbose --silent --insecure \
    --header 'Content-Type: application/x-pem-file' \
    --data-binary @"${crt}" \
    "${url}/api/v2/device-ca"
}

delete_device_ca_cert() {
  local url=$1
  local fingerprint=$2
  curl --fail --verbose --silent --insecure \
    --request DELETE --header 'Content-Type: application/x-pem-file' \
    "${url}/api/v2/device-ca/${fingerprint}"
}

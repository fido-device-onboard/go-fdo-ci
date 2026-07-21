#! /usr/bin/env bash

# FDO delegate permission OIDs
OID_PERMIT_REDIRECT="1.3.6.1.4.1.45724.3.1.1"
OID_PERMIT_ONBOARD_NEW_CRED="1.3.6.1.4.1.45724.3.1.2"
OID_PERMIT_ONBOARD_REUSE_CRED="1.3.6.1.4.1.45724.3.1.3"

generate_cert() {
  local key=$1
  local crt=$2
  local subj=$3
  local form=${4:-der}
  if [[ ! -f "${key}" && ! -f "${crt}" ]]; then
    [ -d "$(dirname "${key}")" ] || mkdir -p "$(dirname "${key}")"
    [ -d "$(dirname "${crt}")" ] || mkdir -p "$(dirname "${crt}")"
    openssl ecparam -name prime256v1 -genkey -outform "${form}" -out "${key}"
    openssl req -x509 -key "${key}" -keyform "${form}" -subj "${subj}" -days 365 -out "${crt}"
  fi
}

extract_pubkey_from_cert() {
  local crt=$1
  local pub=$2
  if [[ ! -f "${pub}" ]]; then
    [ -d "$(dirname "${pub}")" ] || mkdir -p "$(dirname "${pub}")"
    openssl x509 -in "${crt}" -pubkey -noout -out "${pub}"
  fi
}

# Generate a delegate certificate signed by the owner key
# Usage: generate_delegate_cert owner_key owner_crt delegate_key delegate_crt permissions_oid
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

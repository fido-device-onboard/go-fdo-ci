#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)/../ci/utils.sh"

# PLEASE READ:
#
# The FMF tests deploy the FDO servers via RPM packages. These
# packages are either provided by the Packit service or pulled from
# the fedora-iot COPR repository.
#
# All test-related configuration resides under the ${base_dir} working
# directory, which is made available as a testing artifact for
# debugging purposes. The FDO server configuration files also reside
# in ${base_dir} and are copied into the server configuration search
# path at the start of the test.
#
# If a test requires a custom configuration consider the following
# recommendations:
#
# o) Keep all test configuration in ${base_dir} in order to get it
# included in the testing artifacts.
#
# o) To create a custom configuration file copy the necessary
# `generate_${service}_config()` function(s) to your test and modify
# them to produce the desired test configuration. Your generated
# configuration file will automatically be saved in a directory that
# takes precedence over the default in the server's configuration
# search path. A copy of configuration file will be available
# as a testing artifact end of the test.
#
# o) To pass command line arguments to the server create a systemd
# "drop-in" file that overrides the ExecStart= setting in the service
# file. This drop-in file should be placed in the directory defined by
# the variable `systemd_${service}_drop_in_dir`.  Remember to run
# `sudo systemctl daemon-reload` after writing the drop-in file.

installation_source="${INSTALLATION_SOURCE:-source}"
client_installation_source="${CLIENT_INSTALLATION_SOURCE:-${installation_source}}"
server_installation_source="${SERVER_INSTALLATION_SOURCE:-${installation_source}}"

copr_repo="${COPR_REPO:-@fedora-iot/fedora-iot}"
client_copr_repo="${CLIENT_COPR_REPO:-${copr_repo}}"
server_copr_repo="${SERVER_COPR_REPO:-${copr_repo}}"

configs_dir="${base_dir}/configs"
directories+=("${configs_dir}")

rpm_certs_dir="/etc/pki/go-fdo-server" # RPMs generate the default certs/keys
rpm_server_group="go-fdo-server"       # server Group ID created by RPM install

rpm_manufacturer_user="go-fdo-server-manufacturer"
rpm_manufacturer_home_dir="/run/go-fdo-server-manufacturer"
rpm_manufacturer_config_dir="${rpm_manufacturer_home_dir}/.config/go-fdo-server"
rpm_manufacturer_config_file="${rpm_manufacturer_config_dir}/manufacturing.yaml"
rpm_manufacturer_db_type="sqlite"
rpm_manufacturer_database_dir="/var/lib/go-fdo-server-manufacturer"
rpm_manufacturer_db_dsn="file:${rpm_manufacturer_database_dir}/db.sqlite"
manufacturer_config_file="${configs_dir}/manufacturing.yaml"

rpm_rendezvous_user="go-fdo-server-rendezvous"
rpm_rendezvous_home_dir="/run/go-fdo-server-rendezvous"
rpm_rendezvous_config_dir="${rpm_rendezvous_home_dir}/.config/go-fdo-server"
rpm_rendezvous_config_file="${rpm_rendezvous_config_dir}/rendezvous.yaml"
rpm_rendezvous_db_type="sqlite"
rpm_rendezvous_database_dir="/var/lib/go-fdo-server-rendezvous"
rpm_rendezvous_db_dsn="file:${rpm_rendezvous_database_dir}/db.sqlite"
rendezvous_config_file="${configs_dir}/rendezvous.yaml"

rpm_owner_user="go-fdo-server-owner"
rpm_owner_home_dir="/run/go-fdo-server-owner"
rpm_owner_config_dir="${rpm_owner_home_dir}/.config/go-fdo-server"
rpm_owner_config_file="${rpm_owner_config_dir}/owner.yaml"
rpm_owner_db_type="sqlite"
rpm_owner_database_dir="/var/lib/go-fdo-server-owner"
rpm_owner_db_dsn="file:${rpm_owner_database_dir}/db.sqlite"
owner_config_file="${configs_dir}/owner.yaml"
owner_reuse_creds="false"
owner_to0_insecure_tls="false"

# systemd drop-in file configuration
#
systemd_drop_in_base_dir="/run/systemd/system"
#shellcheck disable=SC2034
systemd_manufacturer_drop_in_dir="${systemd_drop_in_base_dir}/go-fdo-server-manufacturer.service.d"
#shellcheck disable=SC2034
systemd_rendezvous_drop_in_dir="${systemd_drop_in_base_dir}/go-fdo-server-rendezvous.service.d"
#shellcheck disable=SC2034
systemd_owner_drop_in_dir="${systemd_drop_in_base_dir}/go-fdo-server-owner.service.d"

# Generate a default configuration file for the manufacturing server
# that references resources from the test base working directory
generate_manufacturer_config() {
  cat <<EOF
log:
  level: "debug"
db:
  type: "${rpm_manufacturer_db_type}"
  dsn: "${rpm_manufacturer_db_dsn}"
manufacturing:
  key: "${rpm_manufacturer_home_dir}/manufacturer.key"
device_ca:
  cert: "${rpm_manufacturer_home_dir}/device_ca.crt"
  key: "${rpm_manufacturer_home_dir}/device_ca.key"
owner:
  cert: "${rpm_manufacturer_home_dir}/owner.crt"
http:
  ip: "${manufacturer_dns}"
  port: "${manufacturer_port}"
EOF
  # Enable HTTP if https protocol is used
  if [ "${manufacturer_protocol}" = "https" ]; then
    cat <<EOF
  cert: "${rpm_manufacturer_home_dir}/manufacturer-http.crt"
  key: "${rpm_manufacturer_home_dir}/manufacturer-http.key"
EOF
  fi
}

# Setup manufacturer home directory, create the configuration and copy
# all necessary certs/keys
configure_service_manufacturer() {
  sudo rm -rf "${rpm_manufacturer_home_dir:?}"
  sudo mkdir -p "${rpm_manufacturer_config_dir}" # creates home dir
  generate_manufacturer_config >"${manufacturer_config_file}"
  sudo cp "${manufacturer_config_file}" "${rpm_manufacturer_config_file}"
  sudo cp "${manufacturer_key}" "${rpm_manufacturer_home_dir}"
  sudo cp "${owner_crt}" "${rpm_manufacturer_home_dir}"
  sudo cp "${device_ca_key}" "${rpm_manufacturer_home_dir}"
  sudo cp "${device_ca_crt}" "${rpm_manufacturer_home_dir}"
  if [ "${manufacturer_protocol}" = "https" ]; then
    sudo cp "${manufacturer_https_key}" "${manufacturer_https_crt}" "${rpm_manufacturer_home_dir}"
  fi
  sudo chown -R ${rpm_manufacturer_user}:${rpm_server_group} ${rpm_manufacturer_home_dir}
}

generate_rendezvous_config() {
  cat <<EOF
log:
  level: "debug"
db:
  type: "${rpm_rendezvous_db_type}"
  dsn: "${rpm_rendezvous_db_dsn}"
http:
  ip: "${rendezvous_dns}"
  port: "${rendezvous_port}"
EOF
  # Enable HTTP if https protocol is used
  if [ "${rendezvous_protocol}" = "https" ]; then
    cat <<EOF
  cert: "${rpm_rendezvous_home_dir}/rendezvous-http.crt"
  key: "${rpm_rendezvous_home_dir}/rendezvous-http.key"
EOF
  fi
}

# Setup rendezvous home directory, create the configuration and copy
# all necessary certs/keys
configure_service_rendezvous() {
  sudo rm -rf "${rpm_rendezvous_home_dir:?}"
  sudo mkdir -p "${rpm_rendezvous_config_dir}" # creates home dir
  generate_rendezvous_config >"${rendezvous_config_file}"
  sudo cp "${rendezvous_config_file}" "${rpm_rendezvous_config_file}"
  if [ "${rendezvous_protocol}" = "https" ]; then
    sudo cp "${rendezvous_https_key}" "${rendezvous_https_crt}" "${rpm_rendezvous_home_dir}"
  fi
  sudo chown -R ${rpm_rendezvous_user}:${rpm_server_group} ${rpm_rendezvous_home_dir}
}

generate_owner_config() {
  cat <<EOF
log:
  level: "debug"
db:
  type: "${rpm_owner_db_type}"
  dsn: "${rpm_owner_db_dsn}"
device_ca:
  cert: "${rpm_owner_home_dir}/device_ca.crt"
owner:
  cert: "${rpm_owner_home_dir}/owner.crt"
  key: "${rpm_owner_home_dir}/owner.key"
  reuse_credentials: "${owner_reuse_creds}"
  to0_insecure_tls: "${owner_to0_insecure_tls}"
http:
  ip: "${owner_dns}"
  port: "${owner_port}"
EOF
  # Enable HTTP if https protocol is used
  if [ "${owner_protocol}" = "https" ]; then
    cat <<EOF
  cert: "${rpm_owner_home_dir}/owner-http.crt"
  key: "${rpm_owner_home_dir}/owner-http.key"
EOF
  fi
}

# Setup owner home directory, create the configuration and copy
# all necessary certs/keys
configure_service_owner() {
  sudo rm -rf "${rpm_owner_home_dir:?}"
  sudo mkdir -p "${rpm_owner_config_dir}" # creates home dir
  generate_owner_config >"${owner_config_file}"
  sudo cp "${owner_config_file}" "${rpm_owner_config_file}"
  sudo cp "${device_ca_crt}" "${rpm_owner_home_dir}"
  sudo cp "${owner_crt}" "${owner_key}" "${rpm_owner_home_dir}"
  if [ "${owner_protocol}" = "https" ]; then
    sudo cp "${owner_https_key}" "${owner_https_crt}" "${rpm_owner_home_dir}"
  fi
  sudo chown -R ${rpm_owner_user}:${rpm_server_group} ${rpm_owner_home_dir}
}

go_fdo_server_rpms="go-fdo-server go-fdo-server-manufacturer go-fdo-server-owner go-fdo-server-rendezvous"
go_fdo_client_rpms="go-fdo-client"

install_rpms_from_source() {
  local rpms="$*"
  case "${rpms}" in
  *go-fdo-client*)
    fetch_client_repo
    pushd "${client_src_dir}" >/dev/null
    commit="$(git rev-parse --short HEAD)"
    rpm -q go-fdo-client 2>/dev/null | grep -q "go-fdo-client.*git${commit}.*$(rpm -q --eval "%dist")" || {
      make rpm
      sudo dnf install -y rpmbuild/rpms/"$(uname -m)"/*git"${commit}".$(uname -m).rpm
    }
    popd >/dev/null
    ;;
  *go-fdo-server*)
    fetch_server_repo
    pushd "${server_src_dir}" >/dev/null
    commit="$(git rev-parse --short HEAD)"
    rpm -q go-fdo-server 2>/dev/null | grep -q "go-fdo-server.*git${commit}.*$(rpm -q --eval "%dist")" || {
      make rpm
      sudo dnf install -y rpmbuild/rpms/"$(uname -m)"/go-fdo-server-[1-9.]*.git"${commit}"*$(rpm -q --eval "%dist").$(uname -m).rpm \
        rpmbuild/rpms/noarch/go-fdo-server-{manufacturer,owner,rendezvous}-[1-9.]*.git"${commit}"*$(rpm -q --eval "%dist").noarch.rpm
    }
    popd >/dev/null
    ;;
  *)
    log_error "Unsupported rpms to install from source: '${rpms}'"
    ;;
  esac
}

rpm_repo_from_copr_project_spec() {
  local copr_project_spec="${1}"
  local slashes="${copr_project_spec//[^\/]/}"
  local slash_count="${#slashes}"
  local hub
  local owner_project
  local owner
  local project
  case ${slash_count} in
  1)
    hub="copr.fedorainfracloud.org"
    owner="${copr_project_spec/\/*/}"
    project="${copr_project_spec/*\//}"
    ;;
  2)
    hub="${copr_project_spec/\/*/}"
    owner_project="${copr_project_spec#*/}"
    owner="${owner_project/\/*/}"
    project="${owner_project/*\//}"
    ;;
  *)
    log_error "Invalid copr project specification"
    ;;
  esac
  echo "copr:${hub}:${owner/@/group_}:${project}"
}

# Print the copr chroot (NAME-RELEASE-ARCH) to enable on the system
# described by the given os-release file (/etc/os-release by default),
# or nothing to let the dnf copr plugin detect it. COPR_CHROOT takes
# precedence over both.
#
# The plugin builds the chroot name out of ID/VERSION_ID from
# /etc/os-release, so on CentOS Stream it looks for 'centos-${VERSION_ID}'
# (falling back to 'epel-${VERSION_ID}') and never matches the
# 'centos-stream-*' chroots the projects are actually built for. Name
# those explicitly and let the plugin guess everywhere else.
#
# The os-release file is a parameter so that the mapping can be tested
# for distributions other than the running one.
copr_chroot_for_system() {
  local os_release="${1:-/etc/os-release}"
  [ -z "${COPR_CHROOT:-}" ] || {
    echo "${COPR_CHROOT}"
    return 0
  }
  source "${os_release}"
  case "${ID}" in
  centos)
    echo "centos-stream-${VERSION_ID}-$(uname -m)"
    ;;
  esac
}

enable_copr_repo() {
  local copr="${1}"
  local chroot
  chroot="$(copr_chroot_for_system)"
  dnf_copr_command="dnf-command(copr)"
  rpm -q --whatprovides "${dnf_copr_command}" &>/dev/null || sudo dnf install -y "${dnf_copr_command}"
  dnf copr list | grep -q "${copr}" || sudo dnf copr enable -y "${copr}" ${chroot:+"${chroot}"}
}

disable_copr_repo() {
  local copr="${1}"
  sudo dnf copr disable -y "${copr}"
  sudo dnf copr remove -y "${copr}"
}

install_rpms_from_copr() {
  local copr="${1}"
  shift
  local rpms="$*"
  local repo
  repo="$(rpm_repo_from_copr_project_spec "${copr}")"
  enable_copr_repo "${copr}"
  # testing-farm-tag-repository is causing problems with builds see:
  # https://docs.testing-farm.io/Testing%20Farm/0.1/test-environment.html#disabling-tag-repository
  sudo dnf install --disablerepo=* --enablerepo="${repo}" -y ${rpms}
  disable_copr_repo "${copr}"
}

install_rpms_from_compose() {
  local rpms="$*"
  source /etc/os-release
  case "${ID}-${VERSION_ID}" in
  fedora-*)
    compose_host="http://kojipkgs.fedoraproject.org"
    compose_id="latest-Fedora-${VERSION_ID}"
    compose_streams="${COMPOSE_STREAMS:-Everything}"
    compose_dir="${VERSION_ID}"
    [ "${RELEASE_TYPE}" != "development" ] || compose_dir="branched"
    [ "${REDHAT_SUPPORT_PRODUCT_VERSION}" != "rawhide" ] || {
      compose_dir="rawhide"
      compose_id="latest-Fedora-Rawhide"
    }
    compose_base_url="${COMPOSE_BASE_URL:-${compose_host}/compose/${compose_dir}/${compose_id}/compose}"
    ;;
  centos-*)
    compose_host="https://composes.stream.centos.org"
    compose_id="latest-CentOS-Stream"
    compose_streams="${COMPOSE_STREAMS:-BaseOS AppStream}"
    compose_base_url="${COMPOSE_BASE_URL:-${compose_host}/stream-${VERSION_ID}/production/${compose_id}/compose}"
    ;;
  rhel-*)
    compose_base_url="${COMPOSE_BASE_URL:-}"
    ! [ -z "${compose_base_url}" ] || log_error "Compose base URL must be set for RHEL (eg='http://download.host/.../latest-RHEL-Compose/compose/')"
    compose_streams="${COMPOSE_STREAMS:-BaseOS AppStream}"
    ;;
  *)
    log_error "OS not supported"
    ;;
  esac
  repo_base_name="go-fdo-ci-compose-${ID}-${VERSION_ID}"
  repo_dir="/etc/yum.repos.d"
  for stream in ${compose_streams}; do
    repo_name="${repo_base_name}-${stream}"
    repo_file="${repo_dir}/${repo_name}.repo"
    sudo tee "${repo_file}" <<EOF
[${repo_name}]
name=${repo_name}
baseurl=${compose_base_url}/${stream}/$(uname -m)/os/
enabled=1
gpgcheck=0
EOF
    if [ "${ID}" = "fedora" ] && [ ! -v "COMPOSE_BASE_URL" ] && [ ! -v "COMPOSE_STREAMS" ]; then
      sudo tee -a "${repo_file}" <<EOF
[${repo_name}-updates]
name=${repo_name}-updates
baseurl=${compose_host}/compose/updates/f${VERSION_ID}-updates/compose/${stream}/$(uname -m)/os/
enabled=1
gpgcheck=0
EOF
    fi
  done
  sudo dnf install --disablerepo=* --enablerepo="${repo_base_name}*" -y ${rpms}
  sudo rm -f "${repo_dir?}/${repo_base_name:?}"*.repo
}

# List the RPM package URLs published under a brew build base URL.
# The URL must point to the version/release directory of the package in
# brew, which contains an '${arch}/' and a 'noarch/' sub-directory listing
# the built RPMs. Prints one full RPM URL per line, e.g.:
#   SOME_RPM_URL=https://${BREW_HOST}/${BREW_PACKAGES_DIR}/${BREW_PACKAGE_NAME}/${BREW_PACKAGE_VERSION}/${BREW_PACKAGE_RELEASE}
#   rpms_from_brew_url "${SOME_RPM_URL}"
rpms_from_brew_url() {
  local brew_base_url="${1%/}" # strip any trailing slash to avoid double slashes below
  local arch
  arch=$(uname -m | sed 's/arm64/aarch64/')
  # --insecure is intentional: internal brew servers use self-signed
  # certificates, same as the --setopt=sslverify=false used when installing
  # the RPMs these URLs point to.
  curl --fail --silent --insecure "${brew_base_url}/${arch}/" | grep rpm | sed "s|.*>\(.*\)\.rpm</.*|${brew_base_url}/${arch}/\1.rpm|"
  curl --fail --silent --insecure "${brew_base_url}/noarch/" | grep rpm | sed "s|.*>\(.*\)\.rpm</.*|${brew_base_url}/noarch/\1.rpm|"
}

install_rpms_from_brew() {
  local brew_url="$1"
  # Please note that --nogpgcheck and sslverify=false are intentional:
  # internal brew servers use self-signed certificates and builds may not be GPG-signed.
  sudo dnf install -y --nogpgcheck --setopt=sslverify=false $(rpms_from_brew_url "${brew_url}")
}

install_rpms_from() {
  local install_source="${1}"
  [ -n "$install_source" ] || log_error "Installation source must be provided as first argument"
  shift
  local rpms="${*}"
  case "${install_source}" in
  "distro")
    sudo dnf install -y ${rpms}
    ;;
  "copr")
    install_rpms_from_copr "${copr_repo}" "${rpms}"
    ;;
  "compose")
    install_rpms_from_compose "${rpms}"
    ;;
  "source")
    install_rpms_from_source "${rpms}"
    ;;
  *)
    log_error "Unsupported installation source: '${install_source}'"
    ;;
  esac
}

install_client() {
  if [ -n "${BREW_CLIENT_RPMS_URL:-}" ]; then
    # Install from a specific brew build base path.
    # BREW_CLIENT_RPMS_URL should point to the version/release directory of the package in brew.
    # e.g.: https://${BREW_HOST}/${BREW_PACKAGES_DIR}/go-fdo-client/1.0.0/4.el10_2.5
    install_rpms_from_brew "${BREW_CLIENT_RPMS_URL}"
  elif [ -v "PACKIT_COPR_RPMS" ] && [ -v "PACKIT_COPR_PROJECT" ]; then
    # If PACKIT_COPR_RPMS is defined it means that all the rpms were built and installed already by packit
    if [[ "${PACKIT_COPR_RPMS}" =~ go-fdo-client ]]; then
      # If PACKIT_COPR_RPMS is defined and contains the 'go-fdo-client'
      # package it means we are running the TMT tests in the client repo
      log_info "Expected Go FDO Client RPM:"
      for i in ${PACKIT_COPR_RPMS}; do
        log "  ⚙ $i\n" 2>&1
      done | sort
      install_rpms_from_copr "${PACKIT_COPR_PROJECT}" "${PACKIT_COPR_RPMS}"
    else
      # If we are running TMT tests but in server's repo we install
      # the client from the fedora-iot copr
      install_rpms_from_copr "${client_copr_repo}" "${go_fdo_client_rpms}"
    fi
  else
    # If PACKIT_COPR_RPMS is not defined it means we are running the test
    # locally or as a github action
    if [ "${client_installation_source}" = "copr" ]; then
      install_rpms_from_copr "${client_copr_repo}" "${go_fdo_client_rpms}"
    else
      install_rpms_from "${client_installation_source}" "${go_fdo_client_rpms}"
    fi
  fi
  log_info "Installed Go FDO Client RPM:"
  log "  ⚙ $(rpm -q ${go_fdo_client_rpms})\n"
}

uninstall_client() {
  # When running a test locally we remove the client package
  # after a successful execution.
  [ -v "PACKIT_COPR_RPMS" ] || sudo dnf remove -y ${go_fdo_client_rpms}
}

run_go_fdo_client() {
  # If the command times out, the return code is 124 (see: man timeout)
  # If the command finishes before the timeout, the return code comes from 'go-fdo-client'
  local exit_code=0
  timeout "${client_timeout}" "/usr/bin/go-fdo-client" "$@" || exit_code=$?
  if [[ ${exit_code} -ne 0 ]]; then
    log_warn "'go-fdo-client' exited with '${exit_code}' (124 -> timeout):\n  - go-fdo-client $*"
  fi
  return ${exit_code}
}

install_server() {
  # Install runtime dependencies
  rpm -q openssl &>/dev/null || sudo dnf install -y openssl
  if [ -n "${BREW_SERVER_RPMS_URL:-}" ]; then
    # Install from a specific brew build base path.
    # BREW_SERVER_RPMS_URL should point to the version/release directory of the package in brew.
    # e.g.: https://${BREW_HOST}/${BREW_PACKAGES_DIR}/go-fdo-server/1.0.1/2.el10_2.3
    install_rpms_from_brew "${BREW_SERVER_RPMS_URL}"
  elif [ -v "PACKIT_COPR_RPMS" ] && [ -v "PACKIT_COPR_PROJECT" ]; then
    # If PACKIT_COPR_RPMS is defined it means that all the rpms were built and installed already by packit
    if [[ "${PACKIT_COPR_RPMS}" =~ go-fdo-server ]]; then
      # If PACKIT_COPR_RPMS is defined and contains the 'go-fdo-server'
      # package it means we are running the TMT tests in the server repo
      log_info "Expected Go FDO Server RPMs:"
      for i in ${PACKIT_COPR_RPMS}; do
        log "  ⚙ $i\n" 2>&1
      done | sort
      install_rpms_from_copr "${PACKIT_COPR_PROJECT}" "${PACKIT_COPR_RPMS}"
    else
      # If we are running TMT tests but in client's repo we install
      # the server from the fedora-iot copr
      install_rpms_from_copr "${server_copr_repo}" "${go_fdo_server_rpms}"
    fi
  else
    # If PACKIT_COPR_RPMS is not defined it means we are running the test
    # locally
    if [ "${server_installation_source}" = "copr" ]; then
      install_rpms_from_copr "${server_copr_repo}" "${go_fdo_server_rpms}"
    else
      install_rpms_from "${server_installation_source}" "${go_fdo_server_rpms}"
    fi
  fi
  # Make sure the RPMS are installed
  installed_rpms=$(rpm -q --qf "%{nvr}.%{arch} " ${go_fdo_server_rpms})
  log_info "Installed Go FDO Server RPMs:"
  for i in ${installed_rpms}; do
    log "  ⚙ $i\n" 2>&1
  done | sort
}

uninstall_server() {
  [ -v "PACKIT_COPR_RPMS" ] || sudo dnf remove -y ${go_fdo_server_rpms}
}

start_service_manufacturer() {
  sudo systemctl start go-fdo-server-manufacturer
}

start_service_rendezvous() {
  sudo systemctl start go-fdo-server-rendezvous
}

start_service_owner() {
  sudo systemctl start go-fdo-server-owner
}

# We do not use pid files but functions to stop the services via systemctl
stop_service() {
  local service=$1
  local stop_service="stop_service_${service}"
  ! declare -F "${stop_service}" >/dev/null || ${stop_service}
}

stop_service_manufacturer() {
  sudo systemctl stop go-fdo-server-manufacturer
}

stop_service_rendezvous() {
  sudo systemctl stop go-fdo-server-rendezvous
}

stop_service_owner() {
  sudo systemctl stop go-fdo-server-owner
}

get_go_fdo_server_logs() {
  local role=$1
  journalctl_args=("--no-pager" "--output=cat" "--unit" "go-fdo-server-${role}")
  . /etc/os-release
  [[ "${ID}" = "centos" && "${VERSION_ID}" = "9" ]] || journalctl_args+=("--invocation=0")
  systemctl status "go-fdo-server-${role}.service" || true
  journalctl "${journalctl_args[@]}"
}

get_service_logs_manufacturer() {
  get_go_fdo_server_logs manufacturer
}

get_service_logs_rendezvous() {
  get_go_fdo_server_logs rendezvous
}

get_service_logs_owner() {
  get_go_fdo_server_logs owner
}

get_service_logs() {
  local service=$1
  log "🛑 '${service}' logs:\n"
  local get_service_logs_func="get_service_logs_${service}"
  ! declare -F "${get_service_logs_func}" >/dev/null || ${get_service_logs_func}
}

save_go_fdo_server_logs() {
  local role=$1
  local log_file=$2
  get_go_fdo_server_logs "${role}" >"${log_file}"
}

save_service_logs_manufacturer() {
  save_go_fdo_server_logs manufacturer "${manufacturer_log}"
}

save_service_logs_rendezvous() {
  save_go_fdo_server_logs rendezvous "${rendezvous_log}"
}

save_service_logs_owner() {
  save_go_fdo_server_logs owner "${owner_log}"
}

save_service_logs() {
  local service=$1
  log "\t⚙ Saving '${service}' logs "
  local save_service_logs_func="save_service_logs_${service}"
  ! declare -F "${save_service_logs_func}" >/dev/null || ${save_service_logs_func}
  log_success
}

save_logs() {
  log_info "Saving logs"
  for service in "${services[@]}"; do
    save_service_logs ${service}
  done
  if [ -v "PACKIT_COPR_RPMS" ]; then
    log_info "Submitting files to TMT '${base_dir:?}'"
    find "${base_dir:?}" -type f -exec tmt-file-submit -l {} \;
  fi
}

cleanup_home_dirs() {
  for server in rendezvous manufacturer owner; do
    local homedir_var="rpm_${server}_home_dir"
    sudo rm -vrf "${!homedir_var:?}"
  done
}

cleanup_databases() {
  for server in rendezvous manufacturer owner; do
    local dbdir_var="rpm_${server}_database_dir"
    if [[ -v "${dbdir_var}" ]]; then
      sudo rm -vf "${!dbdir_var:?}"/*
    fi
  done
}

cleanup_drop_ins() {
  local reload_systemd=0
  for service in rendezvous manufacturer owner; do
    local drop_in_dir_var="systemd_${service}_drop_in_dir"
    if [[ -d "${!drop_in_dir_var}" ]]; then
      reload_systemd=1
      sudo rm -vf "${!drop_in_dir_var:?}"/*
    fi
  done
  if [[ ${reload_systemd} -eq 1 ]]; then
    sudo systemctl daemon-reload
  fi
}

remove_files() {
  log_info "Removing files from '${base_dir:?}'"
  sudo rm -vrf "${base_dir:?}"/*
  log_info "Removing files from '${rpm_certs_dir}'"
  sudo rm -vf "${rpm_certs_dir:?}"/*
  log_info "Removing systemd drop-in files"
  cleanup_drop_ins
  log_info "Removing database files"
  cleanup_databases
  log_info "Removing server home directories"
  cleanup_home_dirs
}

# ---------------------------------------------------------------------------
# SELinux AVC collection
# ---------------------------------------------------------------------------

selinux_reports_dir="${base_dir}/selinux"
selinux_avc_raw="${selinux_reports_dir}/go_fdo_server_avc_raw.txt"
selinux_avc_report="${selinux_reports_dir}/go_fdo_server_avc_report.txt"
selinux_audit2allow_te="${selinux_reports_dir}/go_fdo_server_avc.te"
directories+=("${selinux_reports_dir}")

# Timestamp set just before services start; used to scope ausearch to this run
_avc_start_timestamp=""

# Set to 1 once collect_avcs has run; prevents a second collection in cleanup
# overwriting data gathered by on_failure while services were still running
_avcs_collected=0

# Record the start of the AVC collection window
mark_avc_start() {
  _avc_start_timestamp="$(LC_ALL=C date '+%m/%d/%Y %H:%M:%S')"
  log_info "AVC collection window starts at: ${_avc_start_timestamp}"
}

# Warn if go_fdo_server_t is not in permissive mode (non-fatal)
check_go_fdo_server_permissive() {
  if ! command -v semanage &>/dev/null; then
    log_warn "semanage not found; cannot verify go_fdo_server_t permissive status"
    return 0
  fi
  if semanage permissive -l 2>/dev/null | grep -q 'go_fdo_server_t'; then
    log_info "go_fdo_server_t is in permissive mode"
    return 0
  fi
  if [ "$(getenforce 2>/dev/null)" = "Permissive" ]; then
    log_info "SELinux is globally permissive"
    return 0
  fi
  log_warn "go_fdo_server_t is NOT in permissive mode; AVC denials may block services"
}

# Ensure auditd is running so that AVC records reach the audit log
ensure_auditd_running() {
  if systemctl is-active --quiet auditd 2>/dev/null; then
    log_info "auditd is running"
    return 0
  fi
  log_warn "auditd is not running; attempting to start it"
  sudo systemctl start auditd || log_warn "Could not start auditd; AVC collection may be incomplete"
}

# Collect all AVC records for go-fdo-server since _avc_start_timestamp
collect_avcs() {
  if [ "${_avcs_collected}" -eq 1 ]; then
    log_info "AVC denials already collected; skipping"
    return 0
  fi
  _avcs_collected=1

  if [ -z "${_avc_start_timestamp}" ]; then
    log_warn "AVC start timestamp not set; skipping collection to avoid unrelated host denials"
    return 0
  fi

  log_info "Collecting AVC denials for go-fdo-server"
  mkdir -p "${selinux_reports_dir}"

  if ! command -v ausearch &>/dev/null; then
    log_warn "ausearch not found; skipping AVC collection"
    echo "ausearch not available" >"${selinux_avc_raw}"
    return 0
  fi

  local ausearch_args=("-m" "avc" "--comm" "go-fdo-server")
  ausearch_args+=("-ts" "${_avc_start_timestamp}")

  local rc=0
  sudo LC_ALL=C ausearch "${ausearch_args[@]}" >"${selinux_avc_raw}" 2>/dev/null || rc=$?
  if [ "${rc}" -ne 0 ]; then
    if [ "${rc}" -eq 1 ]; then
      echo "No AVC denials found for go-fdo-server" >"${selinux_avc_raw}"
      log_info "No AVC denials found (policy may already be complete)"
      return 0
    fi
    log_warn "ausearch exited with code ${rc}"
  fi

  local avc_count
  avc_count=$(grep -c 'type=AVC' "${selinux_avc_raw}" 2>/dev/null || echo 0)
  log_info "Found ${avc_count} AVC denial(s)"
}

# Generate a draft TE policy snippet from the collected AVC records
generate_audit2allow_report() {
  log_info "Generating audit2allow report"

  if ! command -v audit2allow &>/dev/null; then
    log_warn "audit2allow not found; skipping TE generation"
    return 0
  fi

  if ! grep -q 'type=AVC' "${selinux_avc_raw}" 2>/dev/null; then
    log_info "No AVC denials to process with audit2allow"
    echo "No AVC denials to report" >"${selinux_audit2allow_te}"
    return 0
  fi

  {
    echo "# Draft SELinux rules generated from go-fdo-server AVC denials"
    echo "# Test run: $(date -u --iso-8601=seconds)"
    echo "# Policy domain: go_fdo_server_t"
    echo "#"
    echo "# These rules were produced by audit2allow and must be reviewed"
    echo "# before being added to the upstream selinux-policy package."
    echo ""
  } >"${selinux_audit2allow_te}"

  audit2allow -i "${selinux_avc_raw}" >>"${selinux_audit2allow_te}" 2>/dev/null ||
    log_warn "audit2allow exited with a non-zero status"
}

# Print a human-readable AVC summary to stdout and save it as an artifact
# Artifact paths are only reported when actual denials were found
report_avcs() {
  local has_denials=0
  if grep -q 'type=AVC' "${selinux_avc_raw}" 2>/dev/null; then
    has_denials=1
  fi

  {
    echo "================================================================"
    echo " go-fdo-server SELinux AVC Denial Report"
    echo " Generated: $(date -u --iso-8601=seconds)"
    echo "================================================================"
    echo ""
    if [ "${has_denials}" -eq 0 ]; then
      if [ ! -s "${selinux_avc_raw}" ]; then
        echo "No AVC data collected."
      else
        echo "No AVC denials were recorded during this test run."
      fi
    else
      echo "--- Raw AVC denial records (from ausearch) ---"
      echo ""
      cat "${selinux_avc_raw}"
      echo ""
      echo "--- audit2allow suggested rules ---"
      echo ""
      cat "${selinux_audit2allow_te}" 2>/dev/null || echo "(audit2allow output not available)"
    fi
    echo ""
    echo "================================================================"
  } | tee "${selinux_avc_report}"

  if [ "${has_denials}" -eq 1 ]; then
    log_info "AVC report saved to: ${selinux_avc_report}"
    log_info "Draft TE file saved to: ${selinux_audit2allow_te}"
  fi
}

# Check SELinux status, ensure auditd is running, and record the AVC collection start timestamp
prepare_selinux_collection() {
  log_info "Checking SELinux status"
  check_go_fdo_server_permissive
  ensure_auditd_running
  mark_avc_start
}

# Override start_services (from ci/utils.sh) to check SELinux status
# and record the AVC start timestamp before any service is launched
start_services() {
  prepare_selinux_collection

  log_info "Adding hostnames to '/etc/hosts'"
  set_hostnames
  log_info "Starting services"
  for service in "${services[@]}"; do
    log "  ⚙ Starting service ${service}"
    start_service "${service}"
    log_success
  done
}

on_failure() {
  trap - EXIT
  # Collect AVC denials before save_logs, which submits all files under base_dir
  collect_avcs
  generate_audit2allow_report
  report_avcs
  save_logs
  stop_services
  test_fail
}

cleanup() {
  trap - EXIT
  # Collect AVC denials before save_logs, which submits all files under base_dir
  collect_avcs
  generate_audit2allow_report
  report_avcs
  [ ! -v "PACKIT_COPR_RPMS" ] || save_logs
  stop_services
  unset_hostnames
  uninstall_server
  uninstall_client
  remove_files
}

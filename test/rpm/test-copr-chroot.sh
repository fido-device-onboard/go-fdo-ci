#! /usr/bin/env bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)/utils.sh"

# Regression test for the Copr chroot used when enabling a Copr
# repository.
#
# The dnf copr plugin derives the chroot from ID/VERSION_ID in
# /etc/os-release, which gives 'centos-${VERSION_ID}' with an
# 'epel-${VERSION_ID}' fallback on CentOS Stream and therefore never
# matches the 'centos-stream-*' chroots the packages are built for.
# Projects without EPEL chroots, like every Packit pull request build,
# fail to enable at all, while @fedora-iot/fedora-iot silently serves
# the EPEL build instead of the CentOS Stream one. Both regressions are
# invisible to 'test-installation.sh', which only checks that some
# package got installed, so they are covered here instead.

copr_chroot_dir="${base_dir}/copr-chroot"

on_failure() {
  log_error "Test failed!"
}

# Write an os-release file for the given ID and VERSION_ID and print
# its path
write_os_release() {
  local id="${1}"
  local version_id="${2}"
  local os_release="${copr_chroot_dir}/os-release-${id}-${version_id}"
  cat >"${os_release}" <<EOF
ID=${id}
VERSION_ID=${version_id}
EOF
  echo "${os_release}"
}

# Check that a chroot is in the NAME-RELEASE-ARCH format expected by
# dnf: dnf5 takes the architecture from the last dash separated field
# and dnf4 rejects anything with less than three fields, so a chroot
# without the architecture, like 'centos-stream-10', is not usable.
verify_chroot_format() {
  local chroot="${1}"
  local fields
  IFS="-" read -ra fields <<<"${chroot}"
  [ "${#fields[@]}" -ge 3 ] ||
    log_error "Chroot '${chroot}' is not in the NAME-RELEASE-ARCH format"
  [ "${fields[-1]}" = "$(uname -m)" ] ||
    log_error "Chroot '${chroot}' does not end with the system architecture '$(uname -m)'"
}

# Check the chroot selected for the given distribution. An empty
# expectation means that the chroot is left to the dnf autodetection.
# COPR_CHROOT is cleared so that the mapping is checked even when the
# caller exported an override.
verify_chroot_for_system() {
  local id="${1}"
  local version_id="${2}"
  local expected="${3}"
  local os_release
  local chroot
  os_release="$(write_os_release "${id}" "${version_id}")"
  chroot="$(COPR_CHROOT="" copr_chroot_for_system "${os_release}")"
  [ "${chroot}" = "${expected}" ] ||
    log_error "Wrong chroot for '${id}-${version_id}': expected '${expected}', got '${chroot}'"
  [ -z "${chroot}" ] || verify_chroot_format "${chroot}"
  log_success "${id}-${version_id} selects the chroot '${chroot}'"
}

# Check that COPR_CHROOT wins over the built-in mapping
verify_chroot_override() {
  local expected="rhel-10-$(uname -m)"
  local os_release
  local chroot
  os_release="$(write_os_release centos 10)"
  chroot="$(COPR_CHROOT="${expected}" copr_chroot_for_system "${os_release}")"
  [ "${chroot}" = "${expected}" ] ||
    log_error "COPR_CHROOT was not honored: expected '${expected}', got '${chroot}'"
  log_success "COPR_CHROOT overrides the selected chroot"
}

# Print the baseurl configured for the given repository id. The
# repository id is looked up in the repository files instead of their
# file name, which differs between dnf4 and dnf5.
repo_baseurl() {
  local repo="${1}"
  awk -v section="[${repo}]" '
    $0 == section { in_section = 1; next }
    /^\[/ { in_section = 0 }
    in_section && /^baseurl=/ { sub(/^baseurl=/, ""); print; exit }
  ' /etc/yum.repos.d/*.repo
}

# Enable the Copr repository on the running system and check that it
# serves the chroot built for this distribution. This is the check that
# fails if the explicit chroot is ever dropped again: on CentOS Stream
# the autodetection either errors out with "Chroot not found in the
# given Copr project" or quietly configures the 'epel-${VERSION_ID}'
# chroot here.
verify_enabled_copr_repo() {
  local copr="${1}"
  local repo
  local chroot
  local chroot_name
  local baseurl
  repo="$(rpm_repo_from_copr_project_spec "${copr}")"
  chroot="$(copr_chroot_for_system)"
  enable_copr_repo "${copr}"
  baseurl="$(repo_baseurl "${repo}")"
  disable_copr_repo "${copr}"
  [ -n "${baseurl}" ] || log_error "No baseurl configured for the repository '${repo}'"
  log_info "Repository '${repo}' serves '${baseurl}'"
  [ -n "${chroot}" ] || {
    log_success "'${copr}' enabled with the chroot detected by dnf"
    return 0
  }
  # 'centos-stream-10-x86_64' -> 'centos-stream'; the release and the
  # architecture are dnf variables in the baseurl
  chroot_name="${chroot%-*-*}"
  [[ "${baseurl}" == */"${chroot_name}"-* ]] ||
    log_error "Repository '${repo}' does not serve a '${chroot_name}' chroot: ${baseurl}"
  log_success "'${copr}' enabled with the '${chroot_name}' chroot"
}

run_test() {

  log_info "Setting the error trap handler"
  trap on_failure EXIT

  log_info "Environment variables"
  show_env

  rm -rf "${copr_chroot_dir:?}"
  mkdir -p "${copr_chroot_dir}"

  log_info "Verify the chroot selected for each distribution"
  verify_chroot_for_system centos 9 "centos-stream-9-$(uname -m)"
  verify_chroot_for_system centos 10 "centos-stream-10-$(uname -m)"
  verify_chroot_for_system fedora 43 ""
  verify_chroot_for_system fedora 44 ""
  verify_chroot_for_system rhel 10.1 ""
  verify_chroot_override

  log_info "Verify the chroot of the Copr repository enabled on this system"
  verify_enabled_copr_repo "${server_copr_repo}"

  rm -rf "${copr_chroot_dir:?}"

  log_info "Unsetting the error trap handler"
  trap - EXIT
  test_pass
}

# Allow running directly
[[ "${BASH_SOURCE[0]}" != "$0" ]] || {
  run_test
}

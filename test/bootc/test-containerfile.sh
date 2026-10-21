#!/bin/bash
set -euo pipefail

# Skip SSH initialization in bootc utils.sh since this test doesn't need it
export BOOTC_SKIP_SSH_INIT=1

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)/utils.sh"

# Test for Containerfile generation across different installation sources.
# This test does not require virtualization or actual container builds;
# it only verifies the generated Containerfile text.

# Mock rpms_from_brew_url for testing (actual brew server not needed)
rpms_from_brew_url() {
  local brew_base_url="${1}"
  # Return dummy RPM URLs for testing
  echo "${brew_base_url}/$(uname -m)/go-fdo-client-1.0.0-1.el10.$(uname -m).rpm"
}

test_dir="${base_dir}/containerfile-test"

on_failure() {
  log_error "Test failed!"
}

# Verify that the generated Containerfile contains the expected pattern
verify_containerfile_contains() {
  local pattern="${1}"
  local description="${2}"
  if ! grep -q "${pattern}" Containerfile; then
    log_error "Containerfile does not contain expected pattern: ${description}"
    log_error "Pattern: ${pattern}"
    log_error "Containerfile content:"
    cat Containerfile >&2
    return 1
  fi
  log_success "Containerfile contains: ${description}"
}

# Verify that the generated Containerfile does NOT contain the pattern
verify_containerfile_not_contains() {
  local pattern="${1}"
  local description="${2}"
  if grep -q "${pattern}" Containerfile; then
    log_error "Containerfile should not contain: ${description}"
    log_error "Pattern: ${pattern}"
    log_error "Containerfile content:"
    cat Containerfile >&2
    return 1
  fi
  log_success "Containerfile does not contain: ${description}"
}

# Test distro installation source
test_distro_source() {
  log_info "Testing distro installation source"
  rm -f Containerfile
  client_installation_source=distro containerfile_client_install > Containerfile
  verify_containerfile_contains "dnf install -y go-fdo-client" "distro installation"
  verify_containerfile_not_contains "copr" "copr commands"
  verify_containerfile_not_contains "COPY" "file copy instructions"
}

# Test copr installation source with explicit chroot on CentOS Stream
test_copr_source() {
  log_info "Testing copr installation source"
  rm -f Containerfile

  # Test with default client Copr repo
  client_installation_source=copr containerfile_client_install > Containerfile
  verify_containerfile_contains "copr enable" "copr enable command"
  verify_containerfile_contains "${client_copr_repo}" "client copr repo"
  verify_containerfile_contains "go-fdo-client" "client package name"
  verify_containerfile_contains "copr disable" "copr disable command"

  # On CentOS Stream, verify explicit chroot is used
  source /etc/os-release
  if [ "${ID}" = "centos" ]; then
    local expected_chroot="centos-stream-${VERSION_ID}-$(uname -m)"
    verify_containerfile_contains "${expected_chroot}" "CentOS Stream chroot"
  fi
}

# Test brew installation source takes precedence
test_brew_precedence() {
  log_info "Testing brew URL takes precedence over client_installation_source"
  rm -f Containerfile

  # Mock brew URL - we won't actually call it since we're just testing text generation
  (
    BREW_CLIENT_RPMS_URL="https://brew.example.com/packages/go-fdo-client/1.0.0/1.el10"
    client_installation_source=distro
    containerfile_client_install > Containerfile
  )

  verify_containerfile_contains "brew.example.com" "brew URL"
  verify_containerfile_contains "nogpgcheck" "brew installation flags"
  verify_containerfile_not_contains "copr" "copr commands (should not appear)"
}

# Test PACKIT_COPR_PROJECT selection
test_packit_selection() {
  log_info "Testing PACKIT_COPR_PROJECT selection"
  rm -f Containerfile

  # When PACKIT_COPR_RPMS contains go-fdo-client, use PACKIT_COPR_PROJECT
  PACKIT_COPR_RPMS="go-fdo-client-1.0.0-1.fc43" \
    PACKIT_COPR_PROJECT="@fedora-iot/go-fdo-client-123" \
    containerfile_client_install > Containerfile

  verify_containerfile_contains "@fedora-iot/go-fdo-client-123" "PACKIT_COPR_PROJECT"
  verify_containerfile_contains "go-fdo-client-1.0.0-1.fc43" "specific NVR"

  # When PACKIT_COPR_RPMS does not contain go-fdo-client, use default client copr
  rm -f Containerfile
  PACKIT_COPR_RPMS="go-fdo-server-1.0.0-1.fc43" \
    PACKIT_COPR_PROJECT="@fedora-iot/go-fdo-server-123" \
    containerfile_client_install > Containerfile

  verify_containerfile_contains "${client_copr_repo}" "default client copr repo"
  verify_containerfile_not_contains "go-fdo-server-123" "server project (should not appear)"
}

# Test compose installation source generates COPY and enablerepo
test_compose_source() {
  log_info "Testing compose installation source"
  rm -f Containerfile
  rm -rf files/compose

  client_installation_source=compose containerfile_client_install > Containerfile

  verify_containerfile_contains "COPY files/compose/\*.repo /etc/yum.repos.d/" "repo file copy"
  verify_containerfile_contains "disablerepo=\*" "disable all repos"
  verify_containerfile_contains "enablerepo=" "enable specific repo pattern"
  verify_containerfile_contains "go-fdo-client" "client package"

  # Verify repo files were actually created
  if [ ! -d "files/compose" ] || [ -z "$(ls -A files/compose/*.repo 2>/dev/null)" ]; then
    log_error "Compose repo files were not generated in files/compose/"
    return 1
  fi
  log_success "Compose repo files generated"
}

# Test source installation source generates COPY for RPMs
test_source_installation() {
  log_info "Testing source installation instructions"
  rm -f Containerfile
  rm -rf files/client-rpms
  mkdir -p files/client-rpms

  # Create a dummy RPM file to simulate built RPMs
  touch files/client-rpms/go-fdo-client-1.0.0-git12345678.fc43.x86_64.rpm

  client_installation_source=source containerfile_client_install > Containerfile

  verify_containerfile_contains "COPY files/client-rpms/\*.rpm /tmp/client-rpms/" "RPM file copy"
  verify_containerfile_contains "dnf install -y /tmp/client-rpms/\*.rpm" "local RPM installation"
  verify_containerfile_contains "rm -rf /tmp/client-rpms" "cleanup temporary RPMs"
}

# Test unsupported source produces error
test_unsupported_source() {
  log_info "Testing unsupported installation source"

  if client_installation_source=invalid containerfile_client_install 2>/dev/null; then
    log_error "Invalid source should have failed"
    return 1
  fi
  log_success "Invalid source correctly rejected"
}

run_test() {
  log_info "Setting the error trap handler"
  trap on_failure EXIT

  log_info "Environment variables"
  show_env

  rm -rf "${test_dir}"
  mkdir -p "${test_dir}"
  cd "${test_dir}"

  test_distro_source
  test_copr_source
  test_brew_precedence
  test_packit_selection
  test_compose_source
  test_source_installation
  test_unsupported_source

  cd - >/dev/null
  rm -rf "${test_dir}"

  log_info "Unsetting the error trap handler"
  trap - EXIT
  test_pass
}

# Allow running directly
[[ "${BASH_SOURCE[0]}" != "$0" ]] || {
  run_test
}

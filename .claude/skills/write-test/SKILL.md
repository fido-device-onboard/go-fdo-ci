---
name: write-test
description: Create new FDO integration test scripts following the layered Bash test framework. Use this skill whenever the user wants to add a new test, write a test script, create a test case, add an FSIM test, add a resale test, add a V2 API test variant, create test metadata, or write FMF test definitions. Also use when the user mentions adding test coverage, writing E2E tests, or creating test scripts for FDO onboarding scenarios.
---

# Writing New FDO Integration Tests

This repo uses a layered Bash test framework where `run_test()` is defined once in `test/ci/` and each execution layer (container, RPM, bootc) overrides only the functions that differ. Before writing any test, understand which pattern you're extending.

## Decide Which Pattern to Follow

Read the base test closest to what you're building before writing anything.

| You want to test... | Start from | Read first |
|---|---|---|
| A new onboarding flow or protocol feature | `test/ci/test-onboarding.sh` | The base `run_test()` lifecycle |
| FSIM (serviceinfo module) behavior | `test/ci/test-fsim-config.sh` | How it chains from `test-onboarding-config.sh` |
| A resale / multi-owner scenario | `test/ci/test-resale.sh` | How it adds `new_owner` service |
| An API lifecycle (CRUD operations) | `test/ci/test-rvinfo-apis-v2.sh` | How it tests API endpoints without full onboarding |
| A negative / failure scenario | `test/ci/test-device-ca-rendezvous-trust.sh` | How it expects and verifies failures |
| A V2 API variant of an existing test | `test/ci/test-onboarding-v2.sh` | How it sources the V1 test then `mgmt-api-v2.sh` |
| Config-file-based server startup | `test/ci/test-onboarding-config.sh` | How it overrides `run_go_fdo_server` and `start_service_*` |

## Source Chaining — The Core Mechanism

Every test file sources its dependencies, and **the last `source` wins** for function redefinition. The order of `source` statements is the single most important thing to get right.

**Basic test**:
```bash
source "test/ci/test-onboarding.sh"  # loads ci/utils.sh + defines run_test
```

**Within-layer override** (e.g., config-based startup):
```bash
source "test/ci/test-onboarding.sh"         # gets run_test + all CI functions
source "test/ci/test-onboarding-config.sh"   # redefines configure_service_* and start_service_*
```

**FSIM chain** (each file only overrides what it needs):
```
ci/utils.sh → ci/test-onboarding.sh → ci/test-onboarding-config.sh
  → ci/test-fsim-config.sh → ci/test-fsim-download.sh
```

**V2 API variant** — source the V1 test, then replace API functions:
```bash
source "test/ci/test-onboarding.sh"        # gets run_test with V1 API calls
source "test/scripts/fdo-api-v2.sh"        # redefines all API functions to use /api/v2/*
```

**Cross-layer test** (container/RPM/bootc):
```bash
source "test/ci/test-onboarding.sh"   # gets CI run_test + functions
source "test/container/utils.sh"      # replaces install/start/stop/curl with container versions
```

## Service Variable Convention

Every service in the `services` array needs these variables. Use the naming pattern `${service_name}_*`:

| Variable | Purpose | Example |
|---|---|---|
| `_service_name` | Canonical name | `myservice_service_name="myservice"` |
| `_dns` | DNS hostname (added to /etc/hosts) | `myservice_dns=myservice` |
| `_ip` | IP address | `myservice_ip=127.0.0.1` |
| `_port` | Listening port | `myservice_port=8050` |
| `_pid_file` | PID file path (CI layer) | `myservice_pid_file="${pid_dir}/myservice.pid"` |
| `_log` | Log file path | `myservice_log="${logs_dir}/${myservice_dns}.log"` |
| `_key` | Service private key | `myservice_key="${certs_dir}/myservice.key"` |
| `_crt` | Service certificate | `myservice_crt="${myservice_key/\.key/.crt}"` |
| `_subj` | Certificate subject | `myservice_subj="/C=US/O=FDO/CN=MyService"` |
| `_service` | Address string | `myservice_service="${myservice_dns}:${myservice_port}"` |
| `_protocol` | `http` or `https` | `myservice_protocol=http` |
| `_url` | Full base URL | `myservice_url="${myservice_protocol}://${myservice_service}"` |
| `_health_url` | Health check endpoint | `myservice_health_url="${myservice_url}/health"` |
| `_db_type` | Database type | `myservice_db_type="sqlite"` |
| `_db_dsn` | Connection string | `myservice_db_dsn="file:${db_dir}/${myservice_service_name}.db"` |

Then append to the services array: `services+=("${myservice_service_name}")`

The framework's `configure_services`, `start_services`, `stop_services`, `wait_for_services_ready`, `generate_service_certs`, `set_hostnames`, and `unset_hostnames` all iterate over this array and resolve variables/functions by name automatically.

## Writing `run_test()`

The standard `run_test()` lifecycle follows these steps in order:

```bash
run_test() {
    trap on_failure EXIT

    show_env
    create_directories

    install_client
    install_server

    generate_service_certs
    configure_services
    start_services
    wait_for_services_ready

    # --- Test-specific setup ---
    set_or_update_rendezvous_info "${manufacturer_url}" "${rv_info}"
    add_device_ca_cert "${rendezvous_url}" "${device_ca_crt}"

    guid=$(run_device_initialization)

    set_or_update_rvto2addr "${owner_url}" ...
    send_manufacturer_ov_to_owner "${manufacturer_url}" "${guid}" "${owner_url}"
    # --- End setup ---

    # --- Assertions ---
    run_fido_device_onboard "${guid}" --debug
    # --- End assertions ---

    trap - EXIT
    test_pass
}
```

If you're overriding `run_test()` (like FSIM tests do), keep the same lifecycle structure but modify the test-specific section.

## File Boilerplate

Every test script must end with this guard so it can be either sourced (for chaining) or executed directly:

```bash
[[ "${BASH_SOURCE[0]}" != "$0" ]] || {
    run_test
    cleanup
}
```

## Creating FMF Test Metadata

Each test needs a `.fmf` metadata file in `test/fmf/tests/`. Structure:

```yaml
summary: Short description of what the test verifies
description: |
    Longer description of the test scenario.
test: ../../ci/test-your-test.sh    # relative path from the .fmf file to the script
framework: shell
duration: 30m
require:                            # RPM packages needed in the test environment
  - openssl
  - jq
tag:
  - e2e
  - server                          # or client
  - your-domain-tag
```

**Tag rules** — always include at least one of `server` or `client` alongside the environment tag. The compound filter in the FMF plan needs both to disambiguate:
- `rpm` + `server` — server RPM tests
- `bootc` + `server` or `bootc` + `client` — bootc tests
- `e2e` + `client` — client E2E tests
- `coordinated` — cross-repo tests

## V2 API Variant — The Simplest Pattern

To create a V2 variant of an existing V1 test, this is all you need:

```bash
#!/bin/bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${script_dir}/test-your-v1-test.sh"
source "${script_dir}/../scripts/fdo-api-v2.sh"

[[ "${BASH_SOURCE[0]}" != "$0" ]] || {
    run_test
    cleanup
}
```

The V2 API module redefines all management API functions (`get_rendezvous_info`, `set_rendezvous_info`, `get_ov_from_manufacturer`, etc.) to use `/api/v2/*` endpoints with the V2 JSON format.

## Adding a Non-FDO Service

Some tests need non-FDO services (e.g., an HTTP server for FSIM wget tests). Follow the same variable convention but define a custom `start_service_*` that launches whatever process you need. See `test/ci/test-fsim-wget.sh` for the pattern — it adds `wget_httpd` backed by Python's `http.server`.

## Checklist for a New Test

1. Identify which existing test to chain from
2. Source it with the correct order
3. Override only the functions that need to change
4. If adding a service: declare all `_*` variables, define `start_service_*`, append to `services`
5. Add the file guard at the bottom
6. Create `.fmf` metadata with correct tags
7. If the test should run in other layers (container/RPM), create thin wrapper scripts in those directories
8. If creating a V2 variant, just source the V1 test + `fdo-api-v2.sh`

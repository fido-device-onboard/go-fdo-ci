---
name: add-test-layer
description: Create a new execution layer for the FDO test framework by overriding Bash functions from the CI base layer. Use this skill when the user wants to add a new test environment, create a new test layer (like the existing container/RPM/bootc layers), adapt the test suite for a new deployment method, or add a new way to run FDO services in tests. Also use when discussing how the layered override architecture works or planning changes to the test framework's execution model.
---

# Adding a New Test Layer

The test framework's power comes from its layered architecture: `run_test()` is defined once in `test/ci/` and each layer only replaces the functions that differ in its environment. This skill walks through creating a new layer.

## How Layers Work

Bash redefinition semantics: when a function is defined more than once, the last definition wins. Layers exploit this by controlling `source` order:

```bash
# In test/<layer>/test-onboarding.sh:
source "test/ci/test-onboarding.sh"    # (1) loads ALL CI functions + run_test
source "test/<layer>/utils.sh"          # (2) redefines only the functions that differ
```

After step (2), `run_test()` still calls `install_client`, `start_services`, etc. — but those names now resolve to the layer's versions. The test logic stays the same; only the underlying operations change.

## Functions You Must Override

These are the functions that always differ between environments. Your `utils.sh` must redefine them:

### `install_client()` / `install_server()`
How binaries get into the environment. CI uses `go build`, containers use `docker compose build`, RPM uses `dnf install`.

### `start_service_manufacturer()`, `start_service_rendezvous()`, `start_service_owner()`
How each FDO service is launched. CI uses `nohup`, containers use `docker compose up`, RPM uses `systemctl start`.

### `start_services()`
The top-level orchestrator. CI does `set_hostnames` then iterates `start_service` per service. Containers do `docker compose up -d`. Override this if your layer needs a different orchestration pattern.

### `stop_service(service)` / `stop_services()`
How services are stopped. CI uses `pkill -F`, containers use `docker compose stop`, RPM uses `systemctl stop`.

### `on_failure()`
What happens when a test fails. Should save logs, stop services, and call `test_fail`. Each layer adds its own log collection (containers save compose logs, RPM collects AVC denials).

### `cleanup()`
Full teardown — stop services, unset hostnames, uninstall binaries, remove working directory. Each layer adds its own cleanup (containers remove compose resources, RPM removes systemd drop-ins, bootc removes VMs).

## Functions You May Need to Override

Depending on your environment, you may also need to replace:

### `run_go_fdo_client(args...)`
How the FDO client binary is invoked. CI runs it locally, containers run `docker compose run`, RPM runs the installed binary at `/usr/bin/go-fdo-client`, bootc SSHes into a VM.

### `run_device_initialization()` / `run_fido_device_onboard(guid, ...)`
If device operations happen in a different context (like bootc's VM-based approach).

### `curl(args...)`
If the test environment can't reach services directly. The container layer replaces `curl` with `docker run curlimages/curl` on the `fdo` Docker network.

### `get_real_ip(service)`
How to resolve a service's IP. CI returns the `${service}_ip` variable. Containers use `docker inspect`.

### `get_service_logs(service)` / `get_logs()`
How to retrieve service logs. CI reads log files, containers use `docker compose logs`, RPM uses `journalctl`.

### `configure_services()`
If your layer needs to transform paths or write layer-specific config files. The container layer does `sed` replacements to translate host paths to container paths.

### `generate_service_certs()`
If certificates need to be generated differently (e.g., RPM can use the packaged cert generation script).

## Creating the Layer

### 1. Create the Directory

```
test/<layer>/
├── utils.sh           # Function overrides
└── test-*.sh          # Thin wrappers (one per CI test you want to run in this layer)
```

### 2. Write `utils.sh`

Your `utils.sh` should:
1. Source the parent layer's utils if extending one (bootc sources `rpm/utils.sh`)
2. Define layer-specific variables
3. Redefine the functions listed above

Structure:
```bash
#!/bin/bash

# Layer-specific variables
layer_specific_var="value"

# Override: install_client
install_client() {
    # Your layer's way of getting the client binary
}

# Override: install_server
install_server() {
    # Your layer's way of getting the server binary
}

# Override: start_service_manufacturer (and rendezvous, owner)
start_service_manufacturer() {
    # Your layer's way of starting the manufacturer
}

# ... override start_service_rendezvous, start_service_owner

# Override: stop_service
stop_service() {
    local service=$1
    # Your layer's way of stopping a service
}

# Override: on_failure
on_failure() {
    # Save logs in your layer's format
    get_logs
    stop_services
    test_fail
}

# Override: cleanup
cleanup() {
    stop_services
    unset_hostnames
    # Your layer-specific cleanup
    remove_files
}
```

### 3. Create Thin Wrapper Test Scripts

Each test you want to run in your layer gets a thin wrapper. The wrapper sources the CI test (getting `run_test`), then sources your `utils.sh` to replace functions:

```bash
#!/bin/bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${script_dir}/../ci/test-onboarding.sh"
source "${script_dir}/utils.sh"

[[ "${BASH_SOURCE[0]}" != "$0" ]] || {
    run_test
    cleanup
}
```

The key insight: `run_test()` itself is NOT redefined — it still calls the same sequence of function names. But now those names resolve to your layer's implementations.

### 4. Handle Layer-Specific Services

If your layer requires extra infrastructure services (like bootc needs `firewalld` and `libvirtd`), define their variables and functions, then append them to the `services` array. Use `configure_service_*` for setup and `start_service_*` / `stop_service_*` for lifecycle.

## Extending an Existing Layer

Bootc extends RPM rather than starting from CI. This is appropriate when your layer shares most behavior with an existing non-CI layer:

```bash
# test/bootc/utils.sh
source "test/rpm/utils.sh"    # inherit RPM's systemctl-based lifecycle
# then override only what differs (VM provisioning, SSH-based client)
```

## Adding to CI / FMF

If your layer runs in GitHub Actions, add its tests to the matrix in `.github/workflows/e2e.yml`. The `setup` job scans `test/ci/` and `test/container/` for test scripts — you may need to add your layer's directory to the scan.

If your layer runs via Packit/TMT (like RPM and bootc), create an FMF plan in `test/fmf/plans/` with the appropriate filter and provisioning. See existing plans for the structure.

## Checklist

1. Create `test/<layer>/utils.sh` with all required function overrides
2. Create thin wrapper scripts for each test you want to run
3. Verify the source chain: CI test first, then your utils.sh
4. Test that `run_test` works end-to-end in your layer
5. Add FMF metadata and/or GitHub Actions integration
6. Add cleanup for any layer-specific resources
7. Handle the `on_failure` trap to save useful diagnostic info

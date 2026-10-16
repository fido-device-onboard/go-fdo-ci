---
name: repo-workflow
description: General guide to working in the go-fdo-ci repository — test structure, CI pipelines, FMF/Packit integration, and common development tasks. Use this skill when the user asks about how the repo works, how to run tests, how CI is set up, what the repo structure is, how Packit and TMT work with this repo, how to make changes, or any general question about working in this codebase. Also use when the user seems unfamiliar with the repo or needs orientation.
---

# go-fdo-ci Repository Workflow

This is a shared CI test repository for the FIDO Device Onboard (FDO) Go implementation. It contains integration tests that verify the FDO protocol across different execution environments. Both `go-fdo-server` and `go-fdo-client` reference this repo for their CI.

## Repository Structure

```
test/
├── ci/           Base layer — builds from source, runs as local processes
├── container/    Overrides CI to use Docker Compose
├── rpm/          Overrides CI to use systemd services (dnf install)
├── bootc/        Extends RPM for bootable-container VM testing
├── fmf/          FMF plans and test metadata for Packit/TMT
│   ├── plans/    TMT plan definitions
│   └── tests/    Test metadata (.fmf) and standalone test scripts
├── compose/      Docker Compose files for client container tests
├── scripts/      Shared utilities (certs, management API helpers)
│   ├── cert-utils.sh              Certificate generation
│   ├── server-api-utils.sh        V1 management API helpers
│   ├── fdo-api-v2.sh              V2 management API helpers
│   ├── client-test-utils.sh       Client test environment setup
│   └── container-utils.sh         Container test utilities
└── utils/        Shared libraries sourced by test layers
    ├── certs.sh         Certificate generation functions
    ├── mgmt-api-v1.sh   V1 REST API helpers
    └── mgmt-api-v2.sh   V2 REST API helpers
```

## The Layered Test Architecture

The framework's core idea: define `run_test()` once, then swap out the underlying operations per environment. Each layer sources the CI base and replaces only the functions that differ.

| Layer | Builds via | Starts services via | Runs client via |
|---|---|---|---|
| CI | `go build` | `nohup` (background processes) | Local binary |
| Container | `docker compose build` | `docker compose up` | `docker compose run` |
| RPM | `dnf install` | `systemctl start` | `/usr/bin/go-fdo-client` |
| Bootc | `podman build` + bootc-image-builder | `systemctl start` (in VM) | SSH into VM |

Read `DEVELOPMENT.md` for full details on the architecture including the function override mechanism and service lifecycle.

## CI Pipelines

### GitHub Actions (`.github/workflows/e2e.yml`)

Runs CI-layer and container-layer tests on every PR and push to main:
1. **Setup job**: scans `test/ci/` and `test/container/` for `test-*.sh` files, generates a matrix
2. **E2E job**: runs each test in parallel, checks out `go-fdo-ci`, `go-fdo-server`, and `go-fdo-client`
3. On failure: calls `get_logs` for each test
4. Always: calls `cleanup`

Supports `workflow_dispatch` with ref inputs for all three repos.

### Packit / TMT (Testing Farm)

RPM and bootc tests run via Packit in Fedora CI. Packit test jobs in `go-fdo-server` and `go-fdo-client` reference this repo via `fmf_url`.

**FMF Plans** in `test/fmf/plans/`:

| Plan | Filter | What it runs |
|---|---|---|
| `rpm-e2e.fmf` | `tag:rpm` | RPM-installed server tests |
| `bootc-e2e.fmf` | `tag:bootc & tag:server` | Server bootc image test |
| `e2e.fmf` | `tag:e2e & tag:client` | Client E2E onboarding tests |
| `bootc-onboarding.fmf` | `tag:bootc & tag:client` | Client bootc image test |
| `coordinated-e2e.fmf` | `tag:coordinated` | Server@PR + client@PR together |

Plans define: discovery filter, provisioning (VM specs), preparation steps (package installs), and environment variables.

### Tag Convention

Tests use compound tags to disambiguate in the combined tree:
- `server` / `client` — which component the test targets
- `rpm` / `bootc` / `e2e` — which environment/layer
- `coordinated` — cross-repo tests that build both server and client from PR branches

## Running Tests Locally

**CI-layer tests** (need root for /etc/hosts, Go toolchain):
```bash
sudo bash test/ci/test-onboarding.sh
```

**Container tests** (need Docker/Podman + compose files from go-fdo-server):
```bash
export COMPOSE_DIR=/path/to/go-fdo-server/deployments/compose
sudo bash test/container/test-onboarding.sh
```

**Environment variables** for customizing test runs:
- `SERVER_LOCAL_PATH` / `CLIENT_LOCAL_PATH` — use local source instead of cloning
- `SERVER_REF` / `CLIENT_REF` — git ref to check out (default: `main`)
- `SERVER_BREW_URL` / `CLIENT_BREW_URL` — install RPMs from brew build URLs
- `SERVER_COPR_REPO` / `CLIENT_COPR_REPO` — install from Packit COPR repos
- `COMPOSE_DIR` — path to Docker Compose files (container layer)

## Common Development Tasks

### Adding a new test
Use the `write-test` skill. In short: source the closest existing test, override only what differs, add FMF metadata with correct tags, create cross-layer wrappers if needed.

### Debugging a test failure
Use the `debug-test-failure` skill. In short: identify the layer, find the logs, check common failure patterns (service startup, TO0 timing, cert mismatches, timeouts).

### Adding a new execution layer
Use the `add-test-layer` skill. In short: create `test/<layer>/utils.sh` with function overrides, create thin wrapper test scripts, add CI integration.

### Adding a V2 API variant
Source the V1 test, then source `test/scripts/fdo-api-v2.sh` or `test/utils/mgmt-api-v2.sh`. The V2 module redefines all API functions.

### Adding a new service
Declare all `${service}_*` variables following the naming convention, define `start_service_${service}()`, optionally `configure_service_${service}()`, and append to the `services` array. The framework's dispatch functions pick it up automatically.

### Modifying shared utilities
Files in `test/utils/` and `test/scripts/` are sourced by multiple layers. Changes propagate everywhere — test across layers before merging.

## Key Conventions

- All test scripts use `set -euo pipefail`
- The EXIT trap (`on_failure`) catches any command failure and cleans up
- Services are managed through the `services` array with convention-based dispatch
- Variable names follow `${service_name}_*` pattern strictly
- File guard at the bottom allows scripts to be both sourced and executed
- Tests must call `test_pass` on success and `test_fail` on failure
- Default ports: manufacturer=8038, rendezvous=8041, owner=8043
- All services bind to 127.0.0.1 in the CI layer

# `go-fdo-ci`

Shared CI test repository for [`go-fdo-server`](https://github.com/fido-device-onboard/go-fdo-server) and [`go-fdo-client`](https://github.com/fido-device-onboard/go-fdo-client).

Contains all FMF test plans, test metadata, and test scripts. Packit test jobs in both source repos reference this repo via `fmf_url` so the same test definitions drive CI for both projects.

## Repository Structure

```
tests/
  bootc/        Bootc image E2E test scripts (server + client)
  ci/           Native binary E2E test scripts (server)
  compose/      Docker Compose files for client container tests
  container/    Container-based E2E test scripts (server)
  fmf/
    plans/      tmt plans referenced by Packit
    tests/      FMF test metadata and test scripts
  rpm/          RPM-installed server test scripts
  scripts/      Shared utility scripts
```

## Test Plans

| Plan | Filter | What it runs |
|---|---|---|
| `plans/rpm-e2e.fmf` | `tag:rpm` | 4 server RPM install tests |
| `plans/bootc-e2e.fmf` | `tag:bootc & tag:server` | Server bootc image test |
| `plans/e2e.fmf` | `tag:e2e & tag:client` | 2 client E2E onboarding tests |
| `plans/bootc-onboarding.fmf` | `tag:bootc & tag:client` | Client bootc image test |
| `plans/coordinated-e2e.fmf` | `tag:coordinated` | Server@PR + client@PR together |

---

## File Manifest

Complete record of every file: where it came from, where it landed, and what (if anything) changed.

**Total files: 63**
- New (created from scratch): 3
- Copied unchanged: 29
- Copied with modifications: 31

### New Files

| File | Purpose |
|---|---|
| `.fmf/version` | FMF tree root marker — makes this repo tmt-discoverable |
| `README.md` | This file |
| `plans/coordinated-e2e.fmf` | Plan for coordinated server@PR + client@PR testing |

---

### From `go-fdo-server`

#### `tests/native/` — Native Binary E2E Tests

| Source | Destination | Changes |
|---|---|---|
| `tests/native/utils.sh` | `tests/native/utils.sh` | Script paths updated (`../../scripts/` → `../scripts/`); `fdo-utils.sh` reference renamed to `server-api-utils.sh`; `install_server()` gains `SERVER_LOCAL_PATH` support; `install_client()` gains `CLIENT_LOCAL_PATH` support and `${CLIENT_REF:-main}` instead of hardcoded `@main` |
| `tests/native/test-device-ca-api.sh` | `tests/native/test-device-ca-api.sh` | Unchanged |
| `tests/native/test-device-ca-rendezvous-trust.sh` | `tests/native/test-device-ca-rendezvous-trust.sh` | Unchanged |
| `tests/native/test-fsim-command.sh` | `tests/native/test-fsim-command.sh` | Unchanged |
| `tests/native/test-fsim-config.sh` | `tests/native/test-fsim-config.sh` | Unchanged |
| `tests/native/test-fsim-download.sh` | `tests/native/test-fsim-download.sh` | Unchanged |
| `tests/native/test-fsim-upload.sh` | `tests/native/test-fsim-upload.sh` | Unchanged |
| `tests/native/test-fsim-wget.sh` | `tests/native/test-fsim-wget.sh` | Unchanged |
| `tests/native/test-onboarding-config.sh` | `tests/native/test-onboarding-config.sh` | Unchanged |
| `tests/native/test-onboarding.sh` | `tests/native/test-onboarding.sh` | Unchanged |
| `tests/native/test-ov-verification.sh` | `tests/native/test-ov-verification.sh` | Unchanged |
| `tests/native/test-resale.sh` | `tests/native/test-resale.sh` | Unchanged |
| `tests/native/test-rv-bypass.sh` | `tests/native/test-rv-bypass.sh` | Unchanged |
| `tests/native/test-onboarding-v2.sh` | `tests/native/test-onboarding-v2.sh` | Source path updated (`../../scripts/` → `../scripts/`) |
| `tests/native/test-rv-bypass-v2.sh` | `tests/native/test-rv-bypass-v2.sh` | Source path updated (`../../scripts/` → `../scripts/`) |
| `tests/native/test-rvinfo-apis-v2.sh` | `tests/native/test-rvinfo-apis-v2.sh` | Source path updated (`../../scripts/` → `../scripts/`) |

#### `tests/container/` — Container-Based E2E Tests

> These scripts use `${COMPOSE_DIR}` (default: `deployments/compose`) to locate compose files. That directory stays in `go-fdo-server`. GitHub Actions must checkout `go-fdo-server` alongside `go-fdo-ci` when running container tests.

| Source | Destination | Changes |
|---|---|---|
| `tests/container/utils.sh` | `tests/container/utils.sh` | Added `COMPOSE_DIR` variable with default value; compose file paths use `${COMPOSE_DIR}` |
| `tests/container/test-device-ca-api.sh` | `tests/container/test-device-ca-api.sh` | Hardcoded `deployments/compose/` replaced with `${COMPOSE_DIR}` |
| `tests/container/test-device-ca-rendezvous-trust.sh` | `tests/container/test-device-ca-rendezvous-trust.sh` | Hardcoded `deployments/compose/` replaced with `${COMPOSE_DIR}` |
| `tests/container/test-fsim-download.sh` | `tests/container/test-fsim-download.sh` | Hardcoded `deployments/compose/` replaced with `${COMPOSE_DIR}` |
| `tests/container/test-fsim-upload.sh` | `tests/container/test-fsim-upload.sh` | Hardcoded `deployments/compose/` replaced with `${COMPOSE_DIR}` |
| `tests/container/test-fsim-wget.sh` | `tests/container/test-fsim-wget.sh` | Hardcoded `deployments/compose/` replaced with `${COMPOSE_DIR}` |
| `tests/container/test-health-api-postgres.sh` | `tests/container/test-health-api-postgres.sh` | Hardcoded `deployments/compose/` replaced with `${COMPOSE_DIR}` |
| `tests/container/test-onboarding-config.sh` | `tests/container/test-onboarding-config.sh` | Hardcoded `deployments/compose/` replaced with `${COMPOSE_DIR}` |
| `tests/container/test-onboarding-postgres.sh` | `tests/container/test-onboarding-postgres.sh` | Hardcoded `deployments/compose/` replaced with `${COMPOSE_DIR}` |
| `tests/container/test-onboarding.sh` | `tests/container/test-onboarding.sh` | Hardcoded `deployments/compose/` replaced with `${COMPOSE_DIR}` |
| `tests/container/test-ov-verification.sh` | `tests/container/test-ov-verification.sh` | Hardcoded `deployments/compose/` replaced with `${COMPOSE_DIR}` |
| `tests/container/test-resale.sh` | `tests/container/test-resale.sh` | Hardcoded `deployments/compose/` replaced with `${COMPOSE_DIR}` |

#### `tests/rpm/` — RPM-Installed Server Tests

| Source | Destination | Changes |
|---|---|---|
| `tests/rpm/utils.sh` | `tests/rpm/utils.sh` | Unchanged |
| `tests/rpm/test-onboarding.sh` | `tests/rpm/test-onboarding.sh` | Unchanged |
| `tests/rpm/test-onboarding-defaults.sh` | `tests/rpm/test-onboarding-defaults.sh` | Unchanged |
| `tests/rpm/test-onboarding-deferred-rendezvous.sh` | `tests/rpm/test-onboarding-deferred-rendezvous.sh` | Unchanged |
| `tests/rpm/test-onboarding-https.sh` | `tests/rpm/test-onboarding-https.sh` | Unchanged |

#### `tests/bootc/` — Bootc Image Tests (Server + Client)

| Source | Destination | Changes |
|---|---|---|
| `tests/bootc/utils.sh` | `tests/bootc/utils.sh` | Unchanged |
| `tests/bootc/test-onboarding.sh` | `tests/bootc/test-onboarding.sh` | Unchanged |

> `tests/bootc/test-bootc-onboarding.sh` also lives here — see the [client section](#from-go-fdo-client) below.

#### `scripts/` → `tests/scripts/` — Server Utility Scripts

| Source | Destination | Changes |
|---|---|---|
| `scripts/cert-utils.sh` | `tests/scripts/cert-utils.sh` | Unchanged (path moved) |
| `scripts/fdo-utils.sh` | `tests/scripts/server-api-utils.sh` | **Renamed** — contains REST API helpers (get/set RV info, OV upload, TO0 trigger); renamed to avoid collision with client's `fdo-utils.sh` |
| `scripts/fdo-api-v2.sh` | `tests/scripts/fdo-api-v2.sh` | Unchanged (path moved) — V2 RVInfo API functions (`/api/v2/rvinfo` endpoint) |
| `scripts/generate-go-fdo-server-certs.sh` | `tests/scripts/generate-go-fdo-server-certs.sh` | Unchanged (path moved) |

#### `tests/fmf/` — FMF Plans and Test Metadata

| Source | Destination | Changes |
|---|---|---|
| `plans/rpm-e2e.fmf` | `plans/rpm-e2e.fmf` | Unchanged — `tag:rpm` is already unambiguous |
| `plans/bootc-e2e.fmf` | `plans/bootc-e2e.fmf` | Filter: `tag:bootc` → `tag:bootc & tag:server` |
| `tests/fmf/tests/rpm-test-onboarding.fmf` | `tests/fmf/tests/rpm-test-onboarding.fmf` | Added `tag:server` tag |
| `tests/fmf/tests/rpm-test-onboarding-defaults.fmf` | `tests/fmf/tests/rpm-test-onboarding-defaults.fmf` | Added `tag:server` tag |
| `tests/fmf/tests/rpm-test-onboarding-deferred-rendezvous.fmf` | `tests/fmf/tests/rpm-test-onboarding-deferred-rendezvous.fmf` | Added `tag:server` tag |
| `tests/fmf/tests/rpm-test-onboarding-https.fmf` | `tests/fmf/tests/rpm-test-onboarding-https.fmf` | Added `tag:server` tag |
| `tests/fmf/tests/bootc-test-onboarding.fmf` | `tests/fmf/tests/bootc-test-onboarding.fmf` | Added `tag:server` tag |

---

### From `go-fdo-client`

#### `.github/scripts/` → `tests/scripts/` — Client Utility Scripts

| Source | Destination | Changes |
|---|---|---|
| `.github/scripts/fdo-utils.sh` | `tests/scripts/client-test-utils.sh` | **Renamed** — contains cert generation and test environment setup; renamed to avoid collision with server's `fdo-utils.sh` |
| `.github/scripts/container-utils.sh` | `tests/scripts/container-utils.sh` | Source reference updated: `fdo-utils.sh` → `client-test-utils.sh` |
| `.github/scripts/test-coverage.sh` | `tests/scripts/test-coverage.sh` | Unchanged (path moved) |

#### `.github/compose/` → `tests/compose/` — Docker Compose Files

| Source | Destination | Changes |
|---|---|---|
| `.github/compose/networks.yaml` | `tests/compose/networks.yaml` | Unchanged (path moved) |
| `.github/compose/servers.yaml` | `tests/compose/servers.yaml` | Unchanged (path moved) |

#### `tests/fmf/` — FMF Plans, Test Metadata, and Test Scripts

| Source | Destination | Changes |
|---|---|---|
| `plans/e2e.fmf` | `plans/e2e.fmf` | Filter: `tag:e2e` → `tag:e2e & tag:client` |
| `plans/bootc-onboarding.fmf` | `plans/bootc-onboarding.fmf` | Filter: `tag:bootc` → `tag:bootc & tag:client` |
| `tests/fmf/tests/e2e-onboarding.fmf` | `tests/fmf/tests/e2e-onboarding.fmf` | Added `tag:client` and `tag:coordinated` tags |
| `tests/fmf/tests/retry-loop.fmf` | `tests/fmf/tests/retry-loop.fmf` | Added `tag:client` and `tag:coordinated` tags |
| `tests/fmf/tests/bootc-onboarding.fmf` | `tests/fmf/tests/bootc-onboarding.fmf` | Added `tag:client` tag; fixed `test:` path to `../../bootc/test-bootc-onboarding.sh` |
| `tests/fmf/tests/test-bootc-onboarding.sh` | `tests/bootc/test-bootc-onboarding.sh` | **Moved to different directory** — co-located with other bootc tests |
| `tests/fmf/tests/test-onboarding.sh` | `tests/fmf/tests/test-onboarding.sh` | Unchanged |
| `tests/fmf/tests/test-retry-loop.sh` | `tests/fmf/tests/test-retry-loop.sh` | Unchanged |
| `tests/fmf/tests/utils.sh` | `tests/fmf/tests/utils.sh` | Unchanged |

---

## Notes on Changes

### Why the Coordinated Plan Uses Absolute Paths

`coordinated-e2e.fmf` clones both repos into `/var/tmp/fdo/server` and `/var/tmp/fdo/client` and sets `SERVER_LOCAL_PATH`/`CLIENT_LOCAL_PATH` to those absolute paths. Relative paths (e.g., `server`, `client`) would not work because tmt runs each test script from the test's own directory (`tests/fmf/tests/`), not from the directory where the `prepare:` step ran. Absolute paths are the only safe option for cross-step path sharing in tmt.

The `SERVER_REF` and `CLIENT_REF` environment variables control which commit each repo is checked out to; both default to `main`.

### Why Filters Use Compound Expressions

The `go-fdo-ci` FMF tree contains all 8 tests from both repos. Simple single-tag filters that worked in each repo's narrow local tree become too broad in the combined tree — for example, `tag:e2e` would match 7 tests instead of 2 after migration. All tests are tagged `client` or `server` to allow unambiguous compound filters (`tag:e2e & tag:client`).

### Why `fdo-utils.sh` Was Renamed Twice

Both repos had a file named `fdo-utils.sh` with completely different contents:
- Server's `scripts/fdo-utils.sh` — REST API helpers (get/set RV info, upload OVs, trigger TO0)
- Client's `.github/scripts/fdo-utils.sh` — cert generation and test environment setup

Merging both into `tests/scripts/` required renaming to avoid collision:
- Server's → `server-api-utils.sh`
- Client's → `client-test-utils.sh`

### Why `test-bootc-onboarding.sh` Moved

The client stored its bootc test script alongside FMF metadata in `tests/fmf/tests/`. In `go-fdo-ci`, bootc scripts live in `tests/bootc/` alongside the server's bootc scripts. The `bootc-onboarding.fmf` metadata was updated to reflect the new path.

### What Stayed in `go-fdo-server` (Not Moved)

`deployments/compose/` — Docker Compose files used by `tests/container/` scripts. These scripts locate the compose files via the `COMPOSE_DIR` environment variable (default: `deployments/compose`). For GitHub Actions, the simplest layout is to checkout `go-fdo-server` at the workspace root so the default path works. Alternatively, set `COMPOSE_DIR` to match the actual checkout layout (e.g., `COMPOSE_DIR=server/deployments/compose`).

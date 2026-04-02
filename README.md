# `go-fdo-ci`

Shared CI test repository for [`go-fdo-server`](https://github.com/fido-device-onboard/go-fdo-server) and [`go-fdo-client`](https://github.com/fido-device-onboard/go-fdo-client).

Contains all FMF test plans, test metadata, and test scripts. Packit test jobs in both source repos reference this repo via `fmf_url` so the same test definitions drive CI for both projects.

## Repository Structure

```
test/
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
| `test/fmf/plans/rpm-e2e.fmf` | `tag:rpm` | 4 server RPM install tests |
| `test/fmf/plans/bootc-e2e.fmf` | `tag:bootc & tag:server` | Server bootc image test |
| `test/fmf/plans/e2e.fmf` | `tag:e2e & tag:client` | 2 client E2E onboarding tests |
| `test/fmf/plans/bootc-onboarding.fmf` | `tag:bootc & tag:client` | Client bootc image test |
| `test/fmf/plans/coordinated-e2e.fmf` | `tag:coordinated` | Server@PR + client@PR together |

---

## File Manifest

Complete record of every file: where it came from, where it landed, and what (if anything) changed.

**Total files: 63**
- New (created from scratch): 3
- Copied unchanged: 44
- Copied with modifications: 16

### New Files

| File | Purpose |
|---|---|
| `.fmf/version` | FMF tree root marker — makes this repo tmt-discoverable |
| `README.md` | This file |
| `test/fmf/plans/coordinated-e2e.fmf` | Plan for coordinated server@PR + client@PR testing |

---

### From `go-fdo-server`

#### `test/ci/` — Native Binary E2E Tests

| Source | Destination | Changes |
|---|---|---|
| `test/ci/utils.sh` | `test/ci/utils.sh` | Script paths updated (`../../scripts/` → `../scripts/`); `fdo-utils.sh` reference renamed to `server-api-utils.sh`; `install_server()` gains `SERVER_LOCAL_PATH` support; `install_client()` gains `CLIENT_LOCAL_PATH` support and `${CLIENT_REF:-main}` instead of hardcoded `@main` |
| `test/ci/test-device-ca-api.sh` | `test/ci/test-device-ca-api.sh` | Unchanged |
| `test/ci/test-device-ca-rendezvous-trust.sh` | `test/ci/test-device-ca-rendezvous-trust.sh` | Unchanged |
| `test/ci/test-fsim-command.sh` | `test/ci/test-fsim-command.sh` | Unchanged |
| `test/ci/test-fsim-config.sh` | `test/ci/test-fsim-config.sh` | Unchanged |
| `test/ci/test-fsim-download.sh` | `test/ci/test-fsim-download.sh` | Unchanged |
| `test/ci/test-fsim-upload.sh` | `test/ci/test-fsim-upload.sh` | Unchanged |
| `test/ci/test-fsim-wget.sh` | `test/ci/test-fsim-wget.sh` | Unchanged |
| `test/ci/test-onboarding-config.sh` | `test/ci/test-onboarding-config.sh` | Unchanged |
| `test/ci/test-onboarding.sh` | `test/ci/test-onboarding.sh` | Unchanged |
| `test/ci/test-ov-verification.sh` | `test/ci/test-ov-verification.sh` | Unchanged |
| `test/ci/test-resale.sh` | `test/ci/test-resale.sh` | Unchanged |
| `test/ci/test-rv-bypass.sh` | `test/ci/test-rv-bypass.sh` | Unchanged |
| `test/ci/test-onboarding-v2.sh` | `test/ci/test-onboarding-v2.sh` | Source path updated (`../../scripts/` → `../scripts/`) |
| `test/ci/test-rv-bypass-v2.sh` | `test/ci/test-rv-bypass-v2.sh` | Source path updated (`../../scripts/` → `../scripts/`) |
| `test/ci/test-rvinfo-apis-v2.sh` | `test/ci/test-rvinfo-apis-v2.sh` | Source path updated (`../../scripts/` → `../scripts/`) |

#### `test/container/` — Container-Based E2E Tests

> These scripts reference `deployments/compose/` via relative path. That directory stays in `go-fdo-server`. GitHub Actions must checkout `go-fdo-server` alongside `go-fdo-ci` when running container tests.

| Source | Destination | Changes |
|---|---|---|
| `test/container/utils.sh` | `test/container/utils.sh` | Unchanged |
| `test/container/test-device-ca-api.sh` | `test/container/test-device-ca-api.sh` | Unchanged |
| `test/container/test-device-ca-rendezvous-trust.sh` | `test/container/test-device-ca-rendezvous-trust.sh` | Unchanged |
| `test/container/test-fsim-download.sh` | `test/container/test-fsim-download.sh` | Unchanged |
| `test/container/test-fsim-upload.sh` | `test/container/test-fsim-upload.sh` | Unchanged |
| `test/container/test-fsim-wget.sh` | `test/container/test-fsim-wget.sh` | Unchanged |
| `test/container/test-health-api-postgres.sh` | `test/container/test-health-api-postgres.sh` | Unchanged |
| `test/container/test-onboarding-config.sh` | `test/container/test-onboarding-config.sh` | Unchanged |
| `test/container/test-onboarding-postgres.sh` | `test/container/test-onboarding-postgres.sh` | Unchanged |
| `test/container/test-onboarding.sh` | `test/container/test-onboarding.sh` | Unchanged |
| `test/container/test-ov-verification.sh` | `test/container/test-ov-verification.sh` | Unchanged |
| `test/container/test-resale.sh` | `test/container/test-resale.sh` | Unchanged |

#### `test/rpm/` — RPM-Installed Server Tests

| Source | Destination | Changes |
|---|---|---|
| `test/rpm/utils.sh` | `test/rpm/utils.sh` | Unchanged |
| `test/rpm/test-onboarding.sh` | `test/rpm/test-onboarding.sh` | Unchanged |
| `test/rpm/test-onboarding-defaults.sh` | `test/rpm/test-onboarding-defaults.sh` | Unchanged |
| `test/rpm/test-onboarding-deferred-rendezvous.sh` | `test/rpm/test-onboarding-deferred-rendezvous.sh` | Unchanged |
| `test/rpm/test-onboarding-https.sh` | `test/rpm/test-onboarding-https.sh` | Unchanged |

#### `test/bootc/` — Bootc Image Tests (Server + Client)

| Source | Destination | Changes |
|---|---|---|
| `test/bootc/utils.sh` | `test/bootc/utils.sh` | Unchanged |
| `test/bootc/test-onboarding.sh` | `test/bootc/test-onboarding.sh` | Unchanged |

> `test/bootc/test-bootc-onboarding.sh` also lives here — see the [client section](#from-go-fdo-client) below.

#### `scripts/` → `test/scripts/` — Server Utility Scripts

| Source | Destination | Changes |
|---|---|---|
| `scripts/cert-utils.sh` | `test/scripts/cert-utils.sh` | Unchanged (path moved) |
| `scripts/fdo-utils.sh` | `test/scripts/server-api-utils.sh` | **Renamed** — contains REST API helpers (get/set RV info, OV upload, TO0 trigger); renamed to avoid collision with client's `fdo-utils.sh` |
| `scripts/fdo-api-v2.sh` | `test/scripts/fdo-api-v2.sh` | Unchanged (path moved) — V2 RVInfo API functions (`/api/v2/rvinfo` endpoint) |
| `scripts/generate-go-fdo-server-certs.sh` | `test/scripts/generate-go-fdo-server-certs.sh` | Unchanged (path moved) |

#### `test/fmf/` — FMF Plans and Test Metadata

| Source | Destination | Changes |
|---|---|---|
| `test/fmf/plans/rpm-e2e.fmf` | `test/fmf/plans/rpm-e2e.fmf` | Unchanged — `tag:rpm` is already unambiguous |
| `test/fmf/plans/bootc-e2e.fmf` | `test/fmf/plans/bootc-e2e.fmf` | Filter: `tag:bootc` → `tag:bootc & tag:server` |
| `test/fmf/tests/rpm-test-onboarding.fmf` | `test/fmf/tests/rpm-test-onboarding.fmf` | Added `tag:server` tag |
| `test/fmf/tests/rpm-test-onboarding-defaults.fmf` | `test/fmf/tests/rpm-test-onboarding-defaults.fmf` | Added `tag:server` tag |
| `test/fmf/tests/rpm-test-onboarding-deferred-rendezvous.fmf` | `test/fmf/tests/rpm-test-onboarding-deferred-rendezvous.fmf` | Added `tag:server` tag |
| `test/fmf/tests/rpm-test-onboarding-https.fmf` | `test/fmf/tests/rpm-test-onboarding-https.fmf` | Added `tag:server` tag |
| `test/fmf/tests/bootc-test-onboarding.fmf` | `test/fmf/tests/bootc-test-onboarding.fmf` | Added `tag:server` tag |

---

### From `go-fdo-client`

#### `.github/scripts/` → `test/scripts/` — Client Utility Scripts

| Source | Destination | Changes |
|---|---|---|
| `.github/scripts/fdo-utils.sh` | `test/scripts/client-test-utils.sh` | **Renamed** — contains cert generation and test environment setup; renamed to avoid collision with server's `fdo-utils.sh` |
| `.github/scripts/container-utils.sh` | `test/scripts/container-utils.sh` | Source reference updated: `fdo-utils.sh` → `client-test-utils.sh` |
| `.github/scripts/test-coverage.sh` | `test/scripts/test-coverage.sh` | Unchanged (path moved) |

#### `.github/compose/` → `test/compose/` — Docker Compose Files

| Source | Destination | Changes |
|---|---|---|
| `.github/compose/networks.yaml` | `test/compose/networks.yaml` | Unchanged (path moved) |
| `.github/compose/servers.yaml` | `test/compose/servers.yaml` | Unchanged (path moved) |

#### `test/fmf/` — FMF Plans, Test Metadata, and Test Scripts

| Source | Destination | Changes |
|---|---|---|
| `test/fmf/plans/e2e.fmf` | `test/fmf/plans/e2e.fmf` | Filter: `tag:e2e` → `tag:e2e & tag:client` |
| `test/fmf/plans/bootc-onboarding.fmf` | `test/fmf/plans/bootc-onboarding.fmf` | Filter: `tag:bootc` → `tag:bootc & tag:client` |
| `test/fmf/tests/e2e-onboarding.fmf` | `test/fmf/tests/e2e-onboarding.fmf` | Added `tag:client` and `tag:coordinated` tags |
| `test/fmf/tests/retry-loop.fmf` | `test/fmf/tests/retry-loop.fmf` | Added `tag:client` and `tag:coordinated` tags |
| `test/fmf/tests/bootc-onboarding.fmf` | `test/fmf/tests/bootc-onboarding.fmf` | Added `tag:client` tag; fixed `test:` path to `../../bootc/test-bootc-onboarding.sh` |
| `test/fmf/tests/test-bootc-onboarding.sh` | `test/bootc/test-bootc-onboarding.sh` | **Moved to different directory** — co-located with other bootc tests |
| `test/fmf/tests/test-onboarding.sh` | `test/fmf/tests/test-onboarding.sh` | Unchanged |
| `test/fmf/tests/test-retry-loop.sh` | `test/fmf/tests/test-retry-loop.sh` | Unchanged |
| `test/fmf/tests/utils.sh` | `test/fmf/tests/utils.sh` | Unchanged |

---

## Notes on Changes

### Why the Coordinated Plan Uses Absolute Paths

`coordinated-e2e.fmf` clones both repos into `/var/tmp/fdo/server` and `/var/tmp/fdo/client` and sets `SERVER_LOCAL_PATH`/`CLIENT_LOCAL_PATH` to those absolute paths. Relative paths (e.g., `server`, `client`) would not work because tmt runs each test script from the test's own directory (`test/fmf/tests/`), not from the directory where the `prepare:` step ran. Absolute paths are the only safe option for cross-step path sharing in tmt.

The `SERVER_REF` and `CLIENT_REF` environment variables control which commit each repo is checked out to; both default to `main`.

### Why Filters Use Compound Expressions

The `go-fdo-ci` FMF tree contains all 8 tests from both repos. Simple single-tag filters that worked in each repo's narrow local tree become too broad in the combined tree — for example, `tag:e2e` would match 7 tests instead of 2 after migration. All tests are tagged `client` or `server` to allow unambiguous compound filters (`tag:e2e & tag:client`).

### Why `fdo-utils.sh` Was Renamed Twice

Both repos had a file named `fdo-utils.sh` with completely different contents:
- Server's `scripts/fdo-utils.sh` — REST API helpers (get/set RV info, upload OVs, trigger TO0)
- Client's `.github/scripts/fdo-utils.sh` — cert generation and test environment setup

Merging both into `test/scripts/` required renaming to avoid collision:
- Server's → `server-api-utils.sh`
- Client's → `client-test-utils.sh`

### Why `test-bootc-onboarding.sh` Moved

The client stored its bootc test script alongside FMF metadata in `test/fmf/tests/`. In `go-fdo-ci`, bootc scripts live in `test/bootc/` alongside the server's bootc scripts. The `bootc-onboarding.fmf` metadata was updated to reflect the new path.

### What Stayed in `go-fdo-server` (Not Moved)

`deployments/compose/` — Docker Compose files used by `test/container/` scripts. These scripts reference `deployments/compose/` as a bare relative path (no `../` prefix), so they require the CWD to be the `go-fdo-server` repo root at runtime. For GitHub Actions, this means `go-fdo-server` must be checked out **at the workspace root** (no `path:` parameter), with `go-fdo-ci` checked out to a subdirectory (e.g., `path: ci`). Checking out `go-fdo-server` to a subdirectory like `path: server` would break these paths.

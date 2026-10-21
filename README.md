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
  rpm/          Shared RPM client/server integration test scripts
  scripts/      Shared utility scripts
```

## Test Plans

The shared integration tests exercise both the FDO client and server.
Plans select tests by installation method rather than by component.

| Plan | Filter | Coverage |
|---|---|---|
| `test/fmf/plans/rpm.fmf` | `tag:rpm` | Four RPM onboarding tests: standard, defaults, deferred rendezvous, and HTTPS |
| `test/fmf/plans/bootc.fmf` | `tag:bootc` | One bootc onboarding test using `test/bootc/test-onboarding.sh` |

The RPM and bootc tests carry both `client` and `server` tags. Their
scripts manage product-package installation through shared helpers;
FMF plans prepare the general dependencies needed to run the tests.

The retry-loop test remains in the repository but is excluded from
these plans until it is migrated to the common functions.

## Packit Tests for This Repository

Pull requests against `go-fdo-ci` run tests-only Packit jobs with
`skip_build: true`. The jobs use the PR's own FMF definitions and set
`INSTALLATION_SOURCE=copr` to select published FDO packages.

| Job | Distributions | Architectures | Combinations |
|---|---|---|---:|
| `rpm` | Fedora latest-stable, latest, rawhide; CentOS Stream 9 and 10 | x86_64, aarch64 | 10 |
| `bootc` | Fedora latest-stable; CentOS Stream 10 | x86_64, aarch64 | 4 |
| **Total** | | | **14** |

Fedora target aliases are resolved by Packit and can change as Fedora
releases advance.

See [RPM_TESTING.md](RPM_TESTING.md) for package-source selection and
the distinction between product-PR and tests-only runs.

## Migration from the Previous Plans

Consumers of the shared FMF definitions should update their
`tmt_plan` values as follows:

| Previous plan | Replacement |
|---|---|
| `test/fmf/plans/rpm-e2e` | `test/fmf/plans/rpm` |
| `test/fmf/plans/e2e` | `test/fmf/plans/rpm` |
| `test/fmf/plans/bootc-e2e` | `test/fmf/plans/bootc` |
| `test/fmf/plans/bootc-onboarding` | `test/fmf/plans/bootc` |

These replacements consolidate the supported onboarding workflows;
they do not preserve the former test selection exactly. In particular,
retry-loop coverage is currently excluded.

The `coordinated-e2e` plan has been removed without a direct replacement.
The standalone client onboarding script and legacy bootc onboarding
script, together with their FMF test metadata, have also been removed.

Repositories following `go-fdo-ci`'s `main` branch must coordinate their
plan-reference updates with this migration.

See [RPM_TESTING.md](RPM_TESTING.md) for package installation source
selection in both RPM and bootc test layers.

---

## Historical Import Manifest

The following tables record the initial import from `go-fdo-server` and
`go-fdo-client`. Paths, file counts, tags, and descriptions in this
section refer to that import, not to the current repository layout.

Some imported plans and scripts have since been renamed or removed.
Use the Test Plans and Migration sections above for current names and
coverage.

**Files recorded at the initial import: 63**
- New: 3
- Copied unchanged: 29
- Copied with modifications: 31

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

> These scripts use `${COMPOSE_DIR}` (default: `deployments/compose`) to locate compose files. That directory stays in `go-fdo-server`. GitHub Actions must checkout `go-fdo-server` alongside `go-fdo-ci` when running container tests.

| Source | Destination | Changes |
|---|---|---|
| `test/container/utils.sh` | `test/container/utils.sh` | Added `COMPOSE_DIR` variable with default value; compose file paths use `${COMPOSE_DIR}` |
| `test/container/test-device-ca-api.sh` | `test/container/test-device-ca-api.sh` | Hardcoded `deployments/compose/` replaced with `${COMPOSE_DIR}` |
| `test/container/test-device-ca-rendezvous-trust.sh` | `test/container/test-device-ca-rendezvous-trust.sh` | Hardcoded `deployments/compose/` replaced with `${COMPOSE_DIR}` |
| `test/container/test-fsim-download.sh` | `test/container/test-fsim-download.sh` | Hardcoded `deployments/compose/` replaced with `${COMPOSE_DIR}` |
| `test/container/test-fsim-upload.sh` | `test/container/test-fsim-upload.sh` | Hardcoded `deployments/compose/` replaced with `${COMPOSE_DIR}` |
| `test/container/test-fsim-wget.sh` | `test/container/test-fsim-wget.sh` | Hardcoded `deployments/compose/` replaced with `${COMPOSE_DIR}` |
| `test/container/test-health-api-postgres.sh` | `test/container/test-health-api-postgres.sh` | Hardcoded `deployments/compose/` replaced with `${COMPOSE_DIR}` |
| `test/container/test-onboarding-config.sh` | `test/container/test-onboarding-config.sh` | Hardcoded `deployments/compose/` replaced with `${COMPOSE_DIR}` |
| `test/container/test-onboarding-postgres.sh` | `test/container/test-onboarding-postgres.sh` | Hardcoded `deployments/compose/` replaced with `${COMPOSE_DIR}` |
| `test/container/test-onboarding.sh` | `test/container/test-onboarding.sh` | Hardcoded `deployments/compose/` replaced with `${COMPOSE_DIR}` |
| `test/container/test-ov-verification.sh` | `test/container/test-ov-verification.sh` | Hardcoded `deployments/compose/` replaced with `${COMPOSE_DIR}` |
| `test/container/test-resale.sh` | `test/container/test-resale.sh` | Hardcoded `deployments/compose/` replaced with `${COMPOSE_DIR}` |

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

> At the initial import, the client bootc script was placed at
> `test/bootc/test-bootc-onboarding.sh`. That legacy script has since
> been removed in favor of `test/bootc/test-onboarding.sh`.

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

## Historical Import Notes

These notes explain decisions made during the initial import.
The coordinated plan, compound discovery filters, and legacy client
bootc script described below have since been superseded by the
consolidated plans documented above.

### Why the Coordinated Plan Used Absolute Paths

The original `coordinated-e2e.fmf` cloned both repos into
`/var/tmp/fdo/server` and `/var/tmp/fdo/client` and set
`SERVER_LOCAL_PATH`/`CLIENT_LOCAL_PATH` to those absolute paths.
This avoided depending on the working directory used by individual
tmt steps.

The `SERVER_REF` and `CLIENT_REF` environment variables controlled
which commit each repo was checked out to; both defaulted to `main`.

### Why Filters Originally Used Compound Expressions

The initial FMF tree combined eight tests from both repos. Single-tag
filters from the separate repositories became too broad in the combined
tree. The original plans used component tags in compound filters such
as `tag:e2e & tag:client`. The current plans instead select the common
tests with `tag:rpm` and `tag:bootc`.

### Why `fdo-utils.sh` Was Renamed Twice

Both repos had a file named `fdo-utils.sh` with completely different contents:
- Server's `scripts/fdo-utils.sh` — REST API helpers (get/set RV info, upload OVs, trigger TO0)
- Client's `.github/scripts/fdo-utils.sh` — cert generation and test environment setup

Merging both into `test/scripts/` required renaming to avoid collision:
- Server's → `server-api-utils.sh`
- Client's → `client-test-utils.sh`

### Why the Legacy Client Bootc Script Was Initially Moved

The client originally stored its bootc test script alongside FMF
metadata in `test/fmf/tests/`. During the import, it was moved to
`test/bootc/`, and `bootc-onboarding.fmf` was updated to reference that
location. The legacy script and metadata have since been removed in
favor of the common bootc test.

### What Stayed in `go-fdo-server` (Not Moved)

`deployments/compose/` — Docker Compose files used by `test/container/` scripts. These scripts locate the compose files via the `COMPOSE_DIR` environment variable (default: `deployments/compose`). For GitHub Actions, the simplest layout is to checkout `go-fdo-server` at the workspace root so the default path works. Alternatively, set `COMPOSE_DIR` to match the actual checkout layout (e.g., `COMPOSE_DIR=server/deployments/compose`).

# CI Retriggering Guide

This document explains how to retrigger CI jobs on pull requests in the `go-fdo-ci` repository. There are two independent CI systems: **GitHub Actions** (E2E workflow) and **Packit / Testing Farm** (TMT plans on real VMs). Each has its own retrigger mechanism. Both use a similar comment syntax: `/ci test` for GitHub Actions and `/packit test` for Packit, with `--commit` to select a ref and `--env KEY=VALUE` to pass environment variables.

## GitHub Actions: `/ci test`

The `coordinated-test.yml` workflow watches for `/ci test` comments on
pull requests. It parses `--commit` and `--env KEY=VALUE` arguments
from the comment and triggers the E2E workflow (`e2e.yml`) with those
values.

The E2E workflow runs `test/ci/` (native binary) and `test/container/`
(Docker Compose) test scripts, which always build server and client
from source. The `SERVER_REF` and `CLIENT_REF` variables control which
git refs are checked out for the build.

**Requirements:**

- The commenter must have **write** permission on the repository.
- A `RETEST_WORKFLOW_TOKEN` repository secret (PAT with `actions:write`
  scope) must be configured.

### Syntax

```
/ci test [--commit <ref>] [--env KEY=VALUE ...]
```

- `--commit <ref>` — `go-fdo-ci` ref to test (defaults to the PR head SHA)
- `--env KEY=VALUE` — pass environment variables to the test jobs

### Supported Environment Variables

| Variable | Default | Description |
|---|---|---|
| `SERVER_REF` | `main` | `go-fdo-server` ref (branch, tag, or `refs/pull/N/head`) |
| `CLIENT_REF` | `main` | `go-fdo-client` ref |

### Examples

**Retrigger with defaults** (tests the PR's CI scripts against `server@main` + `client@main`, built from source):

```
/ci test
```

**Test a specific `go-fdo-ci` branch:**

```
/ci test --commit my-feature-branch
```

**Test with a specific server PR:**

```
/ci test --env SERVER_REF=refs/pull/42/head
```

**Test with both a server and client PR together:**

```
/ci test --env SERVER_REF=refs/pull/42/head --env CLIENT_REF=refs/pull/99/head
```

**Combine `--commit` with `--env` to test a CI branch against specific PRs:**

```
/ci test --commit my-ci-branch --env SERVER_REF=refs/pull/42/head --env CLIENT_REF=refs/pull/99/head
```

### What Happens

1. The workflow adds an :eyes: reaction to acknowledge the comment.
2. It parses `--commit` and `--env` arguments (unknown variables are
   ignored with a warning).
3. It triggers the E2E workflow via `gh workflow run`.
4. It posts a comment with a link to the triggered workflow run.

### Manual Workflow Dispatch

The E2E workflow can also be triggered manually from the GitHub Actions
UI via the **Run workflow** button, which exposes the same set of input
variables.

---

## Packit / Testing Farm: `/packit test`

Packit runs TMT test plans on Testing Farm VMs across multiple
distributions and architectures. Packit jobs are triggered automatically
on pull requests but can be retriggered or customized via PR comments.

**Note:** Packit support requires a `.packit.yaml` in the repository
(see PR #25).

### Job Identifiers

| Identifier | Plan | Targets |
|---|---|---|
| `rpm-e2e-fedora` | `rpm-e2e` | Fedora latest-stable, latest, rawhide (x86_64 + aarch64) |
| `rpm-e2e-centos` | `rpm-e2e` | CentOS Stream 9, 10 (x86_64 + aarch64) |
| `e2e-fedora` | `e2e` | Fedora latest-stable, latest, rawhide (x86_64 + aarch64) |
| `e2e-centos` | `e2e` | CentOS Stream 9, 10 (x86_64 + aarch64) |
| `bootc-e2e-fedora` | `bootc-e2e` | Fedora latest-stable (x86_64 + aarch64) |
| `bootc-onboarding-fedora` | `bootc-onboarding` | Fedora latest-stable (x86_64 + aarch64) |

### Examples

**Retrigger all Packit test jobs:**

```
/packit test
```

**Retrigger only failed jobs:**

```
/packit retest-failed
```

**Retrigger a specific job by identifier:**

```
/packit test --identifier rpm-e2e-fedora
```

**Retrigger multiple jobs by label:**

```
/packit test --labels rpm,fedora
```

**Pass custom environment variables to Testing Farm:**

```
/packit test --env INSTALLATION_SOURCE=copr --env DEBUG=1
```

**Retrigger a specific job with custom variables:**

```
/packit test --identifier e2e-fedora --env INSTALLATION_SOURCE=compose
```

**Test with a specific server PR in Fedora RPM tests:**

```
/packit test --identifier rpm-e2e-fedora --env SERVER_REF=refs/pull/42/head
```

**Test with both a server and client PR in Fedora E2E tests:**

```
/packit test --identifier e2e-fedora --env SERVER_REF=refs/pull/42/head --env CLIENT_REF=refs/pull/99/head
```

**Coordinated test in Fedora bootc E2E tests with custom refs:**

```
/packit test --identifier bootc-e2e-fedora --env SERVER_REF=refs/pull/42/head --env CLIENT_REF=refs/pull/99/head
```

**Run CentOS Stream RPM tests with packages from the distro repos:**

```
/packit test --identifier rpm-e2e-centos --env INSTALLATION_SOURCE=distro
```

For the full Packit retriggering reference, see
https://packit.dev/docs/retriggering.

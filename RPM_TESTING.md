# Testing with RPM Installation Sources

The RPM test layer supports multiple installation sources for both client and
server packages. The source is selected via environment variables, defaulting
to `source` (build RPMs from the current commit).

## Installation Source Selection

Three environment variables control where RPMs come from:

| Variable                       | Description                          | Default    |
|--------------------------------|--------------------------------------|------------|
| `INSTALLATION_SOURCE`          | Default source for both components   | `source`   |
| `CLIENT_INSTALLATION_SOURCE`   | Override source for go-fdo-client    | `$INSTALLATION_SOURCE` |
| `SERVER_INSTALLATION_SOURCE`   | Override source for go-fdo-server    | `$INSTALLATION_SOURCE` |

## Available Sources

### `source` — Build from Git

Clones the source repositories and builds RPMs with `make rpm`. If the
currently checked-out commit is already installed, the build is skipped.

```bash
# Default — both client and server built from source
test/rpm/test-onboarding.sh
```

### `distro` — Install from Distribution Repos

Installs packages directly from the system's configured DNF repositories
(e.g. Fedora, CentOS Stream).

```bash
INSTALLATION_SOURCE=distro test/rpm/test-onboarding.sh
```

### `copr` — Install from a Copr Repository

Enables a Copr repository, installs packages from it, then removes the repo.
The repository is controlled by the `COPR_REPO` environment variable.

| Variable          | Description                            | Default                    |
|-------------------|----------------------------------------|----------------------------|
| `COPR_REPO`       | Default Copr project for both components | `@fedora-iot/fedora-iot`   |
| `CLIENT_COPR_REPO`| Override Copr project for go-fdo-client  | `$COPR_REPO`              |
| `SERVER_COPR_REPO`| Override Copr project for go-fdo-server  | `$COPR_REPO`              |

The `COPR_REPO` value supports two formats:

- **1 slash** — Fedora Copr: `owner/project` (e.g. `@fedora-iot/fedora-iot`)
- **2 slashes** — Custom hub: `hub/owner/project` (e.g. `copr.example.com/@group/project`)

```bash
# Install from the default Copr
INSTALLATION_SOURCE=copr test/rpm/test-onboarding.sh

# Install from a specific Copr project
INSTALLATION_SOURCE=copr COPR_REPO=@myorg/myrepo test/rpm/test-onboarding.sh
```

### `compose` — Install from a Compose Repository

Installs packages from a distribution compose tree. Automatically detects
the OS (Fedora, CentOS Stream, RHEL) and constructs the appropriate
repository URLs.

| Variable            | Description                               | Default (varies by OS)           |
|---------------------|-------------------------------------------|----------------------------------|
| `COMPOSE_BASE_URL`  | Base URL of the compose tree              | Auto-detected for Fedora/CentOS  |
| `COMPOSE_STREAMS`   | Space-separated list of repo streams      | `Everything` (Fedora), `BaseOS AppStream` (CentOS/RHEL) |

```bash
# Install from the latest Fedora compose
INSTALLATION_SOURCE=compose test/rpm/test-onboarding.sh

# Install from a specific RHEL compose
INSTALLATION_SOURCE=compose \
  COMPOSE_BASE_URL=http://download.host/.../latest-RHEL-Compose/compose/ \
  test/rpm/test-onboarding.sh
```

**Note:** `COMPOSE_BASE_URL` is required for RHEL — there is no auto-detected
default.

### Brew — Install from Brew Builds

Brew installation is selected via dedicated URL variables, not through
`INSTALLATION_SOURCE`. When set, these take precedence over all other sources.

| Variable               | Description                                     |
|------------------------|-------------------------------------------------|
| `BREW_CLIENT_RPMS_URL` | Brew build base URL for go-fdo-client            |
| `BREW_SERVER_RPMS_URL` | Brew build base URL for go-fdo-server            |

The URL should point to the version/release directory of the package in Brew.

```bash
BREW_SERVER_RPMS_URL=https://brewhost/packages/go-fdo-server/1.0.1/2.el10 \
  test/rpm/test-onboarding.sh
```

## Mixing Sources

Client and server can use different installation sources:

```bash
# Server from source, client from distro
SERVER_INSTALLATION_SOURCE=source \
  CLIENT_INSTALLATION_SOURCE=distro \
  test/rpm/test-onboarding.sh

# Server from Brew, client from Copr
BREW_SERVER_RPMS_URL=https://brewhost/packages/go-fdo-server/1.0.1/2.el10 \
  CLIENT_INSTALLATION_SOURCE=copr \
  test/rpm/test-onboarding.sh
```

## CI (Packit) Variables

When tests run in Packit/TMT, the following variables are set automatically
and take precedence over `INSTALLATION_SOURCE`:

| Variable           | Description                                              |
|--------------------|----------------------------------------------------------|
| `PACKIT_COPR_RPMS` | Space-separated list of RPMs built by Packit             |
| `PACKIT_COPR_PROJECT` | Copr repository where Packit published the build         |

## Priority Order

The installation logic picks the first matching condition:

1. `BREW_CLIENT_RPMS_URL` / `BREW_SERVER_RPMS_URL` (if set)
2. `PACKIT_COPR_RPMS` + `PACKIT_COPR_PROJECT` (if both set, CI environment)
3. `CLIENT_INSTALLATION_SOURCE` / `SERVER_INSTALLATION_SOURCE` (local/manual runs)

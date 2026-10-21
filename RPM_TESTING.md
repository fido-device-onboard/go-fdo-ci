# Testing with RPM Installation Sources

The RPM test layer supports multiple installation sources for both client and
server packages. The source is selected via environment variables, defaulting
to `source` (build RPMs from the current commit).

## Installation Source Selection

Three environment variables control where RPMs come from:

| Variable                       | Description                          | Default    |
|--------------------------------|--------------------------------------|------------|
| `INSTALLATION_SOURCE`          | Default source for both components   | `source`   |
| `CLIENT_INSTALLATION_SOURCE`   | Override source for `go-fdo-client`    | `$INSTALLATION_SOURCE` |
| `SERVER_INSTALLATION_SOURCE`   | Override source for `go-fdo-server`    | `$INSTALLATION_SOURCE` |

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
| `CLIENT_COPR_REPO`| Override Copr project for `go-fdo-client`  | `$COPR_REPO`              |
| `SERVER_COPR_REPO`| Override Copr project for `go-fdo-server`  | `$COPR_REPO`              |
| `COPR_CHROOT`     | Chroot to enable (`NAME-RELEASE-ARCH`)   | `centos-stream-$VERSION_ID-$(uname -m)` on CentOS Stream, auto-detected by dnf elsewhere |

The `COPR_REPO` value supports two formats:

- **1 slash** — Fedora Copr: `owner/project` (e.g. `@fedora-iot/fedora-iot`)
- **2 slashes** — Custom hub: `hub/owner/project` (e.g. `copr.example.com/@group/project`)

On CentOS Stream the chroot has to be named explicitly: dnf's autodetection
derives `centos-$VERSION_ID` from `/etc/os-release` and therefore misses the
`centos-stream-*` chroots the packages are built for. Set `COPR_CHROOT` to
override the chroot for any system. `test/rpm/test-copr-chroot.sh` guards
this behaviour.

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
| `BREW_CLIENT_RPMS_URL` | Brew build base URL for `go-fdo-client`            |
| `BREW_SERVER_RPMS_URL` | Brew build base URL for `go-fdo-server`            |

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

Product-PR jobs can provide the following variables to identify RPMs
built by Packit. When both variables are set, the RPM helpers use their
artifact-selection logic before consulting `INSTALLATION_SOURCE`.

Tests-only jobs in `go-fdo-ci` use `skip_build: true` and do not supply
product RPM artifacts. These jobs explicitly set
`INSTALLATION_SOURCE=copr` so the RPM helpers install published
packages.

| Variable           | Description                                              |
|--------------------|----------------------------------------------------------|
| `PACKIT_COPR_RPMS` | Space-separated list of RPMs built by Packit             |
| `PACKIT_COPR_PROJECT` | Copr repository where Packit published the build         |

For product-PR runs, the helpers install the component represented by
the Packit artifacts from its PR Copr project. The other component is
installed from its configured Copr repository.

## Priority Order

The installation logic picks the first matching condition:

1. `BREW_CLIENT_RPMS_URL` / `BREW_SERVER_RPMS_URL` (if set)
2. `PACKIT_COPR_RPMS` + `PACKIT_COPR_PROJECT` (if both set, CI environment)
3. `CLIENT_INSTALLATION_SOURCE` / `SERVER_INSTALLATION_SOURCE`
   (including tests-only runs without Packit product artifacts)

## Compose Availability

Selecting `compose` requires the chosen compose to contain the
requested FDO packages. It does not fall back to Copr when a package
is missing.

The CentOS Stream 9 compose used in the reviewed CI runs did not
provide `go-fdo-client`, so RPM tests using
`INSTALLATION_SOURCE=compose` failed during client installation.
Use the published Copr source for the CS9 tests-only configuration.

A compose-mode failure does not establish that the default
Copr-mode job fails; check the environment recorded in the run's
Testing Farm artifacts.

## Bootc Installation Sources

The bootc test layer supports the same installation sources and
environment variables as the RPM layer for both client and server
packages.

**Server installation** is handled by `install_server` from
`test/rpm/utils.sh` on the host system, following the priority order
and source selection described above.

**Client installation** occurs inside the bootc container image build
and follows the same priority order:

1. `BREW_CLIENT_RPMS_URL` (if set) — install from the specified Brew
   build
2. `PACKIT_COPR_RPMS` + `PACKIT_COPR_PROJECT` (if both set) — install
   the PR's Copr artifacts when the list contains `go-fdo-client`;
   otherwise use the default `client_copr_repo`
3. `CLIENT_INSTALLATION_SOURCE` — one of `source`, `distro`, `copr`,
   or `compose`

### Source Mode in Bootc

When `CLIENT_INSTALLATION_SOURCE=source`, the client RPMs are built
on the host system (where golang and rpm-build tools are available)
and then copied into the bootc image via `COPY` instructions. This
keeps the image size down by avoiding the installation of the entire
build toolchain inside the container.

The host and bootc base image must be the same distribution and
version (e.g., `fedora-43` host → `fedora-bootc:43` base image).
This requirement is already satisfied by the bootc test environment.

### Copr Chroot Selection

On CentOS Stream, the bootc client builder explicitly specifies the
`centos-stream-$VERSION_ID-$(uname -m)` chroot when enabling Copr
repositories (using `copr_chroot_for_system` from
`test/rpm/utils.sh`), matching the behavior of the RPM layer and
avoiding the dnf plugin's autodetection, which would incorrectly
select `centos-$VERSION_ID` or `epel-*` chroots.

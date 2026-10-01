# Development Guide

## CI Test Structure

The integration tests verify the FIDO Device Onboard (FDO) workflow across
different execution environments. They are organized into layers, where each
layer sources the one below it and selectively replaces shell functions to
adapt the same test logic to a different runtime.

```
test/
├── utils/              Shared libraries (certs, management API)
│   ├── certs.sh           Certificate generation helpers
│   ├── mgmt-api-v1.sh    REST helpers for the v1 management API
│   └── mgmt-api-v2.sh    REST helpers for the v2 management API
│
├── ci/                 Base layer – builds from source, runs as local processes
│   ├── utils.sh           Variables, service lifecycle, build/install helpers
│   ├── test-onboarding.sh Base onboarding test (run_test + cleanup)
│   ├── test-resale.sh     Resale protocol test (adds a new_owner service)
│   ├── test-fsim-*.sh     FSIM tests (download, upload, command, wget, config)
│   ├── test-onboarding-config.sh  Onboarding via config files instead of CLI flags
│   └── test-*-v2.sh       v2-API variants of each test
│
├── container/          Container layer – overrides CI functions to use Docker Compose
│   ├── utils.sh           Replaces build, start, stop, curl, logs with docker compose
│   ├── compose/           Docker Compose files
│   └── test-*.sh          Thin wrappers that source ci/test-*.sh then container/utils.sh
│
├── rpm/                RPM layer – overrides CI functions to use systemd services
│   ├── utils.sh           Replaces build, start, stop with dnf install + systemctl
│   └── test-*.sh          Thin wrappers that source ci/test-*.sh then rpm/utils.sh
│
├── bootc/              Bootc layer – extends RPM for bootable-container VM testing
│   ├── utils.sh           Adds VM provisioning, ISO generation, SSH-based onboarding
│   └── test-*.sh          Sources rpm/utils.sh then adds bootc-specific overrides
│
├── fmf/                FMF layer – standalone tests for Fedora CI (TMT/Testing Farm)
│   ├── utils.sh           Standalone helper library for FMF environment
│   └── tests/             Self-contained test scripts for Packit/TMT
│
└── scripts/            Miscellaneous scripts (coverage, etc.)
```

### Layer Relationships

Each layer reuses the test logic from `test/ci/` and only replaces the
functions that differ in its environment:

| Layer       | Builds binaries via | Starts services via       | Runs client via               |
|-------------|---------------------|---------------------------|-------------------------------|
| `ci`        | `go build` + `make` | `nohup` (local processes) | Local binary in `$bin_dir`    |
| `container` | `docker compose build` | `docker compose up`    | `docker compose run`          |
| `rpm`       | `dnf install` / `make rpm` | `systemctl start`  | `/usr/bin/go-fdo-client`      |
| `bootc`     | `podman build` + bootc-image-builder | `systemctl start` | SSH into VM          |


## Anatomy of `test/ci/test-onboarding.sh`

The base onboarding test exercises the full FDO device provisioning workflow.
It is defined in `run_test()` and follows these steps:

### 1. Error Trap

```bash
trap on_failure EXIT
```

Sets an EXIT trap so that if any command fails (`set -euo pipefail` is
active), `on_failure` is called. `on_failure` stops services and marks the
test as failed. At the end of the test the trap is cleared with
`trap - EXIT` to prevent `on_failure` from triggering on a successful run.

### 2. Environment / Directories

```bash
show_env
create_directories
```

Logs all environment variables for debugging, then creates the working
directory tree: `workdir/{bin,certs,device-credentials,logs,db}`.

### 3. Build and Install Binaries

```bash
install_client
install_server
```

Clones (if needed) and builds `go-fdo-client` and `go-fdo-server` from
source, installs the binaries into `$bin_dir`. The source paths can be
overridden with `CLIENT_LOCAL_PATH` and `SERVER_LOCAL_PATH` environment
variables; specific git refs can be checked out with `CLIENT_REF` and
`SERVER_REF`.

### 4. Generate Service Certificates

```bash
generate_service_certs
```

Iterates over `services` and generates an EC P-256 key pair + self-signed
certificate for each service that defines `${service}_key`,
`${service}_crt`, and `${service}_subj` variables. Also generates the
Device CA key and certificate.

### 5. Configure Services

```bash
configure_services
```

Generates HTTPS transport certificates (if any service uses `https`
protocol), then calls `configure_service_${service}` for each service in
the `services` array. If the function does not exist, the service is
silently skipped (for services that need no extra configuration). See
[Defining a New Service](#defining-a-new-service) below.

### 6. Start Services

```bash
start_services
```

Adds DNS entries to `/etc/hosts` for each service (mapping
`${service}_dns` to `${service}_ip`), then calls
`start_service_${service}` for each service. In the CI layer, each
service is started with `nohup` as a background process and its PID is
written to a file.

### 7. Wait for Health Checks

```bash
wait_for_services_ready
```

Polls the `${service}_health_url` endpoint (HTTP 200) for each service,
retrying up to 5 times with a 2-second interval.

### 8. Configure Rendezvous Info

```bash
set_or_update_rendezvous_info "${manufacturer_url}" "${rv_info}"
```

Tells the manufacturer server where the rendezvous server is. If
`RendezvousInfo` already exists it is updated (PUT); otherwise it is
created (POST).

### 9. Register Device CA

```bash
add_device_ca_cert "${rendezvous_url}" "${device_ca_crt}"
```

Uploads the Device CA certificate to the rendezvous server so it can
validate device credentials during TO1.

### 10. Device Initialization (DI / TO0)

```bash
guid=$(run_device_initialization)
```

Runs `go-fdo-client device-init` against the manufacturer server. This
creates a device credential blob and returns the device's GUID.

### 11. Configure Owner Redirect

```bash
set_or_update_rvto2addr "${owner_url}" ...
```

Tells the owner server its own redirect address, which the rendezvous
server will return to devices during TO1 so they know where to run TO2.

### 12. Transfer Ownership Voucher

```bash
send_manufacturer_ov_to_owner "${manufacturer_url}" "${guid}" "${owner_url}"
```

Downloads the ownership voucher from the manufacturer and uploads it to
the owner. Then waits `$to0_wait_seconds` for the owner to register the
voucher with the rendezvous server (TO0).

### 13. Device Onboarding (TO1 + TO2)

```bash
run_fido_device_onboard "${guid}" --debug
```

Runs `go-fdo-client onboard`. The client contacts the rendezvous server
(TO1), gets redirected to the owner, and completes onboarding (TO2). The
test validates success by looking for "FIDO Device Onboard Complete" in
the log output.

### 14. Cleanup

```bash
trap - EXIT
test_pass
```

Clears the error trap and marks the test as passed. At the bottom of the
file, `cleanup` is called after `run_test` — it stops services, removes
`/etc/hosts` entries, uninstalls binaries, and deletes the working
directory.


## Service Lifecycle

Services are managed through a convention-based dispatch system built around
the `services` array and dynamically resolved function names.

### The `services` Array

Declared in `test/ci/utils.sh`:

```bash
declare -a services=("manufacturer" "rendezvous" "owner")
```

Every lifecycle operation iterates over this array and dispatches to a
function named `${operation}_${service_name}`.

### Variables per Service

Each service in the array requires a set of shell variables following a
naming convention. Taking `manufacturer` as an example:

| Variable                      | Purpose                                      |
|-------------------------------|----------------------------------------------|
| `manufacturer_service_name`   | Canonical name (used as key for lookups)      |
| `manufacturer_dns`            | DNS hostname (added to `/etc/hosts`)          |
| `manufacturer_ip`             | IP address (bound in `/etc/hosts`)            |
| `manufacturer_port`           | Listening port                                |
| `manufacturer_pid_file`       | Path to PID file (CI layer only)              |
| `manufacturer_log`            | Path to log file                              |
| `manufacturer_key`            | Path to service private key                   |
| `manufacturer_crt`            | Path to service certificate                   |
| `manufacturer_subj`           | Certificate subject (for generation)          |
| `manufacturer_service`        | `"${dns}:${port}"` — address string           |
| `manufacturer_protocol`       | `http` or `https`                             |
| `manufacturer_url`            | Full base URL                                 |
| `manufacturer_health_url`     | Health check endpoint URL                     |
| `manufacturer_db_type`        | Database type (e.g. `sqlite`)                 |
| `manufacturer_db_dsn`         | Database connection string                    |

### Dispatch Functions

The lifecycle functions use Bash indirect variable expansion (`${!var}`)
and `declare -F` to dynamically resolve and call per-service functions:

**`configure_service()`** — calls `configure_service_${service}` if it exists:

```bash
configure_service() {
  local service=$1
  local configure_service="configure_service_${service}"
  ! declare -F "${configure_service}" >/dev/null || ${configure_service}
}
```

**`start_service()`** — calls `start_service_${service}` if it exists:

```bash
start_service() {
  local service=$1
  local start_service="start_service_${service}"
  ! declare -F "${start_service}" >/dev/null || ${start_service}
}
```

**`stop_service()`** — kills the process whose PID is stored in
`${service}_pid_file`:

```bash
stop_service() {
  local service=$1
  local service_pid_file="${service}_pid_file"
  if [[ -v "${service_pid_file}" ]] && [[ -f "${!service_pid_file}" ]]; then
    pkill -F "${!service_pid_file}" && wait "$(cat "${!service_pid_file}")" 2>/dev/null || :
  fi
}
```


## Defining a New Service

To add a service (e.g. `new_owner` in the resale test), follow these steps:

### 1. Declare Service Variables

Define all the required variables using the naming convention
`${service_name}_*`:

```bash
new_owner_service_name=new_owner
new_owner_dns=new_owner
new_owner_ip=127.0.0.1
new_owner_port=8045
new_owner_pid_file="${pid_dir}/new_owner.pid"
new_owner_log="${logs_dir}/${new_owner_dns}.log"
new_owner_key="${certs_dir}/new_owner.key"
new_owner_crt="${new_owner_key/\.key/.crt}"
new_owner_subj="/C=US/O=FDO/CN=New Owner"
new_owner_service="${new_owner_dns}:${new_owner_port}"
new_owner_protocol="http"
new_owner_url="${new_owner_protocol}://${new_owner_service}"
new_owner_health_url="${new_owner_url}/health"
new_owner_db_type="sqlite"
new_owner_db_dsn="file:${db_dir}/${new_owner_service_name}.db"
```

### 2. Define the Start Function

Write a `start_service_${service_name}` function:

```bash
start_service_new_owner() {
  run_go_fdo_server owner "${new_owner_service}" \
    "${new_owner_db_type}" "${new_owner_db_dsn}" \
    "${new_owner_pid_file}" "${new_owner_log}" \
    --owner-key="${new_owner_key}" \
    --device-ca-cert="${device_ca_crt}"
}
```

### 3. (Optional) Define a Configure Function

If the service needs configuration beyond CLI flags (e.g. writing a YAML
config file), define `configure_service_${service_name}`:

```bash
configure_service_new_owner() {
  cat >"${new_owner_config_file}" <<EOF
log:
  level: "debug"
...
EOF
}
```

### 4. Add to the Services Array

Append the service name to the `services` array before `run_test`
(or at the top of `run_test`):

```bash
services+=("${new_owner_service_name}")
```

This is all that is needed. The existing `configure_services`,
`start_services`, `stop_services`, `wait_for_services_ready`,
`generate_service_certs`, `set_hostnames`, and `unset_hostnames` functions
will automatically pick up the new service by iterating over the array and
resolving its variables and functions by name.


## Function Replacement Across Layers

The test framework uses Bash's function redefinition semantics to adapt the
same test logic to different environments. In Bash, when a function is
defined more than once, the last definition wins. The layers exploit this
by controlling the order of `source` statements.

### How It Works

Consider `test/container/test-onboarding.sh`:

```bash
source ".../ci/test-onboarding.sh"     # (1) loads ci/utils.sh, defines run_test
source ".../container/utils.sh"         # (2) redefines functions from ci/utils.sh
```

After step (1), all CI functions are defined — `install_client`,
`install_server`, `start_services`, `stop_services`, `run_go_fdo_client`,
`curl`, etc.

After step (2), the container layer's `utils.sh` redefines a subset of
those functions. For example:

| Function           | CI (`ci/utils.sh`)                       | Container (`container/utils.sh`)                |
|--------------------|------------------------------------------|-------------------------------------------------|
| `install_client`   | `go build` + `install` binary            | `docker compose build`                          |
| `install_server`   | `go build` + `install` binary            | `docker compose build`                          |
| `start_services`   | `set_hostnames` + `nohup` per service    | `docker compose up -d`                          |
| `stop_services`    | `pkill -F` per PID file                  | `docker compose stop`                           |
| `run_go_fdo_client`| Run local binary with `timeout`          | `docker compose run` with path translation      |
| `curl`             | System curl                              | `docker run curlimages/curl` on the `fdo` network|
| `get_real_ip`      | Return `${service}_ip` variable          | `docker inspect` for container IP               |
| `on_failure`       | Stop services + fail                     | Save logs + stop services + fail                |

The `run_test()` function itself is **not** redefined — it remains exactly
as defined in `ci/test-onboarding.sh`. The same sequence of high-level
steps runs in every layer; only the underlying operations change.

### The Same Pattern in RPM and Bootc Layers

**`test/rpm/test-onboarding.sh`:**

```bash
source ".../ci/test-onboarding.sh"   # loads ci/utils.sh + run_test
source ".../rpm/utils.sh"            # replaces install/start/stop with dnf/systemctl
```

The RPM layer replaces `install_client`/`install_server` with `dnf install`,
`start_service_*` with `systemctl start`, and `stop_service` with
`systemctl stop`. It also adds RPM-specific features like systemd drop-in
configuration, SELinux AVC collection, and log retrieval via `journalctl`.

**`test/bootc/utils.sh`:**

```bash
source ".../rpm/utils.sh"            # inherits RPM layer
# then overrides further...
```

The bootc layer inherits everything from the RPM layer and additionally
replaces `install_client` (builds a bootc container image and generates
a kickstart ISO), `run_device_initialization` (provisions a VM via
`virt-install`), and `run_fido_device_onboard` (runs onboarding over SSH
inside the VM). It also adds new services like `firewalld` and `libvirtd`
to the `services` array, with their own `configure_service_*` functions.

### The `test-onboarding-config.sh` Pattern

Some tests need to override how services are started without changing the
execution layer. `test/ci/test-onboarding-config.sh` sources
`test-onboarding.sh` (getting all CI functions and `run_test`) and then
redefines `configure_service_*` and `start_service_*` functions to use
YAML configuration files instead of CLI flags. This is a within-layer
override — same runtime, different server configuration method.

Tests like `test-fsim-config.sh` and `test-fsim-download.sh` further
chain this pattern:

```
ci/utils.sh
  └─ ci/test-onboarding.sh          defines run_test (generic)
       └─ ci/test-onboarding-config.sh  overrides to use config files
            └─ ci/test-fsim-config.sh     overrides configure_service_owner
                 └─ ci/test-fsim-download.sh  overrides run_test with FSIM-specific steps
```

Each file in the chain only redefines the functions it needs to change,
inheriting everything else from the files above it.

### Key Principle

The pattern works because:

1. **`run_test` calls functions by name**, not inline code. Each step is a
   function call that can be independently replaced.
2. **The last `source` wins.** Sourcing a file that redefines a function
   silently replaces the previous definition.
3. **Undeclared dispatch functions are safe.** The `declare -F` guard
   (`! declare -F "func" >/dev/null || func`) means that optional
   per-service functions (like `configure_service_*`) simply do nothing if
   not defined.

---
name: debug-test-failure
description: Debug FDO integration test failures across CI layers (CI, container, RPM, bootc). Use this skill whenever the user reports a test failure, CI pipeline error, flaky test, test timeout, onboarding failure, service startup issue, or any problem running the FDO test suite. Also use when the user asks why a test is failing, wants to investigate a Packit/TMT failure, or needs help understanding test logs or error output.
---

# Debugging FDO Test Failures

This framework uses layered Bash function overrides, so the same `run_test()` runs in very different environments. The first step is always: identify which layer is running, because that determines where logs live, how services start, and what can go wrong.

## Step 1: Identify the Layer

The test script name and path tell you the layer:

| Path prefix | Layer | Services run as | Client runs as |
|---|---|---|---|
| `test/ci/` | CI (native) | `nohup` local processes | Local binary |
| `test/container/` | Container | `docker compose up` | `docker compose run` |
| `test/rpm/` | RPM | `systemctl` | `/usr/bin/go-fdo-client` |
| `test/bootc/` | Bootc | `systemctl` (in VM) | SSH into VM |
| `test/fmf/tests/` | FMF (Packit/TMT) | Varies by plan | Varies by plan |

For FMF tests, check the plan file in `test/fmf/plans/` to see which layer it targets.

## Step 2: Find the Logs

Each layer stores logs differently:

**CI layer**: Log files in `${logs_dir}` (typically `workdir/logs/`):
- `${service_dns}.log` per service (e.g., `manufacturer.log`, `rendezvous.log`, `owner.log`)
- Client output on stdout/stderr of the test script itself

**Container layer**: Docker compose logs:
- `docker compose logs --no-log-prefix <service>`
- On failure, logs are saved to `${logs_dir}/` by `on_failure()`

**RPM layer**: Systemd journal:
- `journalctl -u go-fdo-server-${service} --no-pager` (e.g., `go-fdo-server-manufacturer`)
- SELinux denials: `ausearch -m AVC -ts recent` (collected automatically by `collect_avcs()`)

**Bootc layer**: Same as RPM but inside the VM — access via SSH.

**GitHub Actions**: Look in the "get_logs" step (runs on failure) and the test step's stdout.

## Step 3: Common Failure Patterns

### Service Startup Failures

**Symptom**: `wait_for_services_ready` fails — health check URL returns non-200 or times out (5 retries x 2s = 10s max).

**Diagnosis**:
1. Check the service log file for startup errors
2. Verify the port isn't already in use: `ss -tlnp | grep <port>`
3. For RPM: check `systemctl status go-fdo-server-<service>` and journal
4. For containers: check `docker compose ps` and `docker compose logs <service>`

**Common causes**:
- Certificate file not found or wrong format (DER vs PEM)
- Database path doesn't exist or permissions issue
- Port conflict with another test or service

### TO0 Timing Failures

**Symptom**: Device onboarding fails during TO1 with "not found" — the rendezvous server doesn't know about the device.

**Diagnosis**: After sending the ownership voucher to the owner, the framework waits `$to0_wait_seconds` (default: 10s) for the owner to register with the rendezvous server (TO0). If TO0 hasn't completed by then, onboarding fails.

**Fix**: Increase `to0_wait_seconds` or check why the owner is slow to register. Look for errors in the owner log during the TO0 phase.

### Certificate Mismatches

**Symptom**: TLS handshake errors, "x509: certificate signed by unknown authority", or device credential verification failures.

**Diagnosis**:
1. Verify the device CA cert was uploaded to the rendezvous server: check `add_device_ca_cert` API call
2. Verify each service's key/cert pair match: `openssl x509 -in cert.crt -noout -text`
3. For HTTPS tests: verify the HTTPS transport certs are PEM format (not DER)
4. Check that `_protocol` variables match what the service actually uses

### Client Timeout (Exit Code 124)

**Symptom**: `run_go_fdo_client` exits with code 124 after 300s.

**Diagnosis**: The client couldn't complete the FDO protocol in time. Check:
1. Is the rendezvous server reachable from the client?
2. Does the rendezvous server have the correct owner redirect info?
3. Is the owner service healthy?
4. For containers: check the Docker network is correct (`fdo` network)
5. For bootc: check SSH connectivity to the VM

### Container Path Translation

**Symptom**: File not found errors inside containers, or services can't read certs/configs.

**Diagnosis**: The container layer translates `${base_dir}` to `${container_working_dir}` (`/workdir`). If a test passes paths using the host's `base_dir`, they won't resolve inside the container.

**Fix**: Paths in config files and CLI arguments must use the container working directory. The container layer's `configure_services` handles this via `sed`, but custom configure functions may miss it.

### SELinux Denials (RPM Layer)

**Symptom**: Services fail to start or can't access files on Fedora/RHEL with SELinux enforcing.

**Diagnosis**: Check for AVC denials:
```bash
ausearch -m AVC -ts recent
```
The RPM layer's `on_failure()` automatically runs `collect_avcs()` and saves them.

**Fix**: Usually requires an SELinux policy module or correct file contexts. This is a packaging issue, not a test issue.

### Bootc VM Issues

**Symptom**: `virt-install` fails, SSH can't connect, or firewalld blocks FDO traffic.

**Diagnosis**:
1. Check libvirt is running: `systemctl status libvirtd`
2. Check the VM was created: `virsh list --all`
3. Check firewalld D-Bus readiness (recent fix: poll `busctl` for `org.fedoraproject.FirewallD1`)
4. Check SSH connectivity: the bootc layer polls for 300s (30 x 10s)
5. Check the VM console: `virsh console <vm-name>`

### RV Info Format Mismatch (V1 vs V2)

**Symptom**: API calls return 400 or services reject the rendezvous info.

**Diagnosis**: V1 and V2 use different JSON formats:
- V1: `[{"dns":"...", "device_port":"8041", ...}]` (ports are strings)
- V2: `[[{"dns":"..."}, {"device_port": 8041}, ...]]` (ports are integers, nested arrays)

Check which API version the test sources — if it sources `mgmt-api-v2.sh`, the `rv_info` variable is redefined to V2 format.

## Step 4: Trace the Function Override Chain

When a test behaves unexpectedly, trace which version of each function is active. The last `source` wins. Read the test script's source chain from top to bottom:

```bash
# In test/container/test-onboarding.sh:
source ".../ci/test-onboarding.sh"     # loads CI versions of everything
source ".../container/utils.sh"         # replaces install/start/stop/curl
# Now: run_test = CI version, install_client = container version
```

If you're unsure which function definition is active, add `declare -F <function_name>` or `type <function_name>` in the script temporarily — it shows where the function was last defined.

## Step 5: Reproduce Locally

**CI tests**: Run the script directly:
```bash
sudo bash test/ci/test-onboarding.sh
```
Needs root for `/etc/hosts` modifications. Needs Go toolchain and git.

**Container tests**: Need Docker/Podman and the compose files from `go-fdo-server`:
```bash
export COMPOSE_DIR=/path/to/go-fdo-server/deployments/compose
sudo bash test/container/test-onboarding.sh
```

**RPM tests**: Need the RPMs installed (from Packit COPR, brew, or `make rpm`).

**Bootc tests**: Need libvirt, bootc-image-builder, and a bootc container image.

## Debugging Checklist

1. Identify the layer from the test path
2. Find the logs for that layer
3. Check the error output — is it a startup failure, protocol failure, or timeout?
4. If protocol failure: check certs, RV info, and TO0 timing
5. If startup failure: check ports, file paths, and permissions
6. If timeout: check network connectivity between components
7. Trace the function override chain if behavior is unexpected
8. Check if the same test passes in the CI layer — layer-specific overrides may be the issue

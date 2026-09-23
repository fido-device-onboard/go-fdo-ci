#!/usr/bin/env bash
# Source-only package policy shared by host tests and generated bootc installers.
# Importing this file never installs packages or changes the caller's shell options.

fdo_package_names() {
  case "$1" in
    client) printf '%s\n' go-fdo-client ;;
    server) printf '%s\n' go-fdo-server go-fdo-server-manufacturer go-fdo-server-owner go-fdo-server-rendezvous ;;
    *) echo "Unknown FDO component: $1" >&2; return 1 ;;
  esac
}

# Packit supplies versioned RPM identifiers, not an installation wish list.
# Parse from the right so hyphens in package names cannot match another family.
fdo_packit_specs() {
  local component=$1 token spec name package names matched=0 seen=0
  local -a tokens=()
  names=$(fdo_package_names "$component") || return
  read -r -a tokens <<< "${PACKIT_COPR_RPMS:-}"
  for token in "${tokens[@]}"; do
    spec=${token##*/}
    spec=${spec%.rpm}
    name=${spec%.*}; name=${name%-*}; name=${name%-*}
    if [[ "$name" == "go-fdo-$component" || "$name" == "go-fdo-$component-"* ]]; then seen=1; fi
    while IFS= read -r package; do
      if [[ "$spec" == "$package" ]]; then
        echo "PACKIT_COPR_RPMS requires versioned artifacts, not '$package'" >&2
        return 1
      fi
      if [[ "$name" == "$package" && "$spec" =~ ^[a-zA-Z0-9_.+~^:-]+$ ]]; then
        case "${spec##*.}" in
          noarch|"$(uname -m)") printf '%s\n' "$spec"; matched=1 ;;
          *) ;;
        esac
      fi
    done <<< "$names"
  done
  if [[ $seen -eq 1 && $matched -eq 0 ]]; then
    echo "No $component PR artifact matches $(uname -m)" >&2
    return 1
  fi
}

# Prints source, project (for Copr), and optional build URL/source directory.
# An explicit source cannot silently supersede a product PR artifact.
fdo_resolve_source() {
  local component=$1 prefix source project brew directory specs legacy_directory root
  prefix="FDO_${component^^}"
  source="${prefix}_SOURCE"; source=${!source:-}
  project="${prefix}_COPR_PROJECT"; project=${!project:-@fedora-iot/fedora-iot}
  brew="BREW_${component^^}_RPMS_URL"; brew=${!brew:-}
  directory="${prefix}_SOURCE_DIR"; directory=${!directory:-}
  legacy_directory="${component^^}_LOCAL_PATH"
  directory=${directory:-${!legacy_directory:-}}
  specs=$(fdo_packit_specs "$component") || return
  if [[ -n "$specs" ]]; then
    if [[ -n "$source" && "$source" != packit ]]; then
      echo "Conflicting sources for $component: Packit artifacts and explicit override" >&2
      return 1
    fi
    source=packit
  elif [[ -z "$source" ]]; then
    if [[ -n "$brew" ]]; then source=brew
    elif [[ -n "$directory" ]]; then source=source
    elif [[ "$component" == server ]]; then
      # Preserve direct runs from a go-fdo-server checkout without new variables.
      root=$(git rev-parse --show-toplevel 2>/dev/null || true)
      if [[ -n "$root" && -f "$root/build/package/rpm/go-fdo-server.spec" ]]; then
        source=source; directory=$root
      else source=copr
      fi
    else source=copr
    fi
  fi
  case "$source" in
    packit)
      [[ -n "$specs" && -n "${PACKIT_COPR_PROJECT:-}" ]] || {
        echo "Missing $component artifacts or PACKIT_COPR_PROJECT" >&2; return 1;
      }
      project=$PACKIT_COPR_PROJECT ;;
    copr)
      [[ -z "$brew" && -z "$directory" ]] || { echo "Conflicting inputs for $component Copr source" >&2; return 1; } ;;
    brew)
      [[ -n "$brew" ]] || { echo "Brew source requires BREW_${component^^}_RPMS_URL" >&2; return 1; } ;;
    source)
      [[ -n "$directory" && -z "$brew" ]] || { echo "Source build requires only ${prefix}_SOURCE_DIR" >&2; return 1; } ;;
    *) echo "Unsupported $component source: $source" >&2; return 1 ;;
  esac
  printf '%s\n%s\n%s\n' "$source" "$project" "${brew:-$directory}"
}

fdo_as_root() {
  if [[ $EUID -eq 0 ]]; then "$@"; else sudo "$@"; fi
}

fdo_ensure_dnf_command() {
  local command=$1 provider=dnf
  dnf "$command" --help >/dev/null 2>&1 && return 0
  [[ "$(readlink -f "$(command -v dnf)")" != */dnf5 ]] || provider=dnf5
  fdo_as_root dnf install -y "${provider}-command(${command})"
}

fdo_verify_specs() {
  local spec name installed
  for spec in "$@"; do
    name=${spec%.*}; name=${name%-*}; name=${name%-*}
    installed=$(rpm -q --qf '%{NAME}-%{VERSION}-%{RELEASE}.%{ARCH}\n' "$name") || return
    [[ "$installed" == "$spec" ]] || {
      echo "Expected $spec, installed $installed" >&2; return 1;
    }
  done
}

fdo_require_complete_specs() {
  local component=$1 specs=$2 package spec name found names
  names=$(fdo_package_names "$component") || return
  while IFS= read -r package; do
    found=0
    while IFS= read -r spec; do
      name=${spec%.*}; name=${name%-*}; name=${name%-*}
      [[ "$name" != "$package" ]] || found=$((found + 1))
    done <<< "$specs"
    [[ $found -eq 1 ]] || {
      echo "Expected exactly one artifact for $package, found $found" >&2; return 1;
    }
  done <<< "$names"
}

fdo_brew_urls() {
  local base=${1%/} arch listing found=0
  for arch in "$(uname -m | sed 's/arm64/aarch64/')" noarch; do
    # Brew's internal servers can use self-signed certificates.
    # Some builds have no noarch directory. Accept either listing, but
    # fail if neither provides RPMs (never silently switch to Copr).
    listing=$(curl --fail --silent --insecure "$base/$arch/") || continue
    while IFS= read -r file; do
      [[ -n "$file" ]] || continue
      printf '%s/%s/%s\n' "$base" "$arch" "$file"
      found=1
    done < <(printf '%s\n' "$listing" | sed -n 's/.*>\([^<>]*\.rpm\)<.*/\1/p')
  done
  [[ $found -eq 1 ]] || { echo "No RPMs found at $base" >&2; return 1; }
}

# Use a subshell so repository/temp-file cleanup cannot replace test EXIT traps.
fdo_install_component() (
  set -euo pipefail
  local component=$1 resolved source project location names specs repo_id
  local temporary='' enabled=0 status package file file_name file_spec urls directory commit
  local -a packages=() requested=() files=() expected=() enable_args=()
  resolved=$(fdo_resolve_source "$component") || return
  source=$(sed -n '1p' <<< "$resolved")
  project=$(sed -n '2p' <<< "$resolved")
  location=$(sed -n '3p' <<< "$resolved")
  names=$(fdo_package_names "$component") || return
  mapfile -t packages <<< "$names"
  if [[ "$source" == packit ]]; then
    specs=$(fdo_packit_specs "$component") || return
    fdo_require_complete_specs "$component" "$specs" || return
    mapfile -t requested <<< "$specs"
    if fdo_verify_specs "${requested[@]}" 2>/dev/null; then
      printf 'Verified installed %s PR artifacts:\n%s\n' "$component" "$specs"
      return 0
    fi
  else
    requested=("${packages[@]}")
  fi
  if [[ "$source" == brew ]]; then
    urls=$(fdo_brew_urls "$location") || return
    mapfile -t files <<< "$urls"
    # Preserve the original Brew contract: install the complete URL list,
    # including companion subpackages, and let DNF fetch the RPMs.
    fdo_as_root dnf install -y --nogpgcheck --setopt=sslverify=false "${files[@]}" || return
    rpm -q "${packages[@]}" || return
    return 0
  fi
  temporary=$(mktemp -d) || return
  trap 'status=$?; if [[ $enabled -eq 1 ]]; then fdo_as_root dnf copr disable -y "$project" || status=1; fi; fdo_as_root rm -rf -- "$temporary"; exit "$status"' EXIT
  case "$source" in
    packit|copr)
      fdo_ensure_dnf_command copr || return
      fdo_ensure_dnf_command download || return
      # Explicitly enable even if the repository was left disabled by a prior test.
      enable_args=("$project")
      . /etc/os-release
      if [[ "$ID" == centos ]]; then enable_args+=("centos-stream-${VERSION_ID}"); fi
      enabled=1
      fdo_as_root dnf copr enable -y "${enable_args[@]}" || return
      repo_id="copr:copr.fedorainfracloud.org:${project/\//:}"
      repo_id=${repo_id/:@/:group_}
      # Select product RPMs only from this Copr. Resolve dependencies later
      # using normal distro repositories, rather than disabling them too.
      fdo_as_root dnf download --disablerepo='*' --enablerepo="$repo_id" --destdir="$temporary" "${requested[@]}" || return
      ;;
    source)
      directory=$(cd "$location" && pwd) || return
      commit=$(git -C "$directory" rev-parse --short HEAD) || return
      [[ -f "$directory/build/package/rpm/go-fdo-${component}.spec" ]] || {
        echo "Not a $component RPM source tree: $directory" >&2; return 1;
      }
      fdo_as_root dnf install -y golang make rpm-build || return
      fdo_ensure_dnf_command builddep || return
      fdo_as_root dnf builddep -y "$directory/build/package/rpm/go-fdo-${component}.spec" || return
      make -C "$directory" rpm || return
      # Preserve the existing committed-source RPM contract. Ignore stale RPMs.
      while IFS= read -r file; do cp "$file" "$temporary/" || return; done < <(
        find "$directory/rpmbuild/rpms" -type f -name "*git${commit}*.rpm"
      )
      ;;
  esac
  shopt -s nullglob
  for file in "$temporary"/*.rpm; do
    file_name=$(rpm -qp --qf '%{NAME}' "$file") || return
    for package in "${packages[@]}"; do
      [[ "$file_name" == "$package" ]] || continue
      file_spec=$(rpm -qp --qf '%{NAME}-%{VERSION}-%{RELEASE}.%{ARCH}' "$file") || return
      case "${file_spec##*.}" in noarch|"$(uname -m)") ;; *) continue ;; esac
      files+=("$file"); expected+=("$file_spec")
    done
  done
  specs=$(printf '%s\n' "${expected[@]}")
  fdo_require_complete_specs "$component" "$specs" || return
  if [[ "$source" == packit ]]; then
    for file_spec in "${expected[@]}"; do
      printf '%s\n' "${requested[@]}" | grep -Fx -- "$file_spec" >/dev/null || {
        echo "Downloaded unexpected PR artifact: $file_spec" >&2; return 1;
      }
    done
  fi
  local -a options=(--disablerepo=testing-farm-tag-repository)
  fdo_as_root dnf install -y "${options[@]}" "${files[@]}" || return
  fdo_verify_specs "${expected[@]}" || return
  printf 'Installed %s from %s:\n%s\n' "$component" "$source" "$specs"
)

# Generate a self-contained installer in the build context. The same resolver
# and verifier run inside the image, whose RPM database differs from the host's.
fdo_write_client_installer() {
  local output=$1 resolved source variable urls
  resolved=$(fdo_resolve_source client) || return
  source=${resolved%%$'\n'*}
  [[ "$source" != source ]] || {
    echo 'Source-directory installation is not supported inside bootc images; use Brew or Copr RPMs' >&2
    return 1
  }
  if [[ "$source" == brew ]]; then
    # Resolve the listing on the host as before: the image need not contain
    # curl or have access to Brew directory indexes.
    urls=$(fdo_brew_urls "${BREW_CLIENT_RPMS_URL}") || return
    local -a rpms=()
    mapfile -t rpms <<< "$urls"
    {
      printf '#!/usr/bin/env bash\nset -euo pipefail\n'
      printf 'dnf install -y --nogpgcheck --setopt=sslverify=false'
      printf ' %q' "${rpms[@]}"
      printf '\nrpm -q go-fdo-client\n'
    } > "$output"
    return 0
  fi
  {
    printf '#!/usr/bin/env bash\nset -euo pipefail\n'
    for variable in PACKIT_COPR_RPMS PACKIT_COPR_PROJECT FDO_CLIENT_SOURCE FDO_CLIENT_COPR_PROJECT BREW_CLIENT_RPMS_URL; do
      printf 'export %s=%q\n' "$variable" "${!variable:-}"
    done
    cat "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/packages.sh"
    printf '\nfdo_install_component client\n'
  } > "$output"
}

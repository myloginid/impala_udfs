#!/usr/bin/env bash
set -euo pipefail

# Build RHEL7-compatible UDF .so using a container (podman or docker).
# Output: dist/rhel7/libaes_udf-rhel7.so

RUNTIME=${RUNTIME:-}
# Prefer Docker on CI runners; fall back to Podman if Docker missing.
if command -v docker >/dev/null 2>&1; then
  RUNTIME=${RUNTIME:-docker}
elif command -v podman >/dev/null 2>&1; then
  RUNTIME=${RUNTIME:-podman}
else
  echo "No container runtime found (docker or podman)." >&2
  exit 2
fi

# CentOS 7 provides an RHEL7-compatible userspace and OpenSSL 1.0.2.
# Prefer Quay mirror for reliability on CI runners.
IMAGE=${IMAGE:-quay.io/centos/centos:7}
ARCH=${ARCH:-amd64}

# Map ARCH to runtime-specific flag
RUNTIME_PLATFORM_ARG=""
case "${RUNTIME}" in
  podman)
    RUNTIME_PLATFORM_ARG="--arch ${ARCH}"
    ;;
  docker)
    case "${ARCH}" in
      amd64|x86_64) RUNTIME_PLATFORM_ARG="--platform linux/amd64" ;;
      arm64|aarch64) RUNTIME_PLATFORM_ARG="--platform linux/arm64" ;;
      *) RUNTIME_PLATFORM_ARG="" ;;
    esac
    ;;
esac

# Volume mount
VOLUME_MOUNT="${PWD}:/work"
# Only add :Z label when using podman on SELinux hosts (and not on GitHub Actions)
if [ "${RUNTIME}" = "podman" ] && [ "${GITHUB_ACTIONS:-false}" != "true" ]; then
  if [ -f /sys/fs/selinux/enforce ] && grep -q "^1$" /sys/fs/selinux/enforce 2>/dev/null; then
    VOLUME_MOUNT="${VOLUME_MOUNT}:Z"
  fi
fi

set -x
# Ensure target directory exists on host before build to avoid any mount-sync quirks
mkdir -p dist/rhel7

# Build in a named container so we can docker/podman cp the artifact back
CONTAINER_NAME="aes-udf-rhel7-$$"
# Clean any stale container with same name
${RUNTIME} rm -f "${CONTAINER_NAME}" >/dev/null 2>&1 || true

RUN_RC=0
${RUNTIME} run --pull=always --name "${CONTAINER_NAME}" ${RUNTIME_PLATFORM_ARG} \
  -v "${VOLUME_MOUNT}" -w /work \
  ${IMAGE} \
  /bin/sh -lc "\
    set -euo pipefail; \
    if [ -d /etc/yum.repos.d ]; then \
      for f in /etc/yum.repos.d/*.repo; do \
        sed -i -e 's/^mirrorlist=/#mirrorlist=/' \
               -e 's|^#baseurl=http://mirror.centos.org|baseurl=https://vault.centos.org|' \$f || true; \
      done; \
    fi; \
    yum -y install gcc-c++ make openssl-devel boost-devel curl; \
    mkdir -p /usr/include/impala_udf; \
    curl -fsSL https://raw.githubusercontent.com/apache/impala/master/be/src/udf/udf.h -o /usr/include/impala_udf/udf.h; \
    echo 'Inside container uid/gid:'; id; whoami; \
    echo 'Workspace mount:'; mount | grep ' /work ' || true; \
    echo 'Before build, dist listing:'; ls -la dist || true; ls -la dist/rhel7 || true; \
    make -B rhel7 V=1 IMPALA_UDF_INCLUDE_ROOT=/usr/include; \
    echo '__CONTAINER_POST_BUILD__'; ls -la dist; ls -la dist/rhel7; \
    (sha256sum dist/rhel7/libaes_udf-rhel7.so || true); \
    sync; \
    echo 'probe' > dist/rhel7/_probe_container \
  " || RUN_RC=$?

if [[ ${RUN_RC} -ne 0 ]]; then
  echo "Container build exited with code ${RUN_RC}" >&2
  ${RUNTIME} logs "${CONTAINER_NAME}" || true
fi

# If host doesn't see the artifact, try copying it from the container
if [[ ! -f dist/rhel7/libaes_udf-rhel7.so ]]; then
  echo "Attempting to copy artifact from container filesystem..."
  ${RUNTIME} cp "${CONTAINER_NAME}:/work/dist/rhel7/libaes_udf-rhel7.so" dist/rhel7/ || true
  ${RUNTIME} cp "${CONTAINER_NAME}:/work/dist/rhel7/_probe_container" dist/rhel7/ || true
fi

echo "Built dist/rhel7/libaes_udf-rhel7.so"

# Verify artifact exists on host FS; fail with debug if missing.
if [[ ! -f dist/rhel7/libaes_udf-rhel7.so ]]; then
  echo "ERROR: dist/rhel7/libaes_udf-rhel7.so not found after container build" >&2
  ls -la dist || true
  ls -la dist/rhel7 || true
  exit 3
fi

# Cleanup named container
${RUNTIME} rm -f "${CONTAINER_NAME}" >/dev/null 2>&1 || true

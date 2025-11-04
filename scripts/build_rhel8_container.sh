#!/usr/bin/env bash
set -euo pipefail

# Build RHEL8-compatible UDF .so using a container (podman or docker).
# Output: dist/rhel8/libaes_udf-rhel8.so

RUNTIME=${RUNTIME:-}
if command -v podman >/dev/null 2>&1; then
  RUNTIME=${RUNTIME:-podman}
elif command -v docker >/dev/null 2>&1; then
  RUNTIME=${RUNTIME:-docker}
else
  echo "No container runtime found (podman or docker)." >&2
  exit 2
fi

IMAGE=${IMAGE:-rockylinux:8}
ARCH=${ARCH:-amd64}

# Map ARCH to runtime-specific flag
RUNTIME_PLATFORM_ARG=""
case "${RUNTIME}" in
  podman)
    RUNTIME_PLATFORM_ARG=(--arch "${ARCH}")
    ;;
  docker)
    case "${ARCH}" in
      amd64) RUNTIME_PLATFORM_ARG=(--platform linux/amd64) ;;
      x86_64) RUNTIME_PLATFORM_ARG=(--platform linux/amd64) ;;
      arm64|aarch64) RUNTIME_PLATFORM_ARG=(--platform linux/arm64) ;;
      *) RUNTIME_PLATFORM_ARG=() ;;
    esac
    ;;
esac

set -x
$RUNTIME run --pull=always --rm "${RUNTIME_PLATFORM_ARG[@]}" \
  -v "${PWD}":/work:Z -w /work \
  ${IMAGE} \
  /bin/sh -lc "\
    dnf -y install gcc-c++ make openssl-devel boost-devel curl && \
    mkdir -p /usr/include/impala_udf && \
    curl -fsSL https://raw.githubusercontent.com/apache/impala/master/be/src/udf/udf.h -o /usr/include/impala_udf/udf.h && \
    make rhel8 IMPALA_UDF_INCLUDE_ROOT=/usr/include \
  "

echo "Built dist/rhel8/libaes_udf-rhel8.so"

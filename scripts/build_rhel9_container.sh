#!/usr/bin/env bash
set -euo pipefail

# Build RHEL9-compatible UDF .so using a container (podman or docker).
# Output: dist/rhel9/libaes_udf-rhel9.so

RUNTIME=${RUNTIME:-}
if command -v podman >/dev/null 2>&1; then
  RUNTIME=${RUNTIME:-podman}
elif command -v docker >/dev/null 2>&1; then
  RUNTIME=${RUNTIME:-docker}
else
  echo "No container runtime found (podman or docker)." >&2
  exit 2
fi

IMAGE=${IMAGE:-rockylinux:9}
ARCH=${ARCH:-amd64}

set -x
$RUNTIME run --pull=always --rm --arch ${ARCH} \
  -v "${PWD}":/work:Z -w /work \
  ${IMAGE} \
  /bin/sh -lc "\
    dnf -y install --allowerasing gcc-c++ make openssl-devel boost-devel curl && \
    mkdir -p /usr/include/impala_udf && \
    curl -fsSL https://raw.githubusercontent.com/apache/impala/master/be/src/udf/udf.h -o /usr/include/impala_udf/udf.h && \
    make rhel9 IMPALA_UDF_INCLUDE_ROOT=/usr/include \
  "

echo "Built dist/rhel9/libaes_udf-rhel9.so"

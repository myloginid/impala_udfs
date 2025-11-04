#!/usr/bin/env bash
set -euo pipefail

# Build RHEL7-compatible UDF .so using a container (podman or docker).
# Output: dist/rhel7/libaes_udf-rhel7.so

RUNTIME=${RUNTIME:-}
if command -v podman >/dev/null 2>&1; then
  RUNTIME=${RUNTIME:-podman}
elif command -v docker >/dev/null 2>&1; then
  RUNTIME=${RUNTIME:-docker}
else
  echo "No container runtime found (podman or docker)." >&2
  exit 2
fi

# CentOS 7 provides an RHEL7-compatible userspace and OpenSSL 1.0.2.
IMAGE=${IMAGE:-centos:7}
ARCH=${ARCH:-amd64}

set -x
$RUNTIME run --pull=always --rm --arch ${ARCH} \
  -v "${PWD}":/work:Z -w /work \
  ${IMAGE} \
  /bin/sh -lc "\
    # Point CentOS 7 repos to vault (EOL mirrors no longer serve 7) && \
    if [ -d /etc/yum.repos.d ]; then \
      for f in /etc/yum.repos.d/*.repo; do \
        sed -i -e 's/^mirrorlist=/#mirrorlist=/' \
               -e 's|^#baseurl=http://mirror.centos.org|baseurl=http://vault.centos.org|' \$f || true; \
      done; \
    fi && \
    yum -y install gcc-c++ make openssl-devel curl && \
    mkdir -p /usr/include/impala_udf && \
    curl -fsSL https://raw.githubusercontent.com/apache/impala/master/be/src/udf/udf.h -o /usr/include/impala_udf/udf.h && \
    make rhel7 IMPALA_UDF_INCLUDE_ROOT=/usr/include \
  "

echo "Built dist/rhel7/libaes_udf-rhel7.so"

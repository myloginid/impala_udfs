Impala AES Encrypt/Decrypt UDF (RHEL 8/9)

This project provides Impala scalar UDFs `aes_encrypt(string input, string key)` and `aes_decrypt(string input, string key)` implemented with OpenSSL. They match Hive semantics (AES/ECB/PKCS5Padding) and return/consume raw binary in `STRING`.

Hive compatibility
- Cipher: AES/ECB/PKCS5Padding (equivalent to PKCS#7 for AES).
- Key length must be exactly 16, 24, or 32 bytes; otherwise returns `NULL` (no key derivation or padding).
- Input or key `NULL` → returns `NULL`.
- Symbols: `aes_encrypt`, `aes_decrypt`.

Prerequisites (RHEL 8/9)
- `gcc-c++`, `make`, `openssl-devel`.
- Impala UDF headers available so `<impala_udf/udf.h>` resolves. For CDP/Impala installs this is typically provided by an `impala-udf-devel` (or similar) package that places headers under `/usr/include/impala_udf` (included through `/usr/include`).
On macOS/Linux dev hosts without system OpenSSL headers, set:
- `OPENSSL_INCLUDE_DIR` and `OPENSSL_LIB_DIR` to your OpenSSL install (e.g., Homebrew’s `/opt/homebrew/opt/openssl@3/include` and `/opt/homebrew/opt/openssl@3/lib`).

Build
```bash
make                       # builds to build/libaes_udf.so
make strip                 # optional: strip symbols
make rhel8                 # builds dist/rhel8/libaes_udf-rhel8.so
make rhel9                 # builds dist/rhel9/libaes_udf-rhel9.so

# Quick local crypto sanity (no Impala headers needed):
make check                 # builds and runs a CLI test
```

Containerized builds (podman/docker)
- RHEL 8: `./scripts/build_rhel8_container.sh`
- RHEL 9: `./scripts/build_rhel9_container.sh`
- On Apple Silicon, these scripts default to amd64 (x86_64). To build aarch64 instead, set `ARCH=aarch64`.

Environment variables
- `IMPALA_UDF_INCLUDE_ROOT` (default: `/usr/include`) — should be a directory where `impala_udf/udf.h` is found as `$IMPALA_UDF_INCLUDE_ROOT/impala_udf/udf.h`.

Deploy and register
Option A — HDFS (Impala lib cache)
```bash
hdfs dfs -mkdir -p /user/udf/lib
# Use a release artifact or a local build
# Example: deploy the appropriate .so to HDFS
hdfs dfs -put -f dist/rhel8/libaes_udf-rhel8.so /user/udf/lib/libaes_udf.so
# or
hdfs dfs -put -f dist/rhel9/libaes_udf-rhel9.so /user/udf/lib/libaes_udf.so
# or run helper script (auto-picks a local artifact):
scripts/deploy_hdfs.sh --dst /user/udf/lib/libaes_udf.so

# In impala-shell
-- Adjust database as needed
CREATE FUNCTION IF NOT EXISTS default.aes_encrypt(string, string)
RETURNS string
LOCATION '/user/udf/lib/libaes_udf.so'
SYMBOL='aes_encrypt';

CREATE FUNCTION IF NOT EXISTS default.aes_decrypt(string, string)
RETURNS string
LOCATION '/user/udf/lib/libaes_udf.so'
SYMBOL='aes_decrypt';
```

Quick test in Impala
```sql
SELECT hex(default.aes_encrypt('hello', 'secretkey'));
SELECT CAST(default.aes_decrypt(default.aes_encrypt('hello','secretkey'), 'secretkey') AS STRING);
```

Option B — Local path on each node
- Copy the shared object to the same absolute path on every impalad node, e.g. `/opt/impala/udf/lib/libaes_udf.so`.
- Ensure impalad can load the library and its dependencies:
  - Add the directory to the impalad environment `LD_LIBRARY_PATH` (via CM safety valve or `/etc/default/impala`), e.g. `LD_LIBRARY_PATH=/opt/impala/udf/lib:$LD_LIBRARY_PATH`.
  - Restart impalad daemons.
- Register using the local filesystem path in `LOCATION`:
```sql
CREATE FUNCTION default.aes_encrypt(string, string)
RETURNS string
LOCATION '/opt/impala/udf/lib/libaes_udf.so'
SYMBOL='aes_encrypt';

CREATE FUNCTION default.aes_decrypt(string, string)
RETURNS string
LOCATION '/opt/impala/udf/lib/libaes_udf.so'
SYMBOL='aes_decrypt';
```

SQL helper
- See sql/create_function.sql for ready-to-run statements.
- See sql/drop_function.sql to remove existing functions.

Implementation caveats
- AES-ECB provides no semantic security for repeated blocks; CBC/GCM are preferable but would not match Hive’s AES_ENCRYPT.
- The UDF returns raw binary in a `STRING`; use `hex()` to inspect.

Picking RHEL 8 vs 9 builds
- Build `dist/rhel8/libaes_udf-rhel8.so` on RHEL 8 hosts (OpenSSL 1.1.1 baseline), and `dist/rhel9/libaes_udf-rhel9.so` on RHEL 9 hosts (OpenSSL 3 baseline).
- Deploy the variant that matches the target OS across the cluster, keep the same path on every node, and reference that path in the CREATE FUNCTION’s `LOCATION`.

Releases
- Download prebuilt `.so` files from the GitHub Releases page (e.g., v0.1.0) and deploy them as shown above.

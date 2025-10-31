#!/usr/bin/env bash
set -euo pipefail

# Deploy a selected .so to HDFS for Impala UDF registration.
#
# Usage:
#   scripts/deploy_hdfs.sh [--src <local-so>] [--dst <hdfs-path>]
#
# Defaults:
#   --src: prefer dist/rhel8/libaes_udf-rhel8.so, then dist/rhel9/libaes_udf-rhel9.so, then build/libaes_udf.so
#   --dst: /user/udf/lib/libaes_udf.so

SRC=""
DST="/user/udf/lib/libaes_udf.so"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --src)
      SRC="$2"; shift 2 ;;
    --dst)
      DST="$2"; shift 2 ;;
    *) echo "Unknown arg: $1" >&2; exit 2 ;;
  esac
done

if [[ -z "$SRC" ]]; then
  if [[ -f dist/rhel8/libaes_udf-rhel8.so ]]; then
    SRC=dist/rhel8/libaes_udf-rhel8.so
  elif [[ -f dist/rhel9/libaes_udf-rhel9.so ]]; then
    SRC=dist/rhel9/libaes_udf-rhel9.so
  elif [[ -f build/libaes_udf.so ]]; then
    SRC=build/libaes_udf.so
  else
    echo "No source .so found. Build or download from Releases first." >&2
    exit 1
  fi
fi

echo "Deploying $SRC -> hdfs://$DST"
hdfs dfs -mkdir -p "$(dirname "$DST")"
hdfs dfs -put -f "$SRC" "$DST"

cat <<SQL
-- Registration helpers
CREATE FUNCTION IF NOT EXISTS default.aes_encrypt(string, string)
RETURNS string
LOCATION '$DST'
SYMBOL='aes_encrypt';

CREATE FUNCTION IF NOT EXISTS default.aes_decrypt(string, string)
RETURNS string
LOCATION '$DST'
SYMBOL='aes_decrypt';
SQL

echo "Done"


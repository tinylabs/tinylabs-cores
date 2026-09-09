#!/bin/sh
set -eu

ROOT="${FILES_ROOT:-.}"

FILES="
m3designstart/logical/cortexm3integration_ds/verilog/cm3_code_mux.v
m3designstart/logical/cortexm3integration_ds_obs/verilog/cortexm3ds_logic.v
m3designstart/logical/cortexm3integration_ds_obs/verilog/CORTEXM3INTEGRATIONDS.v
"

missing=0

for file in $FILES; do
    if [ ! -f "$ROOT/$file" ]; then
        echo "ERROR: Required file not found: $file" >&2
        missing=1
    fi
done

if [ "$missing" -ne 0 ]; then
    exit 1
fi

echo "All required files found."

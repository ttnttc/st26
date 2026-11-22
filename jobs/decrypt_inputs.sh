#!/usr/bin/env bash
# Decrypts data/puzzles.enc into $RUNNER_TEMP/pz (outside the workspace). The key comes from the environment only.
set -euo pipefail
: "${ST26_DATA_KEY:?missing}"
mkdir -p "$RUNNER_TEMP/pz"
openssl enc -d -aes-256-cbc -pbkdf2 -iter 200000 -pass env:ST26_DATA_KEY -in data/puzzles.enc | tar -xzf - -C "$RUNNER_TEMP/pz"
echo "inputs: ok"

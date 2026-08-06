#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT_DIR"

bash -n docs/scripts/verify-app-store-archive.sh
bash -n docs/scripts/verify-app-store-ipa.sh
bash -n docs/scripts/verify-mac-app-store-archive.sh
bash -n docs/scripts/verify-mac-app-store-pkg.sh
bash docs/scripts/verify-app-store-archive.sh --self-test
bash docs/scripts/verify-app-store-ipa.sh --self-test
bash docs/scripts/verify-mac-app-store-archive.sh --self-test
bash docs/scripts/verify-mac-app-store-pkg.sh --self-test

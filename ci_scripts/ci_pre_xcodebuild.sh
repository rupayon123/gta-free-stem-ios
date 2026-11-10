#!/bin/bash
set -euo pipefail

# Run only for the intended Xcode Cloud archive action.
[[ "${CI_XCODE_CLOUD:-}" == "TRUE" ]] || { echo 'Missing Xcode Cloud environment'; exit 1; }
[[ "${CI_XCODEBUILD_ACTION:-}" == "archive" ]] || exit 0
commit="${CI_COMMIT:-}"
repo="${CI_PRIMARY_REPOSITORY_PATH:-}"
[[ "$commit" =~ ^[0-9a-f]{40}$ ]] || { echo 'Invalid or missing CI_COMMIT'; exit 1; }
[[ -n "$repo" && -d "$repo" ]] || { echo 'Cloud source checkout unavailable'; exit 1; }
head=$(git -C "$repo" rev-parse --verify 'HEAD^{commit}')
[[ "$head" == "$commit" ]] || { echo 'Cloud checkout does not match CI_COMMIT'; exit 1; }
[[ -z "$(git -C "$repo" status --porcelain=v1 --untracked-files=all -- GTAFreeSTEM GTAFreeSTEMWatch GTAFreeSTEM.xcodeproj project.yml ci_scripts)" ]] || {
  echo 'Cloud release source inputs differ from the checked-out commit'; exit 1;
}
echo "Verified clean Cloud release inputs at $commit"

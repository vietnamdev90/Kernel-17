#!/usr/bin/env bash
# Restore the ignored OnePlus/OPlus DTS sources for the pinned source manifest.
# The full repository is intentionally not cloned: sparse checkout fetches
# only kernel_platform/qcom/opensource/devicetree/oplus.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

# Read the exact upstream URL and SHA from the root module/device-tree project.
read -r SOURCE_URL SOURCE_SHA < <(python3 - <<'PY'
import xml.etree.ElementTree as ET
root = ET.parse("oneplus_15.xml").getroot()
projects = [
    p for p in root.findall("project")
    if p.get("path") in (".", "./")
    and p.get("name") == "android_kernel_modules_and_devicetree_oneplus_sm8850"
]
if len(projects) != 1:
    raise SystemExit("Expected exactly one pinned OnePlus modules/devicetree project")
p = projects[0]
remote_name = p.get("remote") or root.find("default").get("remote")
remotes = [r for r in root.findall("remote") if r.get("name") == remote_name]
if len(remotes) != 1:
    raise SystemExit("Cannot find manifest remote")
revision = p.get("revision", "")
if len(revision) != 40 or any(c not in "0123456789abcdefABCDEF" for c in revision):
    raise SystemExit("Expected a pinned 40-character source commit")
print(remotes[0].get("fetch").rstrip("/") + "/" + p.get("name") + ".git", revision)
PY
)

DTS_DIR="$REPO_ROOT/kernel_platform/qcom/opensource/devicetree"
OPLUS_DIR="$DTS_DIR/oplus"
LINK="$REPO_ROOT/kernel_platform/soc-repo/arch/arm64/boot/dts/vendor"

if [[ ! -f "$OPLUS_DIR/platform_map.bzl" ]]; then
  if [[ -e "$OPLUS_DIR" || -L "$OPLUS_DIR" ]]; then
    echo "Incomplete pre-existing DTS overlay directory: $OPLUS_DIR" >&2
    exit 1
  fi

  TMP="$(mktemp -d -p "${RUNNER_TEMP:-/tmp}" oneplus-dts-XXXXXX)"
  trap 'rm -rf "$TMP"' EXIT
  echo "Fetching pinned OnePlus DTS overlay from $SOURCE_URL @ $SOURCE_SHA"
  git -C "$TMP" init -q
  git -C "$TMP" remote add origin "$SOURCE_URL"
  git -C "$TMP" sparse-checkout init --cone
  git -C "$TMP" sparse-checkout set kernel_platform/qcom/opensource/devicetree/oplus
  git -C "$TMP" -c protocol.version=2 fetch --no-tags --depth=1 --filter=blob:none origin "$SOURCE_SHA"
  git -C "$TMP" -c advice.detachedHead=false checkout -q --detach FETCH_HEAD
  [[ "$(git -C "$TMP" rev-parse HEAD)" == "$SOURCE_SHA" ]] || {
    echo "Wrong upstream source commit" >&2
    exit 1
  }
  test -f "$TMP/kernel_platform/qcom/opensource/devicetree/oplus/platform_map.bzl"
  cp -a "$TMP/kernel_platform/qcom/opensource/devicetree/oplus" "$DTS_DIR/"
fi

# Upstream soc-repo carries this link, but its .gitignore excludes it when
# the consolidated source repository is assembled.
mkdir -p "$(dirname "$LINK")"
if [[ -L "$LINK" ]]; then
  if [[ "$(realpath "$LINK")" != "$(realpath "$DTS_DIR")" ]]; then
    echo "Unexpected DTS vendor symlink: $LINK -> $(readlink "$LINK")" >&2
    exit 1
  fi
elif [[ -e "$LINK" ]]; then
  echo "DTS vendor path already exists and is not a symlink: $LINK" >&2
  exit 1
else
  ln -s ../../../../../qcom/opensource/devicetree "$LINK"
fi

test -f "$LINK/BUILD.bazel"
test -f "$LINK/oplus/platform_map.bzl"
test -f "$LINK/oplus/infiniti-24831-canoe-overlay.dtso"
test -f "$LINK/oplus/infiniti-24863-canoe-overlay.dtso"
echo "Restored DTS vendor package and pinned OPlus overlays."

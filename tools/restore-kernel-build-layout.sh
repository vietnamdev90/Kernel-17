#!/usr/bin/env bash
# Restore generated links and OPlus Bazel variant inputs omitted from Git.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

make_link() {
  local src="$1" dest="$2" relative="$3"
  if [[ ! -e "$src" ]]; then
    echo "Required Bazel package missing: $src" >&2
    exit 1
  fi
  if [[ -L "$dest" ]]; then
    if [[ "$(realpath "$dest")" == "$(realpath "$src")" ]]; then
      return
    fi
    echo "Unexpected symlink at $dest -> $(readlink "$dest")" >&2
    exit 1
  fi
  if [[ -e "$dest" ]]; then
    echo "Existing non-symlink path at $dest; refusing to overwrite" >&2
    exit 1
  fi
  mkdir -p "$(dirname "$dest")"
  ln -s "$relative" "$dest"
  echo "Restored $dest -> $relative"
}

make_link "kernel_platform/oplus/bazel" \
          "kernel_platform/build/kernel/oplus" \
          "../../oplus/bazel"

make_link "kernel_platform/build/bazel_common_rules" \
          "kernel_platform/build/kernel/bazel_common_rules" \
          "../bazel_common_rules"

# This .bzl is deliberately ignored in the original OPlus source tree.
# Without it, oplus_modules_define.bzl cannot be loaded by Bazel.
if [[ ! -f kernel_platform/oplus/bazel/oplus_modules_variant.bzl ]]; then
  sh kernel_platform/oplus/bazel/oplus_modules_variant.sh canoe perf "${OPLUS_FEATURES:-}"
fi

test -f kernel_platform/build/kernel/oplus/BUILD.bazel
test -f kernel_platform/build/kernel/oplus/oplus_modules.bzl
test -f kernel_platform/build/kernel/oplus/oplus_modules_variant.bzl
test -f kernel_platform/build/kernel/bazel_common_rules/dist/dist.bzl

echo "OPlus Bazel packages and variant configuration are ready."

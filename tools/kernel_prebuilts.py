#!/usr/bin/env python3
"""Restore the pinned OnePlus 15 prebuilt toolchain layout from oneplus_15.xml.

The archive contains only kernel_platform/prebuilts/. The manifest's linkfile
entries and the Bazel wrapper link are reconstructed when preparing a build.
"""
from __future__ import annotations

import argparse
import os
from pathlib import Path
from xml.etree import ElementTree

ROOT = Path(__file__).resolve().parent.parent
MANIFEST = ROOT / "oneplus_15.xml"
PREFIX = "kernel_platform/prebuilts/"


def projects():
    root = ElementTree.parse(MANIFEST).getroot()
    result = []
    for project in root.findall("project"):
        path = project.get("path", "")
        if path.startswith(PREFIX):
            result.append((path, project))
    return sorted(result, key=lambda item: item[0])


def within_workspace(path: Path) -> Path:
    # Check lexical paths, not symlink resolution, for manifest-controlled output.
    full = Path(os.path.abspath(path))
    if not full.is_relative_to(ROOT):
        raise ValueError(f"Path outside workspace: {full}")
    return full


def verify() -> None:
    entries = projects()
    if not entries:
        raise RuntimeError("No kernel_platform/prebuilts projects in manifest")
    for project_path, _ in entries:
        location = within_workspace(ROOT / project_path)
        if not location.is_dir() or not any(location.iterdir()):
            raise FileNotFoundError(f"Prebuilt project missing or empty: {location}")
        print(f"OK: {project_path}")
    print(f"Verified {len(entries)} prebuilt projects")


def link(source: Path, destination: Path) -> None:
    destination = within_workspace(destination)
    source = within_workspace(source)
    if not source.exists():
        raise FileNotFoundError(f"Missing linkfile source: {source}")
    destination.parent.mkdir(parents=True, exist_ok=True)

    if destination.is_symlink():
        if destination.resolve() == source.resolve():
            return
        destination.unlink()
    elif destination.exists():
        if destination.resolve() == source.resolve():
            return
        raise FileExistsError(f"Refusing to overwrite existing file: {destination}")

    destination.symlink_to(os.path.relpath(source, destination.parent),
                           target_is_directory=source.is_dir())
    print(f"Link: {destination.relative_to(ROOT)} -> {os.readlink(destination)}")


def restore_links() -> None:
    verify()
    for project_path, project in projects():
        for entry in project.findall("linkfile"):
            source_rel = entry.get("src")
            destination_rel = entry.get("dest")
            if source_rel is None or destination_rel is None:
                raise ValueError(f"Invalid linkfile in project {project_path}")
            link(ROOT / project_path / source_rel, ROOT / destination_rel)

    # tools/bazel is an OPlus wrapper which expects tools/bazel.origin.sh.
    # The original launcher actually lives under build/kernel/kleaf/.
    link(ROOT / "kernel_platform/build/kernel/kleaf/bazel.origin.sh",
         ROOT / "kernel_platform/tools/bazel.origin.sh")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("command", choices=("paths", "verify", "restore-links"))
    args = parser.parse_args()
    if args.command == "paths":
        for project_path, _ in projects():
            print(project_path)
    elif args.command == "verify":
        verify()
    else:
        restore_links()


if __name__ == "__main__":
    main()

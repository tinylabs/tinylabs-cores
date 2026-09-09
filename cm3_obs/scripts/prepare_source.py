#!/usr/bin/env python3
"""Prepare the user-supplied ARM AT421 source before FuseSoC reads the RTL."""

import shutil
import subprocess
import sys
import tarfile
from pathlib import Path

import yaml


ARCHIVE_NAME = "AT421-r0p0-02rel0-1.tar.gz"
DOWNLOAD_URL = (
    "https://support.arm.com/downloads/view/AT421?sortBy=availableBy"
    "&revision=r0p0-02rel0-1"
)
REQUIRED_FILES = (
    Path("m3designstart/logical/cortexm3integration_ds/verilog/cm3_code_mux.v"),
    Path(
        "m3designstart/logical/cortexm3integration_ds_obs/verilog/"
        "cortexm3ds_logic.v"
    ),
    Path(
        "m3designstart/logical/cortexm3integration_ds_obs/verilog/"
        "CORTEXM3INTEGRATIONDS.v"
    ),
)
PATCHES = (
    "files/0001-Remove-verilator-warnings.patch",
    "files/0002-Remove-async-reset.patch",
)
PATCH_MARKER = ".cm3_obs_patches_applied"


def required_files(root: Path):
    return [path for path in REQUIRED_FILES if not (root / path).is_file()]


def safe_extract(archive: Path, destination: Path):
    with tarfile.open(archive, "r:gz") as tar:
        destination_resolved = destination.resolve()
        for member in tar.getmembers():
            target = (destination / member.name).resolve()
            if target != destination_resolved and destination_resolved not in target.parents:
                raise RuntimeError(f"Archive contains an unsafe path: {member.name}")
        tar.extractall(destination)


def normalize_archive_layout(root: Path):
    """Move m3designstart up if the archive wrapped it in a directory."""
    expected = root / REQUIRED_FILES[0]
    if expected.is_file():
        return

    matches = list(root.glob("**/" + str(REQUIRED_FILES[0])))
    if len(matches) != 1:
        return

    source_root = matches[0]
    for _ in REQUIRED_FILES[0].parts:
        source_root = source_root.parent
    extracted_source = source_root / "m3designstart"
    destination = root / "m3designstart"
    if extracted_source.is_dir() and extracted_source != destination:
        shutil.move(str(extracted_source), str(destination))


def apply_patches(root: Path):
    marker = root / PATCH_MARKER
    if marker.exists():
        return

    for patch_name in PATCHES:
        patch_file = Path(__file__).resolve().parents[1] / patch_name
        subprocess.run(
            ["patch", "--batch", "--forward", "-p1", "-i", str(patch_file)],
            cwd=root,
            check=True,
        )
    marker.touch()


def main(input_file: str):
    with open(input_file, encoding="utf-8") as stream:
        generator_input = yaml.safe_load(stream)

    root = Path(generator_input["files_root"]).resolve()
    archive = root / ARCHIVE_NAME

    if not required_files(root):
        apply_patches(root)
        return

    if not archive.is_file():
        print(f"ERROR: {ARCHIVE_NAME} was not found in {root}.", file=sys.stderr)
        print(
            f"Download it from {DOWNLOAD_URL} and place it in {root}.",
            file=sys.stderr,
        )
        raise SystemExit(1)

    print(f"Unpacking {archive.name}...")
    safe_extract(archive, root)
    normalize_archive_layout(root)

    missing = required_files(root)
    if missing:
        names = "\n".join(f"  {path}" for path in missing)
        raise RuntimeError(f"The archive is missing required RTL files:\n{names}")

    apply_patches(root)


if __name__ == "__main__":
    if len(sys.argv) != 2:
        raise SystemExit(f"usage: {sys.argv[0]} <generator-input.yml>")
    main(sys.argv[1])

#!/usr/bin/env python3
"""Focused filesystem-safety tests for the creators helper."""

import importlib.machinery
import importlib.util
import os
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
LOADER = importlib.machinery.SourceFileLoader("creators_helper", str(ROOT / "creators"))
SPEC = importlib.util.spec_from_loader(LOADER.name, LOADER)
if SPEC is None:
    raise RuntimeError("could not load creators helper")
creators = importlib.util.module_from_spec(SPEC)
LOADER.exec_module(creators)


def require(condition, message):
    if not condition:
        raise AssertionError(message)


def test_read_rejects_fifo_without_blocking(workspace):
    fifo = workspace / "state.json"
    os.mkfifo(fifo, 0o600)
    fallback = {"safe": True}
    require(
        creators.read_json(str(fifo), fallback) is fallback,
        "a FIFO state file was not rejected",
    )


def test_read_rejects_wrong_owner_metadata(workspace):
    state = workspace / "owned-state.json"
    state.write_text('{"valid": true}', encoding="utf-8")
    fallback = {"safe": True}
    real_fstat = creators.os.fstat

    def foreign_owner(descriptor):
        info = real_fstat(descriptor)
        return os.stat_result(
            (
                info.st_mode,
                info.st_ino,
                info.st_dev,
                info.st_nlink,
                info.st_uid + 1,
                info.st_gid,
                info.st_size,
                info.st_atime,
                info.st_mtime,
                info.st_ctime,
            )
        )

    creators.os.fstat = foreign_owner
    try:
        require(
            creators.read_json(str(state), fallback) is fallback,
            "a state file with the wrong owner metadata was accepted",
        )
    finally:
        creators.os.fstat = real_fstat


def test_atomic_write_stays_in_opened_parent(workspace):
    parent = workspace / "state"
    parent.mkdir(mode=0o700)
    destination = parent / "record.json"
    moved_parent = workspace / "state-before-replacement"
    real_replace = creators.os.replace

    def replace_after_parent_swap(source, target, **kwargs):
        os.rename(parent, moved_parent)
        parent.mkdir(mode=0o700)
        return real_replace(source, target, **kwargs)

    creators.os.replace = replace_after_parent_swap
    try:
        creators.atomic_write(str(destination), b"safe")
    finally:
        creators.os.replace = real_replace

    require(
        (moved_parent / "record.json").read_bytes() == b"safe",
        "atomic write did not use the already-opened parent directory",
    )
    require(
        not destination.exists(),
        "atomic write followed the replacement parent directory",
    )


def main():
    with tempfile.TemporaryDirectory() as temporary:
        workspace = Path(temporary)
        test_read_rejects_fifo_without_blocking(workspace)
        test_read_rejects_wrong_owner_metadata(workspace)
        test_atomic_write_stays_in_opened_parent(workspace)
    print("state-io.test.py: all checks passed")


if __name__ == "__main__":
    main()

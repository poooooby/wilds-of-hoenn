#!/usr/bin/env python3
"""Checks manifest.json's version and main.lua's exported version agree,
and (when RELEASE_TAG is set, e.g. in CI) that the tag matches both.

Usage:
  python3 tools/validate_release_version.py
  RELEASE_TAG=v0.1.0 python3 tools/validate_release_version.py
"""
from __future__ import annotations

import json
import os
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def fail(msg: str) -> None:
    print(f"ERROR: {msg}", file=sys.stderr)
    sys.exit(1)


def main() -> int:
    manifest_path = ROOT / "manifest.json"
    main_path = ROOT / "main.lua"
    if not manifest_path.is_file():
        fail(f"missing {manifest_path}")
    if not main_path.is_file():
        fail(f"missing {main_path}")

    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    manifest_version = manifest.get("version")
    if not isinstance(manifest_version, str):
        fail("manifest.json has no string \"version\" field")

    main_text = main_path.read_text(encoding="utf-8")
    m = re.search(r'mod\.exports\.version\s*=\s*"([^"]+)"', main_text)
    if not m:
        fail("main.lua has no mod.exports.version = \"...\" assignment")
    main_version = m.group(1)

    print(f"manifest.json version: {manifest_version}")
    print(f"main.lua version:      {main_version}")

    if manifest_version != main_version:
        fail(f"version mismatch: manifest.json={manifest_version} main.lua={main_version}")

    tag = os.environ.get("RELEASE_TAG")
    if tag:
        tag_version = tag[1:] if tag.startswith("v") else tag
        print(f"release tag version:   {tag_version}")
        if tag_version != manifest_version:
            fail(f"tag {tag} does not match manifest.json version {manifest_version}")

    print("validate_release_version: ok")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

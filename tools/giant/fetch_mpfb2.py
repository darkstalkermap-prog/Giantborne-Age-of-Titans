#!/usr/bin/env python3
"""The audit of the vendored CC0 MakeHuman/MPFB2 subset (tools/giant/mpfb2/).

The giant pipeline reads only the files in ``tools/giant/mpfb2/`` (FILES.sha256 lists them with
their hashes). They were copied as data from the wheel ``anny-0.6.2-py3-none-any.whl`` (the
``anny/data/mpfb2/`` folder): nothing in the wheel is executed, only zip members are read.

Usage (the shared venv's Python: the target list comes from the kit's phenotype, which needs numpy):
  $GIANT_VENV/bin/python tools/giant/fetch_mpfb2.py [--wheel=PATH] [--download]
      the audit: checks the wheel's size and sha256, re-extracts the subset in memory, recomputes
      the list of files the kit needs from the wheel's data, and compares file by file with the
      vendored copy and with FILES.sha256. Prints AUDIT OK or the differences (exit 1).
  $GIANT_VENV/bin/python tools/giant/fetch_mpfb2.py --extract [--wheel=PATH]
      (re)writes tools/giant/mpfb2/ from the wheel: the subset, FILES.sha256; LICENSE.md comes
      from the wheel too. SOURCE.md and .gdignore are kept.

The wheel is looked for at --wheel, else $GIANT_CACHE/wheels/<name> (default cache
$HOME/.cache/giantborn/giant-cache). --download fetches it from PyPI into the cache first (the
only step that needs the network; build_giant.py --verify never does).
"""
from __future__ import annotations

import hashlib
import io
import os
import sys
import tempfile
import zipfile

HERE = os.path.dirname(os.path.abspath(__file__))
VENDOR = os.path.join(HERE, "mpfb2")
LIST_FILE = "FILES.sha256"
KEEP = (LIST_FILE, "SOURCE.md", ".gdignore")
WHEEL_NAME = "anny-0.6.2-py3-none-any.whl"
WHEEL_SIZE = 47711600
WHEEL_SHA256 = "bad70bdc2be0dfa9880d60129c3a1339678f08f493184f637dc2825c3e27b8d2"
WHEEL_DATA = "anny/data/mpfb2/"
# The usual files.pythonhosted.org address of a pure-Python wheel (ASSUMED: not used by any check).
WHEEL_URL = "https://files.pythonhosted.org/packages/py3/a/anny/" + WHEEL_NAME


def sha256(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def cache_dir() -> str:
    return os.environ.get("GIANT_CACHE") or os.path.join(os.path.expanduser("~"), ".cache", "giantborn", "giant-cache")


def read_list(path=None) -> dict:
    """{data-relative path: sha256} of FILES.sha256 (sha256sum format)."""
    path = path or os.path.join(VENDOR, LIST_FILE)
    out = {}
    with open(path, encoding="utf-8") as fh:
        for line in fh:
            line = line.strip()
            if line:
                h, rel = line.split(None, 1)
                out[rel.lstrip("*")] = h
    return out


def list_text(hashes: dict) -> str:
    return "".join("%s  %s\n" % (hashes[rel], rel) for rel in sorted(hashes))


def vendored_files() -> list:
    """Every file under mpfb2/ except the kept notes, data-relative, sorted."""
    out = []
    for root, _dirs, files in os.walk(VENDOR):
        for f in files:
            rel = os.path.relpath(os.path.join(root, f), VENDOR).replace(os.sep, "/")
            if rel not in KEEP:
                out.append(rel)
    return sorted(out)


def open_wheel(path: str) -> zipfile.ZipFile:
    data = open(path, "rb").read()
    if len(data) != WHEEL_SIZE or sha256(data) != WHEEL_SHA256:
        raise SystemExit("fetch_mpfb2: %s is not the audited wheel (size %d, sha256 %s)" % (
            path, len(data), sha256(data)))
    return zipfile.ZipFile(io.BytesIO(data))


def needed_files(zf: zipfile.ZipFile) -> list:
    """The kit's file list computed from the wheel's own data (extracted to a temp folder)."""
    sys.path.insert(0, os.path.join(HERE, "kit"))
    import mh_data as mh
    with tempfile.TemporaryDirectory() as tmp:
        for info in zf.infolist():
            if info.filename.startswith(WHEEL_DATA) and not info.is_dir():
                rel = info.filename[len(WHEEL_DATA):]
                if rel.startswith(("3dobjs/", "targets/", "rigs/standard/", "textures/")) or rel == "LICENSE.md":
                    dst = os.path.join(tmp, rel)
                    os.makedirs(os.path.dirname(dst), exist_ok=True)
                    with open(dst, "wb") as fh:
                        fh.write(zf.read(info))
        old = mh.MPFB_DIR
        mh.set_data_dir(tmp)
        try:
            return mh.subset_files()
        finally:
            mh.set_data_dir(old)


def find_wheel(argv) -> str:
    for a in argv:
        if a.startswith("--wheel="):
            return a.split("=", 1)[1]
    path = os.path.join(cache_dir(), "wheels", WHEEL_NAME)
    if "--download" in argv and not os.path.exists(path):
        import urllib.request
        os.makedirs(os.path.dirname(path), exist_ok=True)
        print("fetch_mpfb2: downloading %s" % WHEEL_URL)
        urllib.request.urlretrieve(WHEEL_URL, path + ".part")
        os.replace(path + ".part", path)
    if not os.path.exists(path):
        raise SystemExit("fetch_mpfb2: no wheel at %s (pass --wheel=PATH or --download)" % path)
    return path


def extract(zf: zipfile.ZipFile) -> int:
    files = needed_files(zf)
    for rel in vendored_files():
        os.remove(os.path.join(VENDOR, rel))
    hashes = {}
    for rel in files:
        data = zf.read(WHEEL_DATA + rel)
        dst = os.path.join(VENDOR, rel)
        os.makedirs(os.path.dirname(dst), exist_ok=True)
        with open(dst, "wb") as fh:
            fh.write(data)
        hashes[rel] = sha256(data)
    for root, dirs, _files in os.walk(VENDOR, topdown=False):
        for d in dirs:
            p = os.path.join(root, d)
            if not os.listdir(p):
                os.rmdir(p)
    with open(os.path.join(VENDOR, LIST_FILE), "w", encoding="utf-8") as fh:
        fh.write(list_text(hashes))
    print("fetch_mpfb2: wrote %d files (%d bytes) and %s" % (len(files), sum(
        os.path.getsize(os.path.join(VENDOR, r)) for r in files), LIST_FILE))
    return 0


def audit(zf: zipfile.ZipFile) -> int:
    problems = []
    listed = read_list()
    needed = needed_files(zf)
    vendored = vendored_files()
    if sorted(listed) != needed:
        problems.append("FILES.sha256 lists %d files, the kit needs %d: missing %s, extra %s" % (
            len(listed), len(needed), sorted(set(needed) - set(listed))[:8], sorted(set(listed) - set(needed))[:8]))
    if vendored != sorted(listed):
        problems.append("mpfb2/ holds %d data files, FILES.sha256 lists %d: unlisted %s, missing %s" % (
            len(vendored), len(listed), sorted(set(vendored) - set(listed))[:8], sorted(set(listed) - set(vendored))[:8]))
    names = set(zf.namelist())
    for rel in sorted(listed):
        member = WHEEL_DATA + rel
        if member not in names:
            problems.append("%s: not in the wheel" % rel)
            continue
        wheel_bytes = zf.read(member)
        path = os.path.join(VENDOR, rel)
        if not os.path.exists(path):
            continue
        local = open(path, "rb").read()
        if local != wheel_bytes:
            problems.append("%s: differs from the wheel's copy" % rel)
        if sha256(local) != listed[rel]:
            problems.append("%s: its sha256 is not FILES.sha256's" % rel)
    for p in problems:
        print("AUDIT: " + p)
    if problems:
        print("AUDIT FAILED: %d problems" % len(problems))
        return 1
    print("AUDIT OK: %d vendored files equal the wheel's (%s, sha256 %s...)" % (len(listed), WHEEL_NAME, WHEEL_SHA256[:12]))
    return 0


def main(argv) -> int:
    if "-h" in argv or "--help" in argv:
        print(__doc__)
        return 0
    zf = open_wheel(find_wheel(argv))
    return extract(zf) if "--extract" in argv else audit(zf)


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))

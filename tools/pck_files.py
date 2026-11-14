#!/usr/bin/env python3
"""Lists the files packed in a Godot 4 .pck (pack format 2 or 3) and checks a release's contents.

Usage:
  python3 tools/pck_files.py PCK                      print every packed path, one per line
  python3 tools/pck_files.py --sizes PCK              print every packed file's size and path (the
                                                      listing of a pack, tab-separated)
  python3 tools/pck_files.py --check-no-test PCK      exit 1 when test content is packed
  python3 tools/pck_files.py --audio-share PCK        print one AUDIO_SHARE line: the bytes of the
                                                      imported audio (P23: build_web.sh prints it)
  python3 tools/pck_files.py --giant-share PCK [--verbose]
                                                      print one GIANT_SHARE line: M10's realistic giant
                                                      in the pack (P41, plan M10 §2.12) - its files'
                                                      bytes and their share of the shipped pack, as
                                                      build_web.sh counts it (gzip -9, then base64):
                                                      the pack without them against the pack with
                                                      them; --verbose lists the files

The giant's files (GIANT_PREFIXES) are everything under assets/giant/ (each import's remap) with the
files those remaps point at (.godot/imported/...), the giant's shaders (assets/shaders/giant_*) and
its model scene (scenes/player/giant_model.tscn, packed as a .remap and its exported binary).

Test content (plan M6-M9 decision 8, P22) is anything under scenes/test/, assets/test_world/ or
data/test/: the Web preset excludes it, the Web (test) preset keeps it. A text scene the export
converted to binary shows as its original path plus ".remap" (the binary copy lives under
.godot/exported/), so the original path is what is checked.

Only the standard library is used; the file is read, never changed.
"""
import base64
import gzip
import re
import struct
import sys

MAGIC = 0x43504447  # "GDPC"
TEST_PREFIXES = ("scenes/test/", "assets/test_world/", "data/test/")
# Imported audio as the export packs it (.godot/imported/<file>-<hash>.<ext>): Ogg Vorbis streams
# and sampled WAVs (QOA), plus the .import remaps under assets/audio/.
AUDIO_EXTENSIONS = (".oggvorbisstr", ".sample", ".mp3str")
PACK_DIR_ENCRYPTED = 1
# P41: the giant's own files (plan M10 §2.12: M10's share is assets/giant/, the giant's shaders and scenes).
GIANT_PREFIXES = ("assets/giant/", "assets/shaders/giant_", "scenes/player/giant_model.")


def packed_paths(path):
    """The paths packed in the .pck at `path` (without "res://")."""
    return [name for name, _size in packed_entries(path)]


def packed_entries(path):
    """(path without "res://", size in bytes) of every file packed in the .pck at `path`."""
    return [(name, size) for name, _offset, size in packed_index(_read(path), path)]


def _read(path):
    with open(path, "rb") as f:
        return f.read()


def packed_index(data, path="pck"):
    """(path without "res://", absolute offset, size) of every file packed in the .pck bytes `data`."""
    start = data.find(struct.pack("<I", MAGIC))
    if start < 0:
        raise ValueError("%s: no GDPC header" % path)
    (magic, version, _maj, _min, _pat, flags) = struct.unpack_from("<6I", data, start)
    if magic != MAGIC or version not in (2, 3):
        raise ValueError("%s: unsupported pack format %d" % (path, version))
    if flags & PACK_DIR_ENCRYPTED:
        raise ValueError("%s: the directory is encrypted" % path)
    pos = start + 6 * 4
    (file_base,) = struct.unpack_from("<Q", data, pos)
    pos += 8
    if version >= 3:
        (dir_offset,) = struct.unpack_from("<Q", data, pos)
        pos = start + dir_offset
    else:
        pos += 16 * 4  # reserved
    (count,) = struct.unpack_from("<I", data, pos)
    pos += 4
    out = []
    for _ in range(count):
        (length,) = struct.unpack_from("<I", data, pos)
        pos += 4
        name = data[pos:pos + length].rstrip(b"\0").decode("utf-8", "replace")
        pos += length
        (offset, size) = struct.unpack_from("<QQ", data, pos)
        pos += 8 + 8 + 16 + 4  # offset, size, md5, flags
        if name.startswith("res://"):
            name = name[len("res://"):]
        out.append((name, start + file_base + offset if version >= 3 else offset, size))
    return out


def audio_share(entries):
    """(audio bytes, all bytes, audio files) of packed entries: the imported audio and the remaps
    of assets/audio (P23)."""
    audio = [(n, s) for n, s in entries if n.endswith(AUDIO_EXTENSIONS) or n.startswith("assets/audio/")]
    return sum(s for _n, s in audio), sum(s for _n, s in entries), len(audio)


_REMAP_PATH = re.compile(r'^(?:path(?:\.[a-z0-9_]+)?)="res://([^"]+)"', re.M)


def giant_files(entries, data):
    """The packed files that belong to the giant: GIANT_PREFIXES and every file a remap among them
    points at (an import's imported files, an exported scene's binary)."""
    names = {n for n, _o, _s in entries}
    out = set()
    for name, offset, size in entries:
        if not name.startswith(GIANT_PREFIXES):
            continue
        out.add(name)
        if name.endswith((".import", ".remap")):
            text = data[offset:offset + size].decode("utf-8", "replace")
            for target in _REMAP_PATH.findall(text):
                if target in names:
                    out.add(target)
    return out


def shipped(blob):
    """Bytes as build_web.sh ships them: gzip -9, then base64 (no line breaks)."""
    return len(base64.b64encode(gzip.compress(blob, 9, mtime=0)))


def giant_share(path):
    """{"files", "raw", "shipped", "listing"}: the giant's files in the pack at `path` and their shipped
    share - the pack's files with them (in pack order, the giant's last) against the pack's files
    without them."""
    data = _read(path)
    entries = packed_index(data, path)
    giant = giant_files(entries, data)
    base = b"".join(data[o:o + s] for n, o, s in entries if n not in giant)
    mine = b"".join(data[o:o + s] for n, o, s in entries if n in giant)
    share = shipped(base + mine) - shipped(base) if mine else 0
    listing = sorted((s, n) for n, _o, s in entries if n in giant)
    return {"files": len(giant), "raw": len(mine), "shipped": share, "listing": listing}


def test_content(paths):
    """The packed paths that are test content (see the module notes)."""
    return [p for p in paths if p.startswith(TEST_PREFIXES)]


def main(argv):
    args = [a for a in argv[1:] if not a.startswith("--")]
    check = "--check-no-test" in argv
    if len(args) != 1:
        sys.stderr.write(__doc__)
        return 2
    if "--audio-share" in argv:
        audio, total, files = audio_share(packed_entries(args[0]))
        print("AUDIO_SHARE audio_bytes=%d pck_files_bytes=%d share=%.3f files=%d" % (
            audio, total, audio / float(max(1, total)), files))
        return 0
    if "--giant-share" in argv:
        g = giant_share(args[0])
        print("GIANT_SHARE giant_bytes=%d shipped=%d shipped_mib=%.2f files=%d" % (
            g["raw"], g["shipped"], g["shipped"] / 1048576.0, g["files"]))
        if "--verbose" in argv:
            for size, name in g["listing"]:
                print("  %10d  %s" % (size, name))
        return 0
    if "--sizes" in argv:
        for name, size in packed_entries(args[0]):
            print("%d\t%s" % (size, name))
        return 0
    paths = packed_paths(args[0])
    if not check:
        for p in paths:
            print(p)
        return 0
    found = test_content(paths)
    if found:
        print("pck_files.py: %d test file(s) packed in %s:" % (len(found), args[0]))
        for p in found[:40]:
            print("  " + p)
        return 1
    print("pck_files.py: %s packs %d files and no test content" % (args[0], len(paths)))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))

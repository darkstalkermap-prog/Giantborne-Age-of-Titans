#!/usr/bin/env python3
"""Lists the files packed in a Godot 4 .pck (pack format 2 or 3) and checks a release's contents.

Usage:
  python3 tools/pck_files.py PCK                      print every packed path, one per line
  python3 tools/pck_files.py --check-no-test PCK      exit 1 when test content is packed
  python3 tools/pck_files.py --audio-share PCK        print one AUDIO_SHARE line: the bytes of the
                                                      imported audio (P23: build_web.sh prints it)

Test content (plan M6-M9 decision 8, P22) is anything under scenes/test/, assets/test_world/ or
data/test/: the Web preset excludes it, the Web (test) preset keeps it. A text scene the export
converted to binary shows as its original path plus ".remap" (the binary copy lives under
.godot/exported/), so the original path is what is checked.

Only the standard library is used; the file is read, never changed.
"""
import struct
import sys

MAGIC = 0x43504447  # "GDPC"
TEST_PREFIXES = ("scenes/test/", "assets/test_world/", "data/test/")
# Imported audio as the export packs it (.godot/imported/<file>-<hash>.<ext>): Ogg Vorbis streams
# and sampled WAVs (QOA), plus the .import remaps under assets/audio/.
AUDIO_EXTENSIONS = (".oggvorbisstr", ".sample", ".mp3str")
PACK_DIR_ENCRYPTED = 1


def packed_paths(path):
    """The paths packed in the .pck at `path` (without "res://")."""
    return [name for name, _size in packed_entries(path)]


def packed_entries(path):
    """(path without "res://", size in bytes) of every file packed in the .pck at `path`."""
    with open(path, "rb") as f:
        data = f.read()
    start = data.find(struct.pack("<I", MAGIC))
    if start < 0:
        raise ValueError("%s: no GDPC header" % path)
    (magic, version, _maj, _min, _pat, flags) = struct.unpack_from("<6I", data, start)
    if magic != MAGIC or version not in (2, 3):
        raise ValueError("%s: unsupported pack format %d" % (path, version))
    if flags & PACK_DIR_ENCRYPTED:
        raise ValueError("%s: the directory is encrypted" % path)
    pos = start + 6 * 4
    pos += 8  # file base
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
        (_offset, size) = struct.unpack_from("<QQ", data, pos)
        pos += 8 + 8 + 16 + 4  # offset, size, md5, flags
        if name.startswith("res://"):
            name = name[len("res://"):]
        out.append((name, size))
    return out


def audio_share(entries):
    """(audio bytes, all bytes, audio files) of packed entries: the imported audio and the remaps
    of assets/audio (P23)."""
    audio = [(n, s) for n, s in entries if n.endswith(AUDIO_EXTENSIONS) or n.startswith("assets/audio/")]
    return sum(s for _n, s in audio), sum(s for _n, s in entries), len(audio)


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

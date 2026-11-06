"""Ogg Vorbis encoding for Giantborn's music and ambience (decision 4 of the M6-M9 plan).

Every loop, ambience spot and stinger ships as Ogg Vorbis from ffmpeg's libvorbis encoder:

    ffmpeg -fflags +bitexact -i master.wav -c:a libvorbis -q:a <q> -ar <rate> -ac <channels>
           -flags:a +bitexact -fflags +bitexact out.ogg

The bit-exact flags make ffmpeg write a fixed Ogg serial number and no encoder tag, so two encodes
of the same master are byte-identical (build_audio.py --verify relies on it). ffmpeg's native
`vorbis` encoder is refused: it pads the decoded length (every loop would click and drift) and
takes only stereo (docs/plans/briefs/audio_tech.md section 1).
"""

from __future__ import annotations

import re
import shutil
import subprocess
from pathlib import Path

ENCODER = "libvorbis"


class EncoderError(RuntimeError):
    pass


def ffmpeg_path() -> str:
    path = shutil.which("ffmpeg")
    if path is None:
        raise EncoderError("ffmpeg was not found on PATH")
    return path


def available() -> bool:
    """True when ffmpeg exists and has the libvorbis encoder."""
    try:
        check_encoder()
        return True
    except EncoderError:
        return False


def check_encoder() -> None:
    """Raises EncoderError unless ffmpeg lists the libvorbis encoder."""
    out = subprocess.run([ffmpeg_path(), "-hide_banner", "-encoders"], check=True,
                         capture_output=True, text=True).stdout
    if not re.search(r"^\s*A\S*\s+%s\s" % ENCODER, out, re.MULTILINE):
        raise EncoderError("this ffmpeg has no %s encoder (the native 'vorbis' encoder is refused: "
                           "it pads loops)" % ENCODER)


def ffmpeg_version() -> str:
    """The version token of `ffmpeg -version` (e.g. 6.1.1-3ubuntu5)."""
    try:
        first = subprocess.run([ffmpeg_path(), "-version"], check=True, capture_output=True,
                               text=True).stdout.splitlines()[0]
    except (EncoderError, subprocess.CalledProcessError, IndexError):
        return "unknown"
    m = re.match(r"ffmpeg version (\S+)", first)
    return m.group(1) if m else first.strip()


def libvorbis_version() -> str:
    """The libvorbis encoder library's version: the package version where the system has a
    package database, else the shared library file ffmpeg links, else "unknown"."""
    for pkg in ("libvorbisenc2", "libvorbis0a"):
        try:
            out = subprocess.run(["dpkg-query", "-W", "-f=${Version}", pkg], check=True,
                                 capture_output=True, text=True).stdout.strip()
            if out:
                return out
        except (OSError, subprocess.CalledProcessError):
            pass
    try:
        out = subprocess.run(["ldd", ffmpeg_path()], check=True, capture_output=True, text=True).stdout
        m = re.search(r"libvorbisenc\.so\S*\s+=>\s+(\S+)", out)
        if m:
            return Path(m.group(1)).resolve().name
    except (OSError, EncoderError, subprocess.CalledProcessError):
        pass
    return "unknown"


def encode_ogg(master_wav: Path, out: Path, quality: float, rate: int, channels: int) -> None:
    """Encodes a WAV master into Ogg Vorbis with libvorbis at `quality` (-q:a), `rate` and
    `channels`, bit-exact. Raises EncoderError when ffmpeg fails."""
    out = Path(out)
    out.parent.mkdir(parents=True, exist_ok=True)
    cmd = [ffmpeg_path(), "-nostdin", "-hide_banner", "-loglevel", "error", "-y",
           "-fflags", "+bitexact", "-i", str(master_wav), "-map_metadata", "-1",
           "-c:a", ENCODER, "-q:a", _q(quality), "-ar", str(int(rate)), "-ac", str(int(channels)),
           "-flags:a", "+bitexact", "-fflags", "+bitexact", str(out)]
    res = subprocess.run(cmd, capture_output=True, text=True)
    if res.returncode != 0:
        raise EncoderError("ffmpeg failed on %s: %s" % (master_wav, res.stderr.strip()))


def _q(quality: float) -> str:
    q = float(quality)
    return str(int(q)) if q == int(q) else ("%.2f" % q)

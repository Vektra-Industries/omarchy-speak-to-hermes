#!/usr/bin/env python3
"""Local name wake. The microphone audio never leaves this machine.

A small on-device keyword spotter listens for the phrases in
~/.config/speak-to-hermes/wake-phrase (one phrase per line; example:
"hermes"). When a phrase hits, this plays a short chime, shows the
every-screen pill, and records only the words that follow. Those words
are transcribed locally and handed to speak-to-hermes.sh --from-wav as
text. The room before the name is never uploaded.

Stop the ears: systemctl --user stop speak-to-hermes-wake
"""
from __future__ import annotations

import math
import os
import struct
import subprocess
import sys
import tempfile
import wave
from pathlib import Path

SAMPLE_RATE = 16000
FRAME = 1280  # 80 ms, matches the sherpa streaming chunk used elsewhere
MODEL_URL = (
    "https://github.com/k2-fsa/sherpa-onnx/releases/download/kws-models/"
    "sherpa-onnx-kws-zipformer-gigaspeech-3.3M-2024-01-01.tar.bz2"
)
MODEL_DIR_NAME = "sherpa-onnx-kws-zipformer-gigaspeech-3.3M-2024-01-01"

HOME = Path.home()
CFG = HOME / ".config" / "speak-to-hermes"
SHARE = HOME / ".local" / "share" / "speak-to-hermes"
RUNTIME = Path(os.environ.get("XDG_RUNTIME_DIR", f"/run/user/{os.getuid()}"))
STATE_FILE = RUNTIME / "voxtype" / "state"
MODE_FILE = RUNTIME / "voxtype" / "mode"


def log(msg: str) -> None:
    print(f"wake: {msg}", flush=True)


def phrases() -> list[str]:
    path = CFG / "wake-phrase"
    if path.is_file():
        lines = [ln.strip() for ln in path.read_text().splitlines()]
        lines = [ln for ln in lines if ln and not ln.startswith("#")]
        if lines:
            return lines
    return ["hermes", "hey hermes"]


def speak_bin() -> str:
    env = os.environ.get("SPEAK_BIN", "").strip()
    if env:
        return env
    pointer = CFG / "speak-bin"
    if pointer.is_file():
        line = pointer.read_text().strip().splitlines()[0].strip()
        if line:
            return os.path.expanduser(line)
    return str(HOME / ".local" / "bin" / "speak-to-hermes.sh")


def ensure_model() -> Path:
    root = SHARE / "kws"
    target = root / MODEL_DIR_NAME
    if (target / "tokens.txt").exists():
        return target
    import tarfile
    import urllib.request

    root.mkdir(parents=True, exist_ok=True)
    archive = root / f"{MODEL_DIR_NAME}.tar.bz2"
    log("downloading keyword model (one time, about 13 MB)")
    urllib.request.urlretrieve(MODEL_URL, archive)  # noqa: S310
    with tarfile.open(archive, "r:bz2") as tf:
        tf.extractall(root, filter="data")
    archive.unlink(missing_ok=True)
    if not (target / "tokens.txt").exists():
        raise SystemExit(f"keyword model unpack failed: {target}")
    return target


def build_spotter(model: Path, phrase_list: list[str]):
    import sherpa_onnx
    from sherpa_onnx import text2token

    tokens = text2token(
        [p.upper() for p in phrase_list],
        tokens=str(model / "tokens.txt"),
        tokens_type="bpe",
        bpe_model=str(model / "bpe.model"),
    )
    kw = tempfile.NamedTemporaryFile(
        mode="w", suffix=".txt", prefix="speak-kws-", delete=False, encoding="utf-8"
    )
    for phrase, toks in zip(phrase_list, tokens):
        display = phrase.upper().replace(" ", "_")
        kw.write(" ".join(str(t) for t in toks) + f" @{display}\n")
    kw.close()

    def model_file(part: str) -> str:
        hits = sorted(model.glob(f"{part}-*[!8].onnx"))
        if not hits:
            raise SystemExit(f"missing {part} model under {model}")
        return str(hits[0])

    spotter = sherpa_onnx.KeywordSpotter(
        tokens=str(model / "tokens.txt"),
        encoder=model_file("encoder"),
        decoder=model_file("decoder"),
        joiner=model_file("joiner"),
        keywords_file=kw.name,
        keywords_threshold=0.25,
        num_threads=1,
        provider="cpu",
    )
    return spotter, kw.name


def set_state(state: str, mode: str | None = None) -> None:
    try:
        STATE_FILE.parent.mkdir(parents=True, exist_ok=True)
        STATE_FILE.write_text(state)
        if mode is not None:
            MODE_FILE.write_text(mode)
    except OSError:
        pass


def chime_wav(path: Path) -> None:
    # Two short original tones. Not a copied film cue.
    frames = []
    for freq, ms in ((523.25, 70), (784.0, 110)):
        n = int(SAMPLE_RATE * ms / 1000)
        for i in range(n):
            env = min(1.0, i / 80.0, (n - i) / 120.0)
            sample = int(9000 * env * math.sin(2 * math.pi * freq * i / SAMPLE_RATE))
            frames.append(struct.pack("<h", sample))
    path.write_bytes(b"".join(frames))


def play_pcm(path: Path) -> None:
    if subprocess.call(["pw-play", "--rate", str(SAMPLE_RATE), "--channels", "1",
                        "--format", "s16", str(path)],
                       stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL) == 0:
        return
    wav = path.with_suffix(".wav")
    with wave.open(str(wav), "wb") as wf:
        wf.setnchannels(1)
        wf.setsampwidth(2)
        wf.setframerate(SAMPLE_RATE)
        wf.writeframes(path.read_bytes())
    for cmd in (["pw-play", str(wav)], ["ffplay", "-nodisp", "-autoexit", "-loglevel", "quiet", str(wav)]):
        if subprocess.call(cmd, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL) == 0:
            return


def say_yes() -> None:
    if subprocess.call(["espeak-ng", "-s", "150", "Yes?"],
                       stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL) != 0:
        log("no espeak-ng; chime only")


def write_wav(path: Path, pcm: bytes) -> None:
    with wave.open(str(path), "wb") as wf:
        wf.setnchannels(1)
        wf.setsampwidth(2)
        wf.setframerate(SAMPLE_RATE)
        wf.writeframes(pcm)


def speech_ms(pcm: bytes) -> int:
    if len(pcm) < 2:
        return 0
    samples = memoryview(pcm).cast("h")
    loud = 0
    for i in range(0, len(samples), FRAME):
        chunk = samples[i:i + FRAME]
        if not chunk:
            break
        energy = sum(abs(s) for s in chunk) / len(chunk)
        if energy > 450:
            loud += 1
    return int(loud * FRAME / SAMPLE_RATE * 1000)


def record_command(proc_reader) -> bytes:
    """Read the already-open raw mic until a short silence, or 10 seconds."""
    pcm = bytearray()
    quiet = 0
    loud = 0
    max_frames = int(10 * SAMPLE_RATE / FRAME)
    for _ in range(max_frames):
        frame = proc_reader.read(FRAME * 2)
        if len(frame) < FRAME * 2:
            break
        pcm.extend(frame)
        samples = memoryview(frame).cast("h")
        energy = sum(abs(s) for s in samples) / len(samples)
        if energy > 450:
            loud += 1
            quiet = 0
        else:
            quiet += 1
        if loud >= 2 and quiet >= 5:
            break
    return bytes(pcm)


def open_mic():
    return subprocess.Popen(
        ["pw-record", "--rate", str(SAMPLE_RATE), "--channels", "1",
         "--format", "s16", "--raw", "-"],
        stdout=subprocess.PIPE,
        stderr=subprocess.DEVNULL,
    )


def feed_wav(spotter, stream, wav_path: Path) -> bool:
    import numpy as np

    with wave.open(str(wav_path)) as wf:
        raw = wf.readframes(wf.getnframes())
        rate = wf.getframerate()
    samples = np.frombuffer(raw, dtype=np.int16).astype(np.float32) / 32768.0
    if rate != SAMPLE_RATE:
        # Nearest-neighbour resample is enough for a synthetic test clip.
        idx = (np.arange(int(len(samples) * SAMPLE_RATE / rate)) * rate / SAMPLE_RATE).astype(int)
        idx = np.clip(idx, 0, len(samples) - 1)
        samples = samples[idx]
    stream.accept_waveform(SAMPLE_RATE, samples)
    stream.accept_waveform(SAMPLE_RATE, np.zeros(int(0.4 * SAMPLE_RATE), dtype=np.float32))
    fired = False
    while spotter.is_ready(stream):
        spotter.decode_stream(stream)
        if spotter.get_result(stream):
            fired = True
            spotter.reset_stream(stream)
    return fired


def submit(wav: Path) -> None:
    bin_path = speak_bin()
    if not os.path.isfile(bin_path) or not os.access(bin_path, os.X_OK):
        log(f"speak script missing: {bin_path}")
        set_state("idle", "dictate")
        return
    subprocess.call([bin_path, "--from-wav", str(wav)])


def on_wake(reader) -> None:
    set_state("recording", "hermes")
    chime = SHARE / "wake-chime.pcm"
    if not chime.exists():
        SHARE.mkdir(parents=True, exist_ok=True)
        chime_wav(chime)
    play_pcm(chime)
    pcm = record_command(reader)
    if speech_ms(pcm) < 350:
        say_yes()
        pcm = record_command(reader)
    if speech_ms(pcm) < 200:
        log("name only, no command")
        set_state("idle", "dictate")
        return
    wav = Path("/tmp/speak-to-hermes-wake.wav")
    write_wav(wav, pcm)
    log("name heard, sending the words after it")
    submit(wav)


def listen(spotter) -> None:
    import numpy as np

    stream = spotter.create_stream()
    mic = open_mic()
    assert mic.stdout is not None
    log("listening locally for: " + ", ".join(phrases()))
    try:
        while True:
            frame = mic.stdout.read(FRAME * 2)
            if len(frame) < FRAME * 2:
                break
            samples = np.frombuffer(frame, dtype=np.int16).astype(np.float32) / 32768.0
            stream.accept_waveform(SAMPLE_RATE, samples)
            fired = False
            while spotter.is_ready(stream):
                spotter.decode_stream(stream)
                if spotter.get_result(stream):
                    fired = True
                    spotter.reset_stream(stream)
            if fired:
                log("name heard")
                on_wake(mic.stdout)
                stream = spotter.create_stream()
                set_state("idle", "dictate")
    finally:
        mic.terminate()
        set_state("idle", "dictate")


def main() -> int:
    phrase_list = phrases()
    model = ensure_model()
    spotter, _kw = build_spotter(model, phrase_list)
    if len(sys.argv) >= 3 and sys.argv[1] == "--test-wav":
        stream = spotter.create_stream()
        fired = feed_wav(spotter, stream, Path(sys.argv[2]))
        print("DETECTED" if fired else "NO")
        return 0 if fired else 1
    listen(spotter)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

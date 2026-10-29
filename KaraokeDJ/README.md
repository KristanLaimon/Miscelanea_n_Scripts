# Karaoke Maker

A focused Rust karaoke editor for Windows and Linux, with a shared WebAssembly editor. Built with egui, eframe and wgpu. The dark cyan/coral interface takes inspiration from the supplied DJ reference; the record icon is original artwork.

## Run

Install a current stable Rust toolchain and **FFmpeg plus FFprobe** on PATH. FFmpeg needs `libass`, `libx264`, `libvpx-vp9`, AAC and Opus support. The app never downloads media or uploads your projects.

```sh
cargo run
```

On Windows, use a Visual Studio Developer PowerShell with the C++ build tools and Windows SDK installed. If Git's `link.exe` masks Microsoft's linker, the included helper selects a valid installed MSVC toolset:

```powershell
./scripts/cargo.ps1 run
```

On Debian/Ubuntu, install the native build dependencies first:

```sh
sudo apt-get install build-essential pkg-config libasound2-dev libudev-dev libxkbcommon-dev libwayland-dev libx11-dev libxi-dev libxcursor-dev libxrandr-dev ffmpeg
```

## Create a karaoke video

1. Choose **New**, then **Add audio / video**. Video imports use the first audio track; the picture is discarded.
2. Import UTF-8 `.lrc` or `.txt` lyrics, paste text, or add individual lines. Importing lyrics replaces the existing lines. Plain text is evenly spaced across the song.
3. Play and select a line to edit its words, start and end. Double-click a line to seek. Drag a timeline block to move it, or enter precise times with the keyboard.
4. Set the stage color, lyric color, text size and animation in **Song & style**. On a compact window, these controls move into a menu.
5. **Save** a binary `.kdj` project, then **Export video**. Choose MP4/H.264, MKV/H.264 or WebM/VP9; 480p, 720p, 1080p or 2160p; 24, 30 or 60 fps; and compression quality. Exported videos contain audio and centered lyrics on your stage color.

**Space** plays/pauses outside text fields. **Ctrl+S** saves. **Ctrl+O** opens. Standard controls support Tab navigation; time fields and the Playhead slider provide keyboard alternatives to dragging.

The initial demo has original sample lyrics and no audio. Use **New** before adding a short source. `examples/demo.kdj` and `examples/demo.lrc` are sample files; regenerate them with `cargo run --example demo_project`. On compact windows, **Import file** opens the dialog with both file selection and pasting options; Settings is also available under **More**.

## Projects, recovery and edge cases

- `.kdj` version 1 stores song metadata, timed lyrics, style and a source media path. **Media is linked, not embedded.** Keep it in its original location or reconnect it with **Add audio / video** after moving files or switching machines.
- Manual saves replace the destination atomically. Failed renders leave an existing output intact. The source cannot be used as the video export destination.
- Settings persist between sessions. Autosave writes a separate recovery copy every 10–600 seconds (default 60), including projects that have never been manually saved. Startup offers restoration; restored projects need a manual Save.
- Native recovery uses `%LOCALAPPDATA%/KaraokeMaker/recovery.kdj` on Windows, or `$XDG_STATE_HOME/KaraokeMaker/recovery.kdj` / `~/.local/state/KaraokeMaker/recovery.kdj` on Linux. There is one recovery slot per user, so run one editing session at a time.
- Invalid timings remain editable but cannot be saved or exported. Recovery only stores valid projects. Every line must have a positive duration within the song; overlaps are rejected. A shorter replacement source is rejected when existing lyrics would extend past it.
- Projects and lyric files are limited to 8 MB, 10,000 lines, 4,096 UTF-8 bytes per lyric, and two hours of media. Native import temporarily extracts stereo PCM audio (about 635 MB/hour); exports also need temporary space beside the destination.
- LRC supports repeated timestamps, metadata, millisecond offsets and Unicode text. Duplicate timestamps, malformed timestamps and mixed timed/untimed lines produce errors. Blank timed entries preserve lyric gaps. LRC export stores starts only: explicit ends, style and animation require `.kdj`.
- The color sweep follows the entire line's duration. Word-level timing and vocal removal are not implemented. Export font rendering may differ slightly from the editor preview; FFmpeg uses Arial or the system's available substitute.
- Native rendering runs on a worker thread. Keep the app open until export finishes. Audio output failures still allow editing and video export.

## Browser editor

```sh
rustup target add wasm32-unknown-unknown
cargo install trunk --version 0.21.14 --locked
trunk serve
# Optimized distributable:
trunk build --cargo-profile web-release --locked
```

Open `http://127.0.0.1:8766`. The bundle is written to `dist/web`; serve it over HTTP/HTTPS. The host page contains only the canvas and startup/error text; application logic and UI stay in Rust.

The browser supports lyric editing, project uploads/downloads, LRC and browser-decodable audio playback. Reconnect media after reopening a project. Browser media is limited to 256 MB, and decoding depends on browser codecs. Save requests a download; confirm it completed in your browser's Downloads. Autosave uses local storage, which can be disabled, full or cleared. Download `.kdj` files to keep durable copies. Waveforms and FFmpeg video encoding are desktop capabilities; the export dialog explains how to continue on desktop. Browser tabs cannot provide the native unsaved-close confirmation.

## Checks

```sh
cargo fmt --all -- --check
cargo clippy --all-targets -- -D warnings
cargo test --all-targets
cargo test ffmpeg_import_and_export_all_formats -- --ignored --nocapture
cargo check --lib --target wasm32-unknown-unknown
cargo build
```

For arguments after `--` in the PowerShell helper, pass an array:

```powershell
./scripts/cargo.ps1 -CargoArgs @('test', 'ffmpeg_import_and_export_all_formats', '--', '--ignored', '--nocapture')
```

Tests cover binary round trips and malformed input, LRC parsing, timing validation, atomic replacement, ASS escaping, actual lyric deletion and unsaved-change confirmation. The explicit FFmpeg integration check generates audio, imports audio and video, verifies audio/video streams in all three export formats, and checks that failed exports preserve an existing file. The separately ignored `audio_play_pause_seek_and_restart` test uses an actual audio output device with volume set to zero. After a Trunk build, `node scripts/browser-smoke.mjs` starts an isolated headless Edge instance, serves the bundle, checks file-picker cancellation, a project upload/download round trip, startup, resize and keyboard input, and writes screenshots to `target/browser-wide.png` and `target/browser-compact.png`. Pass another Chromium executable as its first argument if needed.

## Requested skills

Installed project-local instructions: [foxxy-rust-gui](.agents/skills/foxxy-rust-gui/SKILL.md), [ponytail](.agents/skills/ponytail/SKILL.md), and [REA](.agents/skills/reverse-engineer-anything/SKILL.md). REA was installed from `morluto/rea`; no reverse-engineering server or binary-analysis engine is needed to build this application. These skills will be available to Codex on the next turn.

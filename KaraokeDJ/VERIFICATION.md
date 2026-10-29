# Verification

Checked locally on Windows on 2026-10-14 with Rust 1.99.0, FFmpeg/FFprobe and Edge.

- `cargo fmt --all -- --check`: passed.
- Native `cargo clippy --locked --all-targets -- -D warnings`: passed.
- WASM `cargo clippy --lib --target wasm32-unknown-unknown -- -D warnings`: passed.
- `cargo test --all-targets`: passed (hardware-dependent checks are ignored by default).
- `cargo test --lib -- --include-ignored`: all seven tests passed, including silent hardware playback/seek/restart and FFmpeg import/export.
- `cargo build --locked`: passed. The Windows executable is `target/debug/karaoke-maker.exe`.
- Native startup: launched the executable in an isolated hidden test process, verified it stayed running without startup errors, then closed it.
- `trunk build --cargo-profile web-release --locked`: passed. Optimized browser files are in `dist/web` (WASM approximately 9.2 MB).
- `node scripts/browser-smoke.mjs`: passed against the optimized bundle. Checked startup, cancelling a chooser then reopening it, importing a real `.kdj`, downloading identical project bytes, keyboard input, resize and high DPI. Screenshots: `target/browser-wide.png` and `target/browser-compact.png`.

The domain tests exercise LRC offsets/repeated tags/Unicode, malformed and overlapping timings, binary file validation, atomic replacement and ASS escaping. The UI test clicks actual egui controls to delete lyrics, cancel replacement of an unsaved project, and create a new one. FFmpeg tests import audio and exported video, check both audio and video streams in MP4/MKV/WebM, reject source overwrite, and preserve an existing destination when rendering fails.

Linux compilation/runtime, browser codec coverage, screen readers/IME and long 4K exports have not been tested locally. The included CI workflow builds Windows and Linux and bundles WASM, but has not been run on GitHub in this session. No installer, file association or code signing is included. See README for media linking, recovery and browser capability limits.

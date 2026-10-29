use crate::model::{Animation, MAX_DURATION, MAX_FILE, Project};
use std::{
    fs::File,
    io::{Read, Write},
    path::{Path, PathBuf},
    process::{Command, Stdio},
    time::Duration,
};

fn command(program: &str) -> Command {
    let mut cmd = Command::new(program);
    #[cfg(windows)]
    {
        use std::os::windows::process::CommandExt;
        cmd.creation_flags(0x08000000);
    }
    cmd.stdin(Stdio::null());
    cmd
}

fn run(cmd: &mut Command) -> Result<Vec<u8>, String> {
    let result = cmd
        .output()
        .map_err(|e| format!("Could not start FFmpeg/FFprobe. Install both on PATH. {e}"))?;
    if !result.status.success() {
        let error = String::from_utf8_lossy(&result.stderr);
        return Err(error
            .chars()
            .rev()
            .take(2000)
            .collect::<String>()
            .chars()
            .rev()
            .collect());
    }
    Ok(result.stdout)
}

pub fn read_project(path: &Path) -> Result<Project, String> {
    Project::decode(&read_limited(path)?)
}

pub fn read_limited(path: &Path) -> Result<Vec<u8>, String> {
    let mut bytes = Vec::new();
    File::open(path)
        .map_err(|e| e.to_string())?
        .take(MAX_FILE + 1)
        .read_to_end(&mut bytes)
        .map_err(|e| e.to_string())?;
    if bytes.len() as u64 > MAX_FILE {
        return Err("File exceeds the 8 MB project/lyrics limit.".into());
    }
    Ok(bytes)
}

pub fn atomic_write(path: &Path, bytes: &[u8]) -> Result<(), String> {
    let parent = path
        .parent()
        .filter(|p| !p.as_os_str().is_empty())
        .unwrap_or(Path::new("."));
    let mut temp = tempfile::NamedTempFile::new_in(parent).map_err(|e| e.to_string())?;
    temp.write_all(bytes).map_err(|e| e.to_string())?;
    temp.as_file().sync_all().map_err(|e| e.to_string())?;
    temp.persist(path).map_err(|e| e.to_string())?;
    Ok(())
}

pub fn recovery_path() -> PathBuf {
    // shortcut: one recovery slot per user, use a project recovery list if concurrent editing is needed.
    let root = std::env::var_os("LOCALAPPDATA")
        .map(PathBuf::from)
        .or_else(|| std::env::var_os("XDG_STATE_HOME").map(PathBuf::from))
        .or_else(|| std::env::var_os("HOME").map(|p| PathBuf::from(p).join(".local/state")))
        .unwrap_or_else(std::env::temp_dir);
    root.join("KaraokeMaker").join("recovery.kdj")
}

pub fn save_recovery(bytes: &[u8]) -> Result<(), String> {
    let path = recovery_path();
    std::fs::create_dir_all(path.parent().unwrap()).map_err(|e| e.to_string())?;
    atomic_write(&path, bytes)
}

pub struct PreparedMedia {
    pub directory: tempfile::TempDir,
    pub source: String,
    pub duration: f64,
    pub peaks: Vec<f32>,
}

pub fn prepare_media(path: &Path) -> Result<PreparedMedia, String> {
    let path = path.canonicalize().map_err(|e| e.to_string())?;
    if !path.is_file() {
        return Err("Choose a local audio or video file.".into());
    }
    let duration = run(command("ffprobe")
        .args([
            "-v",
            "error",
            "-protocol_whitelist",
            "file,pipe",
            "-show_entries",
            "format=duration",
            "-of",
            "default=noprint_wrappers=1:nokey=1",
        ])
        .arg(&path))?;
    let duration: f64 = String::from_utf8_lossy(&duration)
        .trim()
        .parse()
        .map_err(|_| "Cannot determine the media duration.")?;
    if !duration.is_finite() || !(0.1..=MAX_DURATION).contains(&duration) {
        return Err("Media must be between 0.1 seconds and 2 hours long.".into());
    }
    let directory = tempfile::tempdir().map_err(|e| e.to_string())?;
    run(command("ffmpeg")
        .args([
            "-v",
            "error",
            "-nostdin",
            "-protocol_whitelist",
            "file,pipe",
            "-i",
        ])
        .arg(&path)
        .args([
            "-map",
            "0:a:0",
            "-vn",
            "-ac",
            "2",
            "-ar",
            "44100",
            "-c:a",
            "pcm_s16le",
            "-t",
            "7200.001",
        ])
        .arg(directory.path().join("audio.wav")))?;
    let raw = run(command("ffmpeg")
        .args(["-v", "error", "-nostdin", "-i"])
        .arg(directory.path().join("audio.wav"))
        .args(["-ac", "1", "-ar", "1000", "-f", "f32le", "pipe:1"]))?;
    let samples: Vec<f32> = raw
        .as_chunks::<4>()
        .0
        .iter()
        .map(|v| f32::from_le_bytes(*v).abs())
        .collect();
    let duration = samples.len() as f64 / 1000.0;
    if !(0.1..=MAX_DURATION).contains(&duration) {
        return Err("Extracted audio must be between 0.1 seconds and 2 hours long.".into());
    }
    let chunk = (samples.len() / 1600).max(1);
    let peaks = samples
        .chunks(chunk)
        .map(|c| c.iter().copied().fold(0.0, f32::max))
        .collect();
    Ok(PreparedMedia {
        directory,
        source: path.to_string_lossy().into_owned(),
        duration,
        peaks,
    })
}

pub struct Playback {
    sink: rodio::Sink,
    _stream: rodio::OutputStream,
    _directory: tempfile::TempDir,
    duration: f64,
}

impl Playback {
    pub fn new(media: PreparedMedia) -> Result<Self, String> {
        let stream = rodio::OutputStreamBuilder::open_default_stream()
            .map_err(|e| format!("Audio output unavailable: {e}"))?;
        let sink = rodio::Sink::connect_new(stream.mixer());
        let file =
            File::open(media.directory.path().join("audio.wav")).map_err(|e| e.to_string())?;
        let decoder = rodio::Decoder::try_from(file).map_err(|e| e.to_string())?;
        sink.pause();
        sink.append(decoder);
        Ok(Self {
            sink,
            _stream: stream,
            _directory: media.directory,
            duration: media.duration,
        })
    }
    pub fn play(&self) {
        self.sink.play();
    }
    pub fn pause(&self) {
        self.sink.pause();
    }
    pub fn position(&self) -> f64 {
        if self.sink.empty() {
            self.duration
        } else {
            self.sink.get_pos().as_secs_f64()
        }
    }
    pub fn seek(&self, time: f64) -> Result<(), String> {
        if self.sink.empty() {
            let file =
                File::open(self._directory.path().join("audio.wav")).map_err(|e| e.to_string())?;
            self.sink
                .append(rodio::Decoder::try_from(file).map_err(|e| e.to_string())?);
        }
        self.sink
            .try_seek(Duration::from_secs_f64(time))
            .map_err(|e| e.to_string())
    }
    pub fn volume(&self, value: f32) {
        self.sink.set_volume(value);
    }
}

#[derive(Clone, Copy, Debug, PartialEq)]
pub enum Format {
    Mp4,
    Mkv,
    Webm,
}
impl Format {
    pub fn extension(self) -> &'static str {
        match self {
            Self::Mp4 => "mp4",
            Self::Mkv => "mkv",
            Self::Webm => "webm",
        }
    }
}

#[derive(Clone)]
pub struct ExportOptions {
    pub format: Format,
    pub height: u32,
    pub fps: u32,
    pub crf: u32,
}
impl Default for ExportOptions {
    fn default() -> Self {
        Self {
            format: Format::Mp4,
            height: 1080,
            fps: 30,
            crf: 20,
        }
    }
}

fn ass_time(time: f64) -> String {
    let cs = (time * 100.0).round() as u64;
    format!(
        "{}:{:02}:{:02}.{:02}",
        cs / 360000,
        cs / 6000 % 60,
        cs / 100 % 60,
        cs % 100
    )
}

pub fn subtitles(project: &Project) -> String {
    let [r, g, b] = project.accent;
    let mut ass = format!(
        "[Script Info]\nScriptType: v4.00+\nPlayResX: 1920\nPlayResY: 1080\nWrapStyle: 0\n\n[V4+ Styles]\nFormat: Name, Fontname, Fontsize, PrimaryColour, SecondaryColour, OutlineColour, BackColour, Bold, Italic, Underline, StrikeOut, ScaleX, ScaleY, Spacing, Angle, BorderStyle, Outline, Shadow, Alignment, MarginL, MarginR, MarginV, Encoding\nStyle: Default,Arial,{},&H00{b:02X}{g:02X}{r:02X},&H00FFFFFF,&H00101820,&H00000000,-1,0,0,0,100,100,0,0,1,2,0,5,100,100,0,1\n\n[Events]\nFormat: Layer, Start, End, Style, Name, MarginL, MarginR, MarginV, Effect, Text\n",
        project.font_size
    );
    for line in &project.lyrics {
        // ASS overrides are never accepted from lyric text.
        let text = line
            .text
            .replace('\\', "＼")
            .replace('{', "｛")
            .replace('}', "｝")
            .replace('\r', "")
            .replace('\n', "\\N");
        let effect = match project.animation {
            Animation::None => String::new(),
            Animation::Fade => format!(
                "{{\\fad({0},{0})}}",
                ((line.end - line.start) * 500.0).min(220.0) as u32
            ),
            Animation::Wipe => format!(
                "{{\\kf{}}}",
                ((line.end - line.start) * 100.0).round() as u64
            ),
        };
        ass.push_str(&format!(
            "Dialogue: 0,{},{},Default,,0,0,0,,{effect}{text}\n",
            ass_time(line.start),
            ass_time(line.end)
        ));
    }
    ass
}

pub fn export(
    project: &Project,
    options: &ExportOptions,
    destination: &Path,
) -> Result<(), String> {
    project.validate()?;
    if ![480, 720, 1080, 2160].contains(&options.height)
        || ![24, 30, 60].contains(&options.fps)
        || !(15..=35).contains(&options.crf)
    {
        return Err("Invalid export settings.".into());
    }
    let source = Path::new(
        project
            .media
            .as_ref()
            .ok_or("Add an audio or video source before exporting.")?,
    )
    .canonicalize()
    .map_err(|e| format!("Reconnect the source media before exporting: {e}"))?;
    if !source.is_file() {
        return Err("Export requires a local audio or video file.".into());
    }
    if Some(&source) == destination.canonicalize().ok().as_ref() {
        return Err("Export cannot overwrite the source media.".into());
    }
    let parent = destination
        .parent()
        .filter(|p| !p.as_os_str().is_empty())
        .unwrap_or(Path::new("."));
    let staging = tempfile::tempdir_in(parent).map_err(|e| e.to_string())?;
    std::fs::write(staging.path().join("lyrics.ass"), subtitles(project))
        .map_err(|e| e.to_string())?;
    let output = staging
        .path()
        .join(format!("render.{}", options.format.extension()));
    let [r, g, b] = project.background;
    let width = (options.height * 16 / 9).next_multiple_of(2);
    let mut cmd = command("ffmpeg");
    cmd.current_dir(staging.path())
        .args(["-v", "error", "-nostdin", "-f", "lavfi", "-i"])
        .arg(format!(
            "color=c=0x{r:02x}{g:02x}{b:02x}:s={width}x{}:r={}",
            options.height, options.fps
        ))
        .args(["-protocol_whitelist", "file,pipe", "-i"])
        .arg(source)
        .args([
            "-map",
            "0:v:0",
            "-map",
            "1:a:0",
            "-vf",
            "ass=lyrics.ass",
            "-t",
        ])
        .arg(project.duration.to_string())
        .args(["-pix_fmt", "yuv420p", "-crf"])
        .arg(options.crf.to_string());
    if options.format == Format::Webm {
        cmd.args([
            "-c:v",
            "libvpx-vp9",
            "-b:v",
            "0",
            "-deadline",
            "realtime",
            "-cpu-used",
            "5",
            "-c:a",
            "libopus",
            "-b:a",
            "192k",
        ]);
    } else {
        cmd.args([
            "-c:v", "libx264", "-preset", "medium", "-c:a", "aac", "-b:a", "192k",
        ]);
        if options.format == Format::Mp4 {
            cmd.args(["-movflags", "+faststart"]);
        }
    }
    cmd.arg(&output);
    run(&mut cmd)?;
    let mut file = File::open(&output).map_err(|e| e.to_string())?;
    let mut temp = tempfile::NamedTempFile::new_in(parent).map_err(|e| e.to_string())?;
    std::io::copy(&mut file, &mut temp).map_err(|e| e.to_string())?;
    temp.as_file().sync_all().map_err(|e| e.to_string())?;
    temp.persist(destination).map_err(|e| e.to_string())?;
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn escapes_ass_and_atomic_save() {
        let mut p = Project::demo();
        p.lyrics[0].text = "{\\pos(0,0)}hello\nworld".into();
        let ass = subtitles(&p);
        assert!(!ass.contains("{\\pos"));
        assert!(ass.contains("hello\\Nworld"));
        let dir = tempfile::tempdir().unwrap();
        let file = dir.path().join("song.kdj");
        atomic_write(&file, &p.encode().unwrap()).unwrap();
        atomic_write(&file, &Project::default().encode().unwrap()).unwrap();
        assert_eq!(read_project(&file).unwrap(), Project::default());
    }
    #[test]
    #[ignore = "requires FFmpeg and FFprobe on PATH"]
    fn ffmpeg_import_and_export_all_formats() {
        let dir = tempfile::tempdir().unwrap();
        let source = dir.path().join("source.wav");
        run(command("ffmpeg")
            .args([
                "-v",
                "error",
                "-f",
                "lavfi",
                "-i",
                "sine=frequency=440:duration=2",
            ])
            .arg(&source))
        .unwrap();
        let media = prepare_media(&source).unwrap();
        assert!((media.duration - 2.0).abs() < 0.1);
        assert!(media.peaks.iter().any(|v| *v > 0.01));
        let p = Project {
            duration: 2.0,
            media: Some(media.source),
            lyrics: vec![crate::model::Lyric {
                start: 0.0,
                end: 2.0,
                text: "Sing, ¡hola!".into(),
            }],
            ..Project::default()
        };
        for format in [Format::Mp4, Format::Mkv, Format::Webm] {
            let dest = dir.path().join(format!("test.{}", format.extension()));
            export(
                &p,
                &ExportOptions {
                    height: 480,
                    format,
                    ..ExportOptions::default()
                },
                &dest,
            )
            .unwrap();
            let probe = run(command("ffprobe")
                .args([
                    "-v",
                    "error",
                    "-show_entries",
                    "stream=codec_type",
                    "-of",
                    "csv=p=0",
                ])
                .arg(&dest))
            .unwrap();
            let probe = String::from_utf8_lossy(&probe);
            assert!(probe.contains("video") && probe.contains("audio"));
            let from_video = prepare_media(&dest).unwrap();
            assert!((from_video.duration - 2.0).abs() < 0.2);
        }
        let destination = dir.path().join("keep.mp4");
        std::fs::write(&destination, b"existing output").unwrap();
        let mut broken = p.clone();
        broken.media = Some(
            dir.path()
                .join("missing.wav")
                .to_string_lossy()
                .into_owned(),
        );
        assert!(export(&broken, &ExportOptions::default(), &destination).is_err());
        assert_eq!(std::fs::read(&destination).unwrap(), b"existing output");
        assert!(export(&p, &ExportOptions::default(), &source).is_err());
    }

    #[test]
    #[ignore = "requires FFmpeg, FFprobe and an audio output device; plays silently"]
    fn audio_play_pause_seek_and_restart() {
        let dir = tempfile::tempdir().unwrap();
        let source = dir.path().join("source.wav");
        run(command("ffmpeg")
            .args([
                "-v",
                "error",
                "-f",
                "lavfi",
                "-i",
                "sine=frequency=440:duration=0.5",
            ])
            .arg(&source))
        .unwrap();
        let audio = Playback::new(prepare_media(&source).unwrap()).unwrap();
        audio.volume(0.0);
        audio.play();
        std::thread::sleep(Duration::from_millis(120));
        assert!(audio.position() > 0.0);
        audio.pause();
        audio.seek(0.25).unwrap();
        assert!((audio.position() - 0.25).abs() < 0.1);
        audio.play();
        std::thread::sleep(Duration::from_millis(600));
        assert!((audio.position() - 0.5).abs() < 0.05);
        audio.pause();
        audio.seek(0.0).unwrap();
        assert!(audio.position() < 0.05);
        audio.play();
        std::thread::sleep(Duration::from_millis(100));
        assert!(audio.position() > 0.0 && audio.position() < 0.5);
    }
}

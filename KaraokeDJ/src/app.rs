use crate::model::{self, Animation, Lyric, Project};
use eframe::egui::{self, Align, Align2, Color32, FontId, RichText, Sense, Stroke, pos2, vec2};
use std::sync::mpsc::{self, Receiver, Sender};
use web_time::{Duration, Instant};

#[cfg(target_arch = "wasm32")]
use crate::browser::{self, Playback};
#[cfg(not(target_arch = "wasm32"))]
use crate::native::{self, ExportOptions, Format, Playback};

const BG: Color32 = Color32::from_rgb(16, 20, 27);
const PANEL: Color32 = Color32::from_rgb(23, 29, 38);
const MUTED: Color32 = Color32::from_rgb(145, 158, 177);
const CYAN: Color32 = Color32::from_rgb(64, 218, 218);
const CORAL: Color32 = Color32::from_rgb(255, 126, 114);

enum Event {
    Cancel,
    Open(Project, String),
    Lyrics(String),
    Saved(Project, String),
    RecoverySaved(Project),
    Recovery(Option<Project>),
    Message(String),
    #[cfg(not(target_arch = "wasm32"))]
    Media(native::PreparedMedia),
    #[cfg(target_arch = "wasm32")]
    Media(Vec<u8>, String),
}
type ResultEvent = Result<Event, String>;

#[cfg(not(target_arch = "wasm32"))]
fn task(
    ctx: egui::Context,
    tx: Sender<ResultEvent>,
    future: impl Future<Output = ResultEvent> + Send + 'static,
) {
    std::thread::spawn(move || {
        let _ = tx.send(pollster::block_on(future));
        ctx.request_repaint();
    });
}
#[cfg(target_arch = "wasm32")]
fn task(
    ctx: egui::Context,
    tx: Sender<ResultEvent>,
    future: impl Future<Output = ResultEvent> + 'static,
) {
    wasm_bindgen_futures::spawn_local(async move {
        let _ = tx.send(future.await);
        ctx.request_repaint();
    });
}

#[derive(serde::Serialize, serde::Deserialize)]
struct Settings {
    autosave_seconds: u64,
    scale: f32,
    reduced_motion: bool,
}
impl Default for Settings {
    fn default() -> Self {
        Self {
            autosave_seconds: 60,
            scale: 1.0,
            reduced_motion: false,
        }
    }
}

pub struct KaraokeApp {
    project: Project,
    saved: Project,
    recovered: Option<Project>,
    recovery_offer: Option<Project>,
    name: Option<String>,
    selected: Option<usize>,
    time: f64,
    playing: bool,
    last_frame: Instant,
    playback: Option<Playback>,
    peaks: Vec<f32>,
    volume: f32,
    settings: Settings,
    show_settings: bool,
    show_import: bool,
    import_text: String,
    show_export: bool,
    show_help: bool,
    pending: Option<&'static str>,
    after_save: Option<&'static str>,
    busy: Option<String>,
    error: Option<String>,
    notice: String,
    last_autosave: Instant,
    tx: Sender<ResultEvent>,
    rx: Receiver<ResultEvent>,
    zoom: f32,
    #[cfg(not(target_arch = "wasm32"))]
    export: ExportOptions,
    #[cfg(target_arch = "wasm32")]
    pending_media: Option<(Playback, String, Instant)>,
}

impl KaraokeApp {
    pub fn new(cc: &eframe::CreationContext<'_>) -> Self {
        let settings: Settings = cc
            .storage
            .and_then(|s| eframe::get_value(s, "settings"))
            .unwrap_or_default();
        let settings = Settings {
            autosave_seconds: settings.autosave_seconds.clamp(10, 600),
            scale: if settings.scale.is_finite() {
                settings.scale.clamp(0.85, 1.5)
            } else {
                1.0
            },
            ..settings
        };
        theme(&cc.egui_ctx);
        cc.egui_ctx.set_zoom_factor(settings.scale);
        let project = Project::demo();
        let (tx, rx) = mpsc::channel();
        task(cc.egui_ctx.clone(), tx.clone(), async {
            #[cfg(not(target_arch = "wasm32"))]
            {
                Ok(Event::Recovery(
                    native::read_project(&native::recovery_path()).ok(),
                ))
            }
            #[cfg(target_arch = "wasm32")]
            {
                Ok(Event::Recovery(browser::recovery()))
            }
        });
        Self {
            saved: project.clone(),
            project,
            recovered: None,
            recovery_offer: None,
            name: None,
            selected: Some(2),
            time: 9.5,
            playing: false,
            last_frame: Instant::now(),
            playback: None,
            peaks: vec![],
            volume: 0.7,
            settings,
            show_settings: false,
            show_import: false,
            import_text: String::new(),
            show_export: false,
            show_help: false,
            pending: None,
            after_save: None,
            busy: None,
            error: None,
            notice: "Demo · try Play, then add your audio to start your own song.".into(),
            last_autosave: Instant::now(),
            tx,
            rx,
            zoom: 1.0,
            #[cfg(not(target_arch = "wasm32"))]
            export: ExportOptions::default(),
            #[cfg(target_arch = "wasm32")]
            pending_media: None,
        }
    }

    fn dirty(&self) -> bool {
        self.project != self.saved
    }

    fn replace(&mut self, project: Project, name: Option<String>) {
        self.pause();
        self.playback = None;
        self.peaks.clear();
        self.time = 0.0;
        self.selected = if project.lyrics.is_empty() {
            None
        } else {
            Some(0)
        };
        self.saved = project.clone();
        self.project = project;
        self.name = name;
        self.last_autosave = Instant::now();
        #[cfg(target_arch = "wasm32")]
        {
            self.pending_media = None;
        }
    }

    fn pause(&mut self) {
        self.playing = false;
        if let Some(audio) = &self.playback {
            audio.pause();
        }
    }

    fn seek(&mut self, time: f64) {
        self.time = time.clamp(0.0, (self.project.duration - 0.001).max(0.0));
        if let Some(audio) = &self.playback
            && let Err(error) = audio.seek(self.time)
        {
            self.error = Some(error);
            self.pause();
        }
    }

    fn toggle(&mut self, ctx: &egui::Context) {
        if self.playing {
            self.pause();
            return;
        }
        if self.time >= self.project.duration - 0.05 {
            self.seek(0.0);
        }
        if let Some(audio) = &self.playback {
            #[cfg(not(target_arch = "wasm32"))]
            audio.play();
            #[cfg(target_arch = "wasm32")]
            match audio.play() {
                Ok(promise) => {
                    let tx = self.tx.clone();
                    let ctx = ctx.clone();
                    wasm_bindgen_futures::spawn_local(async move {
                        if let Err(error) = wasm_bindgen_futures::JsFuture::from(promise).await {
                            let _ = tx
                                .send(Err(format!("Browser could not play this media: {error:?}")));
                            ctx.request_repaint();
                        }
                    });
                }
                Err(e) => {
                    self.error = Some(e);
                    return;
                }
            }
        }
        let _ = ctx;
        self.playing = true;
        self.last_frame = Instant::now();
    }

    fn receive(&mut self, ctx: &egui::Context) {
        while let Ok(result) = self.rx.try_recv() {
            self.busy = None;
            match result {
                Err(e) => {
                    self.after_save = None;
                    self.pause();
                    self.error = Some(e);
                }
                Ok(Event::Cancel) => {
                    self.after_save = None;
                }
                Ok(Event::Message(message)) => self.notice = message,
                Ok(Event::Recovery(project)) => self.recovery_offer = project,
                Ok(Event::RecoverySaved(project)) => {
                    self.recovered = Some(project);
                    self.notice = "Recovery copy saved · use Save to keep a .kdj file.".into();
                }
                Ok(Event::Saved(project, name)) => {
                    self.saved = project;
                    self.name = Some(name);
                    self.notice = "Project saved.".into();
                    #[cfg(target_arch = "wasm32")]
                    {
                        self.notice = "Project download started · confirm it completed in your browser's Downloads.".into();
                    }
                    if let Some(action) = self.after_save.take() {
                        self.perform(action, ctx);
                    }
                }
                Ok(Event::Lyrics(text)) => match model::import_lyrics(&text, self.project.duration)
                {
                    Ok(lines) => {
                        self.project.lyrics = lines;
                        self.selected = Some(0);
                        self.notice =
                            "Lyrics imported. Check the timing, then save your project.".into();
                    }
                    Err(e) => self.error = Some(e),
                },
                Ok(Event::Open(project, name)) => {
                    self.replace(project, Some(name));
                    self.notice = "Project opened.".into();
                    #[cfg(not(target_arch = "wasm32"))]
                    if let Some(path) = self.project.media.clone() {
                        self.load_native(ctx, path);
                    }
                    #[cfg(target_arch = "wasm32")]
                    if self.project.media.is_some() {
                        self.notice = "Project opened · choose Add audio / video to reconnect the source in this browser.".into();
                    }
                }
                #[cfg(not(target_arch = "wasm32"))]
                Ok(Event::Media(media)) => {
                    if self
                        .project
                        .lyrics
                        .iter()
                        .any(|l| l.end > media.duration + 0.001)
                    {
                        self.error = Some("This source is shorter than the lyrics. Shorten the lyrics or use a longer source; the current source was kept.".into());
                        continue;
                    }
                    let duration = media.duration;
                    let source = media.source.clone();
                    let peaks = media.peaks.clone();
                    self.playback = None;
                    self.peaks = peaks;
                    self.project.media = Some(source);
                    self.project.duration = duration;
                    self.time = 0.0;
                    match Playback::new(media) {
                        Ok(audio) => {
                            audio.volume(self.volume);
                            self.playback = Some(audio);
                            self.notice =
                                "Audio ready · video sources contribute audio only.".into();
                        }
                        Err(e) => {
                            self.error = Some(format!(
                                "{e} The source is linked; editing and video export are still available."
                            ))
                        }
                    }
                }
                #[cfg(target_arch = "wasm32")]
                Ok(Event::Media(bytes, name)) => match Playback::new(&bytes) {
                    Ok(audio) => {
                        audio.volume(self.volume);
                        self.pending_media = Some((audio, name, Instant::now()));
                        self.busy = Some("Decoding browser audio…".into());
                    }
                    Err(e) => self.error = Some(e),
                },
            }
        }
        #[cfg(target_arch = "wasm32")]
        if let Some((audio, name, started)) = self.pending_media.take() {
            let duration = audio.duration();
            if duration.is_finite() && duration > 0.0 {
                self.busy = None;
                if !(0.1..=model::MAX_DURATION).contains(&duration)
                    || self.project.lyrics.iter().any(|l| l.end > duration + 0.001)
                {
                    self.error = Some("Source must be between 0.1 seconds and 2 hours, and long enough for all lyrics. The previous source was kept.".into());
                } else {
                    self.project.duration = duration;
                    self.project.media = Some(name);
                    self.playback = Some(audio);
                    self.time = 0.0;
                    self.notice = "Browser audio ready. Export video in the desktop app.".into();
                }
            } else if audio.failed() || started.elapsed().as_secs() >= 30 {
                self.busy = None;
                self.error = Some("This browser could not decode that media within 30 seconds. Try WAV, MP3 or AAC/M4A. The previous source was kept.".into());
            } else {
                self.pending_media = Some((audio, name, started));
            }
            ctx.request_repaint_after(Duration::from_millis(100));
        }
        let _ = ctx;
    }

    #[cfg(not(target_arch = "wasm32"))]
    fn load_native(&mut self, ctx: &egui::Context, path: String) {
        self.pause();
        self.busy = Some("Extracting audio and building waveform…".into());
        task(ctx.clone(), self.tx.clone(), async move {
            native::prepare_media(std::path::Path::new(&path)).map(Event::Media)
        });
    }

    fn request(&mut self, action: &'static str, ctx: &egui::Context) {
        if self.dirty() {
            self.pending = Some(action);
        } else {
            self.perform(action, ctx);
        }
    }

    fn perform(&mut self, action: &str, ctx: &egui::Context) {
        self.pause();
        if action == "new" {
            self.replace(Project::default(), None);
            self.notice = "New project · add audio, then import or write lyrics.".into();
            return;
        }
        if action == "close" {
            self.saved = self.project.clone();
            ctx.send_viewport_cmd(egui::ViewportCommand::Close);
            return;
        }
        self.busy = Some("Opening project…".into());
        task(ctx.clone(), self.tx.clone(), async {
            let Some(file) = rfd::AsyncFileDialog::new()
                .add_filter("Karaoke project", &["kdj"])
                .pick_file()
                .await
            else {
                return Ok(Event::Cancel);
            };
            #[cfg(not(target_arch = "wasm32"))]
            {
                Ok(Event::Open(
                    native::read_project(file.path())?,
                    file.path().to_string_lossy().into_owned(),
                ))
            }
            #[cfg(target_arch = "wasm32")]
            {
                Ok(Event::Open(
                    Project::decode(&browser::read_file(&file, model::MAX_FILE).await?)?,
                    file.file_name(),
                ))
            }
        });
    }

    fn save_project(&mut self, ctx: &egui::Context, save_as: bool) {
        let bytes = match self.project.encode() {
            Ok(b) => b,
            Err(e) => {
                self.after_save = None;
                self.error = Some(e);
                return;
            }
        };
        let project = self.project.clone();
        let path = if save_as { None } else { self.name.clone() };
        self.busy = Some("Saving project…".into());
        task(ctx.clone(), self.tx.clone(), async move {
            #[cfg(not(target_arch = "wasm32"))]
            {
                if let Some(path) = path {
                    native::atomic_write(std::path::Path::new(&path), &bytes)?;
                    return Ok(Event::Saved(project, path));
                }
                let Some(file) = rfd::AsyncFileDialog::new()
                    .add_filter("Karaoke project", &["kdj"])
                    .set_file_name("song.kdj")
                    .save_file()
                    .await
                else {
                    return Ok(Event::Cancel);
                };
                native::atomic_write(file.path(), &bytes)?;
                Ok(Event::Saved(
                    project,
                    file.path().to_string_lossy().into_owned(),
                ))
            }
            #[cfg(target_arch = "wasm32")]
            {
                let name = path.unwrap_or_else(|| "song.kdj".into());
                browser::download(&name, &bytes)?;
                Ok(Event::Saved(project, name))
            }
        });
    }

    fn import_file(&mut self, ctx: &egui::Context) {
        self.busy = Some("Reading lyrics…".into());
        task(ctx.clone(), self.tx.clone(), async {
            let Some(file) = rfd::AsyncFileDialog::new()
                .add_filter("Lyrics", &["lrc", "txt"])
                .pick_file()
                .await
            else {
                return Ok(Event::Cancel);
            };
            #[cfg(not(target_arch = "wasm32"))]
            let bytes = native::read_limited(file.path())?;
            #[cfg(target_arch = "wasm32")]
            let bytes = browser::read_file(&file, model::MAX_FILE).await?;
            if bytes.len() as u64 > model::MAX_FILE {
                return Err("Lyrics exceed 8 MB.".into());
            }
            Ok(Event::Lyrics(String::from_utf8(bytes).map_err(
                |_| "Lyrics must use UTF-8 encoding. Save them as UTF-8 and try again.",
            )?))
        });
    }

    fn import_media(&mut self, ctx: &egui::Context) {
        self.pause();
        self.busy = Some("Loading audio / video…".into());
        task(ctx.clone(), self.tx.clone(), async {
            let Some(file) = rfd::AsyncFileDialog::new()
                .add_filter(
                    "Audio or video",
                    &[
                        "mp3", "wav", "flac", "ogg", "m4a", "aac", "mp4", "mkv", "mov", "webm",
                    ],
                )
                .pick_file()
                .await
            else {
                return Ok(Event::Cancel);
            };
            #[cfg(not(target_arch = "wasm32"))]
            {
                native::prepare_media(file.path()).map(Event::Media)
            }
            #[cfg(target_arch = "wasm32")]
            {
                let bytes = browser::read_file(&file, 256 * 1024 * 1024).await?;
                if bytes.len() > 256 * 1024 * 1024 {
                    return Err(
                        "Browser media limit is 256 MB; use the desktop app for larger files."
                            .into(),
                    );
                }
                Ok(Event::Media(bytes, file.file_name()))
            }
        });
    }

    fn export_lrc(&mut self, ctx: &egui::Context) {
        if let Err(e) = self.project.validate() {
            self.error = Some(e);
            return;
        }
        let text = model::lrc(&self.project.lyrics);
        self.busy = Some("Saving LRC…".into());
        task(ctx.clone(), self.tx.clone(), async move {
            #[cfg(not(target_arch = "wasm32"))]
            {
                let Some(file) = rfd::AsyncFileDialog::new()
                    .add_filter("Timed lyrics", &["lrc"])
                    .set_file_name("lyrics.lrc")
                    .save_file()
                    .await
                else {
                    return Ok(Event::Cancel);
                };
                file.write(text.as_bytes())
                    .await
                    .map_err(|e| e.to_string())?;
            }
            #[cfg(target_arch = "wasm32")]
            browser::download("lyrics.lrc", text.as_bytes())?;
            Ok(Event::Message("LRC saved · LRC stores line start times, but cannot preserve gaps, style or animation.".into()))
        });
    }

    fn autosave(&mut self, ctx: &egui::Context) {
        if self.busy.is_some()
            || !self.dirty()
            || self.recovered.as_ref() == Some(&self.project)
            || self.last_autosave.elapsed().as_secs() < self.settings.autosave_seconds
        {
            return;
        }
        self.last_autosave = Instant::now();
        let bytes = match self.project.encode() {
            Ok(b) => b,
            Err(_) => return,
        };
        let project = self.project.clone();
        self.busy = Some("Saving recovery copy…".into());
        task(ctx.clone(), self.tx.clone(), async move {
            #[cfg(not(target_arch = "wasm32"))]
            native::save_recovery(&bytes)?;
            #[cfg(target_arch = "wasm32")]
            browser::save_recovery(&bytes)?;
            Ok(Event::RecoverySaved(project))
        });
    }

    fn add_line(&mut self) {
        let start = self.time;
        let end = self
            .project
            .lyrics
            .iter()
            .filter(|l| l.start > start)
            .map(|l| l.start)
            .min_by(f64::total_cmp)
            .unwrap_or(self.project.duration)
            .min(start + 4.0);
        if end <= start
            || self
                .project
                .lyrics
                .iter()
                .any(|l| start >= l.start && start < l.end)
        {
            self.error = Some("The playhead is inside an existing line. Move it to an empty part of the timeline to add a line.".into());
            return;
        }
        self.project.lyrics.push(Lyric {
            start,
            end,
            text: "New lyric line".into(),
        });
        self.selected = Some(self.project.lyrics.len() - 1);
    }

    fn header(&mut self, ui: &mut egui::Ui, ctx: &egui::Context) {
        ui.horizontal(|ui| {
            let (rect, _) = ui.allocate_exact_size(vec2(40.0, 40.0), Sense::hover());
            paint_icon(ui.painter(), rect);
            ui.vertical(|ui| {
                ui.label(RichText::new("KARAOKE MAKER").strong().size(
                    if ctx.content_rect().width() < 1050.0 {
                        14.0
                    } else {
                        20.0
                    },
                ));
                if ctx.content_rect().width() >= 1050.0 {
                    ui.label(
                        RichText::new("YOUR WORDS. THEIR MOMENT.")
                            .size(10.0)
                            .color(MUTED),
                    );
                }
            });
            ui.add_space(8.0);
            ui.add_enabled_ui(self.busy.is_none(), |ui| {
                if ui.button("New").clicked() {
                    self.request("new", ctx);
                }
                if ui.button("Open…").clicked() {
                    self.request("open", ctx);
                }
                if ui
                    .button("Save")
                    .on_hover_text("Ctrl+S · save a .kdj project")
                    .clicked()
                {
                    self.save_project(ctx, false);
                }
                ui.menu_button("More", |ui| {
                    if ui.button("Settings").clicked() {
                        self.show_settings = true;
                        ui.close();
                    }
                    if ui.button("Save as…").clicked() {
                        self.save_project(ctx, true);
                        ui.close();
                    }
                    if ui.button("Export LRC…").clicked() {
                        self.export_lrc(ctx);
                        ui.close();
                    }
                    if ui.button("Help & shortcuts").clicked() {
                        self.show_help = true;
                        ui.close();
                    }
                });
            });
            ui.with_layout(egui::Layout::right_to_left(Align::Center), |ui| {
                if ui
                    .add_enabled(
                        self.busy.is_none(),
                        egui::Button::new(RichText::new("Export video").color(BG).strong())
                            .fill(CYAN),
                    )
                    .clicked()
                {
                    self.show_export = true;
                }
                if ctx.content_rect().width() >= 1050.0 && ui.button("Settings").clicked() {
                    self.show_settings = true;
                }
            });
        });
    }

    fn lyrics_panel(&mut self, ui: &mut egui::Ui, ctx: &egui::Context) {
        ui.horizontal(|ui| {
            ui.heading("Lyrics");
            ui.label(RichText::new(format!("{} lines", self.project.lyrics.len())).color(MUTED));
        });
        ui.add_space(6.0);
        let compact = ui.available_width() < 300.0;
        ui.horizontal_wrapped(|ui| {
            if ui.button("Import file…").clicked() {
                if self.project.lyrics.is_empty() && !compact {
                    self.import_file(ctx);
                } else {
                    self.show_import = true;
                }
            }
            if !compact && ui.button("Paste lyrics…").clicked() {
                self.show_import = true;
            }
            if ui.button("+ Line").clicked() {
                self.add_line();
            }
        });
        ui.add_space(8.0);
        if ui.ctx().content_rect().height() >= 780.0 {
            ui.label(
                RichText::new("Select a line to edit its words and timing.")
                    .size(13.0)
                    .color(MUTED),
            );
        }
        ui.separator();
        let mut jump = None;
        egui::ScrollArea::vertical()
            .id_salt("lyric-list")
            .auto_shrink([false, false])
            .show_rows(ui, 66.0, self.project.lyrics.len(), |ui, range| {
                for index in range {
                    let line = &self.project.lyrics[index];
                    let selected = self.selected == Some(index);
                    let active = self.project.active(self.time) == Some(index);
                    let text = format!(
                        "{:02}    {} — {}\n       {}",
                        index + 1,
                        model::timestamp(line.start),
                        model::timestamp(line.end),
                        line.text
                    );
                    let response = ui.add_sized(
                        [ui.available_width(), 62.0],
                        egui::Button::new(RichText::new(text).size(15.0).color(if active {
                            CYAN
                        } else {
                            Color32::from_gray(222)
                        }))
                        .selected(selected)
                        .wrap()
                        .sense(Sense::click()),
                    );
                    if response.clicked() {
                        self.selected = Some(index);
                    }
                    if response.double_clicked() {
                        jump = Some(line.start);
                    }
                }
            });
        if let Some(time) = jump {
            self.seek(time);
        }
    }

    fn preview(&mut self, ui: &mut egui::Ui, ctx: &egui::Context) {
        ui.horizontal(|ui| {
            ui.label(
                RichText::new("STAGE PREVIEW")
                    .size(12.0)
                    .color(MUTED)
                    .strong(),
            );
            ui.with_layout(egui::Layout::right_to_left(Align::Center), |ui| {
                ui.label(
                    RichText::new("16:9  ·  lyrics & audio")
                        .size(12.0)
                        .color(MUTED),
                );
            });
        });
        ui.add_space(8.0);
        let size = vec2(
            ui.available_width(),
            (ui.available_width() * 9.0 / 16.0).min((ui.available_height() - 260.0).max(140.0)),
        );
        let (rect, _) = ui.allocate_exact_size(size, Sense::hover());
        let painter = ui.painter_at(rect);
        let [r, g, b] = self.project.background;
        painter.rect_filled(rect, 6, Color32::from_rgb(r, g, b));
        let stage_width = rect.width();
        let stage = egui::Rect::from_center_size(
            rect.center(),
            vec2(stage_width, stage_width * 9.0 / 16.0),
        );
        let accent = Color32::from_rgb(
            self.project.accent[0],
            self.project.accent[1],
            self.project.accent[2],
        );
        let active = self.project.active(self.time);
        if let Some(index) = active {
            let line = &self.project.lyrics[index];
            let fraction =
                ((self.time - line.start) / (line.end - line.start)).clamp(0.0, 1.0) as f32;
            let font_size = (self.project.font_size * stage_width / 1920.0).max(12.0);
            let font = FontId::proportional(font_size);
            let galley = painter.layout(
                line.text.clone(),
                font.clone(),
                Color32::WHITE,
                stage_width * 0.88,
            );
            let origin = stage.center() - galley.size() / 2.0;
            let fade = if self.project.animation == Animation::Fade && !self.settings.reduced_motion
            {
                ((self.time - line.start).min(line.end - self.time) / 0.22).clamp(0.0, 1.0) as f32
            } else {
                1.0
            };
            let base = if self.project.animation == Animation::Wipe && !self.settings.reduced_motion
            {
                Color32::WHITE
            } else {
                accent
            };
            painter.galley(
                origin,
                painter.layout(
                    line.text.clone(),
                    font.clone(),
                    base.gamma_multiply(fade),
                    stage_width * 0.88,
                ),
                base.gamma_multiply(fade),
            );
            if self.project.animation == Animation::Wipe && !self.settings.reduced_motion {
                let clip = egui::Rect::from_min_max(
                    origin,
                    pos2(
                        origin.x + galley.size().x * fraction,
                        origin.y + galley.size().y,
                    ),
                );
                painter.with_clip_rect(rect.intersect(clip)).galley(
                    origin,
                    painter.layout(line.text.clone(), font, accent, stage_width * 0.88),
                    accent,
                );
            }
        } else {
            painter.text(
                stage.center(),
                Align2::CENTER_CENTER,
                if self.project.lyrics.is_empty() {
                    "Your next sing-along starts here"
                } else {
                    "♪"
                },
                FontId::proportional(22.0),
                MUTED,
            );
        }
        // Editor guides stay outside exported stage content.
        painter.text(
            rect.left_top() + vec2(14.0, 12.0),
            Align2::LEFT_TOP,
            "LIVE PREVIEW",
            FontId::monospace(10.0),
            MUTED,
        );
        ui.add_space(10.0);
        ui.horizontal(|ui| {
            if ui.button("|◀ Start").clicked() {
                self.seek(0.0);
            }
            if ui
                .add(
                    egui::Button::new(
                        RichText::new(if self.playing {
                            "Ⅱ Pause"
                        } else {
                            "▶ Play"
                        })
                        .strong()
                        .color(BG),
                    )
                    .fill(CYAN)
                    .min_size(vec2(110.0, 36.0)),
                )
                .clicked()
            {
                self.toggle(ctx);
            }
            ui.label(
                RichText::new(format!(
                    "{} / {}",
                    model::timestamp(self.time),
                    model::timestamp(self.project.duration)
                ))
                .monospace()
                .size(17.0),
            );
            if ui.available_width() > 130.0 {
                ui.add(
                    egui::Slider::new(&mut self.volume, 0.0..=1.0)
                        .text("Volume")
                        .show_value(false),
                );
                if let Some(audio) = &self.playback {
                    audio.volume(self.volume);
                }
            }
        });
        ui.add_space(6.0);
        ui.horizontal(|ui| {
            if ui.button("Add audio / video…").clicked() {
                self.import_media(ctx);
            }
            ui.add(
                egui::Label::new(
                    RichText::new(
                        self.project
                            .media
                            .as_deref()
                            .and_then(|s| s.rsplit(['/', '\\']).next())
                            .unwrap_or("No audio · silent timing preview"),
                    )
                    .size(13.0)
                    .color(MUTED),
                )
                .truncate(),
            );
        });
        ui.separator();
        self.line_editor(ui);
    }

    fn line_editor(&mut self, ui: &mut egui::Ui) {
        let Some(index) = self.selected.filter(|i| *i < self.project.lyrics.len()) else {
            ui.label("Import lyrics or add a line to begin editing.");
            return;
        };
        ui.horizontal(|ui| {
            ui.label(
                RichText::new(format!("EDIT LINE {:02}", index + 1))
                    .size(12.0)
                    .color(CYAN),
            );
            if ui.small_button("Delete line").clicked() {
                self.project.lyrics.remove(index);
                self.selected = None;
            }
        });
        if self.selected.is_none() {
            return;
        }
        let line = &mut self.project.lyrics[index];
        ui.add(
            egui::TextEdit::multiline(&mut line.text)
                .desired_rows(2)
                .desired_width(f32::INFINITY)
                .char_limit(1024),
        );
        ui.horizontal_wrapped(|ui| {
            ui.label("Start");
            ui.add(
                egui::DragValue::new(&mut line.start)
                    .speed(0.01)
                    .range(0.0..=self.project.duration)
                    .fixed_decimals(2)
                    .suffix(" s"),
            );
            if ui.small_button("Set to playhead").clicked() {
                line.start = self.time;
            }
            ui.label("End");
            ui.add(
                egui::DragValue::new(&mut line.end)
                    .speed(0.01)
                    .range(0.0..=self.project.duration)
                    .fixed_decimals(2)
                    .suffix(" s"),
            );
            if ui.small_button("End here").clicked() {
                line.end = self.time;
            }
        });
    }

    fn inspector(&mut self, ui: &mut egui::Ui) {
        ui.heading("Song & style");
        ui.add_space(12.0);
        ui.label(RichText::new("PROJECT").color(MUTED).size(11.0));
        ui.label("Song title");
        ui.add(
            egui::TextEdit::singleline(&mut self.project.title)
                .desired_width(f32::INFINITY)
                .char_limit(256),
        );
        ui.label("Artist");
        ui.add(
            egui::TextEdit::singleline(&mut self.project.artist)
                .desired_width(f32::INFINITY)
                .char_limit(256),
        );
        ui.add_space(14.0);
        ui.separator();
        ui.label(RichText::new("LYRIC APPEARANCE").color(MUTED).size(11.0));
        ui.add_space(5.0);
        ui.label("Animation");
        egui::ComboBox::from_id_salt("animation")
            .selected_text(match self.project.animation {
                Animation::None => "Still",
                Animation::Fade => "Fade in / out",
                Animation::Wipe => "Line color sweep",
            })
            .show_ui(ui, |ui| {
                ui.selectable_value(&mut self.project.animation, Animation::None, "Still");
                ui.selectable_value(
                    &mut self.project.animation,
                    Animation::Fade,
                    "Fade in / out",
                );
                ui.selectable_value(
                    &mut self.project.animation,
                    Animation::Wipe,
                    "Line color sweep",
                );
            });
        ui.add_space(8.0);
        ui.label("Text size (at 1080p)");
        ui.add(egui::Slider::new(&mut self.project.font_size, 20.0..=96.0).suffix(" px"));
        ui.horizontal(|ui| {
            ui.color_edit_button_srgb(&mut self.project.accent);
            ui.label("Lyric color");
        });
        ui.horizontal(|ui| {
            ui.color_edit_button_srgb(&mut self.project.background);
            ui.label("Stage color");
        });
        ui.add_space(14.0);
        ui.separator();
        ui.label(RichText::new("TIMING").color(MUTED).size(11.0));
        ui.add_enabled_ui(self.playback.is_none(), |ui| {
            ui.label("Song duration");
            ui.add(
                egui::DragValue::new(&mut self.project.duration)
                    .speed(1.0)
                    .range(0.1..=model::MAX_DURATION)
                    .suffix(" s"),
            );
        });
        ui.label(
            RichText::new("Plain lyrics are spaced evenly. Fine-tune each line while listening.")
                .size(13.0)
                .color(MUTED),
        );
        if self.project.animation == Animation::Wipe {
            ui.add_space(10.0);
            ui.label(
                RichText::new("The sweep follows line timing. LRC does not include word timing.")
                    .size(13.0)
                    .color(MUTED),
            );
        }
    }

    fn timeline(&mut self, ui: &mut egui::Ui) {
        let compact = ui.ctx().content_rect().height() < 780.0;
        let mut seek = self.time;
        ui.horizontal(|ui| {
            ui.label(RichText::new("TIMELINE").strong().size(12.0).color(MUTED));
            ui.add(
                egui::Slider::new(&mut seek, 0.0..=self.project.duration)
                    .text("Playhead")
                    .fixed_decimals(2)
                    .suffix(" s"),
            );
            if ui.available_width() > 550.0 {
                ui.label(
                    RichText::new("Click to seek · drag a lyric to move it")
                        .size(13.0)
                        .color(MUTED),
                );
            }
            ui.with_layout(egui::Layout::right_to_left(Align::Center), |ui| {
                ui.add(
                    egui::Slider::new(&mut self.zoom, 1.0..=8.0)
                        .text("Zoom")
                        .show_value(false),
                );
            });
        });
        if seek != self.time {
            self.seek(seek);
        }
        let mut jump = None;
        let duration = self.project.duration;
        egui::ScrollArea::horizontal()
            .id_salt("timeline-scroll")
            .show(ui, |ui| {
                let width = (ui.available_width() * self.zoom).max(400.0);
                let (rect, response) = ui.allocate_exact_size(
                    vec2(width, if compact { 100.0 } else { 132.0 }),
                    Sense::click(),
                );
                response.widget_info(|| {
                    egui::WidgetInfo::labeled(
                        egui::WidgetType::Slider,
                        ui.is_enabled(),
                        "Song timeline. Use the Playhead slider to seek with the keyboard.",
                    )
                });
                let painter = ui.painter_at(rect);
                painter.rect_filled(rect, 4, Color32::from_rgb(12, 16, 22));
                let x = |t: f64| rect.left() + (t / duration) as f32 * width;
                let divisions = (width / 100.0).ceil() as usize;
                for n in 0..=divisions {
                    let t = duration * n as f64 / divisions as f64;
                    let px = x(t);
                    painter.line_segment(
                        [pos2(px, rect.top() + 22.0), pos2(px, rect.bottom())],
                        Stroke::new(1.0_f32, Color32::from_gray(38)),
                    );
                    painter.text(
                        pos2(px + 5.0, rect.top() + 5.0),
                        Align2::LEFT_TOP,
                        model::timestamp(t),
                        FontId::monospace(11.0),
                        MUTED,
                    );
                }
                let mid = rect.top() + if compact { 32.0 } else { 49.0 };
                if self.peaks.is_empty() {
                    painter.line_segment(
                        [pos2(rect.left(), mid), pos2(rect.right(), mid)],
                        Stroke::new(1.0_f32, Color32::from_gray(55)),
                    );
                    painter.text(
                        pos2(rect.left() + 12.0, mid),
                        Align2::LEFT_CENTER,
                        "No waveform · add audio to see your song",
                        FontId::proportional(12.0),
                        MUTED,
                    );
                } else {
                    for (i, peak) in self.peaks.iter().enumerate() {
                        let px = rect.left() + i as f32 / self.peaks.len() as f32 * width;
                        let h = peak.clamp(0.01, 1.0) * if compact { 10.0 } else { 22.0 };
                        painter.line_segment(
                            [pos2(px, mid - h), pos2(px, mid + h)],
                            Stroke::new(
                                (width / self.peaks.len() as f32).max(1.0),
                                CYAN.gamma_multiply(0.6),
                            ),
                        );
                    }
                }
                if response.clicked()
                    && let Some(pos) = response.interact_pointer_pos()
                {
                    jump = Some(((pos.x - rect.left()) / width) as f64 * duration);
                }
                for (index, line) in self.project.lyrics.iter_mut().enumerate() {
                    let block = egui::Rect::from_min_max(
                        pos2(
                            x(line.start),
                            rect.top() + if compact { 50.0 } else { 80.0 },
                        ),
                        pos2(x(line.end).max(x(line.start) + 3.0), rect.bottom() - 12.0),
                    );
                    let interaction = ui.interact(
                        block,
                        ui.id().with(("lyric", index)),
                        Sense::click_and_drag(),
                    );
                    interaction.widget_info(|| {
                        egui::WidgetInfo::labeled(
                            egui::WidgetType::Button,
                            ui.is_enabled(),
                            format!("Lyric {}: {}", index + 1, line.text),
                        )
                    });
                    let selected = self.selected == Some(index);
                    painter.rect_filled(
                        block.shrink(1.0),
                        3,
                        if selected {
                            CORAL.gamma_multiply(0.85)
                        } else {
                            Color32::from_rgb(40, 77, 85)
                        },
                    );
                    painter
                        .with_clip_rect(block.shrink(4.0).intersect(ui.clip_rect()))
                        .text(
                            block.left_center() + vec2(8.0, 0.0),
                            Align2::LEFT_CENTER,
                            &line.text,
                            FontId::proportional(13.0),
                            if selected { BG } else { Color32::WHITE },
                        );
                    if interaction.clicked() {
                        self.selected = Some(index);
                    }
                    if interaction.dragged() {
                        self.selected = Some(index);
                        let delta = interaction.drag_delta().x as f64 / width as f64 * duration;
                        let length = line.end - line.start;
                        line.start = (line.start + delta).clamp(0.0, (duration - length).max(0.0));
                        line.end = line.start + length;
                    }
                }
                let px = x(self.time);
                painter.line_segment(
                    [pos2(px, rect.top()), pos2(px, rect.bottom())],
                    Stroke::new(2.0_f32, CORAL),
                );
                painter.circle_filled(pos2(px, rect.top() + 2.0), 4.0, CORAL);
            });
        if let Some(time) = jump {
            self.seek(time);
        }
    }

    fn dialogs(&mut self, ctx: &egui::Context) {
        if let Some(error) = self.error.clone() {
            egui::Modal::new(egui::Id::new("error")).show(ctx, |ui| {
                ui.heading("Could not complete action");
                ui.set_max_width(520.0);
                ui.colored_label(CORAL, error);
                if ui.button("OK").clicked() {
                    self.error = None;
                }
            });
        }
        if let Some(action) = self.pending {
            egui::Modal::new(egui::Id::new("unsaved")).show(ctx, |ui| {
                ui.heading("Keep your changes?");
                ui.label("This project has unsaved changes. Save it before continuing, or discard the edits.");
                ui.horizontal(|ui| {
                    if ui.button("Save first").clicked() { self.pending = None; self.after_save = Some(action); self.save_project(ctx, false); }
                    if ui.button("Discard and continue").clicked() { self.pending = None; self.perform(action, ctx); }
                    if ui.button("Cancel").clicked() { self.pending = None; }
                });
            });
        }
        if self.recovery_offer.is_some() {
            egui::Modal::new(egui::Id::new("recovery")).show(ctx, |ui| {
                ui.heading("A recovery copy is available");
                ui.label(
                    "An autosaved project was found. Restore it to review and save your work.",
                );
                ui.horizontal(|ui| {
                    if ui.button("Restore recovery").clicked() {
                        let recovered = self.recovery_offer.take().unwrap();
                        self.replace(recovered.clone(), None);
                        self.saved = Project::default();
                        self.recovered = Some(recovered);
                        #[cfg(not(target_arch = "wasm32"))]
                        if let Some(path) = self.project.media.clone() {
                            self.load_native(ctx, path);
                        }
                    }
                    if ui.button("Start without restoring").clicked() {
                        self.recovery_offer = None;
                    }
                });
            });
        }
        let mut show = self.show_settings;
        egui::Window::new("Settings").open(&mut show).resizable(false).show(ctx, |ui| {
            ui.heading("Make yourself comfortable");
            ui.label("Autosave recovery interval");
            ui.add(egui::Slider::new(&mut self.settings.autosave_seconds, 10..=600).suffix(" seconds"));
            ui.label("Interface size");
            if ui.add(egui::Slider::new(&mut self.settings.scale, 0.85..=1.5).suffix("×")).changed() { ctx.set_zoom_factor(self.settings.scale); }
            ui.checkbox(&mut self.settings.reduced_motion, "Reduce preview motion");
            ui.label(RichText::new("Recovery protects valid edits. Save creates your portable .kdj file. Media stays linked, rather than embedded.").size(13.0).color(MUTED));
        });
        self.show_settings = show;
        let mut show = self.show_import;
        egui::Window::new("Import lyrics").open(&mut show).default_width(520.0).show(ctx, |ui| {
            ui.label("Import replaces the current lyric lines. LRC keeps timestamps; plain text gets evenly spaced timing.");
            if ui.button("Choose .lrc / .txt file…").clicked() { self.import_file(ctx); self.show_import = false; }
            ui.separator();
            ui.label("Or paste UTF-8 lyrics here:");
            ui.add(egui::TextEdit::multiline(&mut self.import_text).desired_width(f32::INFINITY).desired_rows(12).char_limit(200000));
            if ui.button("Replace lyrics with pasted text").clicked() {
                match model::import_lyrics(&self.import_text, self.project.duration) {
                    Ok(lines) => { self.project.lyrics = lines; self.selected = Some(0); self.show_import = false; },
                    Err(e) => self.error = Some(e),
                }
            }
        });
        self.show_import &= show;
        let mut show = self.show_help;
        egui::Window::new("A song, in a few steps").open(&mut show).default_width(500.0).show(ctx, |ui| {
            ui.label("1. New → Add audio / video. Video contributes only its audio.\n2. Import LRC or plain lyrics, or add individual lines.\n3. Play and select a line to edit words, start and end times.\n4. Choose a color and animation. Save your .kdj project.\n5. Export a video from the desktop app.");
            ui.separator();
            ui.label("Space: play / pause · Ctrl+S: save · Ctrl+O: open\nDouble-click a lyric: seek to it · Drag a timeline block: move timing\nUse Tab and arrow keys to edit timing without a mouse.");
            ui.label("Keep source media in its original location, or reconnect it after moving a project. LRC supports line starts, not explicit end times or word timing.");
            #[cfg(target_arch = "wasm32")]
            ui.colored_label(CORAL, "Browser: save downloads a project, autosave uses local browser storage. Reconnect media after reopening. Desktop FFmpeg is required for video export.");
        });
        self.show_help = show;
        self.export_dialog(ctx);
    }

    #[cfg(target_arch = "wasm32")]
    fn export_dialog(&mut self, ctx: &egui::Context) {
        let mut show = self.show_export;
        egui::Window::new("Export video on desktop").open(&mut show).show(ctx, |ui| {
            ui.label("Video encoding requires FFmpeg in the Windows or Linux desktop app. Save your .kdj project and open it there, then reconnect your source media.");
            if ui.button("Download project…").clicked() { self.save_project(ctx, true); }
            if ui.button("Download LRC…").clicked() { self.export_lrc(ctx); }
        });
        self.show_export = show;
    }

    #[cfg(not(target_arch = "wasm32"))]
    fn export_dialog(&mut self, ctx: &egui::Context) {
        let mut show = self.show_export;
        egui::Window::new("Export your karaoke video").open(&mut show).default_width(440.0).resizable(false).show(ctx, |ui| {
            ui.label("A 16:9 video with your audio, stage color and animated lyrics.");
            ui.add_space(10.0);
            ui.label("File format");
            ui.horizontal(|ui| {
                ui.selectable_value(&mut self.export.format, Format::Mp4, "MP4 (H.264)");
                ui.selectable_value(&mut self.export.format, Format::Mkv, "MKV (H.264)");
                ui.selectable_value(&mut self.export.format, Format::Webm, "WebM (VP9)");
            });
            ui.label("Resolution");
            egui::ComboBox::from_id_salt("resolution").selected_text(format!("{}p", self.export.height)).show_ui(ui, |ui| {
                for h in [480, 720, 1080, 2160] { ui.selectable_value(&mut self.export.height, h, format!("{h}p")); }
            });
            ui.label("Frame rate");
            ui.horizontal(|ui| { for fps in [24, 30, 60] { ui.selectable_value(&mut self.export.fps, fps, format!("{fps} fps")); } });
            ui.label("Compression (lower = higher quality, larger file)");
            ui.add(egui::Slider::new(&mut self.export.crf, 15..=35).text("CRF"));
            ui.label(RichText::new("FFmpeg and FFprobe must be installed on PATH. Export runs in the background; keep the app open until it finishes.").size(13.0).color(MUTED));
            if ui.add_enabled(self.busy.is_none(), egui::Button::new("Choose destination & export…").fill(CYAN)).clicked() {
                if let Err(e) = self.project.validate() { self.error = Some(e); return; }
                if self.project.media.is_none() { self.error = Some("Add an audio or video source before exporting.".into()); return; }
                let project = self.project.clone(); let options = self.export.clone();
                self.pause(); self.busy = Some("Rendering video… This may take a few minutes.".into()); self.show_export = false;
                task(ctx.clone(), self.tx.clone(), async move {
                    let ext = options.format.extension();
                    let Some(file) = rfd::AsyncFileDialog::new().add_filter("Karaoke video", &[ext]).set_file_name(format!("karaoke.{ext}")).save_file().await else { return Ok(Event::Cancel); };
                    native::export(&project, &options, file.path())?;
                    Ok(Event::Message(format!("Video exported to {}", file.path().display())))
                });
            }
        });
        self.show_export &= show;
    }
}

impl eframe::App for KaraokeApp {
    fn update(&mut self, ctx: &egui::Context, _frame: &mut eframe::Frame) {
        self.receive(ctx);
        let now = Instant::now();
        if self.playing {
            self.time = self
                .playback
                .as_ref()
                .map_or(self.time + (now - self.last_frame).as_secs_f64(), |p| {
                    p.position()
                });
            if self.time >= self.project.duration - 0.02 {
                self.pause();
                self.time = self.project.duration;
            }
            ctx.request_repaint_after(Duration::from_millis(16));
        }
        self.last_frame = now;
        if ctx.input(|i| i.viewport().close_requested()) && (self.dirty() || self.busy.is_some()) {
            ctx.send_viewport_cmd(egui::ViewportCommand::CancelClose);
            if self.busy.is_some() {
                self.error =
                    Some("Wait for the current operation to finish before closing.".into());
            } else {
                self.pending = Some("close");
            }
        }
        if self.busy.is_none()
            && !ctx.wants_keyboard_input()
            && self.pending.is_none()
            && self.recovery_offer.is_none()
            && ctx.input_mut(|i| i.consume_key(egui::Modifiers::NONE, egui::Key::Space))
        {
            self.toggle(ctx);
        }
        if self.busy.is_none() {
            if ctx.input_mut(|i| i.consume_key(egui::Modifiers::COMMAND, egui::Key::S)) {
                self.save_project(ctx, false);
            }
            if ctx.input_mut(|i| i.consume_key(egui::Modifiers::COMMAND, egui::Key::O)) {
                self.request("open", ctx);
            }
        }
        self.autosave(ctx);
        ctx.request_repaint_after(Duration::from_secs(1));
        egui::TopBottomPanel::top("header")
            .frame(egui::Frame::new().fill(PANEL).inner_margin(14))
            .show(ctx, |ui| self.header(ui, ctx));
        egui::TopBottomPanel::bottom("status")
            .frame(egui::Frame::new().fill(BG).inner_margin(8))
            .show(ctx, |ui| {
                ui.horizontal(|ui| {
                    if let Some(busy) = &self.busy {
                        ui.spinner();
                        ui.label(busy);
                    } else if let Err(e) = self.project.validate() {
                        ui.colored_label(CORAL, e);
                    } else {
                        ui.add(
                            egui::Label::new(RichText::new(&self.notice).size(12.0).color(MUTED))
                                .truncate(),
                        );
                    }
                    ui.with_layout(egui::Layout::right_to_left(Align::Center), |ui| {
                        ui.colored_label(
                            if self.dirty() { CORAL } else { CYAN },
                            if self.dirty() {
                                "● Unsaved edits"
                            } else {
                                "● Saved"
                            },
                        );
                    });
                });
            });
        egui::TopBottomPanel::bottom("timeline")
            .resizable(ctx.content_rect().height() >= 780.0)
            .default_height(if ctx.content_rect().height() < 780.0 {
                170.0
            } else {
                210.0
            })
            .height_range(if ctx.content_rect().height() < 780.0 {
                160.0..=180.0
            } else {
                190.0..=350.0
            })
            .frame(egui::Frame::new().fill(PANEL).inner_margin(12))
            .show(ctx, |ui| {
                ui.add_enabled_ui(self.busy.is_none(), |ui| self.timeline(ui));
            });
        let wide = ctx.content_rect().width() >= 1050.0;
        egui::SidePanel::left("lyrics")
            .resizable(true)
            .default_width(if wide { 340.0 } else { 260.0 })
            .width_range(
                220.0..=if wide {
                    500.0
                } else {
                    (ctx.content_rect().width() * 0.36).max(220.0)
                },
            )
            .frame(egui::Frame::new().fill(PANEL).inner_margin(16))
            .show(ctx, |ui| {
                ui.add_enabled_ui(self.busy.is_none(), |ui| self.lyrics_panel(ui, ctx));
            });
        if wide {
            egui::SidePanel::right("inspector")
                .resizable(false)
                .exact_width(250.0)
                .frame(egui::Frame::new().fill(PANEL).inner_margin(16))
                .show(ctx, |ui| {
                    egui::ScrollArea::vertical().show(ui, |ui| {
                        ui.add_enabled_ui(self.busy.is_none(), |ui| self.inspector(ui));
                    });
                });
        }
        egui::CentralPanel::default()
            .frame(egui::Frame::new().fill(BG).inner_margin(20))
            .show(ctx, |ui| {
                ui.add_enabled_ui(self.busy.is_none(), |ui| {
                    ui.horizontal(|ui| {
                        let width =
                            (ui.available_width() - if wide { 0.0 } else { 140.0 }).max(40.0);
                        ui.add_sized(
                            [width, 30.0],
                            egui::Label::new(RichText::new(&self.project.title).size(24.0))
                                .truncate(),
                        );
                        if !wide {
                            ui.menu_button("Song & style", |ui| self.inspector(ui));
                        }
                    });
                    ui.label(
                        RichText::new(if self.project.artist.is_empty() {
                            "Your karaoke project"
                        } else {
                            &self.project.artist
                        })
                        .color(MUTED),
                    );
                    ui.add_space(12.0);
                    egui::ScrollArea::vertical()
                        .scroll_bar_visibility(
                            egui::scroll_area::ScrollBarVisibility::AlwaysVisible,
                        )
                        .show(ui, |ui| self.preview(ui, ctx));
                });
            });
        self.dialogs(ctx);
    }

    fn save(&mut self, storage: &mut dyn eframe::Storage) {
        eframe::set_value(storage, "settings", &self.settings);
    }
}

fn theme(ctx: &egui::Context) {
    ctx.set_theme(egui::Theme::Dark);
    let mut style = egui::Style {
        visuals: egui::Visuals::dark(),
        ..Default::default()
    };
    style.visuals.panel_fill = PANEL;
    style.visuals.window_fill = PANEL;
    style.visuals.extreme_bg_color = BG;
    style.visuals.selection.bg_fill = Color32::from_rgb(36, 85, 93);
    style.visuals.selection.stroke = Stroke::new(1.0_f32, CYAN);
    style.visuals.widgets.inactive.bg_fill = Color32::from_rgb(35, 44, 57);
    style.visuals.widgets.hovered.bg_fill = Color32::from_rgb(48, 68, 82);
    style.visuals.widgets.active.bg_fill = Color32::from_rgb(36, 85, 93);
    style.visuals.override_text_color = Some(Color32::from_rgb(226, 232, 240));
    style.spacing.item_spacing = vec2(8.0, 8.0);
    style.spacing.button_padding = vec2(12.0, 8.0);
    style.spacing.interact_size = vec2(36.0, 32.0);
    style
        .text_styles
        .insert(egui::TextStyle::Body, FontId::proportional(16.0));
    style
        .text_styles
        .insert(egui::TextStyle::Button, FontId::proportional(15.0));
    style
        .text_styles
        .insert(egui::TextStyle::Heading, FontId::proportional(24.0));
    ctx.set_style_of(egui::Theme::Dark, style);
}

fn paint_icon(painter: &egui::Painter, rect: egui::Rect) {
    painter.rect_filled(rect, 9, BG);
    let center = rect.center();
    painter.circle_stroke(center, rect.width() * 0.32, Stroke::new(3.0_f32, CYAN));
    painter.circle_filled(center, 3.0, CORAL);
    painter.line_segment(
        [center + vec2(5.0, -8.0), center + vec2(13.0, -15.0)],
        Stroke::new(4.0_f32, CORAL),
    );
}

pub fn icon() -> egui::IconData {
    let size = 64;
    let mut rgba = vec![0; size * size * 4];
    for y in 0..size {
        for x in 0..size {
            let dx = x as f32 - 31.5;
            let dy = y as f32 - 31.5;
            let distance = dx.hypot(dy);
            let color = if distance < 5.0 {
                CORAL
            } else if (18.0..=23.0).contains(&distance) {
                CYAN
            } else {
                BG
            };
            let offset = (y * size + x) * 4;
            rgba[offset..offset + 4].copy_from_slice(&color.to_array());
        }
    }
    egui::IconData {
        rgba,
        width: size as u32,
        height: size as u32,
    }
}

#[cfg(all(test, not(target_arch = "wasm32")))]
mod tests {
    use super::*;
    use eframe::App;

    fn draw(
        app: &mut KaraokeApp,
        ctx: &egui::Context,
        size: egui::Vec2,
        events: Vec<egui::Event>,
    ) -> egui::FullOutput {
        let input = egui::RawInput {
            screen_rect: Some(egui::Rect::from_min_size(egui::Pos2::ZERO, size)),
            events,
            ..Default::default()
        };
        ctx.run(input, |ctx| {
            app.update(ctx, &mut eframe::Frame::_new_kittest())
        })
    }

    fn text_center(shape: &egui::Shape, label: &str) -> Option<egui::Pos2> {
        match shape {
            egui::Shape::Text(text) if text.galley.job.text == label => {
                Some(text.pos + text.galley.size() * 0.5)
            }
            egui::Shape::Vec(shapes) => shapes.iter().find_map(|s| text_center(s, label)),
            _ => None,
        }
    }

    fn click(app: &mut KaraokeApp, ctx: &egui::Context, label: &str) {
        let size = vec2(1440.0, 960.0);
        let _ = draw(app, ctx, size, vec![]);
        let output = draw(app, ctx, size, vec![]);
        let pos = output
            .shapes
            .iter()
            .find_map(|s| text_center(&s.shape, label))
            .unwrap_or_else(|| panic!("Missing visible control: {label}"));
        for pressed in [true, false] {
            let _ = draw(
                app,
                ctx,
                size,
                vec![
                    egui::Event::PointerMoved(pos),
                    egui::Event::PointerButton {
                        pos,
                        button: egui::PointerButton::Primary,
                        pressed,
                        modifiers: egui::Modifiers::NONE,
                    },
                ],
            );
        }
    }

    #[test]
    fn editor_delete_and_unsaved_confirmation() {
        let ctx = egui::Context::default();
        let mut app = KaraokeApp::new(&eframe::CreationContext::_new_kittest(ctx.clone()));
        // Keep recovery from the real user's storage out of this UI test.
        (app.tx, app.rx) = mpsc::channel();
        assert!(!app.dirty());
        click(&mut app, &ctx, "Delete line");
        assert_eq!(app.project.lyrics.len(), 6);
        assert!(app.dirty());
        click(&mut app, &ctx, "New");
        assert_eq!(app.pending, Some("new"));
        click(&mut app, &ctx, "Cancel");
        assert_eq!(app.project.lyrics.len(), 6);
        click(&mut app, &ctx, "New");
        click(&mut app, &ctx, "Discard and continue");
        assert_eq!(app.project, Project::default());
        assert!(!app.dirty());
        app.time = 1.0;
        app.add_line();
        assert_eq!(app.selected, Some(0));
        assert!(app.project.validate().is_ok());
        let before = app.project.clone();
        app.add_line();
        assert_eq!(app.project, before);
        app.error = None;
        for size in [vec2(800.0, 650.0), vec2(1920.0, 1080.0)] {
            let output = draw(&mut app, &ctx, size, vec![]);
            assert!(!output.shapes.is_empty());
        }
    }
}

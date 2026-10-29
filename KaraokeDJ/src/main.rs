#[cfg(not(target_arch = "wasm32"))]
fn main() -> eframe::Result {
    let options = eframe::NativeOptions {
        viewport: eframe::egui::ViewportBuilder::default()
            .with_title("Karaoke Maker")
            .with_inner_size([1440.0, 960.0])
            .with_min_inner_size([800.0, 650.0])
            .with_icon(karaoke_maker::app::icon()),
        renderer: eframe::Renderer::Wgpu,
        ..Default::default()
    };
    eframe::run_native(
        "Karaoke Maker",
        options,
        Box::new(|cc| Ok(Box::new(karaoke_maker::app::KaraokeApp::new(cc)))),
    )
}

#[cfg(target_arch = "wasm32")]
fn main() {
    karaoke_maker::start();
}

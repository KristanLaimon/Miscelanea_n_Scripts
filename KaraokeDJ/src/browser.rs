use wasm_bindgen::JsValue;

pub struct Playback {
    audio: web_sys::HtmlAudioElement,
    url: String,
}

impl Playback {
    pub fn new(bytes: &[u8]) -> Result<Self, String> {
        let parts = js_sys::Array::new();
        parts.push(&js_sys::Uint8Array::from(bytes));
        let blob = web_sys::Blob::new_with_u8_array_sequence(&parts).map_err(error)?;
        let url = web_sys::Url::create_object_url_with_blob(&blob).map_err(error)?;
        let audio = match web_sys::HtmlAudioElement::new_with_src(&url) {
            Ok(audio) => audio,
            Err(e) => {
                let _ = web_sys::Url::revoke_object_url(&url);
                return Err(error(e));
            }
        };
        audio.set_preload("auto");
        Ok(Self { audio, url })
    }
    pub fn play(&self) -> Result<js_sys::Promise, String> {
        self.audio.play().map_err(error)
    }
    pub fn pause(&self) {
        let _ = self.audio.pause();
    }
    pub fn position(&self) -> f64 {
        self.audio.current_time()
    }
    pub fn duration(&self) -> f64 {
        self.audio.duration()
    }
    pub fn failed(&self) -> bool {
        self.audio.network_state() == 3
    }
    pub fn seek(&self, time: f64) -> Result<(), String> {
        self.audio.set_current_time(time);
        Ok(())
    }
    pub fn volume(&self, value: f32) {
        self.audio.set_volume(value as f64);
    }
}

impl Drop for Playback {
    fn drop(&mut self) {
        self.pause();
        self.audio.set_src("");
        let _ = web_sys::Url::revoke_object_url(&self.url);
    }
}

fn error(e: JsValue) -> String {
    format!("Browser audio error: {e:?}")
}

pub async fn read_file(file: &rfd::FileHandle, limit: u64) -> Result<Vec<u8>, String> {
    if file.inner().size() > limit as f64 {
        return Err(format!(
            "File exceeds the {} MB browser limit.",
            limit / 1024 / 1024
        ));
    }
    let buffer = wasm_bindgen_futures::JsFuture::from(file.inner().array_buffer())
        .await
        .map_err(|e| format!("Could not read the selected file: {e:?}"))?;
    Ok(js_sys::Uint8Array::new(&buffer).to_vec())
}

pub fn download(name: &str, bytes: &[u8]) -> Result<(), String> {
    use wasm_bindgen::JsCast;
    let window = web_sys::window().ok_or("Browser window unavailable.")?;
    let document = window.document().ok_or("Browser document unavailable.")?;
    let anchor = document
        .create_element("a")
        .map_err(error)?
        .dyn_into::<web_sys::HtmlAnchorElement>()
        .map_err(|e| error(e.into()))?;
    let parts = js_sys::Array::new();
    parts.push(&js_sys::Uint8Array::from(bytes));
    let blob = web_sys::Blob::new_with_u8_array_sequence(&parts).map_err(error)?;
    let url = web_sys::Url::create_object_url_with_blob(&blob).map_err(error)?;
    anchor.set_href(&url);
    anchor.set_download(name);
    anchor.click();
    let revoke = wasm_bindgen::closure::Closure::once_into_js(move || {
        let _ = web_sys::Url::revoke_object_url(&url);
    });
    window
        .set_timeout_with_callback_and_timeout_and_arguments_0(revoke.unchecked_ref(), 1000)
        .map_err(error)?;
    Ok(())
}

pub fn save_recovery(bytes: &[u8]) -> Result<(), String> {
    let storage = web_sys::window()
        .and_then(|w| w.local_storage().ok().flatten())
        .ok_or("Browser storage is unavailable; download your project to keep it.")?;
    let hex: String = bytes.iter().map(|b| format!("{b:02x}")).collect();
    storage
        .set_item("karaoke-maker-recovery", &hex)
        .map_err(|_| "Browser recovery storage is full; download your project.".into())
}

pub fn recovery() -> Option<crate::model::Project> {
    let hex = web_sys::window()?
        .local_storage()
        .ok()??
        .get_item("karaoke-maker-recovery")
        .ok()??;
    if hex.len() as u64 > crate::model::MAX_FILE * 2 || !hex.is_ascii() {
        return None;
    }
    let bytes: Option<Vec<_>> = (0..hex.len())
        .step_by(2)
        .map(|i| u8::from_str_radix(hex.get(i..i + 2)?, 16).ok())
        .collect();
    crate::model::Project::decode(&bytes?).ok()
}

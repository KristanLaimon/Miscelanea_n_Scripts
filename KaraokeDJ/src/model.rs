use bincode::Options;
use serde::{Deserialize, Serialize};

pub const MAX_FILE: u64 = 8 * 1024 * 1024;
pub const MAX_DURATION: f64 = 7200.0;
const HEADER: &[u8] = b"KDJ\0\x01";

#[derive(Clone, Debug, PartialEq, Serialize, Deserialize)]
pub struct Lyric {
    pub start: f64,
    pub end: f64,
    pub text: String,
}

#[derive(Clone, Copy, Debug, PartialEq, Serialize, Deserialize)]
pub enum Animation {
    None,
    Fade,
    Wipe,
}

#[derive(Clone, Debug, PartialEq, Serialize, Deserialize)]
pub struct Project {
    pub title: String,
    pub artist: String,
    pub media: Option<String>,
    pub duration: f64,
    pub lyrics: Vec<Lyric>,
    pub animation: Animation,
    pub font_size: f32,
    pub background: [u8; 3],
    pub accent: [u8; 3],
}

impl Default for Project {
    fn default() -> Self {
        Self {
            title: "Untitled song".into(),
            artist: String::new(),
            media: None,
            duration: 60.0,
            lyrics: vec![],
            animation: Animation::Wipe,
            font_size: 80.0,
            background: [12, 19, 29],
            accent: [64, 218, 218],
        }
    }
}

impl Project {
    pub fn demo() -> Self {
        Self {
            title: "A little more light".into(),
            artist: "Demo project · add your own audio".into(),
            duration: 32.0,
            lyrics: [
                (0.0, 4.0, "When the night begins to fall"),
                (4.0, 8.0, "And the city fades from view"),
                (8.0, 12.0, "There's a little more light"),
                (12.0, 16.0, "Every time I sing with you"),
                (17.0, 21.0, "Let the music take us home"),
                (21.0, 26.0, "To a place we've always known"),
                (26.0, 31.0, "There's a little more light with you"),
            ]
            .into_iter()
            .map(|(start, end, text)| Lyric {
                start,
                end,
                text: text.into(),
            })
            .collect(),
            ..Self::default()
        }
    }

    pub fn validate(&self) -> Result<(), String> {
        if !self.duration.is_finite() || !(0.1..=MAX_DURATION).contains(&self.duration) {
            return Err("Song duration must be between 0.1 seconds and 2 hours.".into());
        }
        if self.title.len() > 1024
            || self.artist.len() > 1024
            || self
                .media
                .as_ref()
                .is_some_and(|s| s.len() > 32768 || s.contains('\0'))
        {
            return Err("Project metadata is too long or contains an invalid path.".into());
        }
        if !self.font_size.is_finite()
            || !(20.0..=96.0).contains(&self.font_size)
            || self.lyrics.len() > 10000
        {
            return Err("Invalid font size or too many lyric lines (maximum 10,000).".into());
        }
        for line in &self.lyrics {
            if !line.start.is_finite()
                || !line.end.is_finite()
                || line.start < 0.0
                || line.end <= line.start
                || line.end > self.duration + 0.001
                || line.text.len() > 4096
            {
                return Err("Each lyric needs a start before its end, within the song, and at most 4,096 bytes of text.".into());
            }
        }
        let mut ordered: Vec<_> = self.lyrics.iter().collect();
        ordered.sort_by(|a, b| a.start.total_cmp(&b.start));
        if ordered.windows(2).any(|w| w[0].end > w[1].start + 0.001) {
            return Err(
                "Lyric lines overlap. Adjust their start and end times before saving or exporting."
                    .into(),
            );
        }
        Ok(())
    }

    pub fn encode(&self) -> Result<Vec<u8>, String> {
        self.validate()?;
        let mut data = HEADER.to_vec();
        data.extend(
            bincode::DefaultOptions::new()
                .with_limit(MAX_FILE)
                .serialize(self)
                .map_err(|e| e.to_string())?,
        );
        if data.len() as u64 > MAX_FILE {
            return Err("Project exceeds 8 MB.".into());
        }
        Ok(data)
    }

    pub fn decode(data: &[u8]) -> Result<Self, String> {
        if data.len() as u64 > MAX_FILE || !data.starts_with(HEADER) {
            return Err("This is not a supported .kdj project (version 1).".into());
        }
        let project: Self = bincode::DefaultOptions::new()
            .with_limit(MAX_FILE)
            .reject_trailing_bytes()
            .deserialize(&data[HEADER.len()..])
            .map_err(|e| format!("Damaged project: {e}"))?;
        project.validate()?;
        Ok(project)
    }

    pub fn active(&self, time: f64) -> Option<usize> {
        self.lyrics
            .iter()
            .position(|line| time >= line.start && time < line.end)
    }
}

pub fn timestamp(seconds: f64) -> String {
    let ms = (seconds.max(0.0) * 1000.0).round() as u64;
    format!(
        "{:02}:{:02}.{:02}",
        ms / 60000,
        ms / 1000 % 60,
        ms / 10 % 100
    )
}

pub fn import_lyrics(text: &str, duration: f64) -> Result<Vec<Lyric>, String> {
    if text.len() as u64 > MAX_FILE {
        return Err("Lyrics exceed 8 MB.".into());
    }
    let text = text.trim_start_matches('\u{feff}');
    let mut timed = Vec::new();
    let mut plain = Vec::new();
    let mut offset = 0.0;
    for (number, raw) in text.lines().enumerate() {
        let raw = raw.trim();
        if raw.is_empty() {
            continue;
        }
        if let Some(value) = raw
            .strip_prefix("[offset:")
            .and_then(|s| s.strip_suffix(']'))
        {
            offset = value.parse::<f64>().map_err(|_| "Invalid LRC offset.")? / 1000.0;
            if !offset.is_finite() {
                return Err("Invalid LRC offset.".into());
            }
            continue;
        }
        let mut rest = raw;
        let mut times = Vec::new();
        while let Some(tag) = rest.strip_prefix('[') {
            let Some((stamp, after)) = tag.split_once(']') else {
                return Err(format!("Unclosed LRC tag on line {}.", number + 1));
            };
            if stamp.chars().next().is_some_and(|c| c.is_ascii_digit()) {
                let (minutes, seconds) = stamp
                    .split_once(':')
                    .ok_or_else(|| format!("Invalid timestamp on line {}.", number + 1))?;
                let minutes: u32 = minutes.parse().map_err(|_| "Invalid LRC minutes.")?;
                let seconds: f64 = seconds.parse().map_err(|_| "Invalid LRC seconds.")?;
                if !seconds.is_finite() || !(0.0..60.0).contains(&seconds) {
                    return Err("LRC seconds must be below 60.".into());
                }
                times.push(minutes as f64 * 60.0 + seconds);
            } else if !stamp.contains(':') {
                break;
            }
            rest = after;
        }
        if times.is_empty() {
            if !rest.trim().is_empty() {
                plain.push(rest.trim().to_owned());
            }
        } else {
            for start in times {
                timed.push((start, rest.trim().to_owned()));
            }
        }
    }
    let lyrics: Vec<Lyric> = if timed.is_empty() {
        let step = duration / plain.len().max(1) as f64;
        plain
            .into_iter()
            .enumerate()
            .map(|(i, text)| Lyric {
                start: i as f64 * step,
                end: (i + 1) as f64 * step,
                text,
            })
            .collect()
    } else {
        if !plain.is_empty() {
            return Err("Mixed timed and untimed lyrics. Use either LRC timestamps or plain text for all lines.".into());
        }
        for (time, _) in &mut timed {
            *time = (*time + offset).max(0.0);
        }
        timed.sort_by(|a, b| a.0.total_cmp(&b.0));
        if timed.windows(2).any(|w| w[0].0 == w[1].0) {
            return Err(
                "LRC has duplicate timestamps, including after applying its offset.".into(),
            );
        }
        timed
            .iter()
            .enumerate()
            .map(|(i, (start, text))| Lyric {
                start: *start,
                end: timed.get(i + 1).map_or(duration, |l| l.0),
                text: text.clone(),
            })
            .collect()
    };
    if lyrics.is_empty() {
        return Err("No lyric lines found.".into());
    }
    Project {
        duration,
        lyrics: lyrics.clone(),
        ..Project::default()
    }
    .validate()?;
    Ok(lyrics)
}

pub fn lrc(lyrics: &[Lyric]) -> String {
    let mut ordered: Vec<_> = lyrics.iter().collect();
    ordered.sort_by(|a, b| a.start.total_cmp(&b.start));
    ordered
        .into_iter()
        .map(|l| {
            format!(
                "[{}]{}\n",
                timestamp(l.start),
                l.text.replace(['\r', '\n'], " ")
            )
        })
        .collect()
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn binary_roundtrip_and_reject_corruption() {
        let p = Project::demo();
        assert_eq!(Project::decode(&p.encode().unwrap()).unwrap(), p);
        assert!(Project::decode(b"not a project").is_err());
        let mut bytes = p.encode().unwrap();
        bytes.push(0);
        assert!(Project::decode(&bytes).is_err());
        let mut bad = p;
        bad.lyrics[0].end = f64::NAN;
        assert!(bad.encode().is_err());
    }
    #[test]
    fn lrc_offsets_repeated_tags_and_unicode() {
        let lines = import_lyrics(
            "[ar:Artist]\n[offset:-500]\n[00:01.00][00:04.500]¡Canta!\n[00:03.00]世界",
            8.0,
        )
        .unwrap();
        assert_eq!(
            lines.iter().map(|l| l.start).collect::<Vec<_>>(),
            [0.5, 2.5, 4.0]
        );
        assert_eq!(lines[0].end, 2.5);
        assert_eq!(lines[1].text, "世界");
        assert_eq!(import_lyrics(&lrc(&lines), 8.0).unwrap(), lines);
        assert!(import_lyrics("[00:61]bad", 90.0).is_err());
        assert!(import_lyrics("[00:01]a\n[00:01]b", 10.0).is_err());
        assert!(import_lyrics("[01:00]late", 20.0).is_err());
        assert!(import_lyrics("[00:01]a\nuntimed", 20.0).is_err());
    }
    #[test]
    fn plain_lyrics_and_overlap_validation() {
        let lines = import_lyrics("One\n\nTwo", 8.0).unwrap();
        assert_eq!(lines[1].start, 4.0);
        let mut p = Project::demo();
        p.lyrics[0].end = 5.0;
        assert!(p.validate().is_err());
        assert_eq!(Project::demo().active(4.0), Some(1));
    }
}

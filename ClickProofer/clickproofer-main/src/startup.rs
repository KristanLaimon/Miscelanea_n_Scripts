use std::{
    ffi::OsStr,
    os::windows::ffi::OsStrExt,
    ptr::{null, null_mut},
};
use windows_sys::{
    Win32::{Foundation::*, System::Registry::*},
    w,
};

const RUN: *const u16 = w!("Software\\Microsoft\\Windows\\CurrentVersion\\Run");
const SETTINGS: *const u16 = w!("Software\\ClickProofer");
const NAME: *const u16 = w!("ClickProofer");
const THRESHOLD: *const u16 = w!("ThresholdMs");

fn check(status: u32) -> Result<(), String> {
    if status == ERROR_SUCCESS {
        Ok(())
    } else {
        Err(format!(
            "Windows registry: {}",
            std::io::Error::from_raw_os_error(status as i32)
        ))
    }
}

fn set(key: *const u16, name: *const u16, kind: u32, data: &[u8]) -> Result<(), String> {
    unsafe {
        let mut handle = null_mut();
        check(RegCreateKeyExW(
            HKEY_CURRENT_USER,
            key,
            0,
            null(),
            REG_OPTION_NON_VOLATILE,
            KEY_SET_VALUE,
            null(),
            &mut handle,
            null_mut(),
        ))?;
        let status = RegSetValueExW(handle, name, 0, kind, data.as_ptr(), data.len() as u32);
        RegCloseKey(handle);
        check(status)
    }
}

pub fn enabled() -> Result<bool, String> {
    let mut size = 0;
    let status = unsafe {
        RegGetValueW(
            HKEY_CURRENT_USER,
            RUN,
            NAME,
            RRF_RT_REG_SZ,
            null_mut(),
            null_mut(),
            &mut size,
        )
    };
    match status {
        ERROR_FILE_NOT_FOUND | ERROR_PATH_NOT_FOUND => Ok(false),
        ERROR_SUCCESS => Ok(true),
        _ => {
            check(status)?;
            Ok(false)
        }
    }
}

fn startup_command(executable: &OsStr) -> Result<Vec<u16>, String> {
    let path: Vec<u16> = executable.encode_wide().collect();
    if path.contains(&0) || path.contains(&(b'"' as u16)) {
        return Err("The executable path contains an invalid character.".into());
    }
    let mut command = vec![b'"' as u16];
    command.extend(path);
    command.extend("\" --auto-start".encode_utf16());
    if command.len() > 260 {
        return Err("Move ClickProofer to a shorter path before enabling startup (Windows limit: 260 characters).".into());
    }
    command.push(0);
    Ok(command)
}

pub fn enable() -> Result<(), String> {
    let executable = std::env::current_exe().map_err(|error| error.to_string())?;
    let command = startup_command(executable.as_os_str())?;
    let bytes: Vec<u8> = command.iter().flat_map(|unit| unit.to_le_bytes()).collect();
    set(RUN, NAME, REG_SZ, &bytes)
}

pub fn disable() -> Result<(), String> {
    let status = unsafe { RegDeleteKeyValueW(HKEY_CURRENT_USER, RUN, NAME) };
    if status == ERROR_FILE_NOT_FOUND || status == ERROR_PATH_NOT_FOUND {
        Ok(())
    } else {
        check(status)
    }
}

pub fn save_threshold(threshold: u32) -> Result<(), String> {
    if !(1..=250).contains(&threshold) {
        return Err("Threshold must be 1-250 ms.".into());
    }
    set(SETTINGS, THRESHOLD, REG_DWORD, &threshold.to_le_bytes())
}

pub fn load_threshold() -> Result<u32, String> {
    let mut threshold = 33u32;
    let mut size = 4;
    let status = unsafe {
        RegGetValueW(
            HKEY_CURRENT_USER,
            SETTINGS,
            THRESHOLD,
            RRF_RT_REG_DWORD,
            null_mut(),
            (&mut threshold as *mut u32).cast(),
            &mut size,
        )
    };
    match status {
        ERROR_FILE_NOT_FOUND | ERROR_PATH_NOT_FOUND => Ok(33),
        ERROR_SUCCESS if (1..=250).contains(&threshold) => Ok(threshold),
        ERROR_SUCCESS => Err("Saved threshold is invalid. Remove HKCU\\Software\\ClickProofer\\ThresholdMs to reset it.".into()),
        _ => { check(status)?; Ok(33) }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn quotes_paths_with_spaces_and_preserves_unicode() {
        let command = startup_command(OsStr::new("C:\\Mis apps\\ratón.exe")).unwrap();
        assert_eq!(
            String::from_utf16_lossy(&command[..command.len() - 1]),
            "\"C:\\Mis apps\\ratón.exe\" --auto-start"
        );
        assert_eq!(command.last(), Some(&0));
    }

    #[test]
    fn rejects_invalid_or_overlong_commands() {
        assert!(startup_command(OsStr::new("bad\"path")).is_err());
        assert!(startup_command(OsStr::new("bad\0path")).is_err());
        assert!(startup_command(OsStr::new(&"x".repeat(260))).is_err());
    }
}

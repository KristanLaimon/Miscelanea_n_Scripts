#![cfg_attr(not(test), windows_subsystem = "windows")]

mod filter;
mod startup;

use filter::ButtonFilter;
use std::{
    cell::RefCell,
    ptr::{null, null_mut},
    sync::{
        atomic::{AtomicBool, AtomicU32, AtomicU64, Ordering::Relaxed},
        mpsc,
    },
    thread,
};
use windows_sys::{
    Win32::{
        Foundation::*,
        Graphics::Gdi::*,
        System::{LibraryLoader::*, Threading::*},
        UI::{Input::KeyboardAndMouse::*, Shell::*, WindowsAndMessaging::*},
    },
    w,
};

static ENABLED: AtomicBool = AtomicBool::new(false);
static THRESHOLD: AtomicU32 = AtomicU32::new(33);
static BLOCKED: AtomicU64 = AtomicU64::new(0);
const START: i32 = 101;
const STARTUP: i32 = 102;
const THRESHOLD_EDIT: i32 = 103;
const STATUS: i32 = 104;
const STARTUP_STATUS: i32 = 105;
const OPEN: i32 = 106;
const EXIT: i32 = 107;
const TRAY_MESSAGE: u32 = WM_APP + 1;
const CLASS: *const u16 = w!("ClickProoferWindow");

thread_local! {
    static FILTERS: RefCell<[ButtonFilter; 5]> = RefCell::new([ButtonFilter::default(); 5]);
}

fn wide(text: &str) -> Vec<u16> {
    text.encode_utf16().chain(Some(0)).collect()
}

fn show_error(text: &str) {
    unsafe {
        MessageBoxW(
            null_mut(),
            wide(text).as_ptr(),
            w!("ClickProofer"),
            MB_OK | MB_ICONERROR,
        );
    }
}

unsafe extern "system" fn mouse_hook(code: i32, message: WPARAM, data: LPARAM) -> LRESULT {
    if code >= 0 {
        let event = unsafe { &*(data as *const MSLLHOOKSTRUCT) };
        if event.flags & LLMHF_INJECTED == 0 {
            let button_event = match message as u32 {
                WM_LBUTTONDOWN => Some((0, true)),
                WM_LBUTTONUP => Some((0, false)),
                WM_RBUTTONDOWN => Some((1, true)),
                WM_RBUTTONUP => Some((1, false)),
                WM_MBUTTONDOWN => Some((2, true)),
                WM_MBUTTONUP => Some((2, false)),
                WM_XBUTTONDOWN | WM_XBUTTONUP => {
                    let button = (event.mouseData >> 16) as u16;
                    match button {
                        XBUTTON1 => Some((3, message as u32 == WM_XBUTTONDOWN)),
                        XBUTTON2 => Some((4, message as u32 == WM_XBUTTONDOWN)),
                        _ => None,
                    }
                }
                _ => None,
            };
            if let Some((button, down)) = button_event {
                let blocked = FILTERS.with(|filters| {
                    filters.borrow_mut()[button].suppress(
                        down,
                        event.time,
                        ENABLED.load(Relaxed),
                        THRESHOLD.load(Relaxed),
                    )
                });
                if blocked {
                    if down {
                        BLOCKED.fetch_add(1, Relaxed);
                    }
                    return 1;
                }
            }
        }
    }
    unsafe { CallNextHookEx(null_mut(), code, message, data) }
}

struct HookThread {
    id: u32,
    handle: thread::JoinHandle<()>,
}

impl HookThread {
    fn start() -> Result<Self, String> {
        let (sender, receiver) = mpsc::channel();
        let handle = thread::spawn(move || unsafe {
            // The hook thread never performs UI, disk IO, or registry work.
            let mut message: MSG = std::mem::zeroed();
            PeekMessageW(&mut message, null_mut(), 0, 0, PM_NOREMOVE);
            let hook =
                SetWindowsHookExW(WH_MOUSE_LL, Some(mouse_hook), GetModuleHandleW(null()), 0);
            if hook.is_null() {
                let _ = sender.send(Err(format!(
                    "Cannot install mouse hook: {}",
                    std::io::Error::last_os_error()
                )));
                return;
            }
            if sender.send(Ok(GetCurrentThreadId())).is_ok() {
                while GetMessageW(&mut message, null_mut(), 0, 0) > 0 {
                    TranslateMessage(&message);
                    DispatchMessageW(&message);
                }
            }
            UnhookWindowsHookEx(hook);
        });
        match receiver.recv().map_err(|e| e.to_string())? {
            Ok(id) => Ok(Self { id, handle }),
            Err(error) => {
                let _ = handle.join();
                Err(error)
            }
        }
    }

    fn stop(self) {
        ENABLED.store(false, Relaxed);
        unsafe {
            PostThreadMessageW(self.id, WM_QUIT, 0, 0);
        }
        let _ = self.handle.join();
    }
}

unsafe fn set_text(window: HWND, id: i32, text: &str) {
    unsafe {
        SetWindowTextW(GetDlgItem(window, id), wide(text).as_ptr());
    }
}

unsafe fn read_threshold(window: HWND) -> Result<u32, String> {
    let mut buffer = [0u16; 32];
    let length = unsafe {
        GetWindowTextW(
            GetDlgItem(window, THRESHOLD_EDIT),
            buffer.as_mut_ptr(),
            buffer.len() as i32,
        )
    };
    String::from_utf16_lossy(&buffer[..length as usize])
        .trim()
        .parse::<u32>()
        .ok()
        .filter(|value| (1..=250).contains(value))
        .ok_or_else(|| "Enter a threshold between 1 and 250 milliseconds.".into())
}

unsafe fn refresh_status(window: HWND) {
    let running = ENABLED.load(Relaxed);
    unsafe {
        set_text(
            window,
            START,
            if running {
                "Stop filtering"
            } else {
                "Start filtering"
            },
        );
        EnableWindow(GetDlgItem(window, THRESHOLD_EDIT), (!running) as i32);
        set_text(
            window,
            STATUS,
            &format!(
                "{} | Blocked repeats: {}",
                if running { "Filtering" } else { "Stopped" },
                BLOCKED.load(Relaxed)
            ),
        );
    }
}

unsafe fn refresh_startup(window: HWND) -> Result<(), String> {
    let enabled = startup::enabled()?;
    unsafe {
        set_text(
            window,
            STARTUP,
            if enabled {
                "Disable startup"
            } else {
                "Enable startup"
            },
        );
        set_text(
            window,
            STARTUP_STATUS,
            if enabled {
                "Automatic startup: enabled at sign-in"
            } else {
                "Automatic startup: disabled"
            },
        );
    }
    Ok(())
}

unsafe fn tray_icon(window: HWND, action: u32) -> Result<(), String> {
    let mut data: NOTIFYICONDATAW = unsafe { std::mem::zeroed() };
    data.cbSize = std::mem::size_of::<NOTIFYICONDATAW>() as u32;
    data.hWnd = window;
    data.uID = 1;
    data.uFlags = NIF_MESSAGE | NIF_ICON | NIF_TIP;
    data.uCallbackMessage = TRAY_MESSAGE;
    data.hIcon = unsafe { LoadIconW(null_mut(), IDI_APPLICATION) };
    let tip = wide("ClickProofer - right-click for options");
    data.szTip[..tip.len()].copy_from_slice(&tip);
    if unsafe { Shell_NotifyIconW(action, &data) } == 0 {
        return Err("Cannot update the ClickProofer tray icon.".into());
    }
    Ok(())
}

unsafe fn tray_menu(window: HWND) -> Result<(), String> {
    let startup_enabled = startup::enabled()?;
    unsafe {
        let menu = CreatePopupMenu();
        if menu.is_null() {
            return Err(std::io::Error::last_os_error().to_string());
        }
        let mut point: POINT = std::mem::zeroed();
        let ready = AppendMenuW(menu, MF_STRING, OPEN as usize, w!("Open ClickProofer")) != 0
            && AppendMenuW(
                menu,
                MF_STRING,
                START as usize,
                if ENABLED.load(Relaxed) {
                    w!("Stop filtering")
                } else {
                    w!("Start filtering")
                },
            ) != 0
            && AppendMenuW(
                menu,
                MF_STRING,
                STARTUP as usize,
                if startup_enabled {
                    w!("Disable startup")
                } else {
                    w!("Enable startup")
                },
            ) != 0
            && AppendMenuW(menu, MF_SEPARATOR, 0, null()) != 0
            && AppendMenuW(menu, MF_STRING, EXIT as usize, w!("Exit ClickProofer")) != 0
            && GetCursorPos(&mut point) != 0;
        if !ready {
            DestroyMenu(menu);
            return Err("Cannot create the tray menu.".into());
        }
        SetForegroundWindow(window);
        let command = TrackPopupMenu(
            menu,
            TPM_RETURNCMD | TPM_RIGHTBUTTON,
            point.x,
            point.y,
            0,
            window,
            null(),
        );
        DestroyMenu(menu);
        // Let the shell dismiss the menu when the user clicks elsewhere.
        PostMessageW(window, WM_NULL, 0, 0);
        if command != 0 {
            SendMessageW(window, WM_COMMAND, command as WPARAM, 0);
        }
    }
    Ok(())
}

unsafe extern "system" fn window_proc(
    window: HWND,
    message: u32,
    wparam: WPARAM,
    lparam: LPARAM,
) -> LRESULT {
    match message {
        WM_COMMAND => {
            if (wparam >> 16) as u32 == BN_CLICKED {
                let result = match (wparam & 0xffff) as i32 {
                    OPEN => {
                        unsafe {
                            ShowWindow(window, SW_RESTORE);
                            SetForegroundWindow(window);
                            SetFocus(GetDlgItem(window, START));
                        }
                        Ok(())
                    }
                    EXIT => {
                        unsafe {
                            DestroyWindow(window);
                        }
                        return 0;
                    }
                    START => {
                        if ENABLED.load(Relaxed) {
                            ENABLED.store(false, Relaxed);
                            Ok(())
                        } else {
                            unsafe { read_threshold(window) }.and_then(|threshold| {
                                startup::save_threshold(threshold)?;
                                THRESHOLD.store(threshold, Relaxed);
                                ENABLED.store(true, Relaxed);
                                Ok(())
                            })
                        }
                    }
                    STARTUP => startup::enabled().and_then(|enabled| {
                        if enabled {
                            startup::disable()?;
                        } else {
                            let threshold = unsafe { read_threshold(window) }?;
                            startup::save_threshold(threshold)?;
                            startup::enable()?;
                        }
                        unsafe { refresh_startup(window) }
                    }),
                    _ => Ok(()),
                };
                if let Err(error) = result {
                    show_error(&error);
                }
                unsafe {
                    refresh_status(window);
                }
            }
            0
        }
        WM_TIMER => {
            unsafe {
                refresh_status(window);
            }
            0
        }
        TRAY_MESSAGE => {
            match lparam as u32 {
                WM_LBUTTONUP => unsafe {
                    SendMessageW(window, WM_COMMAND, OPEN as WPARAM, 0);
                },
                WM_RBUTTONUP | WM_CONTEXTMENU => {
                    if let Err(error) = unsafe { tray_menu(window) } {
                        show_error(&error);
                    }
                }
                _ => {}
            }
            0
        }
        WM_CLOSE => {
            unsafe {
                ShowWindow(window, SW_HIDE);
            }
            0
        }
        WM_DESTROY => {
            ENABLED.store(false, Relaxed);
            unsafe {
                KillTimer(window, 1);
                let _ = tray_icon(window, NIM_DELETE);
                PostQuitMessage(0);
            }
            0
        }
        _ => unsafe {
            if message == RegisterWindowMessageW(w!("TaskbarCreated")) {
                if let Err(error) = tray_icon(window, NIM_ADD) {
                    ShowWindow(window, SW_RESTORE);
                    show_error(&error);
                }
                return 0;
            }
            DefWindowProcW(window, message, wparam, lparam)
        },
    }
}

unsafe fn control(
    window: HWND,
    class: *const u16,
    text: &str,
    style: u32,
    id: i32,
    rect: [i32; 4],
) -> Result<(), String> {
    let [x, y, width, height] = rect;
    let handle = unsafe {
        CreateWindowExW(
            0,
            class,
            wide(text).as_ptr(),
            WS_CHILD | WS_VISIBLE | style,
            x,
            y,
            width,
            height,
            window,
            id as usize as HMENU,
            GetModuleHandleW(null()),
            null(),
        )
    };
    if handle.is_null() {
        return Err(std::io::Error::last_os_error().to_string());
    }
    unsafe {
        SendMessageW(
            handle,
            WM_SETFONT,
            GetStockObject(DEFAULT_GUI_FONT) as WPARAM,
            1,
        );
    }
    Ok(())
}

fn run() -> Result<(), String> {
    let autostart = std::env::args().any(|argument| argument == "--auto-start");
    unsafe {
        let mutex = CreateMutexW(null(), 0, w!("Local\\ClickProofer.SingleInstance"));
        if mutex.is_null() {
            return Err(std::io::Error::last_os_error().to_string());
        }
        if GetLastError() == ERROR_ALREADY_EXISTS {
            let existing = FindWindowW(CLASS, null());
            if !autostart && !existing.is_null() {
                ShowWindow(existing, SW_RESTORE);
                SetForegroundWindow(existing);
            }
            CloseHandle(mutex);
            return Ok(());
        }
        let result = run_window(autostart);
        CloseHandle(mutex);
        result
    }
}

unsafe fn run_window(autostart: bool) -> Result<(), String> {
    let threshold = startup::load_threshold()?;
    THRESHOLD.store(threshold, Relaxed);
    let instance = unsafe { GetModuleHandleW(null()) };
    let class = WNDCLASSW {
        lpfnWndProc: Some(window_proc),
        hInstance: instance,
        lpszClassName: CLASS,
        hCursor: unsafe { LoadCursorW(null_mut(), IDC_ARROW) },
        hbrBackground: (COLOR_BTNFACE + 1) as HBRUSH,
        ..unsafe { std::mem::zeroed() }
    };
    if unsafe { RegisterClassW(&class) } == 0 {
        return Err(std::io::Error::last_os_error().to_string());
    }
    let window = unsafe {
        CreateWindowExW(
            WS_EX_CONTROLPARENT,
            CLASS,
            w!("ClickProofer"),
            WS_OVERLAPPED | WS_CAPTION | WS_SYSMENU | WS_MINIMIZEBOX,
            CW_USEDEFAULT,
            CW_USEDEFAULT,
            480,
            330,
            null_mut(),
            null_mut(),
            instance,
            null(),
        )
    };
    if window.is_null() {
        return Err(std::io::Error::last_os_error().to_string());
    }
    let setup = (|| unsafe {
        control(
            window,
            w!("STATIC"),
            "Block rapid repeats on left, right, middle and side buttons.",
            0,
            0,
            [18, 18, 435, 24],
        )?;
        control(
            window,
            w!("STATIC"),
            "&Threshold (ms, 1-250):",
            0,
            0,
            [18, 60, 170, 24],
        )?;
        control(
            window,
            w!("EDIT"),
            &threshold.to_string(),
            WS_TABSTOP | WS_BORDER | ES_NUMBER as u32,
            THRESHOLD_EDIT,
            [190, 55, 80, 26],
        )?;
        control(
            window,
            w!("STATIC"),
            "Pause to edit. Use the recorder's estimate, then test.",
            0,
            0,
            [18, 91, 430, 24],
        )?;
        control(
            window,
            w!("BUTTON"),
            "Start filtering",
            WS_TABSTOP | BS_PUSHBUTTON as u32,
            START,
            [18, 126, 195, 36],
        )?;
        control(
            window,
            w!("BUTTON"),
            "Enable startup",
            WS_TABSTOP | BS_PUSHBUTTON as u32,
            STARTUP,
            [235, 126, 210, 36],
        )?;
        control(window, w!("STATIC"), "", 0, STATUS, [18, 179, 430, 24])?;
        control(
            window,
            w!("STATIC"),
            "",
            0,
            STARTUP_STATUS,
            [18, 209, 430, 24],
        )?;
        control(
            window,
            w!("STATIC"),
            "Closing hides to tray. Right-click the tray icon to exit.",
            0,
            0,
            [18, 248, 430, 24],
        )?;
        refresh_startup(window)?;
        refresh_status(window);
        tray_icon(window, NIM_ADD)?;
        Ok::<(), String>(())
    })();
    if let Err(error) = setup {
        unsafe {
            DestroyWindow(window);
        }
        return Err(error);
    }
    let hook = match HookThread::start() {
        Ok(hook) => hook,
        Err(error) => {
            unsafe {
                DestroyWindow(window);
            }
            return Err(error);
        }
    };
    ENABLED.store(autostart, Relaxed);
    unsafe {
        refresh_status(window);
        if SetTimer(window, 1, 500, None) == 0 {
            DestroyWindow(window);
            hook.stop();
            return Err("Cannot create the status timer.".into());
        }
        // Never show the startup window, even briefly or minimized.
        if !autostart {
            ShowWindow(window, SW_SHOW);
            SetFocus(GetDlgItem(window, START));
        }
        let mut message: MSG = std::mem::zeroed();
        let result = loop {
            match GetMessageW(&mut message, null_mut(), 0, 0) {
                -1 => break Err(std::io::Error::last_os_error().to_string()),
                0 => break Ok(()),
                _ => {
                    if IsDialogMessageW(window, &message) == 0 {
                        TranslateMessage(&message);
                        DispatchMessageW(&message);
                    }
                }
            }
        };
        hook.stop();
        if IsWindow(window) != 0 {
            DestroyWindow(window);
        }
        result
    }
}

fn main() {
    if let Err(error) = run() {
        show_error(&error);
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::time::{Duration, Instant};

    #[test]
    fn startup_stays_hidden_close_preserves_filtering_and_exit_stops_it() {
        unsafe extern "system" fn find_window(window: HWND, data: LPARAM) -> i32 {
            unsafe {
                *(data as *mut HWND) = window;
            }
            0
        }

        let ui_thread = unsafe { GetCurrentThreadId() };
        let check = thread::spawn(move || unsafe {
            let deadline = Instant::now() + Duration::from_secs(5);
            let mut window: HWND = null_mut();
            while window.is_null() && Instant::now() < deadline {
                EnumThreadWindows(
                    ui_thread,
                    Some(find_window),
                    (&mut window as *mut HWND) as LPARAM,
                );
                thread::sleep(Duration::from_millis(10));
            }
            assert!(
                !window.is_null(),
                "Startup did not create its hidden window"
            );
            // Wait until setup finishes and the UI starts processing messages.
            SendMessageW(window, WM_NULL, 0, 0);
            let hidden_on_startup = IsWindowVisible(window) == 0;
            let filtering_on_startup = ENABLED.load(Relaxed);
            SendMessageW(window, WM_COMMAND, OPEN as WPARAM, 0);
            let opened = IsWindowVisible(window) != 0;
            SendMessageW(window, WM_CLOSE, 0, 0);
            let hidden_on_close = IsWindowVisible(window) == 0 && IsWindow(window) != 0;
            let filtering_after_close = ENABLED.load(Relaxed);
            SendMessageW(window, WM_COMMAND, START as WPARAM, 0);
            let stopped_from_tray = !ENABLED.load(Relaxed);
            SendMessageW(window, WM_COMMAND, EXIT as WPARAM, 0);
            (
                hidden_on_startup,
                filtering_on_startup,
                opened,
                hidden_on_close,
                filtering_after_close,
                stopped_from_tray,
                IsWindow(window) == 0,
            )
        });
        unsafe { run_window(true) }.unwrap();
        assert_eq!(
            check.join().unwrap(),
            (true, true, true, true, true, true, true)
        );
        assert!(!ENABLED.load(Relaxed));
    }
}

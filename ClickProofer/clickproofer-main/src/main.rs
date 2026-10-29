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
        UI::{Input::KeyboardAndMouse::*, WindowsAndMessaging::*},
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
        WM_DESTROY => {
            ENABLED.store(false, Relaxed);
            unsafe {
                KillTimer(window, 1);
                PostQuitMessage(0);
            }
            0
        }
        _ => unsafe { DefWindowProcW(window, message, wparam, lparam) },
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
    unsafe {
        let mutex = CreateMutexW(null(), 0, w!("Local\\ClickProofer.SingleInstance"));
        if mutex.is_null() {
            return Err(std::io::Error::last_os_error().to_string());
        }
        if GetLastError() == ERROR_ALREADY_EXISTS {
            let existing = FindWindowW(CLASS, null());
            if !existing.is_null() {
                ShowWindow(existing, SW_RESTORE);
                SetForegroundWindow(existing);
            }
            CloseHandle(mutex);
            return Ok(());
        }
        let result = run_window();
        CloseHandle(mutex);
        result
    }
}

unsafe fn run_window() -> Result<(), String> {
    let threshold = startup::load_threshold()?;
    THRESHOLD.store(threshold, Relaxed);
    let autostart = std::env::args().any(|argument| argument == "--auto-start");
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
            "Minimize to keep filtering. Closing stops filtering.",
            0,
            0,
            [18, 248, 430, 24],
        )?;
        refresh_startup(window)?;
        refresh_status(window);
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
        ShowWindow(window, if autostart { SW_SHOWMINIMIZED } else { SW_SHOW });
        SetFocus(GetDlgItem(window, START));
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
        result
    }
}

fn main() {
    if let Err(error) = run() {
        show_error(&error);
    }
}

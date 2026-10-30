// gntrees-launcher — Raycast-style application launcher (kind: app, domain: launcher).
//
// Version 1: list installed applications, filter by typing, open on Enter.
// The status row above the input is a placeholder for COSMIC applets; for now it
// only reports information that can be read from /proc and /sys.

use std::collections::BTreeMap;
use std::fs;
use std::io::Write;
use std::os::unix::net::{UnixListener, UnixStream};
use std::path::{Path, PathBuf};
use std::process::{Command, Stdio};
use std::sync::atomic::{AtomicBool, Ordering};

use serde::Serialize;
use tauri::Manager;

#[derive(Serialize, Clone)]
struct AppEntry {
    id: String,
    name: String,
    comment: String,
    exec: String,
}

#[derive(Serialize)]
struct Status {
    time: String,
    date: String,
    battery: Option<u32>,
    charging: bool,
    memory: u32,
    network: String,
}

struct DesktopEntry {
    name: String,
    comment: String,
    exec: String,
}

fn app_dirs() -> Vec<PathBuf> {
    let mut dirs = Vec::new();

    match std::env::var_os("XDG_DATA_HOME") {
        Some(home) => dirs.push(PathBuf::from(home).join("applications")),
        None => {
            if let Some(home) = std::env::var_os("HOME") {
                dirs.push(PathBuf::from(home).join(".local/share/applications"));
            }
        }
    }

    let data_dirs = std::env::var("XDG_DATA_DIRS")
        .unwrap_or_else(|_| String::from("/usr/local/share:/usr/share"));
    for dir in data_dirs.split(':') {
        if !dir.is_empty() {
            dirs.push(Path::new(dir).join("applications"));
        }
    }

    dirs
}

fn parse_entry(path: &Path) -> Option<(DesktopEntry, bool)> {
    let text = fs::read_to_string(path).ok()?;

    let mut in_entry = false;
    let mut kind = String::new();
    let mut name = String::new();
    let mut comment = String::new();
    let mut exec = String::new();
    let mut terminal = false;
    let mut hidden = false;

    for line in text.lines() {
        let line = line.trim();

        if line.starts_with('[') {
            in_entry = line == "[Desktop Entry]";
            continue;
        }
        if !in_entry {
            continue;
        }

        let Some((key, value)) = line.split_once('=') else {
            continue;
        };

        match key {
            "Type" => kind = value.to_string(),
            "Name" if name.is_empty() => name = value.to_string(),
            "Comment" if comment.is_empty() => comment = value.to_string(),
            "Exec" => exec = value.to_string(),
            "NoDisplay" => hidden = hidden || value == "true",
            "Hidden" => hidden = hidden || value == "true",
            "Terminal" => terminal = value == "true",
            _ => {}
        }
    }

    if kind != "Application" || hidden || exec.is_empty() {
        return None;
    }

    Some((
        DesktopEntry {
            name,
            comment,
            exec,
        },
        terminal,
    ))
}

/// Every visible application, keyed by desktop file id. User directories win.
fn collect_apps() -> BTreeMap<String, (AppEntry, bool)> {
    let mut apps = BTreeMap::new();

    for dir in app_dirs() {
        let Ok(entries) = fs::read_dir(&dir) else {
            continue;
        };

        for entry in entries.flatten() {
            let path = entry.path();
            if path.extension().and_then(|e| e.to_str()) != Some("desktop") {
                continue;
            }
            let Some(stem) = path.file_stem().and_then(|s| s.to_str()) else {
                continue;
            };
            if apps.contains_key(stem) {
                continue;
            }
            let Some((desktop, terminal)) = parse_entry(&path) else {
                continue;
            };

            apps.insert(
                stem.to_string(),
                (
                    AppEntry {
                        id: stem.to_string(),
                        name: desktop.name,
                        comment: desktop.comment,
                        exec: desktop.exec,
                    },
                    terminal,
                ),
            );
        }
    }

    apps
}

#[tauri::command]
fn list_apps() -> Vec<AppEntry> {
    let mut apps: Vec<AppEntry> = collect_apps()
        .into_values()
        .map(|(app, _)| app)
        .collect();

    apps.sort_by(|a, b| a.name.to_lowercase().cmp(&b.name.to_lowercase()));
    apps
}

fn split_exec(exec: &str) -> Vec<String> {
    let mut parts = Vec::new();
    let mut cur = String::new();
    let mut quote: Option<char> = None;
    let mut started = false;

    for ch in exec.chars() {
        match quote {
            Some(q) if ch == q => {
                quote = None;
                started = true;
            }
            Some(_) => {
                cur.push(ch);
                started = true;
            }
            None => match ch {
                '\'' | '"' => {
                    quote = Some(ch);
                    started = true;
                }
                ch if ch.is_whitespace() => {
                    if started {
                        parts.push(std::mem::take(&mut cur));
                        started = false;
                    }
                }
                ch => {
                    cur.push(ch);
                    started = true;
                }
            },
        }
    }
    if started {
        parts.push(cur);
    }

    parts
        .into_iter()
        // Drop field codes such as %U or %f: no file argument is available.
        .filter(|arg| !(arg.len() == 2 && arg.starts_with('%')))
        .map(|arg| arg.replace("%%", "%"))
        .filter(|arg| !arg.is_empty())
        .collect()
}

/// Terminal emulator used for entries that need a tty.
fn terminal_emulator() -> Option<&'static str> {
    ["/usr/bin/alacritty", "/usr/bin/cosmic-term"]
        .into_iter()
        .find(|path| Path::new(path).exists())
}

#[tauri::command]
fn launch_app(id: String) -> Result<(), String> {
    let apps = collect_apps();
    let (app, terminal) = apps
        .get(&id)
        .ok_or_else(|| format!("aplikasi tidak ditemukan: {id}"))?;

    let mut command = Vec::new();
    if *terminal {
        let emulator =
            terminal_emulator().ok_or_else(|| String::from("terminal emulator tidak ada"))?;
        command.push(emulator.to_string());
        command.push(String::from("-e"));
    }
    command.extend(split_exec(&app.exec));

    let (program, args) = command
        .split_first()
        .ok_or_else(|| format!("Exec kosong: {}", app.exec))?;

    // setsid detaches the child so it survives this process exiting.
    Command::new("setsid")
        .arg(program)
        .args(args)
        .stdin(Stdio::null())
        .stdout(Stdio::null())
        .stderr(Stdio::null())
        .spawn()
        .map(|_| ())
        .map_err(|err| format!("gagal menjalankan {program}: {err}"))
}

fn battery() -> (Option<u32>, bool) {
    let Ok(dir) = fs::read_dir("/sys/class/power_supply") else {
        return (None, false);
    };

    for entry in dir.flatten() {
        let path = entry.path();
        if !entry.file_name().to_string_lossy().starts_with("BAT") {
            continue;
        }
        let Ok(capacity) = fs::read_to_string(path.join("capacity")) else {
            continue;
        };
        let Ok(level) = capacity.trim().parse::<u32>() else {
            continue;
        };
        let status = fs::read_to_string(path.join("status")).unwrap_or_default();
        let charging = matches!(status.trim(), "Charging" | "Full");
        return (Some(level), charging);
    }

    (None, false)
}

fn memory_percent() -> u32 {
    let Ok(text) = fs::read_to_string("/proc/meminfo") else {
        return 0;
    };

    let mut total = 0f64;
    let mut available = 0f64;

    for line in text.lines() {
        let mut fields = line.split_whitespace();
        match fields.next() {
            Some("MemTotal:") => total = fields.next().and_then(|v| v.parse().ok()).unwrap_or(0.0),
            Some("MemAvailable:") => {
                available = fields.next().and_then(|v| v.parse().ok()).unwrap_or(0.0)
            }
            _ => {}
        }
    }

    if total <= 0.0 {
        return 0;
    }

    (((total - available) / total) * 100.0).round() as u32
}

/// First non-loopback interface that reports `up`, else "offline".
fn network() -> String {
    let Ok(dir) = fs::read_dir("/sys/class/net") else {
        return String::from("offline");
    };

    let mut names: Vec<String> = dir
        .flatten()
        .map(|entry| entry.file_name().to_string_lossy().into_owned())
        .filter(|name| name != "lo")
        .collect();
    names.sort();

    for name in &names {
        let state =
            fs::read_to_string(format!("/sys/class/net/{name}/operstate")).unwrap_or_default();
        if state.trim() == "up" {
            return name.clone();
        }
    }

    String::from("offline")
}

#[tauri::command]
fn status() -> Status {
    let now = chrono::Local::now();
    let (battery, charging) = battery();

    Status {
        time: now.format("%H:%M").to_string(),
        date: now.format("%a %d %b").to_string(),
        battery,
        charging,
        memory: memory_percent(),
        network: network(),
    }
}

#[tauri::command]
fn hide(window: tauri::WebviewWindow) {
    let _ = window.hide();
}

/// One launcher per session. A second launch asks the resident instance to show
/// itself and exits, so holding Super does not stack windows.
fn setup_single_instance(app: &tauri::AppHandle) {
    let dir = std::env::var_os("XDG_RUNTIME_DIR")
        .map(PathBuf::from)
        .unwrap_or_else(|| PathBuf::from("/tmp"));
    let path = dir.join("gntrees-launcher.sock");

    if let Ok(mut stream) = UnixStream::connect(&path) {
        let _ = stream.write_all(b"show\n");
        std::process::exit(0);
    }

    let _ = fs::remove_file(&path);
    let Ok(listener) = UnixListener::bind(&path) else {
        return;
    };

    let handle = app.clone();
    std::thread::spawn(move || {
        for stream in listener.incoming() {
            if stream.is_err() {
                break;
            }
            let handle = handle.clone();
            let target = handle.clone();
            let _ = handle.run_on_main_thread(move || {
                if let Some(window) = target.get_webview_window("main") {
                    let _ = window.show();
                    let _ = window.set_focus();
                }
            });
        }
    });
}

fn main() {
    tauri::Builder::default()
        .invoke_handler(tauri::generate_handler![
            list_apps, launch_app, status, hide
        ])
        .setup(|app| {
            setup_single_instance(&app.handle().clone());
            Ok(())
        })
        .on_window_event(|window, event| {
            static HAD_FOCUS: AtomicBool = AtomicBool::new(false);

            if let tauri::WindowEvent::Focused(focused) = event {
                if *focused {
                    HAD_FOCUS.store(true, Ordering::Relaxed);
                } else if HAD_FOCUS.load(Ordering::Relaxed) {
                    // Clicking anywhere outside dismisses the launcher.
                    let _ = window.hide();
                }
            }
        })
        .run(tauri::generate_context!())
        .expect("gagal menjalankan gntrees-launcher");
}

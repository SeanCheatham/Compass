use anyhow::{anyhow, Context, Result};
use compass_core::protocol::daemon::{capabilities, DaemonRequest, DaemonResponse};
use compass_core::protocol::SCHEMA_VERSION;
use compass_core::tournament::read_model::ProductTournamentReadModelSummary;
use compass_core::tournament::store::TournamentWorkspaceStore;
use compass_core::COMPASS_CORE_VERSION;
use std::env;
use std::fs::{self, OpenOptions};
use std::io::{BufRead, BufReader, Write};
use std::os::unix::fs::PermissionsExt;
use std::os::unix::net::{UnixListener, UnixStream};
use std::path::{Path, PathBuf};
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::{Arc, Mutex};
use std::thread;
use std::time::{Duration, Instant};

const COMPASSD_VERSION: &str = env!("CARGO_PKG_VERSION");

fn main() {
    if let Err(error) = run() {
        eprintln!("compassd: {error:#}");
        std::process::exit(1);
    }
}

fn run() -> Result<()> {
    let args = Args::parse(env::args().skip(1))?;
    if let Some(parent) = args.socket.parent() {
        fs::create_dir_all(parent)
            .with_context(|| format!("creating socket directory {}", parent.display()))?;
    }
    if let Some(parent) = args.log.parent() {
        fs::create_dir_all(parent)
            .with_context(|| format!("creating log directory {}", parent.display()))?;
    }

    let logger = Logger::new(args.log)?;
    logger.log("starting compassd")?;

    let _lock = InstanceLock::acquire(&args.socket)?;
    if UnixStream::connect(&args.socket).is_ok() {
        return Err(anyhow!(
            "another compassd is already listening at {}",
            args.socket.display()
        ));
    }
    let _ = fs::remove_file(&args.socket);

    let listener = UnixListener::bind(&args.socket)
        .with_context(|| format!("binding socket {}", args.socket.display()))?;
    fs::set_permissions(&args.socket, fs::Permissions::from_mode(0o600))
        .with_context(|| format!("setting socket permissions {}", args.socket.display()))?;
    listener.set_nonblocking(true)?;

    let shutdown = Arc::new(AtomicBool::new(false));
    let logger = Arc::new(logger);
    logger.log(format!("listening socket={}", args.socket.display()))?;

    while !shutdown.load(Ordering::SeqCst) {
        match listener.accept() {
            Ok((stream, _addr)) => {
                let shutdown = Arc::clone(&shutdown);
                let logger = Arc::clone(&logger);
                thread::spawn(move || {
                    if let Err(error) = handle_client(stream, shutdown, logger.clone()) {
                        let _ = logger.log(format!("client error: {error:#}"));
                    }
                });
            }
            Err(error) if error.kind() == std::io::ErrorKind::WouldBlock => {
                thread::sleep(Duration::from_millis(50));
            }
            Err(error) => return Err(error).context("accepting daemon connection"),
        }
    }

    logger.log("shutting down compassd")?;
    let _ = fs::remove_file(&args.socket);
    Ok(())
}

fn handle_client(stream: UnixStream, shutdown: Arc<AtomicBool>, logger: Arc<Logger>) -> Result<()> {
    let peer = stream.try_clone()?;
    let mut reader = BufReader::new(stream);
    let mut writer = peer;
    let mut line = String::new();
    loop {
        line.clear();
        let bytes = reader.read_line(&mut line)?;
        if bytes == 0 {
            break;
        }
        let started = Instant::now();
        let response = match serde_json::from_str::<DaemonRequest>(&line) {
            Ok(request) => handle_request(request, &shutdown),
            Err(error) => DaemonResponse::error("", vec![format!("invalid request JSON: {error}")]),
        };
        let method = if response.id.is_empty() {
            "<decode>"
        } else {
            response.id.as_str()
        };
        let encoded = serde_json::to_string(&response)?;
        writer.write_all(encoded.as_bytes())?;
        writer.write_all(b"\n")?;
        writer.flush()?;
        logger.log(format!(
            "request id={} ok={} duration_ms={}",
            method,
            response.ok,
            started.elapsed().as_millis()
        ))?;
        if shutdown.load(Ordering::SeqCst) {
            break;
        }
    }
    Ok(())
}

fn handle_request(request: DaemonRequest, shutdown: &AtomicBool) -> DaemonResponse {
    if request.schema_version != SCHEMA_VERSION {
        return DaemonResponse::error(
            request.id,
            vec![format!(
                "unsupported schema_version {}; expected {}",
                request.schema_version, SCHEMA_VERSION
            )],
        );
    }

    match request.method.as_str() {
        "ping" => DaemonResponse::ok(
            request.id,
            serde_json::json!({
                "compassdVersion": COMPASSD_VERSION,
                "coreVersion": COMPASS_CORE_VERSION,
                "schemaVersion": SCHEMA_VERSION
            }),
        ),
        "get_capabilities" => DaemonResponse::ok(
            request.id,
            capabilities(COMPASSD_VERSION, COMPASS_CORE_VERSION),
        ),
        "shutdown" => {
            shutdown.store(true, Ordering::SeqCst);
            DaemonResponse::empty_ok(request.id)
        }
        "tournament_load" => with_tournament_store(request, |store| store.read_state()),
        "tournament_validate" => with_tournament_store(request, |store| store.validate()),
        "tournament_read_model" => with_tournament_store(request, |store| {
            let state = store.read_state()?;
            Ok(ProductTournamentReadModelSummary::from_state(&state))
        }),
        _ => DaemonResponse::error(
            request.id,
            vec![format!("unknown method {}", request.method)],
        ),
    }
}

fn with_tournament_store<T: serde::Serialize>(
    request: DaemonRequest,
    handler: impl FnOnce(TournamentWorkspaceStore) -> Result<T>,
) -> DaemonResponse {
    let id = request.id;
    let repo_path = request
        .params
        .get("repo_path")
        .or_else(|| request.params.get("repoPath"))
        .and_then(|value| value.as_str())
        .map(str::to_owned);
    let Some(repo_path) = repo_path else {
        return DaemonResponse::error(id, vec!["missing repo_path".to_owned()]);
    };
    match handler(TournamentWorkspaceStore::new(repo_path)) {
        Ok(result) => DaemonResponse::ok(id, result),
        Err(error) => DaemonResponse::error(id, vec![format!("{error:#}")]),
    }
}

#[derive(Debug)]
struct Args {
    socket: PathBuf,
    log: PathBuf,
}

impl Args {
    fn parse(mut args: impl Iterator<Item = String>) -> Result<Self> {
        let mut socket = None;
        let mut log = None;
        while let Some(arg) = args.next() {
            match arg.as_str() {
                "--socket" => socket = args.next().map(PathBuf::from),
                "--log" => log = args.next().map(PathBuf::from),
                "--help" | "-h" => {
                    println!("usage: compassd --socket <path> [--log <path>]");
                    std::process::exit(0);
                }
                value => return Err(anyhow!("unknown argument {value}")),
            }
        }
        let socket = socket.ok_or_else(|| anyhow!("--socket is required"))?;
        let log = log.unwrap_or_else(default_log_path);
        Ok(Self { socket, log })
    }
}

fn default_log_path() -> PathBuf {
    let home = env::var_os("HOME")
        .map(PathBuf::from)
        .unwrap_or_else(|| PathBuf::from("."));
    home.join("Library")
        .join("Logs")
        .join("Compass")
        .join("compassd.log")
}

struct Logger {
    file: Mutex<fs::File>,
}

impl Logger {
    fn new(path: PathBuf) -> Result<Self> {
        let file = OpenOptions::new()
            .create(true)
            .append(true)
            .open(&path)
            .with_context(|| format!("opening log {}", path.display()))?;
        Ok(Self {
            file: Mutex::new(file),
        })
    }

    fn log(&self, message: impl AsRef<str>) -> Result<()> {
        let mut file = self.file.lock().expect("logger lock poisoned");
        writeln!(file, "{}", message.as_ref())?;
        Ok(())
    }
}

struct InstanceLock {
    path: PathBuf,
}

impl InstanceLock {
    fn acquire(socket: &Path) -> Result<Self> {
        let lock_path = socket.with_extension("lock");
        match OpenOptions::new()
            .write(true)
            .create_new(true)
            .open(&lock_path)
        {
            Ok(mut file) => {
                writeln!(file, "pid={}", std::process::id())?;
                Ok(Self { path: lock_path })
            }
            Err(error) if error.kind() == std::io::ErrorKind::AlreadyExists => {
                if UnixStream::connect(socket).is_ok() {
                    Err(anyhow!(
                        "another compassd instance owns {}",
                        lock_path.display()
                    ))
                } else {
                    let _ = fs::remove_file(&lock_path);
                    Self::acquire(socket)
                }
            }
            Err(error) => Err(error).with_context(|| format!("creating {}", lock_path.display())),
        }
    }
}

impl Drop for InstanceLock {
    fn drop(&mut self) {
        let _ = fs::remove_file(&self.path);
    }
}

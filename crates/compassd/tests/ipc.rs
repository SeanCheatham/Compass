use serde_json::Value;
use std::io::{BufRead, BufReader, Write};
use std::os::unix::net::UnixStream;
use std::process::{Child, Command, Stdio};
use std::time::{Duration, Instant};

#[test]
fn ping_round_trip_and_shutdown() {
    let root = std::env::temp_dir().join(format!(
        "compassd-test-{}-{}",
        std::process::id(),
        unique_suffix()
    ));
    std::fs::create_dir_all(&root).unwrap();
    let socket = root.join("compassd.sock");
    let log = root.join("compassd.log");

    let mut child = Command::new(env!("CARGO_BIN_EXE_compassd"))
        .arg("--socket")
        .arg(&socket)
        .arg("--log")
        .arg(&log)
        .stdout(Stdio::null())
        .stderr(Stdio::piped())
        .spawn()
        .unwrap();

    let result = (|| {
        wait_for_socket(&socket, &mut child);
        let ping = send(&socket, "ping-1", "ping");
        assert_eq!(ping["ok"], true);
        assert_eq!(ping["result"]["schemaVersion"], 1);
        assert!(ping["result"]["compassdVersion"].as_str().unwrap().len() > 0);

        let capabilities = send(&socket, "caps-1", "get_capabilities");
        assert_eq!(capabilities["ok"], true);
        assert!(capabilities["result"]["methods"]
            .as_array()
            .unwrap()
            .iter()
            .any(|value| value == "ping"));

        let tournament = send_with_params(
            &socket,
            "tournament-1",
            "tournament_read_model",
            serde_json::json!({ "repo_path": root.to_string_lossy() }),
        );
        assert_eq!(tournament["ok"], true);
        assert_eq!(tournament["result"]["schemaVersion"], 1);
        assert_eq!(tournament["result"]["contenderCount"], 0);

        let shutdown = send(&socket, "shutdown-1", "shutdown");
        assert_eq!(shutdown["ok"], true);
    })();

    let status = child.wait().unwrap();
    let _ = std::fs::remove_dir_all(&root);
    assert!(status.success());
    result
}

fn send(socket: &std::path::Path, id: &str, method: &str) -> Value {
    send_with_params(socket, id, method, serde_json::json!({}))
}

fn send_with_params(socket: &std::path::Path, id: &str, method: &str, params: Value) -> Value {
    let mut stream = UnixStream::connect(socket).unwrap();
    let request = serde_json::json!({
        "schema_version": 1,
        "id": id,
        "method": method,
        "params": params
    });
    writeln!(stream, "{request}").unwrap();
    let mut reader = BufReader::new(stream);
    let mut response = String::new();
    reader.read_line(&mut response).unwrap();
    serde_json::from_str(&response).unwrap()
}

fn wait_for_socket(socket: &std::path::Path, child: &mut Child) {
    let started = Instant::now();
    loop {
        if UnixStream::connect(socket).is_ok() {
            return;
        }
        if let Some(status) = child.try_wait().unwrap() {
            panic!("compassd exited before socket was ready: {status}");
        }
        assert!(
            started.elapsed() < Duration::from_secs(5),
            "socket was not ready"
        );
        std::thread::sleep(Duration::from_millis(25));
    }
}

fn unique_suffix() -> u128 {
    std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .unwrap()
        .as_nanos()
}

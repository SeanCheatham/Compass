use base64::engine::general_purpose::STANDARD;
use base64::Engine;
use compass_guest_agent::framing;
use compass_guest_agent::rpc::{
    dispatch, AgentRPCRequest, AgentRPCResponse, PathArgs, ReadFileArgs, WriteFileArgs,
};

#[test]
fn frame_round_trips_read_file_request() {
    let request = AgentRPCRequest::ReadFile(ReadFileArgs {
        path: "/tmp/demo.txt".to_owned(),
    });
    let frame = framing::encode(&request).unwrap();
    let decoded: AgentRPCRequest = framing::decode(&frame).unwrap();
    assert_eq!(decoded, request);
}

#[test]
fn handlers_write_read_stat_and_list() {
    let root = temp_root();
    let path = root.join("nested").join("demo.txt");

    let write = dispatch(AgentRPCRequest::WriteFile(WriteFileArgs {
        path: path.to_string_lossy().to_string(),
        data_base64: STANDARD.encode("hello"),
    }));
    assert_eq!(write, AgentRPCResponse::WriteFile {});

    let read = dispatch(AgentRPCRequest::ReadFile(ReadFileArgs {
        path: path.to_string_lossy().to_string(),
    }));
    assert_eq!(
        read,
        AgentRPCResponse::ReadFile(compass_guest_agent::rpc::ReadFileResult {
            data_base64: STANDARD.encode("hello")
        })
    );

    let stat = dispatch(AgentRPCRequest::Stat(PathArgs {
        path: path.to_string_lossy().to_string(),
    }));
    assert!(
        matches!(stat, AgentRPCResponse::Stat(result) if result.metadata.clone().unwrap().is_regular_file)
    );

    let list = dispatch(AgentRPCRequest::ListDirectory(PathArgs {
        path: root.join("nested").to_string_lossy().to_string(),
    }));
    assert!(matches!(list, AgentRPCResponse::ListDirectory(result) if result.entries.len() == 1));

    let _ = std::fs::remove_dir_all(root);
}

fn temp_root() -> std::path::PathBuf {
    let root = std::env::temp_dir().join(format!(
        "compass-guest-agent-test-{}-{}",
        std::process::id(),
        unique_suffix()
    ));
    std::fs::create_dir_all(&root).unwrap();
    root
}

fn unique_suffix() -> u128 {
    std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .unwrap()
        .as_nanos()
}

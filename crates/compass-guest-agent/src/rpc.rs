use base64::engine::general_purpose::STANDARD;
use base64::Engine;
use glob::glob;
use serde::{Deserialize, Serialize};
use std::fs;
use std::path::Path;
use std::process::Command;
use std::time::UNIX_EPOCH;

#[derive(Clone, Debug, Deserialize, Serialize, PartialEq)]
pub enum AgentRPCRequest {
    #[serde(rename = "readFile")]
    ReadFile(ReadFileArgs),
    #[serde(rename = "writeFile")]
    WriteFile(WriteFileArgs),
    #[serde(rename = "stat")]
    Stat(PathArgs),
    #[serde(rename = "listDirectory")]
    ListDirectory(PathArgs),
    #[serde(rename = "glob")]
    Glob(GlobArgs),
    #[serde(rename = "grep")]
    Grep(GrepArgs),
    #[serde(rename = "bash")]
    Bash(BashArgs),
}

#[derive(Clone, Debug, Deserialize, Serialize, PartialEq)]
pub enum AgentRPCResponse {
    #[serde(rename = "readFile")]
    ReadFile(ReadFileResult),
    #[serde(rename = "writeFile")]
    WriteFile {},
    #[serde(rename = "stat")]
    Stat(StatResult),
    #[serde(rename = "listDirectory")]
    ListDirectory(ListDirectoryResult),
    #[serde(rename = "glob")]
    Glob(GlobResult),
    #[serde(rename = "grep")]
    Grep(ProcessResult),
    #[serde(rename = "bash")]
    Bash(ProcessResult),
    #[serde(rename = "error")]
    Error(RPCError),
}

#[derive(Clone, Debug, Deserialize, Serialize, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct ReadFileArgs {
    pub path: String,
}

#[derive(Clone, Debug, Deserialize, Serialize, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct WriteFileArgs {
    pub path: String,
    pub data_base64: String,
}

#[derive(Clone, Debug, Deserialize, Serialize, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct PathArgs {
    pub path: String,
}

#[derive(Clone, Debug, Deserialize, Serialize, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct GlobArgs {
    pub pattern: String,
    pub root_path: String,
    pub walk_cap: usize,
}

#[derive(Clone, Debug, Deserialize, Serialize, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct GrepArgs {
    pub pattern: String,
    pub path: String,
    pub glob: Option<String>,
    pub case_insensitive: bool,
    pub timeout_seconds: f64,
}

#[derive(Clone, Debug, Deserialize, Serialize, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct BashArgs {
    pub command: String,
    pub working_directory: String,
    pub timeout_seconds: f64,
}

#[derive(Clone, Debug, Deserialize, Serialize, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct ReadFileResult {
    pub data_base64: String,
}

#[derive(Clone, Debug, Deserialize, Serialize, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct StatResult {
    pub metadata: Option<FileMetadata>,
}

#[derive(Clone, Debug, Deserialize, Serialize, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct ListDirectoryResult {
    pub entries: Vec<DirectoryEntry>,
}

#[derive(Clone, Debug, Deserialize, Serialize, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct GlobResult {
    pub matches: Vec<GlobMatch>,
}

#[derive(Clone, Debug, Deserialize, Serialize, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct ProcessResult {
    pub exit_code: i32,
    pub stdout: String,
    pub stderr: String,
}

#[derive(Clone, Debug, Deserialize, Serialize, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct RPCError {
    pub kind: ErrorKind,
    pub detail: String,
}

#[derive(Clone, Debug, Deserialize, Serialize, PartialEq)]
#[serde(rename_all = "camelCase")]
pub enum ErrorKind {
    NotFound,
    NotRegularFile,
    NotDirectory,
    IoFailure,
    InvalidArguments,
    InternalError,
}

#[derive(Clone, Debug, Deserialize, Serialize, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct FileMetadata {
    pub path: String,
    pub is_directory: bool,
    pub is_regular_file: bool,
    pub size: Option<usize>,
    pub modification_date_epoch: Option<f64>,
}

#[derive(Clone, Debug, Deserialize, Serialize, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct DirectoryEntry {
    pub path: String,
    pub name: String,
    pub is_directory: bool,
}

#[derive(Clone, Debug, Deserialize, Serialize, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct GlobMatch {
    pub path: String,
    pub modification_date_epoch: Option<f64>,
}

pub fn dispatch(request: AgentRPCRequest) -> AgentRPCResponse {
    match request {
        AgentRPCRequest::ReadFile(args) => read_file(&args.path),
        AgentRPCRequest::WriteFile(args) => write_file(&args.path, &args.data_base64),
        AgentRPCRequest::Stat(args) => stat(&args.path),
        AgentRPCRequest::ListDirectory(args) => list_directory(&args.path),
        AgentRPCRequest::Glob(args) => glob_files(&args.pattern, &args.root_path, args.walk_cap),
        AgentRPCRequest::Grep(args) => grep(args),
        AgentRPCRequest::Bash(args) => bash(args),
    }
}

fn read_file(path: &str) -> AgentRPCResponse {
    let path_ref = Path::new(path);
    if !path_ref.exists() {
        return rpc_error(ErrorKind::NotFound, path);
    }
    if !path_ref.is_file() {
        return rpc_error(ErrorKind::NotRegularFile, path);
    }
    match fs::read(path_ref) {
        Ok(data) => AgentRPCResponse::ReadFile(ReadFileResult {
            data_base64: STANDARD.encode(data),
        }),
        Err(error) => rpc_error(ErrorKind::IoFailure, error.to_string()),
    }
}

fn write_file(path: &str, data_base64: &str) -> AgentRPCResponse {
    let data = match STANDARD.decode(data_base64) {
        Ok(data) => data,
        Err(_) => {
            return rpc_error(
                ErrorKind::InvalidArguments,
                "writeFile: data is not valid base64",
            )
        }
    };
    let path_ref = Path::new(path);
    if path_ref.is_dir() {
        return rpc_error(ErrorKind::NotRegularFile, path);
    }
    if let Some(parent) = path_ref.parent() {
        if let Err(error) = fs::create_dir_all(parent) {
            return rpc_error(ErrorKind::IoFailure, error.to_string());
        }
    }
    match fs::write(path_ref, data) {
        Ok(()) => AgentRPCResponse::WriteFile {},
        Err(error) => rpc_error(ErrorKind::IoFailure, error.to_string()),
    }
}

fn stat(path: &str) -> AgentRPCResponse {
    let path_ref = Path::new(path);
    if !path_ref.exists() {
        return AgentRPCResponse::Stat(StatResult { metadata: None });
    }
    match fs::metadata(path_ref) {
        Ok(metadata) => AgentRPCResponse::Stat(StatResult {
            metadata: Some(FileMetadata {
                path: path.to_owned(),
                is_directory: metadata.is_dir(),
                is_regular_file: metadata.is_file(),
                size: usize::try_from(metadata.len()).ok(),
                modification_date_epoch: modified_epoch(&metadata),
            }),
        }),
        Err(error) => rpc_error(ErrorKind::IoFailure, error.to_string()),
    }
}

fn list_directory(path: &str) -> AgentRPCResponse {
    let path_ref = Path::new(path);
    if !path_ref.exists() {
        return rpc_error(ErrorKind::NotFound, path);
    }
    if !path_ref.is_dir() {
        return rpc_error(ErrorKind::NotDirectory, path);
    }
    let entries = match fs::read_dir(path_ref) {
        Ok(entries) => entries,
        Err(error) => return rpc_error(ErrorKind::IoFailure, error.to_string()),
    };
    let mut result = Vec::new();
    for entry in entries.flatten() {
        let path = entry.path();
        result.push(DirectoryEntry {
            path: path.to_string_lossy().to_string(),
            name: entry.file_name().to_string_lossy().to_string(),
            is_directory: path.is_dir(),
        });
    }
    result.sort_by(|lhs, rhs| lhs.path.cmp(&rhs.path));
    AgentRPCResponse::ListDirectory(ListDirectoryResult { entries: result })
}

fn glob_files(pattern: &str, root_path: &str, walk_cap: usize) -> AgentRPCResponse {
    let root = Path::new(root_path);
    if !root.is_dir() {
        return rpc_error(ErrorKind::NotDirectory, root_path);
    }
    let full_pattern = root.join(pattern);
    let mut matches = Vec::new();
    for (visited, entry) in match glob(full_pattern.to_string_lossy().as_ref()) {
        Ok(entries) => entries,
        Err(error) => return rpc_error(ErrorKind::InvalidArguments, error.to_string()),
    }
    .enumerate()
    {
        if visited >= walk_cap {
            break;
        }
        if let Ok(path) = entry {
            if !path.is_file() {
                continue;
            }
            let metadata = fs::metadata(&path).ok();
            matches.push(GlobMatch {
                path: path.to_string_lossy().to_string(),
                modification_date_epoch: metadata.as_ref().and_then(modified_epoch),
            });
        }
    }
    matches.sort_by(|lhs, rhs| lhs.path.cmp(&rhs.path));
    AgentRPCResponse::Glob(GlobResult { matches })
}

fn grep(args: GrepArgs) -> AgentRPCResponse {
    let mut command = Command::new("/usr/bin/grep");
    command.arg("-rnE");
    if args.case_insensitive {
        command.arg("-i");
    }
    if let Some(glob) = args.glob.filter(|value| !value.is_empty()) {
        command.arg(format!("--include={glob}"));
    }
    command.arg(args.pattern).arg(args.path);
    process_response(command.output())
        .map(AgentRPCResponse::Grep)
        .unwrap_or_else(|error| error)
}

fn bash(args: BashArgs) -> AgentRPCResponse {
    let mut command = Command::new("/bin/zsh");
    command
        .arg("-lc")
        .arg(args.command)
        .current_dir(args.working_directory);
    process_response(command.output())
        .map(AgentRPCResponse::Bash)
        .unwrap_or_else(|error| error)
}

fn process_response(
    output: std::io::Result<std::process::Output>,
) -> Result<ProcessResult, AgentRPCResponse> {
    match output {
        Ok(output) => Ok(ProcessResult {
            exit_code: output.status.code().unwrap_or(-1),
            stdout: String::from_utf8_lossy(&output.stdout).to_string(),
            stderr: String::from_utf8_lossy(&output.stderr).to_string(),
        }),
        Err(error_value) => Err(rpc_error(ErrorKind::IoFailure, error_value.to_string())),
    }
}

fn modified_epoch(metadata: &fs::Metadata) -> Option<f64> {
    metadata
        .modified()
        .ok()
        .and_then(|value| value.duration_since(UNIX_EPOCH).ok())
        .map(|value| value.as_secs_f64())
}

fn rpc_error(kind: ErrorKind, detail: impl Into<String>) -> AgentRPCResponse {
    AgentRPCResponse::Error(RPCError {
        kind,
        detail: detail.into(),
    })
}

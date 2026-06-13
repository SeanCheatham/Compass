use serde::{Deserialize, Serialize};
use std::ffi::{CStr, CString};
use std::os::raw::c_char;
use std::panic::{catch_unwind, AssertUnwindSafe};
use std::path::PathBuf;
use tessera_core::TesseraProjectService;

#[derive(Debug, Deserialize)]
struct VerifyProjectRequest {
    root: String,
}

#[derive(Debug, Deserialize)]
struct RunEntrypointRequest {
    root: String,
    entrypoint: String,
    #[serde(default)]
    input: Option<serde_json::Value>,
}

#[derive(Debug, Serialize)]
struct EngineResponse<T>
where
    T: Serialize,
{
    ok: bool,
    kind: &'static str,
    #[serde(skip_serializing_if = "Option::is_none")]
    result: Option<T>,
    #[serde(skip_serializing_if = "Option::is_none")]
    message: Option<String>,
}

#[no_mangle]
pub extern "C" fn compass_engine_verify_project(request_json: *const c_char) -> *mut c_char {
    ffi_boundary(|| verify_project(request_json))
}

#[no_mangle]
pub extern "C" fn compass_engine_run_entrypoint(request_json: *const c_char) -> *mut c_char {
    ffi_boundary(|| run_entrypoint(request_json))
}

#[no_mangle]
pub extern "C" fn compass_engine_free_string(ptr: *mut c_char) {
    if ptr.is_null() {
        return;
    }
    unsafe {
        drop(CString::from_raw(ptr));
    }
}

fn verify_project(request_json: *const c_char) -> String {
    let request: VerifyProjectRequest = match decode_request(request_json) {
        Ok(request) => request,
        Err(message) => return encode_error("verify_project", message),
    };
    if request.root.trim().is_empty() {
        return encode_error("verify_project", "root is required");
    }
    let report = TesseraProjectService::new().verify_root(PathBuf::from(request.root));
    encode_response(EngineResponse {
        ok: report.ok,
        kind: "verify_project",
        result: Some(report),
        message: None,
    })
}

fn run_entrypoint(request_json: *const c_char) -> String {
    let request: RunEntrypointRequest = match decode_request(request_json) {
        Ok(request) => request,
        Err(message) => return encode_error("run_entrypoint", message),
    };
    if request.root.trim().is_empty() {
        return encode_error("run_entrypoint", "root is required");
    }
    if request.entrypoint.trim().is_empty() {
        return encode_error("run_entrypoint", "entrypoint is required");
    }
    let result = TesseraProjectService::new().execute_entrypoint_root(
        PathBuf::from(request.root),
        &request.entrypoint,
        request.input.as_ref(),
    );
    encode_response(EngineResponse {
        ok: result.ok,
        kind: "run_entrypoint",
        result: Some(result),
        message: None,
    })
}

fn ffi_boundary(operation: impl FnOnce() -> String) -> *mut c_char {
    let response = catch_unwind(AssertUnwindSafe(operation))
        .unwrap_or_else(|_| encode_error("panic", "Compass engine panicked"));
    CString::new(response)
        .unwrap_or_else(|_| {
            CString::new(encode_error("encoding", "response contained NUL")).unwrap()
        })
        .into_raw()
}

fn decode_request<T>(request_json: *const c_char) -> Result<T, String>
where
    T: for<'de> Deserialize<'de>,
{
    if request_json.is_null() {
        return Err("request_json is null".to_string());
    }
    let request = unsafe { CStr::from_ptr(request_json) }
        .to_str()
        .map_err(|error| format!("request_json is not UTF-8: {error}"))?;
    serde_json::from_str(request).map_err(|error| format!("invalid request JSON: {error}"))
}

fn encode_response<T>(response: EngineResponse<T>) -> String
where
    T: Serialize,
{
    serde_json::to_string(&response).unwrap_or_else(|error| {
        encode_error(
            "encoding",
            format!("failed to encode response JSON: {error}"),
        )
    })
}

fn encode_error(kind: &'static str, message: impl Into<String>) -> String {
    let response: EngineResponse<serde_json::Value> = EngineResponse {
        ok: false,
        kind,
        result: None,
        message: Some(message.into()),
    };
    serde_json::to_string(&response).unwrap()
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::ffi::CString;
    use std::fs;
    use std::time::{SystemTime, UNIX_EPOCH};

    #[test]
    fn verify_project_reports_valid_tessera_workspace() {
        let root = make_project("valid");
        write_standard_project(&root, "\"entrypoint!\"");
        let response = call_verify(&root);
        assert_eq!(response["kind"], "verify_project");
        assert_eq!(response["ok"], true);
        assert_eq!(response["result"]["ok"], true);
        assert_eq!(response["result"]["trace"]["covered_source_count"], 1);
    }

    #[test]
    fn verify_project_reports_missing_tests() {
        let root = make_project("missing-tests");
        fs::create_dir_all(root.join("src")).unwrap();
        fs::write(root.join("src/display-name.tes"), "(concat name \"!\")\n").unwrap();
        let response = call_verify(&root);
        assert_eq!(response["kind"], "verify_project");
        assert_eq!(response["ok"], false);
        assert_eq!(response["result"]["ok"], false);
        assert!(response["result"]["diagnostics"]
            .as_array()
            .unwrap()
            .iter()
            .any(|diagnostic| diagnostic["message"]
                .as_str()
                .unwrap()
                .contains("no Tessera project tests")));
    }

    #[test]
    fn verify_project_reports_failing_test() {
        let root = make_project("failing");
        write_standard_project(&root, "\"wrong\"");
        let response = call_verify(&root);
        assert_eq!(response["ok"], false);
        assert_eq!(response["result"]["tests"][0]["ok"], false);
    }

    #[test]
    fn run_entrypoint_executes_manifest_entrypoint() {
        let root = make_project("entrypoint");
        write_standard_project(&root, "\"entrypoint!\"");
        let response = call_entrypoint(&root, "cli", None);
        assert_eq!(response["kind"], "run_entrypoint");
        assert_eq!(response["ok"], true);
        assert_eq!(response["result"]["json"], "entrypoint!");
    }

    #[test]
    fn run_entrypoint_accepts_input_override() {
        let root = make_project("entrypoint-input");
        write_standard_project(&root, "\"override!\"");
        let response = call_entrypoint(
            &root,
            "cli",
            Some(serde_json::json!({
                "name": "override"
            })),
        );
        assert_eq!(response["ok"], true);
        assert_eq!(response["result"]["json"], "override!");
    }

    fn call_verify(root: &std::path::Path) -> serde_json::Value {
        let request = CString::new(serde_json::json!({ "root": root }).to_string()).unwrap();
        let ptr = compass_engine_verify_project(request.as_ptr());
        decode_and_free(ptr)
    }

    fn call_entrypoint(
        root: &std::path::Path,
        entrypoint: &str,
        input: Option<serde_json::Value>,
    ) -> serde_json::Value {
        let request = CString::new(
            serde_json::json!({
                "root": root,
                "entrypoint": entrypoint,
                "input": input
            })
            .to_string(),
        )
        .unwrap();
        let ptr = compass_engine_run_entrypoint(request.as_ptr());
        decode_and_free(ptr)
    }

    fn decode_and_free(ptr: *mut c_char) -> serde_json::Value {
        assert!(!ptr.is_null());
        let response = unsafe { CStr::from_ptr(ptr) }.to_str().unwrap().to_string();
        compass_engine_free_string(ptr);
        serde_json::from_str(&response).unwrap()
    }

    fn make_project(label: &str) -> PathBuf {
        let stamp = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .unwrap()
            .as_nanos();
        let root = std::env::temp_dir().join(format!("compass-engine-{label}-{stamp}"));
        fs::create_dir_all(&root).unwrap();
        root
    }

    fn write_standard_project(root: &std::path::Path, expected: &str) {
        fs::create_dir_all(root.join("src")).unwrap();
        fs::create_dir_all(root.join("contexts")).unwrap();
        fs::create_dir_all(root.join("tests")).unwrap();
        fs::write(
            root.join("tessera.json"),
            r#"{
  "name": "ffi-test",
  "version": "0.1.0",
  "entrypoints": {
    "cli": {
      "source": "display-name",
      "context": "user",
      "expect": "Text",
      "kind": "cli"
    }
  }
}
"#,
        )
        .unwrap();
        fs::write(root.join("src/display-name.tes"), "(concat name \"!\")\n").unwrap();
        fs::write(
            root.join("contexts/user.json"),
            r#"{ "name": "entrypoint" }"#,
        )
        .unwrap();
        fs::write(
            root.join("tests/display-name.json"),
            format!(
                r#"{{
  "name": "display-name",
  "source": "display-name",
  "context": "user",
  "expect": {expected}
}}
"#
            ),
        )
        .unwrap();
    }
}

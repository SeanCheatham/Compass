use serde::{Deserialize, Serialize};
use std::ffi::{c_char, CStr, CString};
use std::panic::{catch_unwind, AssertUnwindSafe};
use std::path::PathBuf;
use tessera_core::{
    check_source as check_tessera_source, format_project_source as format_tessera_source,
    inspect_project as inspect_tessera_project, parse_source as parse_tessera_source,
    run_entrypoint as run_tessera_entrypoint, run_test as run_tessera_test,
    verify_project as verify_tessera_project, PROJECT_REPORT_SCHEMA_VERSION, TESSERA_CORE_VERSION,
};

const ENGINE_ABI_VERSION: u32 = 1;
const VERSION_KIND: &str = "version";
const VERIFY_PROJECT_KIND: &str = "verify_project";
const RUN_ENTRYPOINT_KIND: &str = "run_entrypoint";
const RUN_TEST_KIND: &str = "run_test";
const INSPECT_PROJECT_KIND: &str = "inspect_project";
const PARSE_SOURCE_KIND: &str = "parse_source";
const CHECK_SOURCE_KIND: &str = "check_source";
const FORMAT_SOURCE_KIND: &str = "format_source";

const SUPPORTED_OPERATIONS: &[&str] = &[
    VERSION_KIND,
    VERIFY_PROJECT_KIND,
    RUN_ENTRYPOINT_KIND,
    RUN_TEST_KIND,
    INSPECT_PROJECT_KIND,
    PARSE_SOURCE_KIND,
    CHECK_SOURCE_KIND,
    FORMAT_SOURCE_KIND,
];

#[derive(Debug, Serialize)]
struct EngineVersion {
    engine_abi_version: u32,
    compass_engine_version: &'static str,
    project_report_schema_version: u32,
    tessera_core_version: &'static str,
    operations: &'static [&'static str],
}

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

#[derive(Debug, Deserialize)]
struct RunTestRequest {
    root: String,
    test_path: String,
}

#[derive(Debug, Deserialize)]
struct SourcePathRequest {
    root: String,
    path: String,
}

#[derive(Debug, Deserialize)]
struct CheckSourceRequest {
    root: String,
    path: String,
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
pub extern "C" fn compass_engine_version() -> *mut c_char {
    ffi_boundary(version)
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
pub extern "C" fn compass_engine_run_test(request_json: *const c_char) -> *mut c_char {
    ffi_boundary(|| run_test(request_json))
}

#[no_mangle]
pub extern "C" fn compass_engine_inspect_project(request_json: *const c_char) -> *mut c_char {
    ffi_boundary(|| inspect_project(request_json))
}

#[no_mangle]
pub extern "C" fn compass_engine_parse_source(request_json: *const c_char) -> *mut c_char {
    ffi_boundary(|| parse_source(request_json))
}

#[no_mangle]
pub extern "C" fn compass_engine_check_source(request_json: *const c_char) -> *mut c_char {
    ffi_boundary(|| check_source(request_json))
}

#[no_mangle]
pub extern "C" fn compass_engine_format_source(request_json: *const c_char) -> *mut c_char {
    ffi_boundary(|| format_source(request_json))
}

#[no_mangle]
/// Frees a string returned by the Compass engine.
///
/// # Safety
///
/// `ptr` must be null or a pointer previously returned by this library from
/// `CString::into_raw`. Each non-null pointer may be freed exactly once.
pub unsafe extern "C" fn compass_engine_free_string(ptr: *mut c_char) {
    if ptr.is_null() {
        return;
    }
    unsafe {
        // SAFETY: `ptr` must come from `CString::into_raw` in this library. Null
        // pointers are handled above, and `from_raw` takes ownership exactly once.
        drop(CString::from_raw(ptr));
    }
}

fn version() -> String {
    encode_response(EngineResponse {
        ok: true,
        kind: VERSION_KIND,
        result: Some(EngineVersion {
            engine_abi_version: ENGINE_ABI_VERSION,
            compass_engine_version: env!("CARGO_PKG_VERSION"),
            project_report_schema_version: PROJECT_REPORT_SCHEMA_VERSION,
            tessera_core_version: TESSERA_CORE_VERSION,
            operations: SUPPORTED_OPERATIONS,
        }),
        message: None,
    })
}

fn verify_project(request_json: *const c_char) -> String {
    handle_request(
        VERIFY_PROJECT_KIND,
        request_json,
        |request: VerifyProjectRequest| {
            let root = required_path(request.root, "root")?;
            let report = verify_tessera_project(root);
            Ok((report.ok, report))
        },
    )
}

fn run_entrypoint(request_json: *const c_char) -> String {
    handle_request(
        RUN_ENTRYPOINT_KIND,
        request_json,
        |request: RunEntrypointRequest| {
            let root = required_path(request.root, "root")?;
            let entrypoint = required_string(request.entrypoint, "entrypoint")?;
            let result = run_tessera_entrypoint(root, &entrypoint, request.input.as_ref());
            Ok((result.ok, result))
        },
    )
}

fn run_test(request_json: *const c_char) -> String {
    handle_request(RUN_TEST_KIND, request_json, |request: RunTestRequest| {
        let root = required_path(request.root, "root")?;
        let test_path = required_string(request.test_path, "test_path")?;
        let result = run_tessera_test(root, &test_path);
        Ok((result.ok, result))
    })
}

fn inspect_project(request_json: *const c_char) -> String {
    handle_request(
        INSPECT_PROJECT_KIND,
        request_json,
        |request: VerifyProjectRequest| {
            let root = required_path(request.root, "root")?;
            let report = inspect_tessera_project(root);
            Ok((report.ok, report))
        },
    )
}

fn parse_source(request_json: *const c_char) -> String {
    handle_request(
        PARSE_SOURCE_KIND,
        request_json,
        |request: SourcePathRequest| {
            let root = required_path(request.root, "root")?;
            let path = required_string(request.path, "path")?;
            let report = parse_tessera_source(root, &path);
            Ok((report.ok, report))
        },
    )
}

fn check_source(request_json: *const c_char) -> String {
    handle_request(
        CHECK_SOURCE_KIND,
        request_json,
        |request: CheckSourceRequest| {
            let root = required_path(request.root, "root")?;
            let path = required_string(request.path, "path")?;
            let report = check_tessera_source(root, &path, request.input.as_ref());
            Ok((report.ok, report))
        },
    )
}

fn format_source(request_json: *const c_char) -> String {
    handle_request(
        FORMAT_SOURCE_KIND,
        request_json,
        |request: SourcePathRequest| {
            let root = required_path(request.root, "root")?;
            let path = required_string(request.path, "path")?;
            let report = format_tessera_source(root, &path);
            Ok((report.ok, report))
        },
    )
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
    // SAFETY: The exported C API requires callers to pass a valid, NUL-terminated
    // UTF-8 string pointer for the lifetime of this call.
    let request = unsafe { CStr::from_ptr(request_json) }
        .to_str()
        .map_err(|error| format!("request_json is not UTF-8: {error}"))?;
    serde_json::from_str(request).map_err(|error| format!("invalid request JSON: {error}"))
}

fn handle_request<T, R>(
    kind: &'static str,
    request_json: *const c_char,
    operation: impl FnOnce(T) -> Result<(bool, R), String>,
) -> String
where
    T: for<'de> Deserialize<'de>,
    R: Serialize,
{
    let request = match decode_request(request_json) {
        Ok(request) => request,
        Err(message) => return encode_error(kind, message),
    };
    match operation(request) {
        Ok((ok, result)) => encode_response(EngineResponse {
            ok,
            kind,
            result: Some(result),
            message: None,
        }),
        Err(message) => encode_error(kind, message),
    }
}

fn required_path(value: String, field: &'static str) -> Result<PathBuf, String> {
    required_string(value, field).map(PathBuf::from)
}

fn required_string(value: String, field: &'static str) -> Result<String, String> {
    if value.trim().is_empty() {
        Err(format!("{field} is required"))
    } else {
        Ok(value)
    }
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
    use std::ops::Deref;
    use std::path::{Path, PathBuf};
    use std::time::{SystemTime, UNIX_EPOCH};

    #[test]
    fn version_reports_schema_and_supported_operations() {
        let ptr = compass_engine_version();
        let response = decode_and_free(ptr);
        assert_eq!(response["kind"], "version");
        assert_eq!(response["ok"], true);
        assert_eq!(response["result"]["engine_abi_version"], 1);
        assert_eq!(response["result"]["project_report_schema_version"], 1);
        assert!(response["result"]["operations"]
            .as_array()
            .unwrap()
            .iter()
            .any(|operation| operation == "inspect_project"));
    }

    #[test]
    fn verify_project_reports_valid_tessera_workspace() {
        let root = make_project("valid");
        write_standard_project(&root, "\"entrypoint!\"");
        let response = call_verify(&root);
        assert_eq!(response["kind"], "verify_project");
        assert_eq!(response["ok"], true);
        assert_eq!(response["result"]["ok"], true);
        assert_eq!(response["result"]["metadata"]["schema_version"], 1);
        assert_eq!(response["result"]["trace"]["covered_source_count"], 1);
        assert_eq!(response["result"]["trace"]["executions"][0]["kind"], "test");
        assert!(response["result"]["failures"]
            .as_array()
            .unwrap()
            .is_empty());
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
        assert_eq!(
            response["result"]["failures"][0]["expected_json"],
            serde_json::json!("wrong")
        );
        assert_eq!(
            response["result"]["failures"][0]["actual_json"],
            serde_json::json!("entrypoint!")
        );
    }

    #[test]
    fn run_entrypoint_executes_manifest_entrypoint() {
        let root = make_project("entrypoint");
        write_standard_project(&root, "\"entrypoint!\"");
        let response = call_entrypoint(&root, "cli", None);
        assert_eq!(response["kind"], "run_entrypoint");
        assert_eq!(response["ok"], true);
        assert_eq!(response["result"]["metadata"]["schema_version"], 1);
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

    #[test]
    fn inspect_project_reports_tessera_index() {
        let root = make_project("inspect");
        write_standard_project(&root, "\"entrypoint!\"");
        let response = call_request(
            compass_engine_inspect_project,
            serde_json::json!({ "root": root.display().to_string() }),
        );
        assert_eq!(response["kind"], "inspect_project");
        assert_eq!(response["ok"], true);
        assert_eq!(
            response["result"]["sources"][0]["path"],
            "src/display-name.tes"
        );
        assert_eq!(
            response["result"]["sources"][0]["entrypoints"][0],
            serde_json::json!("cli")
        );
        assert_eq!(
            response["result"]["sources"][0]["tests"][0],
            serde_json::json!("tests/display-name.json")
        );
    }

    #[test]
    fn focused_source_and_test_operations_work() {
        let root = make_project("focused");
        write_standard_project(&root, "\"entrypoint!\"");

        let parsed = call_request(
            compass_engine_parse_source,
            serde_json::json!({ "root": root.display().to_string(), "path": "display-name" }),
        );
        assert_eq!(parsed["kind"], "parse_source");
        assert_eq!(parsed["ok"], true);

        let checked = call_request(
            compass_engine_check_source,
            serde_json::json!({
                "root": root.display().to_string(),
                "path": "src/display-name.tes",
                "input": { "name": "entrypoint" }
            }),
        );
        assert_eq!(checked["kind"], "check_source");
        assert_eq!(checked["ok"], true);
        assert_eq!(checked["result"]["ty"], "Text");

        let formatted = call_request(
            compass_engine_format_source,
            serde_json::json!({ "root": root.display().to_string(), "path": "src/display-name.tes" }),
        );
        assert_eq!(formatted["kind"], "format_source");
        assert_eq!(formatted["ok"], true);
        assert_eq!(formatted["result"]["changed"], false);

        let test = call_request(
            compass_engine_run_test,
            serde_json::json!({
                "root": root.display().to_string(),
                "test_path": "tests/display-name.json"
            }),
        );
        assert_eq!(test["kind"], "run_test");
        assert_eq!(test["ok"], true);
        assert_eq!(test["result"]["json"], "entrypoint!");
    }

    fn call_verify(root: &std::path::Path) -> serde_json::Value {
        call_request(
            compass_engine_verify_project,
            serde_json::json!({ "root": root }),
        )
    }

    fn call_entrypoint(
        root: &std::path::Path,
        entrypoint: &str,
        input: Option<serde_json::Value>,
    ) -> serde_json::Value {
        call_request(
            compass_engine_run_entrypoint,
            serde_json::json!({
                "root": root,
                "entrypoint": entrypoint,
                "input": input
            }),
        )
    }

    fn call_request(
        function: extern "C" fn(*const c_char) -> *mut c_char,
        value: serde_json::Value,
    ) -> serde_json::Value {
        let request = CString::new(value.to_string()).unwrap();
        let ptr = function(request.as_ptr());
        decode_and_free(ptr)
    }

    fn decode_and_free(ptr: *mut c_char) -> serde_json::Value {
        assert!(!ptr.is_null());
        // SAFETY: The engine returns owned, NUL-terminated strings allocated by
        // `CString::into_raw`; tests immediately copy and then free them.
        let response = unsafe { CStr::from_ptr(ptr) }.to_str().unwrap().to_string();
        unsafe {
            // SAFETY: `ptr` came from an engine FFI call in this test and has not
            // been freed yet.
            compass_engine_free_string(ptr);
        }
        serde_json::from_str(&response).unwrap()
    }

    struct TestProject {
        root: PathBuf,
    }

    impl TestProject {
        fn new(label: &str) -> Self {
            let stamp = SystemTime::now()
                .duration_since(UNIX_EPOCH)
                .unwrap()
                .as_nanos();
            let root = std::env::temp_dir().join(format!("compass-engine-{label}-{stamp}"));
            fs::create_dir_all(&root).unwrap();
            Self { root }
        }
    }

    impl Deref for TestProject {
        type Target = Path;

        fn deref(&self) -> &Self::Target {
            &self.root
        }
    }

    impl Drop for TestProject {
        fn drop(&mut self) {
            let _ = fs::remove_dir_all(&self.root);
        }
    }

    fn make_project(label: &str) -> TestProject {
        TestProject::new(label)
    }

    fn write_standard_project(root: &Path, expected: &str) {
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

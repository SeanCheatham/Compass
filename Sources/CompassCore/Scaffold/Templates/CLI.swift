import Foundation

/// `crates/cli` scaffold templates.
public enum RustScaffoldCLITemplates {
  public static let cliManifest = """
    [package]
    name = "app-cli"
    edition.workspace = true
    license.workspace = true
    version.workspace = true

    [dependencies]
    app-core.workspace = true
    """

  public static let cliMain = """
    use app_core::greeting;

    fn main() {
        let mut args = std::env::args().skip(1);
        match args.next().as_deref() {
            None | Some("status") => {
                println!("{}", greeting("world"));
            }
            Some(other) => {
                eprintln!("unknown command: {other}");
                eprintln!("usage: app-cli [status]");
                std::process::exit(2);
            }
        }
    }
    """

  /// Golden-output acceptance harness: runs the built binary and asserts
  /// stdout/stderr/exit codes for core user flows.
  public static let cliSmokeTest = """
    use std::process::Command;

    fn run(args: &[&str]) -> (i32, String, String) {
        let output = Command::new(env!("CARGO_BIN_EXE_app-cli"))
            .args(args)
            .output()
            .expect("run app-cli");
        let code = output.status.code().unwrap_or(-1);
        let stdout = String::from_utf8_lossy(&output.stdout).into_owned();
        let stderr = String::from_utf8_lossy(&output.stderr).into_owned();
        (code, stdout, stderr)
    }

    #[test]
    fn status_prints_greeting_golden() {
        let (code, stdout, stderr) = run(&["status"]);
        assert_eq!(code, 0, "stderr={stderr}");
        assert_eq!(stdout.trim(), "hello, world");
        assert!(stderr.is_empty(), "stderr was: {stderr}");
    }

    #[test]
    fn default_args_match_status_golden() {
        let (code, stdout, _) = run(&[]);
        assert_eq!(code, 0);
        assert_eq!(stdout.trim(), "hello, world");
    }

    #[test]
    fn unknown_command_exits_2() {
        let (code, stdout, stderr) = run(&["nope"]);
        assert_eq!(code, 2);
        assert!(stdout.is_empty(), "stdout was: {stdout}");
        assert!(stderr.contains("unknown command: nope"), "stderr was: {stderr}");
    }
    """
}

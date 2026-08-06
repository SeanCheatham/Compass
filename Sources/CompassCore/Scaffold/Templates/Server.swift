import Foundation

/// `crates/server` scaffold templates (axum HTTP adapter over `crates/core`).
public enum RustScaffoldServerTemplates {
  public static let serverManifest = """
    [package]
    name = "app-server"
    edition.workspace = true
    license.workspace = true
    version.workspace = true

    [[bin]]
    name = "app-server"
    path = "src/main.rs"

    [dependencies]
    app-core.workspace = true
    axum.workspace = true
    tokio.workspace = true
    tower.workspace = true
    http-body-util.workspace = true
    """

  public static let serverLib = """
    use app_core::greeting;
    use axum::{routing::get, Router};

    /// HTTP router shared by the binary and integration tests.
    pub fn app() -> Router {
        Router::new().route("/status", get(status))
    }

    async fn status() -> String {
        greeting("world")
    }
    """

  public static let serverMain = """
    use app_server::app;
    use std::net::SocketAddr;

    #[tokio::main]
    async fn main() {
        let addr = SocketAddr::from(([127, 0, 0, 1], 8080));
        let listener = tokio::net::TcpListener::bind(addr)
            .await
            .expect("bind server");
        println!("listening on http://{addr}");
        axum::serve(listener, app()).await.expect("serve");
    }
    """

  public static let httpIntegrationTest = """
    use app_server::app;
    use axum::body::Body;
    use http_body_util::BodyExt;
    use tower::ServiceExt;

    #[tokio::test]
    async fn status_returns_greeting() {
        let response = app()
            .oneshot(
                axum::http::Request::builder()
                    .uri("/status")
                    .body(Body::empty())
                    .unwrap(),
            )
            .await
            .expect("status request");
        assert_eq!(response.status(), axum::http::StatusCode::OK);
        let bytes = response
            .into_body()
            .collect()
            .await
            .expect("read body")
            .to_bytes();
        let body = String::from_utf8_lossy(&bytes);
        assert_eq!(body, "hello, world");
    }
    """
}

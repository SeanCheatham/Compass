use anyhow::{bail, Result};
use compass_guest_agent::{framing, rpc};
use std::io::{Read, Write};

fn main() {
    if let Err(error) = run() {
        eprintln!("compass-guest-agent: {error:#}");
        std::process::exit(1);
    }
}

fn run() -> Result<()> {
    let mut args = std::env::args().skip(1);
    match args.next().as_deref() {
        Some("--stdio-once") => {
            let mut input = Vec::new();
            std::io::stdin().read_to_end(&mut input)?;
            let request = framing::decode::<rpc::AgentRPCRequest>(&input)?;
            let response = rpc::dispatch(request);
            std::io::stdout().write_all(&framing::encode(&response)?)?;
            Ok(())
        }
        Some("--help") | Some("-h") => {
            println!("usage: compass-guest-agent [--stdio-once]");
            Ok(())
        }
        Some(flag) => {
            bail!("unsupported argument {flag}; vsock listen is enabled in rollout builds")
        }
        None => {
            eprintln!(
                "compass-guest-agent: Rust RPC handlers are available; use --stdio-once for framed test transport"
            );
            Ok(())
        }
    }
}

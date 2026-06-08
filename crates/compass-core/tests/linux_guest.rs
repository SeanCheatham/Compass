use compass_core::vm::linux::LinuxGuestConfig;
use std::path::PathBuf;

#[test]
fn qemu_args_include_hvf_vsock_and_ssh_forward() {
    let config = LinuxGuestConfig {
        qemu_binary: PathBuf::from("/opt/homebrew/bin/qemu-system-aarch64"),
        image_path: PathBuf::from("/tmp/compass-guest.qcow2"),
        ssh_host_port: 2207,
        guest_cid: 7,
        memory_mib: 2048,
        cpu_count: 2,
    };

    let args = config.qemu_args().join(" ");
    assert!(args.contains("-accel hvf"));
    assert!(args.contains("vhost-vsock-pci,guest-cid=7"));
    assert!(args.contains("hostfwd=tcp:127.0.0.1:2207-:22"));
    assert_eq!(config.ssh_destination(), "compass@127.0.0.1:2207");
}

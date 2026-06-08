use serde::{Deserialize, Serialize};
use std::path::PathBuf;

#[derive(Clone, Debug, Deserialize, Serialize, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct LinuxGuestConfig {
    pub qemu_binary: PathBuf,
    pub image_path: PathBuf,
    pub ssh_host_port: u16,
    pub guest_cid: u32,
    pub memory_mib: u32,
    pub cpu_count: u8,
}

impl LinuxGuestConfig {
    pub fn qemu_args(&self) -> Vec<String> {
        vec![
            "-accel".to_owned(),
            "hvf".to_owned(),
            "-machine".to_owned(),
            "virt".to_owned(),
            "-cpu".to_owned(),
            "host".to_owned(),
            "-smp".to_owned(),
            self.cpu_count.to_string(),
            "-m".to_owned(),
            format!("{}M", self.memory_mib),
            "-drive".to_owned(),
            format!("if=virtio,format=qcow2,file={}", self.image_path.display()),
            "-device".to_owned(),
            format!("vhost-vsock-pci,guest-cid={}", self.guest_cid),
            "-netdev".to_owned(),
            format!(
                "user,id=net0,hostfwd=tcp:127.0.0.1:{}-:22",
                self.ssh_host_port
            ),
            "-device".to_owned(),
            "virtio-net-pci,netdev=net0".to_owned(),
            "-nographic".to_owned(),
        ]
    }

    pub fn ssh_destination(&self) -> String {
        format!("compass@127.0.0.1:{}", self.ssh_host_port)
    }
}

impl Default for LinuxGuestConfig {
    fn default() -> Self {
        Self {
            qemu_binary: PathBuf::from("/opt/homebrew/bin/qemu-system-aarch64"),
            image_path: PathBuf::from(
                "~/Library/Application Support/Compass/SharedVM/linux/compass-guest.qcow2",
            ),
            ssh_host_port: 22_207,
            guest_cid: 3,
            memory_mib: 4096,
            cpu_count: 4,
        }
    }
}

import Foundation

/// Host-side IP discovery for the Compass shared VM guest.
///
/// VZ does not expose a "current guest IP" API; the guest is just a DHCP
/// client on the VZ NAT subnet. Two host-side sources can identify the IP
/// for a given MAC:
///
///   * `/var/db/dhcpd_leases` — macOS bootpd's lease file. The most reliable
///     source; lasts across DHCP refreshes and survives reboots.
///   * `arp -an` — the host's current ARP table. Fast, but only populated
///     after the host has talked to the guest at least once (which it
///     usually has, immediately after boot).
///
/// We prefer dhcpd_leases for stability, fall back to arp, and parse both
/// tolerantly: macOS sometimes prints MAC octets with leading zeros stripped
/// (`52:8a:1:2:3:4` vs `52:8a:01:02:03:04`), so we canonicalize both sides
/// before comparison.
enum SharedCompassVMGuestIPDiscovery {
    /// Default location of macOS bootpd's lease file.
    static let defaultDHCPLeasesPath = "/var/db/dhcpd_leases"

    /// Default `arp` binary location.
    static let defaultARPExecutablePath = "/usr/sbin/arp"

    enum LookupSource: Equatable {
        case dhcpLeases
        case arp
    }

    struct DiscoveredIP: Equatable {
        var ip: String
        var source: LookupSource
    }

    /// Polls dhcpd_leases + arp on a fixed cadence until either an IP is
    /// found or the deadline passes. Returns nil on timeout. Never throws.
    static func waitForGuestIP(
        macAddress: String,
        timeout: TimeInterval = 60,
        pollInterval: TimeInterval = 2,
        dhcpLeasesPath: String = defaultDHCPLeasesPath,
        arpExecutablePath: String = defaultARPExecutablePath,
        fileManager: FileManager = .default
    ) async -> DiscoveredIP? {
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            if let found = await lookupGuestIP(
                macAddress: macAddress,
                dhcpLeasesPath: dhcpLeasesPath,
                arpExecutablePath: arpExecutablePath,
                fileManager: fileManager
            ) {
                return found
            }
            let sleepNs = UInt64(max(0.1, pollInterval) * 1_000_000_000)
            try? await Task.sleep(nanoseconds: sleepNs)
        } while Date() < deadline

        return await lookupGuestIP(
            macAddress: macAddress,
            dhcpLeasesPath: dhcpLeasesPath,
            arpExecutablePath: arpExecutablePath,
            fileManager: fileManager
        )
    }

    /// Single-shot lookup. Tries dhcpd_leases first, then arp.
    static func lookupGuestIP(
        macAddress: String,
        dhcpLeasesPath: String = defaultDHCPLeasesPath,
        arpExecutablePath: String = defaultARPExecutablePath,
        fileManager: FileManager = .default
    ) async -> DiscoveredIP? {
        let canonicalMAC = canonicalize(mac: macAddress)
        guard !canonicalMAC.isEmpty else { return nil }

        if fileManager.fileExists(atPath: dhcpLeasesPath),
           let data = try? Data(contentsOf: URL(fileURLWithPath: dhcpLeasesPath)),
           let text = String(data: data, encoding: .utf8),
           let ip = parseDHCPLeases(text, forCanonicalMAC: canonicalMAC) {
            return DiscoveredIP(ip: ip, source: .dhcpLeases)
        }

        if let arpText = await runARPDashAN(executablePath: arpExecutablePath),
           let ip = parseARPTable(arpText, forCanonicalMAC: canonicalMAC) {
            return DiscoveredIP(ip: ip, source: .arp)
        }

        return nil
    }

    // MARK: - Parsers

    /// Parses `/var/db/dhcpd_leases` and returns the `ip_address` for the
    /// entry whose `hw_address` matches the supplied canonicalized MAC.
    static func parseDHCPLeases(_ text: String, forCanonicalMAC canonicalMAC: String) -> String? {
        // Lease file is a sequence of `{ ... }` blocks. Use a naive scan
        // that tracks the open/close brace pairs at top level (no nesting
        // is expected) and parses key=value lines inside each block.
        var currentBlock: [String: String] = [:]
        var inBlock = false
        var lastMatchedIP: String?
        var lastMatchedLease: UInt64 = 0

        for rawLine in text.split(whereSeparator: \.isNewline) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line == "{" {
                inBlock = true
                currentBlock = [:]
                continue
            }
            if line == "}" {
                inBlock = false
                if let hw = currentBlock["hw_address"],
                   let ip = currentBlock["ip_address"],
                   canonicalize(mac: hw) == canonicalMAC {
                    // Prefer the entry with the newest lease timestamp so we
                    // don't latch on to a stale assignment if the guest has
                    // re-DHCP'd.
                    let lease = parseHexLease(currentBlock["lease"])
                    if lease >= lastMatchedLease {
                        lastMatchedIP = ip
                        lastMatchedLease = lease
                    }
                }
                continue
            }
            guard inBlock else { continue }
            // Lines are `<key>=<value>`. Trim and store.
            guard let equalsRange = line.range(of: "=") else { continue }
            let key = line[line.startIndex..<equalsRange.lowerBound]
                .trimmingCharacters(in: .whitespaces)
            let value = line[equalsRange.upperBound..<line.endIndex]
                .trimmingCharacters(in: .whitespaces)
            currentBlock[key] = value
        }
        return lastMatchedIP
    }

    /// Parses `arp -an` output and returns the IP for the entry whose MAC
    /// matches the supplied canonicalized MAC.
    ///
    /// Sample line: `? (192.168.64.4) at 52:8a:1:2:3:4 on bridge100 ifscope [bridge]`
    static func parseARPTable(_ text: String, forCanonicalMAC canonicalMAC: String) -> String? {
        for rawLine in text.split(whereSeparator: \.isNewline) {
            let line = String(rawLine)
            guard let openParen = line.firstIndex(of: "("),
                  let closeParen = line.firstIndex(of: ")"),
                  openParen < closeParen else {
                continue
            }
            let ip = String(line[line.index(after: openParen)..<closeParen])
                .trimmingCharacters(in: .whitespaces)
            guard !ip.isEmpty else { continue }
            // After ` at `, the next whitespace-separated token is the MAC.
            guard let atRange = line.range(of: " at ", range: closeParen..<line.endIndex) else {
                continue
            }
            let remainder = line[atRange.upperBound..<line.endIndex]
            let mac = remainder
                .split(whereSeparator: { $0 == " " || $0 == "\t" })
                .first
                .map(String.init) ?? ""
            if canonicalize(mac: mac) == canonicalMAC {
                return ip
            }
        }
        return nil
    }

    // MARK: - Helpers

    /// Normalizes a MAC address to lowercase, zero-padded, colon-separated
    /// (e.g. `52:8a:01:02:03:04`). Strips any leading `1,` prefix from
    /// dhcpd_leases entries (`1,52:8a:1:2:3:4` → `52:8a:01:02:03:04`).
    static func canonicalize(mac: String) -> String {
        var trimmed = mac.trimmingCharacters(in: .whitespaces).lowercased()
        // Strip a leading `n,` prefix (dhcpd_leases hw_address format).
        if let commaIdx = trimmed.firstIndex(of: ",") {
            trimmed = String(trimmed[trimmed.index(after: commaIdx)..<trimmed.endIndex])
        }
        // Some sources use `-` as the separator; normalize to `:`.
        trimmed = trimmed.replacingOccurrences(of: "-", with: ":")
        let parts = trimmed.split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count == 6 else { return "" }
        var result: [String] = []
        result.reserveCapacity(6)
        for part in parts {
            guard !part.isEmpty, part.count <= 2 else { return "" }
            // Reject non-hex characters.
            for scalar in part.unicodeScalars {
                guard CharacterSet.hexDigits.contains(scalar) else { return "" }
            }
            let padded = part.count == 1 ? "0\(part)" : String(part)
            result.append(padded)
        }
        return result.joined(separator: ":")
    }

    /// Returns the integer value of a hex literal like `0x1a2b3c` or `1a2b3c`.
    /// Bad input → 0.
    private static func parseHexLease(_ raw: String?) -> UInt64 {
        guard var raw else { return 0 }
        if raw.hasPrefix("0x") || raw.hasPrefix("0X") {
            raw = String(raw.dropFirst(2))
        }
        return UInt64(raw, radix: 16) ?? 0
    }

    private static func runARPDashAN(executablePath: String) async -> String? {
        await Task.detached { () -> String? in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: executablePath)
            process.arguments = ["-an"]
            let stdout = Pipe()
            let stderr = Pipe()
            process.standardOutput = stdout
            process.standardError = stderr
            do {
                try process.run()
            } catch {
                return nil
            }
            process.waitUntilExit()
            guard process.terminationStatus == 0 else { return nil }
            let data = (try? stdout.fileHandleForReading.readToEnd()) ?? Data()
            return String(data: data, encoding: .utf8)
        }.value
    }
}

private extension CharacterSet {
    static let hexDigits: CharacterSet = {
        var set = CharacterSet()
        set.insert(charactersIn: "0123456789abcdefABCDEF")
        return set
    }()
}

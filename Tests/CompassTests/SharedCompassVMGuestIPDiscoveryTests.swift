import XCTest

@testable import Compass

final class SharedCompassVMGuestIPDiscoveryTests: XCTestCase {
  // MARK: canonicalize

  func testCanonicalizeFullyExpandedMACReturnsLowercaseColonForm() {
    XCTAssertEqual(
      SharedCompassVMGuestIPDiscovery.canonicalize(mac: "52:8A:01:02:03:04"),
      "52:8a:01:02:03:04"
    )
  }

  func testCanonicalizePadsSingleHexDigitOctets() {
    XCTAssertEqual(
      SharedCompassVMGuestIPDiscovery.canonicalize(mac: "52:8a:1:2:3:4"),
      "52:8a:01:02:03:04"
    )
  }

  func testCanonicalizeStripsDHCPLeasesPrefix() {
    XCTAssertEqual(
      SharedCompassVMGuestIPDiscovery.canonicalize(mac: "1,52:8a:1:2:3:4"),
      "52:8a:01:02:03:04"
    )
  }

  func testCanonicalizeAcceptsDashSeparator() {
    XCTAssertEqual(
      SharedCompassVMGuestIPDiscovery.canonicalize(mac: "52-8a-01-02-03-04"),
      "52:8a:01:02:03:04"
    )
  }

  func testCanonicalizeRejectsTooFewOctets() {
    XCTAssertEqual(
      SharedCompassVMGuestIPDiscovery.canonicalize(mac: "52:8a:01:02:03"),
      ""
    )
  }

  func testCanonicalizeRejectsNonHexCharacters() {
    XCTAssertEqual(
      SharedCompassVMGuestIPDiscovery.canonicalize(mac: "52:8a:0g:02:03:04"),
      ""
    )
  }

  func testCanonicalizeRejectsOctetsWithMoreThanTwoDigits() {
    XCTAssertEqual(
      SharedCompassVMGuestIPDiscovery.canonicalize(mac: "52:8a:001:02:03:04"),
      ""
    )
  }

  // MARK: parseDHCPLeases

  func testParseDHCPLeasesReturnsMatchingIP() {
    let sample = """
      {
      \tname=guest
      \tip_address=192.168.64.4
      \thw_address=1,52:8a:1:2:3:4
      \tidentifier=1,52:8a:1:2:3:4
      \tlease=0x65bb0001
      }
      """
    let ip = SharedCompassVMGuestIPDiscovery.parseDHCPLeases(
      sample,
      forCanonicalMAC: "52:8a:01:02:03:04"
    )
    XCTAssertEqual(ip, "192.168.64.4")
  }

  func testParseDHCPLeasesPicksNewestLeaseAmongMultipleEntriesForSameMAC() {
    let sample = """
      {
      \tip_address=192.168.64.4
      \thw_address=1,52:8a:1:2:3:4
      \tlease=0x10000000
      }
      {
      \tip_address=192.168.64.9
      \thw_address=1,52:8a:1:2:3:4
      \tlease=0x80000000
      }
      """
    let ip = SharedCompassVMGuestIPDiscovery.parseDHCPLeases(
      sample,
      forCanonicalMAC: "52:8a:01:02:03:04"
    )
    XCTAssertEqual(ip, "192.168.64.9")
  }

  func testParseDHCPLeasesReturnsNilWhenMACDoesNotMatch() {
    let sample = """
      {
      \tip_address=192.168.64.4
      \thw_address=1,aa:bb:cc:dd:ee:ff
      \tlease=0x65bb0001
      }
      """
    let ip = SharedCompassVMGuestIPDiscovery.parseDHCPLeases(
      sample,
      forCanonicalMAC: "52:8a:01:02:03:04"
    )
    XCTAssertNil(ip)
  }

  func testParseDHCPLeasesReturnsNilOnEmptyInput() {
    XCTAssertNil(
      SharedCompassVMGuestIPDiscovery.parseDHCPLeases("", forCanonicalMAC: "52:8a:01:02:03:04")
    )
  }

  // MARK: parseARPTable

  func testParseARPTableReturnsIPForMatchingMAC() {
    let sample = """
      ? (192.168.64.1) at b8:27:eb:1:2:3 on bridge100 ifscope [bridge]
      ? (192.168.64.4) at 52:8a:1:2:3:4 on bridge100 ifscope [bridge]
      ? (192.168.64.255) at ff:ff:ff:ff:ff:ff on bridge100 ifscope [bridge]
      """
    let ip = SharedCompassVMGuestIPDiscovery.parseARPTable(
      sample,
      forCanonicalMAC: "52:8a:01:02:03:04"
    )
    XCTAssertEqual(ip, "192.168.64.4")
  }

  func testParseARPTableReturnsNilWhenMACDoesNotAppear() {
    let sample = "? (192.168.64.1) at b8:27:eb:1:2:3 on bridge100 ifscope [bridge]"
    let ip = SharedCompassVMGuestIPDiscovery.parseARPTable(
      sample,
      forCanonicalMAC: "52:8a:01:02:03:04"
    )
    XCTAssertNil(ip)
  }

  func testParseARPTableSkipsLinesWithoutParenthesizedIP() {
    let sample = """
      Bogus header line without any IP
      ? (192.168.64.4) at 52:8a:1:2:3:4 on bridge100 ifscope [bridge]
      """
    let ip = SharedCompassVMGuestIPDiscovery.parseARPTable(
      sample,
      forCanonicalMAC: "52:8a:01:02:03:04"
    )
    XCTAssertEqual(ip, "192.168.64.4")
  }

  // MARK: randomGuestMAC

  func testRandomGuestMACIsCanonicalAndLocallyAdministeredUnicast() {
    for _ in 0..<32 {
      let mac = SharedCompassVMBundle.randomGuestMAC()
      XCTAssertEqual(
        SharedCompassVMGuestIPDiscovery.canonicalize(mac: mac),
        mac,
        "randomGuestMAC should already be canonical"
      )
      let firstOctetHex = String(mac.prefix(2))
      let firstOctet = UInt8(firstOctetHex, radix: 16) ?? 0
      XCTAssertEqual(firstOctet & 0b0000_0010, 0b0000_0010, "expected locally-administered bit set")
      XCTAssertEqual(firstOctet & 0b0000_0001, 0, "expected unicast bit clear")
    }
  }
}

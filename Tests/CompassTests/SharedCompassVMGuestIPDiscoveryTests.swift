import Foundation
import Testing

@testable import Compass

struct SharedCompassVMGuestIPDiscoveryTests {
  // MARK: canonicalize

  @Test
  func testCanonicalizeFullyExpandedMACReturnsLowercaseColonForm() throws {
    try #require(
      SharedCompassVMGuestIPDiscovery.canonicalize(mac: "52:8A:01:02:03:04") == "52:8a:01:02:03:04"
    )
  }

  @Test
  func testCanonicalizePadsSingleHexDigitOctets() throws {
    try #require(
      SharedCompassVMGuestIPDiscovery.canonicalize(mac: "52:8a:1:2:3:4") == "52:8a:01:02:03:04"
    )
  }

  @Test
  func testCanonicalizeStripsDHCPLeasesPrefix() throws {
    try #require(
      SharedCompassVMGuestIPDiscovery.canonicalize(mac: "1,52:8a:1:2:3:4") == "52:8a:01:02:03:04"
    )
  }

  @Test
  func testCanonicalizeAcceptsDashSeparator() throws {
    try #require(
      SharedCompassVMGuestIPDiscovery.canonicalize(mac: "52-8a-01-02-03-04") == "52:8a:01:02:03:04"
    )
  }

  @Test
  func testCanonicalizeRejectsTooFewOctets() throws {
    try #require(
      SharedCompassVMGuestIPDiscovery.canonicalize(mac: "52:8a:01:02:03") == ""
    )
  }

  @Test
  func testCanonicalizeRejectsNonHexCharacters() throws {
    try #require(
      SharedCompassVMGuestIPDiscovery.canonicalize(mac: "52:8a:0g:02:03:04") == ""
    )
  }

  @Test
  func testCanonicalizeRejectsOctetsWithMoreThanTwoDigits() throws {
    try #require(
      SharedCompassVMGuestIPDiscovery.canonicalize(mac: "52:8a:001:02:03:04") == ""
    )
  }

  // MARK: parseDHCPLeases

  @Test
  func testParseDHCPLeasesReturnsMatchingIP() throws {
    let sample = """
      {
      	name=guest
      	ip_address=192.168.64.4
      	hw_address=1,52:8a:1:2:3:4
      	identifier=1,52:8a:1:2:3:4
      	lease=0x65bb0001
      }
      """
    let ip = SharedCompassVMGuestIPDiscovery.parseDHCPLeases(
      sample,
      forCanonicalMAC: "52:8a:01:02:03:04"
    )
    try #require(ip == "192.168.64.4")
  }

  @Test
  func testParseDHCPLeasesPicksNewestLeaseAmongMultipleEntriesForSameMAC() throws {
    let sample = """
      {
      	ip_address=192.168.64.4
      	hw_address=1,52:8a:1:2:3:4
      	lease=0x10000000
      }
      {
      	ip_address=192.168.64.9
      	hw_address=1,52:8a:1:2:3:4
      	lease=0x80000000
      }
      """
    let ip = SharedCompassVMGuestIPDiscovery.parseDHCPLeases(
      sample,
      forCanonicalMAC: "52:8a:01:02:03:04"
    )
    try #require(ip == "192.168.64.9")
  }

  @Test
  func testParseDHCPLeasesReturnsNilWhenMACDoesNotMatch() throws {
    let sample = """
      {
      	ip_address=192.168.64.4
      	hw_address=1,aa:bb:cc:dd:ee:ff
      	lease=0x65bb0001
      }
      """
    let ip = SharedCompassVMGuestIPDiscovery.parseDHCPLeases(
      sample,
      forCanonicalMAC: "52:8a:01:02:03:04"
    )
    try #require(ip == nil)
  }

  @Test
  func testParseDHCPLeasesReturnsNilOnEmptyInput() throws {
    try #require(
      SharedCompassVMGuestIPDiscovery.parseDHCPLeases("", forCanonicalMAC: "52:8a:01:02:03:04")
        == nil
    )
  }

  // MARK: parseARPTable

  @Test
  func testParseARPTableReturnsIPForMatchingMAC() throws {
    let sample = """
      ? (192.168.64.1) at b8:27:eb:1:2:3 on bridge100 ifscope [bridge]
      ? (192.168.64.4) at 52:8a:1:2:3:4 on bridge100 ifscope [bridge]
      ? (192.168.64.255) at ff:ff:ff:ff:ff:ff on bridge100 ifscope [bridge]
      """
    let ip = SharedCompassVMGuestIPDiscovery.parseARPTable(
      sample,
      forCanonicalMAC: "52:8a:01:02:03:04"
    )
    try #require(ip == "192.168.64.4")
  }

  @Test
  func testParseARPTableReturnsNilWhenMACDoesNotAppear() throws {
    let sample = "? (192.168.64.1) at b8:27:eb:1:2:3 on bridge100 ifscope [bridge]"
    let ip = SharedCompassVMGuestIPDiscovery.parseARPTable(
      sample,
      forCanonicalMAC: "52:8a:01:02:03:04"
    )
    try #require(ip == nil)
  }

  @Test
  func testParseARPTableSkipsLinesWithoutParenthesizedIP() throws {
    let sample = """
      Bogus header line without any IP
      ? (192.168.64.4) at 52:8a:1:2:3:4 on bridge100 ifscope [bridge]
      """
    let ip = SharedCompassVMGuestIPDiscovery.parseARPTable(
      sample,
      forCanonicalMAC: "52:8a:01:02:03:04"
    )
    try #require(ip == "192.168.64.4")
  }

  // MARK: randomGuestMAC

  @Test
  func testRandomGuestMACIsCanonicalAndLocallyAdministeredUnicast() throws {
    for _ in 0..<32 {
      let mac = SharedCompassVMBundle.randomGuestMAC()
      try #require(
        SharedCompassVMGuestIPDiscovery.canonicalize(mac: mac) == mac,
        "randomGuestMAC should already be canonical"
      )
      let firstOctetHex = String(mac.prefix(2))
      let firstOctet = UInt8(firstOctetHex, radix: 16) ?? 0
      try #require(firstOctet & 0b0000_0010 == 0b0000_0010, "expected locally-administered bit set")
      try #require(firstOctet & 0b0000_0001 == 0, "expected unicast bit clear")
    }
  }
}

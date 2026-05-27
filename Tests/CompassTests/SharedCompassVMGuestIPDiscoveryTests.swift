import Foundation
import Testing

@testable import Compass

struct SharedCompassVMGuestIPDiscoveryTests {
  // MARK: canonicalize

  @Test
  func testCanonicalizeFullyExpandedMACReturnsLowercaseColonForm() {
    #require(
      SharedCompassVMGuestIPDiscovery.canonicalize(mac: "52:8A:01:02:03:04") ==
      "52:8a:01:02:03:04"
    )
  }

  @Test
  func testCanonicalizePadsSingleHexDigitOctets() {
    #require(
      SharedCompassVMGuestIPDiscovery.canonicalize(mac: "52:8a:1:2:3:4") ==
      "52:8a:01:02:03:04"
    )
  }

  @Test
  func testCanonicalizeStripsDHCPLeasesPrefix() {
    #require(
      SharedCompassVMGuestIPDiscovery.canonicalize(mac: "1,52:8a:1:2:3:4") ==
      "52:8a:01:02:03:04"
    )
  }

  @Test
  func testCanonicalizeAcceptsDashSeparator() {
    #require(
      SharedCompassVMGuestIPDiscovery.canonicalize(mac: "52-8a-01-02-03-04") ==
      "52:8a:01:02:03:04"
    )
  }

  @Test
  func testCanonicalizeRejectsTooFewOctets() {
    #require(
      SharedCompassVMGuestIPDiscovery.canonicalize(mac: "52:8a:01:02:03") ==
      ""
    )
  }

  @Test
  func testCanonicalizeRejectsNonHexCharacters() {
    #require(
      SharedCompassVMGuestIPDiscovery.canonicalize(mac: "52:8a:0g:02:03:04") ==
      ""
    )
  }

  @Test
  func testCanonicalizeRejectsOctetsWithMoreThanTwoDigits() {
    #require(
      SharedCompassVMGuestIPDiscovery.canonicalize(mac: "52:8a:001:02:03:04") ==
      ""
    )
  }

  // MARK: parseDHCPLeases

  @Test
  func testParseDHCPLeasesReturnsMatchingIP() {
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
    #require(ip == "192.168.64.4")
  }

  @Test
  func testParseDHCPLeasesPicksNewestLeaseAmongMultipleEntriesForSameMAC() {
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
    #require(ip == "192.168.64.9")
  }

  @Test
  func testParseDHCPLeasesReturnsNilWhenMACDoesNotMatch() {
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
    #require(ip == nil)
  }

  @Test
  func testParseDHCPLeasesReturnsNilOnEmptyInput() {
    #require(
      SharedCompassVMGuestIPDiscovery.parseDHCPLeases("", forCanonicalMAC: "52:8a:01:02:03:04")
      == nil
    )
  }

  // MARK: parseARPTable

  @Test
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
    #require(ip == "192.168.64.4")
  }

  @Test
  func testParseARPTableReturnsNilWhenMACDoesNotAppear() {
    let sample = "? (192.168.64.1) at b8:27:eb:1:2:3 on bridge100 ifscope [bridge]"
    let ip = SharedCompassVMGuestIPDiscovery.parseARPTable(
      sample,
      forCanonicalMAC: "52:8a:01:02:03:04"
    )
    #require(ip == nil)
  }

  @Test
  func testParseARPTableSkipsLinesWithoutParenthesizedIP() {
    let sample = """
      Bogus header line without any IP
      ? (192.168.64.4) at 52:8a:1:2:3:4 on bridge100 ifscope [bridge]
      """
    let ip = SharedCompassVMGuestIPDiscovery.parseARPTable(
      sample,
      forCanonicalMAC: "52:8a:01:02:03:04"
    )
    #require(ip == "192.168.64.4")
  }

  // MARK: randomGuestMAC

  @Test
  func testRandomGuestMACIsCanonicalAndLocallyAdministeredUnicast() {
    for _ in 0..<32 {
      let mac = SharedCompassVMBundle.randomGuestMAC()
      #require(
        SharedCompassVMGuestIPDiscovery.canonicalize(mac: mac) == mac,
        "randomGuestMAC should already be canonical"
      )
      let firstOctetHex = String(mac.prefix(2))
      let firstOctet = UInt8(firstOctetHex, radix: 16) ?? 0
      #require(firstOctet & 0b0000_0010 == 0b0000_0010, "expected locally-administered bit set")
      #require(firstOctet & 0b0000_0001 == 0, "expected unicast bit clear")
    }
  }
}
import XCTest

@testable import Compass

final class SharedCompassVMGuestCredentialTests: XCTestCase {
  // MARK: - In-memory storage fake

  private final class InMemoryStorage: SharedCompassVMGuestCredential.Storage {
    var storedPasswords: [String: String] = [:]
    var storeCallCount = 0
    var deleteCallCount = 0

    func store(password: String, account: String) throws {
      storedPasswords[account] = password
      storeCallCount += 1
    }

    func retrieve(account: String) throws -> String? {
      storedPasswords[account]
    }

    func delete(account: String) throws {
      storedPasswords.removeValue(forKey: account)
      deleteCallCount += 1
    }
  }

  // MARK: - Password generation

  func testGeneratePasswordReturnsRequestedLength() throws {
    let pw = try SharedCompassVMGuestCredential.generatePassword(length: 32)
    XCTAssertEqual(pw.count, 32)
  }

  func testGeneratePasswordDrawsOnlyFromAlphanumericAlphabet() throws {
    let pw = try SharedCompassVMGuestCredential.generatePassword(length: 256)
    let alphabet = Set(SharedCompassVMGuestCredential.passwordAlphabet)
    for character in pw {
      XCTAssertTrue(
        alphabet.contains(character), "unexpected character '\(character)' in generated password")
    }
  }

  func testGeneratePasswordReturnsDifferentValuesAcrossCalls() throws {
    var seen = Set<String>()
    for _ in 0..<8 {
      seen.insert(try SharedCompassVMGuestCredential.generatePassword(length: 32))
    }
    // 8 random 32-char passwords colliding is statistically impossible.
    XCTAssertEqual(seen.count, 8)
  }

  // MARK: - Account allocation

  func testMakeAccountReturnsStableFormat() {
    let account = SharedCompassVMGuestCredential.makeAccount()
    XCTAssertTrue(account.hasPrefix("guest."))
    // UUID string is 36 chars; combined length is 6 + 36 = 42.
    XCTAssertEqual(account.count, 42)
  }

  func testMakeAccountReturnsFreshIdentifiers() {
    var seen = Set<String>()
    for _ in 0..<8 {
      seen.insert(SharedCompassVMGuestCredential.makeAccount())
    }
    XCTAssertEqual(seen.count, 8)
  }

  // MARK: - Ensure / retrieve / delete roundtrip

  func testEnsureGeneratesAndPersistsPasswordOnFirstCall() throws {
    let storage = InMemoryStorage()
    let account = SharedCompassVMGuestCredential.makeAccount()
    let credential = try SharedCompassVMGuestCredential.ensure(
      account: account,
      storage: storage
    )
    XCTAssertEqual(credential.account, account)
    XCTAssertEqual(credential.password.count, SharedCompassVMGuestCredential.defaultPasswordLength)
    XCTAssertEqual(storage.storedPasswords[account], credential.password)
    XCTAssertEqual(storage.storeCallCount, 1)
  }

  func testEnsureReturnsExistingPasswordWithoutReissuing() throws {
    let storage = InMemoryStorage()
    let account = SharedCompassVMGuestCredential.makeAccount()
    let first = try SharedCompassVMGuestCredential.ensure(account: account, storage: storage)
    let second = try SharedCompassVMGuestCredential.ensure(account: account, storage: storage)
    XCTAssertEqual(first.password, second.password)
    // Second call must NOT have triggered another store.
    XCTAssertEqual(storage.storeCallCount, 1)
  }

  func testRetrieveReturnsNilForUnknownAccount() throws {
    let storage = InMemoryStorage()
    let value = try SharedCompassVMGuestCredential.retrieve(
      account: "missing.account",
      storage: storage
    )
    XCTAssertNil(value)
  }

  func testRemoveDeletesStoredPasswordIdempotently() throws {
    let storage = InMemoryStorage()
    let account = SharedCompassVMGuestCredential.makeAccount()
    _ = try SharedCompassVMGuestCredential.ensure(account: account, storage: storage)
    try SharedCompassVMGuestCredential.remove(account: account, storage: storage)
    XCTAssertNil(storage.storedPasswords[account])
    // Remove on already-deleted account: still safe.
    try SharedCompassVMGuestCredential.remove(account: account, storage: storage)
    XCTAssertEqual(storage.deleteCallCount, 2)
  }

  // MARK: - Bundle state codable roundtrip

  func testBundleStateRoundTripsKeychainAccountField() throws {
    let account = SharedCompassVMGuestCredential.makeAccount()
    let state = SharedCompassVMBundle.State(
      provisionStep: .guestPrepping,
      guestPasswordKeychainAccount: account
    )
    let encoder = JSONEncoder()
    let decoder = JSONDecoder()
    let data = try encoder.encode(state)
    let decoded = try decoder.decode(SharedCompassVMBundle.State.self, from: data)
    XCTAssertEqual(decoded.guestPasswordKeychainAccount, account)
  }
}

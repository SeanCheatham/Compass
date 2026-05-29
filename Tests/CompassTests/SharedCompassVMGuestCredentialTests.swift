import Foundation
import Testing

@testable import Compass

struct SharedCompassVMGuestCredentialTests {
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

  @Test
  func testGeneratePasswordReturnsRequestedLength() throws {
    let pw = try SharedCompassVMGuestCredential.generatePassword(length: 32)
    try #require(pw.count == 32)
  }

  @Test
  func testGeneratePasswordDrawsOnlyFromAlphanumericAlphabet() throws {
    let pw = try SharedCompassVMGuestCredential.generatePassword(length: 256)
    let alphabet = Set(SharedCompassVMGuestCredential.passwordAlphabet)
    for character in pw {
      try #require(
        alphabet.contains(character), "unexpected character '\(character)' in generated password")
    }
  }

  @Test
  func testGeneratePasswordReturnsDifferentValuesAcrossCalls() throws {
    var seen = Set<String>()
    for _ in 0..<8 {
      seen.insert(try SharedCompassVMGuestCredential.generatePassword(length: 32))
    }
    // 8 random 32-char passwords colliding is statistically impossible.
    try #require(seen.count == 8)
  }

  // MARK: - Account allocation

  @Test
  func testMakeAccountReturnsStableFormat() throws {
    let account = SharedCompassVMGuestCredential.makeAccount()
    try #require(account.hasPrefix("guest."))
    // UUID string is 36 chars; combined length is 6 + 36 = 42.
    try #require(account.count == 42)
  }

  @Test
  func testMakeAccountReturnsFreshIdentifiers() throws {
    var seen = Set<String>()
    for _ in 0..<8 {
      seen.insert(SharedCompassVMGuestCredential.makeAccount())
    }
    try #require(seen.count == 8)
  }

  // MARK: - Ensure / retrieve / delete roundtrip

  @Test
  func testEnsureGeneratesAndPersistsPasswordOnFirstCall() throws {
    let storage = InMemoryStorage()
    let account = SharedCompassVMGuestCredential.makeAccount()
    let credential = try SharedCompassVMGuestCredential.ensure(
      account: account,
      storage: storage
    )
    try #require(credential.account == account)
    try #require(credential.password.count == SharedCompassVMGuestCredential.defaultPasswordLength)
    try #require(storage.storedPasswords[account] == credential.password)
    try #require(storage.storeCallCount == 1)
  }

  @Test
  func testEnsureReturnsExistingPasswordWithoutReissuing() throws {
    let storage = InMemoryStorage()
    let account = SharedCompassVMGuestCredential.makeAccount()
    let first = try SharedCompassVMGuestCredential.ensure(account: account, storage: storage)
    let second = try SharedCompassVMGuestCredential.ensure(account: account, storage: storage)
    try #require(first.password == second.password)
    // Second call must NOT have triggered another store.
    try #require(storage.storeCallCount == 1)
  }

  @Test
  func testRetrieveReturnsNilForUnknownAccount() throws {
    let storage = InMemoryStorage()
    let value = try SharedCompassVMGuestCredential.retrieve(
      account: "missing.account",
      storage: storage
    )
    try #require(value == nil)
  }

  @Test
  func testConsoleLoginReturnsNilWithoutKeychainAccount() throws {
    let storage = InMemoryStorage()
    let login = try SharedCompassVMGuestCredential.consoleLogin(
      guestUserName: "compass",
      keychainAccount: nil,
      storage: storage
    )
    try #require(login == nil)
  }

  @Test
  func testConsoleLoginReturnsUsernameAndPasswordWhenStored() throws {
    let storage = InMemoryStorage()
    let account = SharedCompassVMGuestCredential.makeAccount()
    _ = try SharedCompassVMGuestCredential.ensure(account: account, storage: storage)
    let login = try SharedCompassVMGuestCredential.consoleLogin(
      guestUserName: "compass",
      keychainAccount: account,
      storage: storage
    )
    try #require(login?.userName == "compass")
    try #require(login?.password.count == SharedCompassVMGuestCredential.defaultPasswordLength)
  }

  @Test
  func testRemoveDeletesStoredPasswordIdempotently() throws {
    let storage = InMemoryStorage()
    let account = SharedCompassVMGuestCredential.makeAccount()
    _ = try SharedCompassVMGuestCredential.ensure(account: account, storage: storage)
    try SharedCompassVMGuestCredential.remove(account: account, storage: storage)
    try #require(storage.storedPasswords[account] == nil)
    // Remove on already-deleted account: still safe.
    try SharedCompassVMGuestCredential.remove(account: account, storage: storage)
    try #require(storage.deleteCallCount == 2)
  }

  // MARK: - Bundle state codable roundtrip

  @Test
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
    try #require(decoded.guestPasswordKeychainAccount == account)
  }
}
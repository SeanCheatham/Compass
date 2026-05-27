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
    #require(pw.count == 32)
  }

  @Test
  func testGeneratePasswordDrawsOnlyFromAlphanumericAlphabet() throws {
    let pw = try SharedCompassVMGuestCredential.generatePassword(length: 256)
    let alphabet = Set(SharedCompassVMGuestCredential.passwordAlphabet)
    for character in pw {
      #require(
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
    #require(seen.count == 8)
  }

  // MARK: - Account allocation

  @Test
  func testMakeAccountReturnsStableFormat() {
    let account = SharedCompassVMGuestCredential.makeAccount()
    #require(account.hasPrefix("guest."))
    // UUID string is 36 chars; combined length is 6 + 36 = 42.
    #require(account.count == 42)
  }

  @Test
  func testMakeAccountReturnsFreshIdentifiers() {
    var seen = Set<String>()
    for _ in 0..<8 {
      seen.insert(SharedCompassVMGuestCredential.makeAccount())
    }
    #require(seen.count == 8)
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
    #require(credential.account == account)
    #require(credential.password.count == SharedCompassVMGuestCredential.defaultPasswordLength)
    #require(storage.storedPasswords[account] == credential.password)
    #require(storage.storeCallCount == 1)
  }

  @Test
  func testEnsureReturnsExistingPasswordWithoutReissuing() throws {
    let storage = InMemoryStorage()
    let account = SharedCompassVMGuestCredential.makeAccount()
    let first = try SharedCompassVMGuestCredential.ensure(account: account, storage: storage)
    let second = try SharedCompassVMGuestCredential.ensure(account: account, storage: storage)
    #require(first.password == second.password)
    // Second call must NOT have triggered another store.
    #require(storage.storeCallCount == 1)
  }

  @Test
  func testRetrieveReturnsNilForUnknownAccount() throws {
    let storage = InMemoryStorage()
    let value = try SharedCompassVMGuestCredential.retrieve(
      account: "missing.account",
      storage: storage
    )
    #require(value == nil)
  }

  @Test
  func testConsoleLoginReturnsNilWithoutKeychainAccount() throws {
    let storage = InMemoryStorage()
    let login = try SharedCompassVMGuestCredential.consoleLogin(
      guestUserName: "compass",
      keychainAccount: nil,
      storage: storage
    )
    #require(login == nil)
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
    #require(login?.userName == "compass")
    #require(login?.password.count == SharedCompassVMGuestCredential.defaultPasswordLength)
  }

  @Test
  func testRemoveDeletesStoredPasswordIdempotently() throws {
    let storage = InMemoryStorage()
    let account = SharedCompassVMGuestCredential.makeAccount()
    _ = try SharedCompassVMGuestCredential.ensure(account: account, storage: storage)
    try SharedCompassVMGuestCredential.remove(account: account, storage: storage)
    #require(storage.storedPasswords[account] == nil)
    // Remove on already-deleted account: still safe.
    try SharedCompassVMGuestCredential.remove(account: account, storage: storage)
    #require(storage.deleteCallCount == 2)
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
    #require(decoded.guestPasswordKeychainAccount == account)
  }
}
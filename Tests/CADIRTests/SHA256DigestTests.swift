import Foundation
import Testing
@testable import CADIR
#if canImport(CryptoKit)
import CryptoKit
#endif

@Suite("SHA-256 digest")
struct SHA256DigestTests {
    @Test(.timeLimit(.minutes(1)))
    func publishedVectorsMatch() {
        #expect(SHA256Digest.hexDigest(for: Data())
            == "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855")
        #expect(SHA256Digest.hexDigest(for: Data("abc".utf8))
            == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
        #expect(SHA256Digest.hexDigest(for: Data("abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq".utf8))
            == "248d6a61d20638b8e5c026930c3e6039a33ce45964ff2167f6ecedd419db06c1")
        #expect(SHA256Digest.hexDigest(for: Data(("abcdefghbcdefghicdefghijdefghijkefghijklfghijklmghijklmn"
            + "hijklmnoijklmnopjklmnopqklmnopqrlmnopqrsmnopqrstnopqrstu").utf8))
            == "cf5b16a778af8380036ce59e7b0492370b249b11e8f07a51afac45037afee9d1")
        #expect(SHA256Digest.hexDigest(for: Data(repeating: UInt8(ascii: "a"), count: 1_000_000))
            == "cdc76e5c9914fb9281a1c7e284d73e67f1809a48a497200e046d39ccc7112cd0")
    }

    #if canImport(CryptoKit)
    /// Every length across the one- and two-block padding boundaries, and a long message read in
    /// place, agree with the platform implementation.
    @Test(.timeLimit(.minutes(1)))
    func everyPaddingBoundaryMatchesThePlatformDigest() {
        var generator = SystemRandomNumberGenerator()
        for length in Array(0...300) + [4_095, 4_096, 65_537] {
            let data = Data((0..<length).map { _ in UInt8.random(in: .min ... .max, using: &generator) })
            let expected = CryptoKit.SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
            #expect(SHA256Digest.hexDigest(for: data) == expected, "length \(length)")
        }
    }
    #endif
}

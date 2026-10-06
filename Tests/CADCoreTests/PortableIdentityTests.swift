import Foundation
import Testing
@testable import CADCore

@Suite("Portable identity")
struct PortableIdentityTests {
    @Test(.timeLimit(.minutes(1)))
    func canonicalTextPreservesCurrentUUIDByteOrder() throws {
        let identity = try PortableIdentity128(canonicalString: "00112233-4455-6677-8899-AABBCCDDEEFF")

        #expect(identity.high == 0x0011_2233_4455_6677)
        #expect(identity.low == 0x8899_AABB_CCDD_EEFF)
        #expect(identity.canonicalString == "00112233-4455-6677-8899-AABBCCDDEEFF")
        #expect(try PortableIdentity128(canonicalString: identity.canonicalString) == identity)
        #expect(try PortableIdentity128(canonicalString: identity.canonicalString.lowercased()) == identity)
    }

    @Test(.timeLimit(.minutes(1)))
    func malformedCanonicalTextFailsTyped() {
        for value in [
            "001122334455-6677-8899-AABBCCDDEEFF",
            "00112233-4455-6677-8899-AABBCCDDEEF",
            "00112233-4455-6677-8899-AABBCCDDEEFF!",
            "00112233-4455-6677-8899-AABBCCDDEEGG"
        ] {
            #expect(throws: PortableIdentityError.self) {
                _ = try PortableIdentity128(canonicalString: value)
            }
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func randomIdentityUsesRFC4122VersionAndVariant() {
        let first = PortableIdentity128()
        let second = PortableIdentity128()

        #expect((first.high >> 12) & 0xF == 4)
        #expect((first.low >> 62) == 2)
        #expect((second.high >> 12) & 0xF == 4)
        #expect((second.low >> 62) == 2)
        #expect(first != second)
    }

    @Test(.timeLimit(.minutes(1)))
    func taggedIDPreservesBitPatternAndNativeCodableText() throws {
        let identity = PortableIdentity128(high: 0x0011_2233_4455_6677, low: 0x8899_AABB_CCDD_EEFF)
        let id = FeatureID(identity)

        #expect(id.bitPattern.high == identity.high)
        #expect(id.bitPattern.low == identity.low)
        #expect(id.rawValue == identity)
        #expect(id.description == identity.canonicalString)

        let data = try JSONEncoder().encode(id)
        let decoded = try JSONDecoder().decode(FeatureID.self, from: data)
        #expect(decoded == id)
    }
}

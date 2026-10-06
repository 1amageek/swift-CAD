import Foundation
import Testing
import Synchronization
import CADCore
import CADGeometry
@testable import CADIR

@Suite("Original STEP Native identity codecs")
struct OriginalSTEPIdentityCodecTests {
    private let identity = PortableIdentity128(high: 0x0123456789ABCDEF, low: 0xFEDCBA9876543210)

    @available(macOS 15.0, iOS 18.0, visionOS 2.0, watchOS 11.0, tvOS 18.0, *)
    private func decoder(work: Int = 1000, storage: Int = 1000, depth: Int = 32,
        check: @escaping @Sendable () throws -> Void = {}) throws -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.userInfo[NativeRationalSourceDecodingContext.key] = try NativeRationalSourceAllowance(
            maximumWork: work, maximumCells: 100, maximumStorage: storage,
            maximumDepth: 0, operationCheck: check)
        decoder.userInfo[OriginalAffineWordDecodingContext.maximumSourceDepthKey] = depth
        return decoder
    }

    private func line() -> OriginalSTEPLineSource {
        let length = OriginalSTEPLengthSource(id: identity, law: .conversion(.init(
            name: "original inch", dimensionsID: .init(high: 1, low: 2),
            dimensions: ["1", "0", "0", "0", "0", "0", "0"],
            measureID: .init(high: 3, low: 4), measureKind: .lengthMeasureWithUnit,
            factorLiteral: "2.5400E-2", base: .init(id: .init(high: 5, low: 6), law: .metre(prefix: nil)))))
        return .init(location: .init(id: identity, name: "point", coordinates: .init(x: 2, y: 3, z: 4)),
            direction: .init(id: .init(high: 7, low: 8), name: "direction", coordinates: .unitX),
            vectorID: identity, vectorName: "vector", magnitude: 2, lengthUnit: .inch,
            originalLengthSource: length)
    }

    @Test(.timeLimit(.minutes(1)))
    @available(macOS 15.0, iOS 18.0, visionOS 2.0, watchOS 11.0, tvOS 18.0, *)
    func admitsParserCapacityBeforeAllocationAndChecksFinalCancellation() throws {
        let data = try JSONEncoder().encode(identity.canonicalString)
        let exact = try decoder(work: 125, storage: 13)
        #expect(try exact.decode(NativeIdentityProbe.self, from: data).identity == identity)
        let allowance = try #require(exact.userInfo[NativeRationalSourceDecodingContext.key] as? NativeRationalSourceAllowance)
        let receipt = try allowance.snapshot()
        #expect(receipt.work == 125 && receipt.storage == 13)

        // A valid-length malformed identity would fail in Core unless storage wins first.
        let malformed = try JSONEncoder().encode("01234567-89AB-CDEF-FEDC-BA987654321Z")
        #expect { _ = try decoder(storage: 12).decode(NativeIdentityProbe.self, from: malformed) }
        throws: { ($0 as? KernelError)?.code == .resourceLimitExceeded }
        #expect { _ = try decoder(work: 124, storage: 13).decode(NativeIdentityProbe.self, from: data) }
        throws: { ($0 as? KernelError)?.code == .resourceLimitExceeded }

        // Exercise the production record decoder, with no capacity for its identity parser.
        let element = OriginalSTEPPlacementElement(id: identity, name: "point", coordinates: .unitX)
        #expect { _ = try decoder(storage: 12).decode(OriginalSTEPPlacementElement.self,
            from: JSONEncoder().encode(element)) }
        throws: { ($0 as? KernelError)?.code == .resourceLimitExceeded }

        let calls = Mutex(0)
        let cancelled = try decoder(storage: 13, check: {
            let final = calls.withLock { count in count += 1; return count == 4 }
            if final { throw CancellationError() }
        })
        #expect(throws: CancellationError.self) { _ = try cancelled.decode(NativeIdentityProbe.self, from: data) }
        #expect(calls.withLock { $0 } == 4)
    }

    @Test(.timeLimit(.minutes(1)))
    @available(macOS 15.0, iOS 18.0, visionOS 2.0, watchOS 11.0, tvOS 18.0, *)
    func oversizedTextRefusesBeforeParserStorage() throws {
        let bounded = try decoder(work: 37, storage: 0)
        let data = try JSONEncoder().encode(identity.canonicalString + String(repeating: "0", count: 4096))
        #expect(throws: DecodingError.self) { _ = try bounded.decode(NativeIdentityProbe.self, from: data) }
        let allowance = try #require(bounded.userInfo[NativeRationalSourceDecodingContext.key] as? NativeRationalSourceAllowance)
        let receipt = try allowance.snapshot()
        #expect(receipt.work == 37 && receipt.storage == 0)
    }

    @Test(.timeLimit(.minutes(1)))
    @available(macOS 15.0, iOS 18.0, visionOS 2.0, watchOS 11.0, tvOS 18.0, *)
    func preservesCanonicalTextBitsAndCompleteLengthChain() throws {
        let source = line()
        let data = try JSONEncoder().encode(source)
        let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(object["vectorID"] as? String == "01234567-89AB-CDEF-FEDC-BA9876543210")
        let restored = try decoder().decode(OriginalSTEPLineSource.self, from: data)
        #expect(restored == source)
        #expect(restored.vectorID.high == identity.high && restored.vectorID.low == identity.low)
        let length = try #require(restored.originalLengthSource)
        guard case .conversion(let conversion) = length.law else { Issue.record("Expected original conversion."); return }
        #expect(conversion.factorLiteral == "2.5400E-2")
        #expect(conversion.dimensionsID == PortableIdentity128(high: 1, low: 2))
        #expect(conversion.measureID == PortableIdentity128(high: 3, low: 4))
        var lower = object
        lower["vectorID"] = identity.canonicalString.lowercased()
        #expect(try decoder().decode(OriginalSTEPLineSource.self,
            from: JSONSerialization.data(withJSONObject: lower)) == source)
    }

    @Test(.timeLimit(.minutes(1)))
    @available(macOS 15.0, iOS 18.0, visionOS 2.0, watchOS 11.0, tvOS 18.0, *)
    func rejectsMalformedUnknownAndUnadmittedRecords() throws {
        let data = try JSONEncoder().encode(line())
        let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        for text in ["0123456789ABCDEF-FEDC-BA9876543210", "01234567-89AB-CDEF-FEDC-BA987654321Z"] {
            var bad = object; bad["vectorID"] = text
            let bytes = try JSONSerialization.data(withJSONObject: bad)
            #expect(throws: DecodingError.self) { _ = try decoder().decode(OriginalSTEPLineSource.self, from: bytes) }
        }
        var bad = object; bad["proxyIdentity"] = identity.canonicalString
        #expect(throws: DecodingError.self) {
            _ = try decoder().decode(OriginalSTEPLineSource.self, from: JSONSerialization.data(withJSONObject: bad))
        }
        #expect(throws: NativeRationalSourceDecodingError.missingCallerAllowance) {
            let unadmitted = JSONDecoder()
            unadmitted.userInfo[OriginalAffineWordDecodingContext.maximumSourceDepthKey] = 32
            _ = try unadmitted.decode(OriginalSTEPLineSource.self, from: data)
        }
        for limits in [(0, 1000), (1000, 0)] {
            #expect { _ = try decoder(work: limits.0, storage: limits.1).decode(OriginalSTEPLineSource.self, from: data) }
            throws: { ($0 as? KernelError)?.code == .resourceLimitExceeded }
        }
        #expect(throws: DecodingError.self) { _ = try decoder(depth: 1).decode(OriginalSTEPLineSource.self, from: data) }
        #expect(throws: CancellationError.self) {
            _ = try decoder(check: { throw CancellationError() }).decode(OriginalSTEPLineSource.self, from: data)
        }
    }
}

private struct NativeIdentityProbe: Decodable {
    let identity: PortableIdentity128
    init(from decoder: Decoder) throws {
        identity = try OriginalSTEPIdentityCoding.decode(from: decoder)
    }
}

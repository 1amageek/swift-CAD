import CADCore
import Testing
@testable import CADIR

@Suite("Tessellation limits")
struct TessellationLimitsTests {
    private static func resource(
        of error: any Error
    ) -> (TessellationResource, Int)? {
        guard let tessellationError = error as? TessellationError else { return nil }
        switch tessellationError {
        case let .invalidLimit(resource, requested):
            return (resource, requested)
        default:
            return nil
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func packageLimitsValidate() throws {
        try TessellationLimits.hardCeiling.validate()
        try TessellationLimits.standard.validate()
    }

    @Test(.timeLimit(.minutes(1)))
    func theStandardLimitsAreAdmittedByTheHardCeiling() {
        let ceiling = TessellationLimits.hardCeiling
        let standard = TessellationLimits.standard
        #expect(standard.maximumVertexCount <= ceiling.maximumVertexCount)
        #expect(standard.maximumIndexCount <= ceiling.maximumIndexCount)
        #expect(standard.maximumTriangleCount <= ceiling.maximumTriangleCount)
        #expect(standard.maximumByteCount <= ceiling.maximumByteCount)
    }

    @Test(.timeLimit(.minutes(1)))
    func loweredLimitsValidate() throws {
        var limits = TessellationLimits.standard
        limits.maximumVertexCount = 1
        limits.maximumIndexCount = 3
        limits.maximumTriangleCount = 1
        limits.maximumByteCount = 64
        try limits.validate()
    }

    @Test(
        "A non-positive limit is rejected on the dimension it names",
        .timeLimit(.minutes(1)),
        arguments: [0, -1, Int.min]
    )
    func nonPositiveLimitsAreRejected(value: Int) throws {
        var vertexLimits = TessellationLimits.standard
        vertexLimits.maximumVertexCount = value
        var indexLimits = TessellationLimits.standard
        indexLimits.maximumIndexCount = value
        var triangleLimits = TessellationLimits.standard
        triangleLimits.maximumTriangleCount = value
        var byteLimits = TessellationLimits.standard
        byteLimits.maximumByteCount = value

        let cases: [(TessellationLimits, TessellationResource)] = [
            (vertexLimits, .vertexCount),
            (indexLimits, .indexCount),
            (triangleLimits, .triangleCount),
            (byteLimits, .byteCount)
        ]
        for (limits, expected) in cases {
            do {
                try limits.validate()
                Issue.record("Expected \(expected) to be rejected for \(value).")
            } catch {
                let reported = try #require(Self.resource(of: error))
                #expect(reported.0 == expected)
                #expect(reported.1 == value)
            }
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func aLimitThatWidensTheHardCeilingIsRejected() throws {
        let ceiling = TessellationLimits.hardCeiling
        var vertexLimits = ceiling
        vertexLimits.maximumVertexCount += 1
        var indexLimits = ceiling
        indexLimits.maximumIndexCount += 1
        var triangleLimits = ceiling
        triangleLimits.maximumTriangleCount += 1
        var byteLimits = ceiling
        byteLimits.maximumByteCount += 1

        let cases: [(TessellationLimits, TessellationResource)] = [
            (vertexLimits, .vertexCount),
            (indexLimits, .indexCount),
            (triangleLimits, .triangleCount),
            (byteLimits, .byteCount)
        ]
        for (limits, expected) in cases {
            do {
                try limits.validate()
                Issue.record("Expected a widened \(expected) to be rejected.")
            } catch {
                let reported = try #require(Self.resource(of: error))
                #expect(reported.0 == expected)
            }
        }
    }

    /// The limits are `Int`, so a nonfinite or unrepresentable value cannot be
    /// expressed. The extreme representable value is still refused because it
    /// widens the hard ceiling.
    @Test(.timeLimit(.minutes(1)))
    func theLargestRepresentableLimitIsRejected() throws {
        var limits = TessellationLimits.standard
        limits.maximumByteCount = Int.max

        do {
            try limits.validate()
            Issue.record("Expected the largest representable byte limit to be rejected.")
        } catch {
            let reported = try #require(Self.resource(of: error))
            #expect(reported.0 == .byteCount)
            #expect(reported.1 == Int.max)
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func loweringTakesTheSmallerOfEachDimension() {
        let coarse = TessellationLimits(
            maximumVertexCount: 100,
            maximumIndexCount: 900,
            maximumTriangleCount: 300,
            maximumByteCount: 8_000
        )
        let fine = TessellationLimits(
            maximumVertexCount: 200,
            maximumIndexCount: 300,
            maximumTriangleCount: 100,
            maximumByteCount: 16_000
        )

        let lowered = coarse.lowered(to: fine)

        #expect(lowered.maximumVertexCount == 100)
        #expect(lowered.maximumIndexCount == 300)
        #expect(lowered.maximumTriangleCount == 100)
        #expect(lowered.maximumByteCount == 8_000)
        #expect(lowered == fine.lowered(to: coarse))
    }

    @Test(.timeLimit(.minutes(1)))
    func loweringNeverWidensEitherOperand() {
        let standard = TessellationLimits.standard
        let ceiling = TessellationLimits.hardCeiling

        let lowered = standard.lowered(to: ceiling)

        #expect(lowered.maximumVertexCount <= standard.maximumVertexCount)
        #expect(lowered.maximumIndexCount <= standard.maximumIndexCount)
        #expect(lowered.maximumTriangleCount <= standard.maximumTriangleCount)
        #expect(lowered.maximumByteCount <= standard.maximumByteCount)
        #expect(lowered == standard)
    }
}

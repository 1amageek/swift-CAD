import CADCore
@testable import CADGeometry
import Testing

@Suite("Original homogeneous graph inverse brackets")
struct OriginalGraphBandInverseTests {
    private let tolerance = ModelingTolerance.standard

    @Test(.timeLimit(.minutes(1)), arguments: [2, 4], [false, true])
    func originalAffineCoordinatesRetainClosedInverseWithBoundedWork(
        degree: Int, reversed: Bool
    ) throws {
        let points = (0...degree).map { index in
            let x = Double(index) / Double(degree)
            return Point2D(x: reversed ? 1 - x : x, y: x * x)
        }
        for weight in [1.0, 7.0] {
            let source = try piece(points: points, weights: Array(repeating: weight, count: points.count))
            var usage = OriginalTessellationProofUsage()
            let inverse = try source.inverse(u: 0.317, tolerance: tolerance, proofUsage: &usage)
            let expected = reversed ? 1 - 0.317 : 0.317
            #expect(inverse.contains(expected))
            #expect(inverse.upper - inverse.lower < 1e-12)
            #expect(usage.usedCellCount <= 4)
            #expect(source.points == points)
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func varyingWeightsKeepOriginalNonaffineInverseAuthority() throws {
        let points = [Point2D(x: 0, y: 0), Point2D(x: 0.5, y: 0.25), Point2D(x: 1, y: 1)]
        let source = try piece(points: points, weights: [1, 2, 1])
        var usage = OriginalTessellationProofUsage()
        let inverse = try source.inverse(u: 0.5, tolerance: tolerance, proofUsage: &usage)
        // The original unequal-weight law is U(t)=(2t-t^2)/(1+2t-2t^2).
        // Its unique inverse at U=1/2 is exactly t=1/2.
        #expect(inverse.contains(0.5))
        #expect(inverse.upper - inverse.lower < 1e-12)
        #expect(source.endpointAffineResidualUpperBound > 0.1)
        #expect(usage.usedCellCount > 0)
    }

    @Test(.timeLimit(.minutes(1)))
    func oneULPOriginalDeviationIsNeverDeclaredExactlyAffine() throws {
        let middle = 0.5.nextUp
        let source = try piece(points: [Point2D(x: 0, y: 0), Point2D(x: middle, y: 0),
                                       Point2D(x: 1, y: 0)], weights: [1, 1, 1])
        var usage = OriginalTessellationProofUsage()
        let inverse = try source.inverse(u: 0.5, tolerance: tolerance, proofUsage: &usage)
        // U(t)=t+2*(middle-1/2)*t*(1-t); its t at U=1/2 is strictly below 1/2.
        #expect(source.endpointAffineResidualUpperBound >= (middle - 0.5) * 0.5)
        #expect(inverse.lower <= 0.5.nextDown)
        #expect(inverse.upper >= 0.5.nextDown)
        #expect(inverse.lower < inverse.upper)
    }

    @Test(.timeLimit(.minutes(1)))
    func exhaustedOriginalUsageRefusesBothEndpointAndInteriorInverses() throws {
        let source = try piece(points: [Point2D(x: 0, y: 0), Point2D(x: 1, y: 1)], weights: [1, 1])
        var usage = try OriginalTessellationProofUsage(maximumCellCount: 1, tolerance: tolerance)
        try usage.consume(depth: 0, tolerance: tolerance)
        for u in [0.0, 0.5, 1.0] {
            do {
                _ = try source.inverse(u: u, tolerance: tolerance, proofUsage: &usage)
                Issue.record("Exhausted original inverse work must refuse.")
            } catch let error as KernelError {
                #expect(error.code == .resourceLimitExceeded)
            }
        }
        #expect(usage.usedCellCount == 1)
    }

    @Test(.timeLimit(.minutes(1)))
    func cancellationRefusesAnOtherwiseValidOriginalInverse() async throws {
        let source = try piece(points: [Point2D(x: 0, y: 0), Point2D(x: 1, y: 1)], weights: [1, 1])
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            var usage = OriginalTessellationProofUsage()
            return try source.inverse(u: 0.5, tolerance: tolerance, proofUsage: &usage)
        }
        do {
            _ = try await task.value
            Issue.record("Cancelled original inverse work must refuse.")
        } catch is CancellationError {
            // The original invocation cancellation contract propagates unchanged.
        }
    }

    private func piece(points: [Point2D], weights: [Double]) throws -> OriginalGraphBandRationalPiece {
        try OriginalGraphBandRationalPiece(boundaryIndex: 0, nativeIndex: 0,
            nativeParameters: ScalarInterval(lower: 0, upper: 1), points: points,
            weights: weights, tolerance: tolerance)
    }
}

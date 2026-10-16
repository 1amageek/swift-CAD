import CADCore
import CADGeometry
import Foundation
import Testing
@testable import CADKernel

@Suite("Kernel original intersection compile prerequisites")
struct KernelIntersectionPrerequisiteTests {
    private func authoredOptions() -> SurfaceSurfaceIntersectionOptions {
        .init(maximumSubdivisionDepth: 3, maximumSubdivisionCells: 97, maximumIterations: 7,
            maximumSeedCount: 11, maximumContinuationPointCount: 101,
            maximumContinuationPointCountPerComponent: 29, maximumRootAttempts: 31,
            maximumBoundarySubdivisionDepth: 5, maximumBoundarySubdivisionCells: 103,
            maximumPeriodicSeamAttempts: 13, maximumResidualCertificationDepth: 9,
            maximumResidualCertificationCells: 107)
    }

    @Test(.timeLimit(.minutes(1)))
    func codecRetainsEverySelectedLimitAndOption() throws {
        let source = OffsetFeasibilityLimits(maximumCumulativeWork: 109,
            maximumCumulativeStorageBytes: 113, surfaceIntersectionOptions: authoredOptions(),
            remainingSourceDepth: 2, maximumAlgebraicDepth: 17)
        try source.validate(tolerance: .standard)
        let encoded = try JSONEncoder().encode(source)
        #expect(try JSONDecoder().decode(OffsetFeasibilityLimits.self, from: encoded) == source)
        let unselected = OffsetFeasibilityLimits(surfaceIntersectionOptions: authoredOptions(),
            remainingSourceDepth: 0, maximumAlgebraicDepth: 0)
        #expect(try JSONDecoder().decode(OffsetFeasibilityLimits.self,
            from: JSONEncoder().encode(unselected)) == unselected)
    }

    @Test(.timeLimit(.minutes(1)))
    func codecDoesNotReplaceMissingOrInvalidAuthoredFields() throws {
        let source = OffsetFeasibilityLimits(surfaceIntersectionOptions: authoredOptions())
        var object = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(source)) as? [String: Any])
        var options = try #require(object["surfaceIntersectionOptions"] as? [String: Any])
        options.removeValue(forKey: "maximumResidualCertificationCells")
        object["surfaceIntersectionOptions"] = options
        let incomplete = try JSONSerialization.data(withJSONObject: object)
        #expect(throws: DecodingError.self) { try JSONDecoder().decode(OffsetFeasibilityLimits.self, from: incomplete) }
        let invalid = OffsetFeasibilityLimits(maximumCumulativeWork: -1,
            surfaceIntersectionOptions: authoredOptions(), remainingSourceDepth: 17, maximumAlgebraicDepth: 33)
        let decoded = try JSONDecoder().decode(OffsetFeasibilityLimits.self, from: JSONEncoder().encode(invalid))
        #expect(decoded == invalid)
        #expect(throws: KernelError.self) { try decoded.validate(tolerance: .standard) }
    }

    private func owners() throws -> [PreparedBSplineSurfaceDifferentialEncloser.OriginalNativeSpan] {
        let source = BSplineSurface3D(uDegree: 1, vDegree: 1,
            uKnots: [-1, -1, 0, 1, 1], vKnots: [-1, -1, 1, 1],
            controlPoints: [[.init(x: -1, y: -1, z: 0), .init(x: 0, y: -1, z: 0), .init(x: 1, y: -1, z: 0)],
                [.init(x: -1, y: 1, z: 0), .init(x: 0, y: 1, z: 0), .init(x: 1, y: 1, z: 0)]])
        let prepared = try PreparedBSplineSurfaceDifferentialEncloser(surface: source, tolerance: .standard)
        return try prepared.originalNativeSpans(over: SurfaceParameterBox(
            u: .init(lower: -1, upper: 1), v: .init(lower: -1, upper: 1)), tolerance: .standard)
    }

    private func execution() throws -> OriginalQueryExecution {
        OriginalQueryExecution(budget: try .init(workLimit: 262_144,
            storageByteLimit: 268_435_456), limits: try .init(maximumValueDepth: 32,
                maximumCoefficientDepth: 32, remainingSourceDepth: 16,
                maximumSubdivisionDepth: 32))
    }

    private func partition(using execution: inout OriginalQueryExecution) throws -> TrimmedNativePartition.Result {
        let tiny = 1e-200
        return try TrimmedNativePartition().partition(parameters: [
            .init(u: -tiny, v: -tiny), .init(u: tiny, v: -tiny), .init(u: tiny, v: tiny)],
            triangles: [.init(first: 0, second: 1, third: 2)], spans: owners(), tolerance: .standard, using: &execution)
    }

    @Test(.timeLimit(.minutes(1)))
    func tinyNonzeroOriginalTrianglesRetainBothNativeOwners() throws {
        var budget = try execution()
        let result = try partition(using: &budget)
        #expect(result.triangles.count == 3)
        #expect(result.owners.count == result.triangles.count)
        #expect(Set(result.owners.map(\.uSpanIndex)) == Set([1, 2]))
        #expect(budget.availableWork < 262_144)
        for (triangle, owner) in zip(result.triangles, result.owners) {
            for index in [triangle.first, triangle.second, triangle.third] {
                #expect(owner.uBounds.lower <= result.parameters[index].u)
                #expect(owner.uBounds.upper >= result.parameters[index].u)
            }
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func partitionSharesItsOriginalWorkAndCoefficientByteCeiling() throws {
        var measurement = try execution()
        _ = try partition(using: &measurement)
        let cost = measurement.localWork
        #expect(cost > 0)
        var exact = try execution()
        try exact.consumeWork(262_144 - cost)
        _ = try partition(using: &exact)
        #expect(exact.availableWork == 0)
        var insufficient = try execution()
        try insufficient.consumeWork(262_144 - cost + 1)
        do {
            _ = try partition(using: &insufficient)
            Issue.record("Expected the shared work ceiling to reject partitioning.")
        } catch {
            let published = OriginalQueryFailure.published(error,
                context: insufficient.context, tolerance: .standard)
            #expect(OriginalQueryFailure.classification(of: published)?.code == .resourceLimitExceeded)
        }
        do {
            try insufficient.retainStorage(bytes: Int.max)
            Issue.record("Expected the shared coefficient byte ceiling to reject retention.")
        } catch {
            let published = OriginalQueryFailure.published(error,
                context: insufficient.context, tolerance: .standard)
            #expect(OriginalQueryFailure.classification(of: published)?.code == .resourceLimitExceeded)
        }
    }
}

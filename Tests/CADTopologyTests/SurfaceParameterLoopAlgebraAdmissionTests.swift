import CADCore
import CADGeometry
import Testing
@testable import CADTopology

@Suite("Loop chart algebra admission", .timeLimit(.minutes(1)))
struct SurfaceParameterLoopAlgebraAdmissionTests {
    private let tolerance = ModelingTolerance.standard
    private let surface = Surface3D.plane(Plane3D(origin: .origin, normal: .unitZ))

    private func curves() -> [SurfaceParameterCurve] {
        let points: [SurfaceParameter] = [
            .init(u: 0, v: 0), .init(u: 1, v: 0), .init(u: 1, v: 1), .init(u: 0, v: 1),
        ]
        return points.indices.map { .polyline([points[$0], points[($0 + 1) % points.count]]) }
    }

    private func execution(_ budget: OriginalQueryBudget, coefficientDepth: Int = 32)
        throws -> OriginalQueryExecution {
        OriginalQueryExecution(budget: budget,
            limits: try .init(maximumValueDepth: 32, maximumCoefficientDepth: coefficientDepth,
                remainingSourceDepth: 16, maximumSubdivisionDepth: 8))
    }

    private func isResource(_ error: any Error, _ expected: ExactResource) -> Bool {
        if let failure = error as? OriginalQueryFailure {
            return isResource(failure.originalError, expected)
        }
        if let failure = error as? ExactScalarFailure {
            switch failure {
            case .resourceLimit(let resource): return resource == expected
            case .admissionRejected(let cause): return isResource(cause, expected)
            default: return false
            }
        }
        return false
    }

    private func isCancellation(_ error: any Error) -> Bool {
        if let failure = error as? OriginalQueryFailure {
            return isCancellation(failure.originalError)
        }
        if let failure = error as? ExactScalarFailure {
            switch failure {
            case .cancelled: return true
            case .admissionRejected(let cause): return isCancellation(cause)
            default: return false
            }
        }
        return false
    }

    @Test func selectedCapPreservesTheAuthoredPolylineLoop() throws {
        let input = curves()
        let budget = try OriginalQueryBudget()
        var execution = try execution(budget)
        let result = try SurfaceParameterLoopUnwrapper().unwrap(input, on: surface,
            tolerance: tolerance, context: "Authored polyline square",
            maximumSubdivisionDepth: 8, remainingSourceDepth: 16,
            maximumAlgebraicDepth: 32, using: &execution)
        #expect(result.map(\.curve) == input)
        #expect(result.allSatisfy { $0.uShift == 0 && $0.vShift == 0 })
        for index in result.indices {
            let next = result[(index + 1) % result.count]
            #expect(abs(result[index].chartEnd.u - next.chartStart.u) <= tolerance.distance * 8)
            #expect(abs(result[index].chartEnd.v - next.chartStart.v) <= tolerance.distance * 8)
        }
        #expect(budget.snapshot.work == execution.localWork)
        #expect(budget.snapshot.work > 0 && budget.snapshot.storageBytes > 0)
    }

    @Test func omittedCapStillRefusesTheOriginalPolylineLaw() throws {
        var execution = try execution(OriginalQueryBudget())
        do {
            _ = try SurfaceParameterLoopUnwrapper().unwrap(curves(), on: surface,
                tolerance: tolerance, context: "Unselected polyline algebra",
                maximumSubdivisionDepth: 8, remainingSourceDepth: 16, using: &execution)
            Issue.record("An omitted algebra capability admitted original polyline bounds.")
        } catch let error as KernelError {
            #expect(error.phase == .geometry)
            #expect(error.code == .unsupportedCapability)
            #expect(error.message == "Original Euclidean polyline bounds require caller algebra admission.")
        }
    }

    @Test func selectedAndAmbientCoefficientDepthRemainIndependent() throws {
        // Unequal sqrt(2) and sqrt(5) lengths require the original coefficient field.
        let input: [SurfaceParameterCurve] = [
            .polyline([.init(u: 0, v: 0), .init(u: 1, v: 1), .init(u: 3, v: 2)]),
            .polyline([.init(u: 3, v: 2), .init(u: 0, v: 0)]),
        ]
        for (selectedDepth, ambientDepth) in [(0, 32), (32, 0)] {
            var execution = try execution(OriginalQueryBudget(), coefficientDepth: ambientDepth)
            do {
                _ = try SurfaceParameterLoopUnwrapper().unwrap(input, on: surface,
                    tolerance: tolerance, context: "Unequal irrational polyline lengths",
                    maximumSubdivisionDepth: 8, remainingSourceDepth: 16,
                    maximumAlgebraicDepth: selectedDepth, using: &execution)
                Issue.record("A zero coefficient-depth ceiling admitted an irrational segment length.")
            } catch { #expect(isResource(error, .coefficientDepth)) }
        }
    }

    @Test func workBoundaryIncludesPriorCallerWork() throws {
        func run(_ budget: OriginalQueryBudget) throws -> [SurfaceParameterLoopUnwrapper.UnwrappedCurve] {
            var execution = try execution(budget)
            try execution.consumeWork(11)
            return try SurfaceParameterLoopUnwrapper().unwrap(curves(),
                uPeriod: nil, vPeriod: nil,
                uClosureTolerance: tolerance.distance * 8, vClosureTolerance: tolerance.distance * 8,
                on: surface, tolerance: tolerance, context: "Cumulative loop work",
                maximumSubdivisionDepth: 8, remainingSourceDepth: 16,
                maximumAlgebraicDepth: 32, using: &execution)
        }
        let measured = try OriginalQueryBudget()
        let expected = try run(measured)
        let requiredWork = measured.snapshot.work
        #expect(requiredWork > 11)
        let exact = try OriginalQueryBudget(workLimit: requiredWork)
        let repeated = try run(exact)
        #expect(repeated == expected)
        #expect(exact.snapshot.work == requiredWork)
        let short = try OriginalQueryBudget(workLimit: requiredWork - 1)
        do {
            _ = try run(short)
            Issue.record("Loop unwrapping escaped the original cumulative work ceiling.")
        } catch { #expect(isResource(error, .work)) }
        #expect(short.snapshot.work <= requiredWork - 1)
    }

    @Test func cancellationCannotPublishAnUnwrappedLoop() throws {
        let budget = try OriginalQueryBudget(checkpoint: { throw ExactScalarFailure.cancelled })
        var execution = try execution(budget)
        do {
            _ = try SurfaceParameterLoopUnwrapper().unwrap(curves(), on: surface,
                tolerance: tolerance, context: "Cancelled loop",
                maximumSubdivisionDepth: 8, remainingSourceDepth: 16,
                maximumAlgebraicDepth: 32, using: &execution)
            Issue.record("Cancelled loop unwrapping returned a result.")
        } catch { #expect(isCancellation(error)) }
        #expect(budget.snapshot.work == 0 && budget.snapshot.storageBytes == 0)
    }
}

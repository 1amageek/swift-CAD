import CADCore
import CADGeometry
import Testing
@testable import CADTopology

@Suite("Distance domain lifetime", .timeLimit(.minutes(1)))
struct DistanceDomainLifetimeTests {
    private let first = BRepDistanceSelection.point(Point3D(x: 4, y: 0, z: 0))
    private let second = BRepDistanceSelection.point(Point3D(x: 4, y: 0, z: 3))
    private let options = BRepDistanceOptions(absoluteAccuracy: ModelingTolerance.standard.distance)

    private func execution(_ budget: OriginalQueryBudget) throws -> OriginalQueryExecution {
        OriginalQueryExecution(budget: budget, limits: try .init(
            maximumValueDepth: 32, maximumCoefficientDepth: 32,
            remainingSourceDepth: 16, maximumSubdivisionDepth: 32))
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

    private func expectSameWitnesses(_ first: [BRepDistanceWitness], _ second: [BRepDistanceWitness]) {
        #expect(first.count == second.count)
        for (a, b) in zip(first, second) {
            #expect(a.firstSupport == b.firstSupport && a.secondSupport == b.secondSupport)
            #expect(a.firstPoint == b.firstPoint && a.secondPoint == b.secondPoint)
            #expect(a.firstParameters == b.firstParameters && a.secondParameters == b.secondParameters)
        }
    }

    @Test func pointDistancePreservesValuesAndCumulativeWorkAndBytes() throws {
        func run(_ budget: OriginalQueryBudget) throws -> BRepDistanceQueryResult {
            var execution = try execution(budget)
            try execution.consumeWork(7)
            return try DefaultBRepDistanceQuery().distance(from: first, to: second,
                in: BRepModel(), options: options, tolerance: .standard, using: &execution)
        }
        let ordinary = try DefaultBRepDistanceQuery().distance(from: first, to: second,
            in: BRepModel(), options: options, tolerance: .standard)
        let measured = try OriginalQueryBudget()
        let expected = try run(measured)
        #expect(expected.lowerBound <= 3 && expected.upperBound >= 3)
        #expect(expected.upperBound - expected.lowerBound <= options.absoluteAccuracy)
        #expect(expected.lowerBound == ordinary.lowerBound && expected.upperBound == ordinary.upperBound)
        expectSameWitnesses(expected.witnesses, ordinary.witnesses)
        let work = measured.snapshot.work, bytes = measured.snapshot.storageBytes
        #expect(work > 7 && bytes > 0)
        let exact = try OriginalQueryBudget(workLimit: work, storageByteLimit: bytes)
        let repeated = try run(exact)
        #expect(repeated.lowerBound == expected.lowerBound && repeated.upperBound == expected.upperBound)
        expectSameWitnesses(repeated.witnesses, expected.witnesses)
        #expect(exact.snapshot.work == work && exact.snapshot.storageBytes == bytes)
        let shortWork = try OriginalQueryBudget(workLimit: work - 1)
        do {
            _ = try run(shortWork)
            Issue.record("Distance escaped the original cumulative work ceiling.")
        } catch { #expect(isResource(error, .work)) }
        let shortBytes = try OriginalQueryBudget(storageByteLimit: bytes - 1)
        do {
            _ = try run(shortBytes)
            Issue.record("Distance escaped the original cumulative byte ceiling.")
        } catch { #expect(isResource(error, .storage)) }
    }

    @Test func zeroBytesRefusesBeforeDomainPublication() throws {
        let budget = try OriginalQueryBudget(storageByteLimit: 0)
        var execution = try execution(budget)
        do {
            _ = try DefaultBRepDistanceQuery().distance(from: first, to: second,
                in: BRepModel(), options: options, tolerance: .standard, using: &execution)
            Issue.record("Zero-byte distance admission published a result.")
        } catch { #expect(isResource(error, .storage)) }
        #expect(budget.snapshot.storageBytes == 0)
    }

    @Test func cancellationRefusesBeforeDomainPublication() throws {
        let budget = try OriginalQueryBudget(checkpoint: { throw ExactScalarFailure.cancelled })
        var execution = try execution(budget)
        do {
            _ = try DefaultBRepDistanceQuery().distance(from: first, to: second,
                in: BRepModel(), options: options, tolerance: .standard, using: &execution)
            Issue.record("Cancelled distance admission published a result.")
        } catch { #expect(isCancellation(error)) }
        #expect(budget.snapshot.work == 0 && budget.snapshot.storageBytes == 0)
    }
}

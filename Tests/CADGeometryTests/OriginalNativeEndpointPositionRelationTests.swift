import CADCore
import CADGeometry
import Testing

@Suite("Original Native endpoint source equality")
struct OriginalNativeEndpointPositionRelationTests {
    private static let tolerance = ModelingTolerance.standard
    private static func spline() -> BSplineCurve3D {
        .init(degree: 1, knots: [0,0,1,1], controlPoints: [.origin, .init(x: 1, y: 0, z: 0)])
    }
    private static func execution(_ budget: OriginalQueryBudget) throws -> OriginalQueryExecution {
        .init(budget: budget, limits: try .init(maximumValueDepth: 32, maximumCoefficientDepth: 32,
            remainingSourceDepth: 8, maximumSubdivisionDepth: 0))
    }
    private static func prove(_ first: Curve3D, _ a: Double, _ second: Curve3D, _ b: Double,
        using execution: inout OriginalQueryExecution) throws -> OriginalCurveEndpointPositionRelation? {
        try .prove(first: first, at: a, second: second, at: b, remainingSourceDepth: 8,
            maximumSubdivisionDepth: 0, tolerance: tolerance, usage: &execution, maximumAlgebraicDepth: 32)
    }
    private static func original(_ error: any Error) -> any Error {
        if let retained = error as? OriginalQueryFailure { return original(retained.originalError) }
        if case .admissionRejected(let underlying)? = error as? ExactScalarFailure { return original(underlying) }
        return error
    }
    private static func expectWorkRefusal(_ body: () throws -> Void) {
        do { try body(); Issue.record("Work exhaustion published an endpoint relation.") }
        catch {
            guard case .resourceLimit(.work)? = original(error) as? ExactScalarFailure else {
                Issue.record("Endpoint work refusal lost its exact scalar cause."); return
            }
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func sameAndUnequalNativeEndpointsRunOnCooperativeWorkers() async throws {
        try await withThrowingTaskGroup(of: Void.self) { group in
            for _ in 0..<4 { group.addTask {
                var execution = try Self.execution(OriginalQueryBudget())
                let source = Curve3D.bSpline(Self.spline())
                let same = try Self.prove(source, 0.25, source, 0.25, using: &execution)
                #expect(same != nil)
                let unequal = try Self.prove(source, 0, source, 1, using: &execution)
                #expect(unequal == nil)
                let closed = Curve3D.bSpline(.init(degree: 1, knots: [0,0,0.5,1,1],
                    controlPoints: [.origin, .init(x: 1, y: 0, z: 0), .origin]))
                let joined = try Self.prove(closed, 0, closed, 1, using: &execution)
                #expect(joined != nil)
            } }
            try await group.waitForAll()
        }
    }

    @Test func foreignNativeSourcesRemainExactAndRetainTheirCOWPayload() throws {
        let source = Self.spline()
        var nearby = source
        nearby.controlPoints[1].x += Self.tolerance.distance / 2
        let displacement = nearby.controlPoints[1].x - source.controlPoints[1].x
        #expect(displacement > 0 && displacement < Self.tolerance.distance)
        var execution = try Self.execution(OriginalQueryBudget())
        for pair in [(source, nearby), (nearby, source)] {
            let unequal = try Self.prove(.bSpline(pair.0), 1, .bSpline(pair.1), 1, using: &execution)
            #expect(unequal == nil)
        }
        var caller = source
        let result = try Self.prove(.bSpline(caller), 0.25, .bSpline(caller), 0.25, using: &execution)
        let retained = try #require(result)
        caller.controlPoints[1].x = 99
        caller.weights[1] = 2
        guard case .bSpline(let first) = retained.first, case .bSpline(let second) = retained.second else {
            Issue.record("A Native endpoint relation lost its authored source case."); return
        }
        #expect(first == source && second == source)
        #expect(caller != first)
    }

    @Test func measuredBudgetDoesNotTurnGeometricAgreementIntoSourceEquality() throws {
        let source = Curve3D.bSpline(Self.spline())
        let measured = try OriginalQueryBudget()
        var measuring = try Self.execution(measured)
        let relation = try Self.prove(source, 0.25, source, 0.25, using: &measuring)
        #expect(relation != nil)
        let required = measured.snapshot.work
        #expect(required > 0)
        let exactBudget = try OriginalQueryBudget(workLimit: required)
        var exact = try Self.execution(exactBudget)
        let exactRelation = try Self.prove(source, 0.25, source, 0.25, using: &exact)
        #expect(exactRelation != nil && exactBudget.snapshot.work == required)
        Self.expectWorkRefusal { _ = try Self.prove(source, 0.25, source, 0.25, using: &exact) }
        var oneLess = try Self.execution(OriginalQueryBudget(workLimit: required - 1))
        Self.expectWorkRefusal { _ = try Self.prove(source, 0.25, source, 0.25, using: &oneLess) }
        var scaled = Self.spline(); scaled.weights = [2,2]
        let foreign = Curve3D.bSpline(scaled)
        var limited = try Self.execution(OriginalQueryBudget(workLimit: required))
        Self.expectWorkRefusal { _ = try Self.prove(source, 0.25, foreign, 0.25, using: &limited) }
        var admitted = try Self.execution(OriginalQueryBudget())
        let samePosition = try Self.prove(source, 0.25, foreign, 0.25, using: &admitted)
        #expect(samePosition != nil)
        let cancelled = try OriginalQueryBudget(checkpoint: { throw ExactScalarFailure.cancelled })
        var stopped = try Self.execution(cancelled)
        do {
            _ = try Self.prove(source, 0.25, source, 0.25, using: &stopped)
            Issue.record("Cancellation published an endpoint relation.")
        } catch {
            guard case .cancelled? = Self.original(error) as? ExactScalarFailure else {
                Issue.record("Endpoint cancellation lost its exact scalar cause."); return
            }
        }
        #expect(cancelled.snapshot.work == 0 && cancelled.snapshot.storageBytes == 0)
    }
}

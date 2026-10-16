import CADCore
import CADGeometry

@main
struct OriginalNativeEndpointPositionPortable {
    struct Failure: Error { let detail: String }
    static let tolerance = ModelingTolerance.standard
    static func require(_ condition: Bool, _ detail: String) throws {
        guard condition else { throw Failure(detail: detail) }
    }
    static func spline() -> BSplineCurve3D {
        .init(degree: 1, knots: [0,0,1,1], controlPoints: [.origin, .init(x: 1, y: 0, z: 0)])
    }
    static func execution(_ budget: OriginalQueryBudget) throws -> OriginalQueryExecution {
        .init(budget: budget, limits: try .init(maximumValueDepth: 32, maximumCoefficientDepth: 32,
            remainingSourceDepth: 8, maximumSubdivisionDepth: 0))
    }
    static func prove(_ first: Curve3D, _ a: Double, _ second: Curve3D, _ b: Double,
        using execution: inout OriginalQueryExecution) throws -> OriginalCurveEndpointPositionRelation? {
        try .prove(first: first, at: a, second: second, at: b, remainingSourceDepth: 8,
            maximumSubdivisionDepth: 0, tolerance: tolerance, usage: &execution, maximumAlgebraicDepth: 32)
    }
    static func original(_ error: any Error) -> any Error {
        if let retained = error as? OriginalQueryFailure { return original(retained.originalError) }
        if case .admissionRejected(let underlying)? = error as? ExactScalarFailure { return original(underlying) }
        return error
    }
    static func workRefusal(_ operation: () throws -> Void) throws {
        do { try operation() }
        catch {
            guard case .resourceLimit(.work)? = original(error) as? ExactScalarFailure else { throw error }
            return
        }
        throw Failure(detail: "Work exhaustion published an endpoint relation.")
    }
    static func retained(using execution: inout OriginalQueryExecution) throws -> OriginalCurveEndpointPositionRelation {
        var caller = spline()
        guard let relation = try prove(.bSpline(caller), 0.25, .bSpline(caller), 0.25, using: &execution) else {
            throw Failure(detail: "An identical Native source did not retain its endpoint.")
        }
        caller.controlPoints[1].x = 99; caller.weights[1] = 2
        try require(caller != spline(), "The COW control did not mutate its caller input.")
        return relation
    }
    static func main() throws {
        let source = Curve3D.bSpline(spline())
        var admitted = try execution(OriginalQueryBudget())
        let relation = try retained(using: &admitted)
        guard case .bSpline(let first) = relation.first, case .bSpline(let second) = relation.second else {
            throw Failure(detail: "The endpoint relation lost its retained Native source case.")
        }
        try require(first == spline() && second == spline(), "Caller COW mutation changed retained endpoint authority.")
        let unequal = try prove(source, 0, source, 1, using: &admitted)
        try require(unequal == nil, "Distinct Native endpoints became equal.")
        let closed = Curve3D.bSpline(.init(degree: 1, knots: [0,0,0.5,1,1],
            controlPoints: [.origin, .init(x: 1, y: 0, z: 0), .origin]))
        let joined = try prove(closed, 0, closed, 1, using: &admitted)
        try require(joined != nil, "Exact authored closed Native endpoints were lost.")
        var nearby = spline(); nearby.controlPoints[1].x += tolerance.distance / 2
        let displacement = nearby.controlPoints[1].x - spline().controlPoints[1].x
        try require(displacement > 0 && displacement < tolerance.distance, "The foreign endpoint must be distinct within tolerance.")
        for pair in [(spline(), nearby), (nearby, spline())] {
            let distinct = try prove(.bSpline(pair.0), 1, .bSpline(pair.1), 1, using: &admitted)
            try require(distinct == nil, "Proximity became exact Native endpoint equality.")
        }
        print("PASS Native endpoint exact positions and lifetime")
        let measured = try OriginalQueryBudget()
        var measuring = try execution(measured)
        let measuredRelation = try prove(source, 0.25, source, 0.25, using: &measuring)
        try require(measuredRelation != nil, "Identical Native sources failed their measured admission.")
        let required = measured.snapshot.work
        try require(required > 0, "Endpoint source comparison bypassed work admission.")
        let exactBudget = try OriginalQueryBudget(workLimit: required)
        var exact = try execution(exactBudget)
        let exactRelation = try prove(source, 0.25, source, 0.25, using: &exact)
        try require(exactRelation != nil && exactBudget.snapshot.work == required, "Exact N endpoint work did not finish.")
        try workRefusal { _ = try prove(source, 0.25, source, 0.25, using: &exact) }
        var oneLess = try execution(OriginalQueryBudget(workLimit: required - 1))
        try workRefusal { _ = try prove(source, 0.25, source, 0.25, using: &oneLess) }
        var scaled = spline(); scaled.weights = [2,2]
        var limited = try execution(OriginalQueryBudget(workLimit: required))
        try workRefusal { _ = try prove(source, 0.25, .bSpline(scaled), 0.25, using: &limited) }
        let geometricAgreement = try prove(source, 0.25, .bSpline(scaled), 0.25, using: &admitted)
        try require(geometricAgreement != nil, "Exact coordinates lost a common point of distinct source payloads.")
        print("PASS Native endpoint exact source and cumulative work")
        let cancelled = try OriginalQueryBudget(checkpoint: { throw ExactScalarFailure.cancelled })
        var stopped = try execution(cancelled)
        do {
            _ = try prove(source, 0.25, source, 0.25, using: &stopped)
            throw Failure(detail: "Cancellation published an endpoint relation.")
        } catch {
            guard case .cancelled? = original(error) as? ExactScalarFailure else { throw error }
        }
        try require(cancelled.snapshot.work == 0 && cancelled.snapshot.storageBytes == 0,
            "Cancelled endpoint comparison debited resources.")
        print("PASS Native endpoint cancellation")
    }
}

import L0
import L1
import L2
import L3
import L4
import L5
import L6

public enum GeometricFailureFixtures {
    typealias G = GeometryFixtures
    public static func scalar(_ error: any Error) -> ExactScalarFailure? {
        switch error {
        case let e as ExactScalarFailure: return e
        case let e as ExactGeometricRelationFailure:
            switch e { case .scalar(let v): return v; case .polynomial(let v): return scalar(v)
            case .cell(let v): return scalar(v); case .topology(let v): return scalar(v)
            case .parameter(let v): return scalar(v); case .operationRejected(let v): return scalar(v); default: return nil }
        case let e as ExactParametricRelationFailure:
            switch e { case .scalar(let v): return v; case .polynomial(let v): return scalar(v)
            case .cell(let v): return scalar(v); case .topology(let v): return scalar(v)
            case .operationRejected(let v): return scalar(v); default: return nil }
        case let e as ExactPolynomialFailure:
            switch e { case .scalar(let v): return v; case .operationRejected(let v): return scalar(v); default: return nil }
        case let e as ExactRealCellFailure:
            switch e { case .scalar(let v): return v; case .polynomial(let v): return scalar(v)
            case .root(let v): return scalar(v); case .operationRejected(let v): return scalar(v); default: return nil }
        case let e as ExactRealTopologyFailure:
            switch e { case .scalar(let v): return v; case .polynomial(let v): return scalar(v)
            case .root(let v): return scalar(v); case .cell(let v): return scalar(v)
            case .operationRejected(let v): return scalar(v); default: return nil }
        case let e as ExactRealRootFailure:
            switch e { case .scalar(let v): return v; case .polynomial(let v): return scalar(v)
            case .operationRejected(let v): return scalar(v); default: return nil }
        default: return nil
        }
    }
    public static func require(_ condition: Bool) throws {
        if !condition { throw FixtureFailure.assertion }
    }
    public static func verify() throws {
        var setup = try G.ledger()
        let raw = try G.original(cs: true, mode: 2, &setup)
        var baseline = try G.ledger()
        let r = try G.geometry.resolve(raw, limits: G.limits(), using: &baseline)
        let w = baseline.work, b = baseline.storageBytes, vd = baseline.valueDepth, cd = baseline.coefficientDepth
        var exact = ExactScalarLedger(limits: try .init(work: w, storageBytes: b, valueDepth: vd, coefficientDepth: cd))
        _ = try G.geometry.resolve(raw, limits: G.limits(), using: &exact)
        for axis in 0..<4 {
            if (axis == 2 && vd == 0) || (axis == 3 && cd == 0) { continue }
            var a = ExactScalarLedger(limits: try .init(work: axis == 0 ? w-1 : w, storageBytes: axis == 1 ? b-1 : b,
                valueDepth: axis == 2 ? vd-1 : vd, coefficientDepth: axis == 3 ? cd-1 : cd))
            let expected: ExactResource = axis == 0 ? .work : axis == 1 ? .storage : axis == 2 ? .valueDepth : .coefficientDepth
            var rejected = false
            do { _ = try G.geometry.resolve(raw, limits: G.limits(), using: &a) }
            catch { if case .resourceLimit(let resource) = scalar(error) { rejected = resource == expected } }
            try require(rejected)
        }
        for stop in [1, b] {
            var a = PublicationAdmission(ledger: try G.ledger(), storageStop: stop, workStop: Int.max)
            var rejected = false
            do { _ = try G.geometry.resolve(raw, limits: G.limits(), using: &a) }
            catch { if case .cancelled = scalar(error) { rejected = true } }
            try require(rejected)
        }
        for limited in [try G.limits(strata: 0), try G.limits(spans: 0)] {
            var a = try G.ledger(), rejected = false
            do { _ = try G.geometry.resolve(raw, limits: limited, using: &a) }
            catch ExactGeometricRelationFailure.resultLimit { rejected = true }
            try require(rejected)
        }
        let f = try G.field(of: r, &setup), zero = try f.integer(0, using: &setup)
        let station = ExactGeometricStation<G.B>.curveParameter(field: f, value: zero)
        var query = try G.ledger()
        _ = try G.geometry.fiber(at: station, in: r, limits: G.limits(), using: &query)
        var finalCancel = PublicationAdmission(ledger: try G.ledger(), storageStop: query.storageBytes, workStop: Int.max)
        var rejected = false
        do { _ = try G.geometry.fiber(at: station, in: r, limits: G.limits(), using: &finalCancel) }
        catch { if case .cancelled = scalar(error) { rejected = true } }
        try require(rejected)
        var a = try G.ledger()
        let invalid = ExactGeometricStation<G.B>.curveParameter(field: f, value: try f.integer(2, using: &a))
        rejected = false
        do { _ = try G.geometry.fiber(at: invalid, in: r, limits: G.limits(), using: &a) }
        catch ExactGeometricRelationFailure.invalidStation { rejected = true }
        try require(rejected)
        let foreign = try G.F.base(field: G.B(), maximumExtensionLevel: 10, using: &a)
        let point = try ExactXYZ<G.B>(field: foreign, x: foreign.integer(0, using: &a),
            y: foreign.integer(0, using: &a), z: foreign.integer(0, using: &a))
        rejected = false
        do { _ = try G.geometry.contains(point, in: r, limits: G.limits(), using: &a) }
        catch { if case .incompatibleDomain = scalar(error) { rejected = true } }
        try require(rejected)
        let normal = try G.limits()
        let zeroCells = try ExactGeometricRelationLimits(cells: .init(maximumStoredCells: 0, maximumRootsPerStack: 100),
            topology: normal.topology, maximumStrata: 30_000, maximumProjectionSpans: 1000)
        rejected = false
        do { _ = try G.geometry.contains(G.xyz(r, 0, 0, 0, &a), in: r, limits: zeroCells, using: &a) }
        catch ExactGeometricRelationFailure.cell(.cellLimit) { rejected = true }
        try require(rejected)
        let emptyRaw = try G.original(cs: true, mode: 5, &setup)
        var emptyBaseline = try G.ledger()
        let empty = try G.geometry.resolve(emptyRaw, limits: G.limits(strata: 0, spans: 0), using: &emptyBaseline)
        try require(empty.isEmpty && empty.original.selection.cells.isEmpty)
        var emptyCancel = PublicationAdmission(ledger: try G.ledger(), storageStop: emptyBaseline.storageBytes, workStop: Int.max)
        rejected = false
        do { _ = try G.geometry.resolve(emptyRaw, limits: G.limits(strata: 0, spans: 0), using: &emptyCancel) }
        catch { if case .cancelled = scalar(error) { rejected = true } }
        try require(rejected)
        print("PASS: L6 resolve exact admission work=\(w) storage=\(b); limits/cancel/final-empty/foreign/station")
    }
    enum FixtureFailure: Error { case assertion }
}

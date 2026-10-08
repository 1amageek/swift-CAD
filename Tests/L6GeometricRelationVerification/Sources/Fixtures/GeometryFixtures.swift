import L0
import L1
import L2
import L3
import L4
import L5
import L6

public enum GeometryFixtures {
    public typealias B = ExactRationalScalarDomain
    public typealias F = ExactAlgebraicScalarDomain<B>
    public typealias C = ExactRealCellDomain<B>
    public typealias P = ExactPolynomialDomain<F>
    public typealias Geometry = DefaultExactGeometricRelationResolver<B, C, ExactRealTopology<B>>
    public typealias Parameters = ExactParametricRelationDomain<B, C, ExactRealTopology<B>>
    public static var geometry: Geometry { .init(cells: C.self, topology: .init(cells: C.self)) }
    public static var parameters: Parameters { .init(cells: C.self, topology: .init(cells: C.self)) }
    public static func ledger() throws -> ExactScalarLedger {
        .init(limits: try .init(work: 80_000_000, storageBytes: 1_073_741_824, valueDepth: 400, coefficientDepth: 400))
    }
    public static func limits(strata: Int = 30_000, spans: Int = 1000) throws -> ExactGeometricRelationLimits {
        try .init(cells: .init(maximumStoredCells: 30_000, maximumRootsPerStack: 100),
            topology: .init(maximumGeneratedCells: 30_000, maximumRootsPerStack: 100,
                maximumClosures: 1000, maximumAttachmentPieces: 30_000, maximumComponents: 1000),
            maximumStrata: strata, maximumProjectionSpans: spans)
    }
    public static func field(of g: ExactGeometricRelation<B>, _ a: inout ExactScalarLedger) throws -> F {
        let c = try C(retaining: g.original.original.predicate.source, using: &a)
        return try c.coefficientField(of: g.original.original.predicate.source, using: &a)
    }
    public static func xyz(_ g: ExactGeometricRelation<B>, _ x: Int, _ y: Int, _ z: Int,
        _ a: inout ExactScalarLedger) throws -> ExactXYZ<B> {
        let f = try field(of: g, &a)
        return try .init(field: f, x: f.integer(x, using: &a), y: f.integer(y, using: &a), z: f.integer(z, using: &a))
    }
    public static func original(cs: Bool, mode: Int, _ a: inout ExactScalarLedger) throws -> ExactParametricRelation<B> {
        let f = try F.base(field: B(), maximumExtensionLevel: 10, using: &a)
        let c = try C(field: f, variableCount: cs ? 1 : 2, using: &a), s = try C(field: f, variableCount: 2, using: &a)
        let p = c.polynomials, q = s.polynomials
        let t = try p.variable(0, using: &a), u = try q.variable(0, using: &a), v = try q.variable(1, using: &a)
        let one = try f.integer(1, using: &a), zero = try f.integer(0, using: &a)
        let p1 = try p.constant(one, using: &a), q1 = try q.constant(one, using: &a)
        let p0 = try p.constant(zero, using: &a), q0 = try q.constant(zero, using: &a)
        var left = [p0, p0, t, p1], right = [u, v, q0, q1]
        if cs {
            switch mode {
            case 1: left = [t, p0, try p.multiplying(t, t, using: &a), p1]
            case 2: left = [t, p0, p0, p1]
            case 3:
                left = [p0, p0, p0, p1]
                right = [try q.subtracting(q.multiplying(u, u, using: &a), q1, using: &a), v, q0, q1]
            case 4:
                left = [t, p0, p0, p1]
                let half = try f.dividing(one, f.integer(2, using: &a), using: &a)
                right = [u, try q.multiplying(v, q.subtracting(u, q.constant(half, using: &a), using: &a), using: &a), q0, q1]
            case 5: left = [p0, p0, p1, p1]
            case 6:
                let weight = try p.adding(p1, p.multiplying(t, t, using: &a), using: &a)
                left = [try p.multiplying(t, weight, using: &a), p0, p0, weight]
            default: break
            }
        } else {
            let w = try p.variable(1, using: &a)
            left = [t, w, p0, p1]
            switch mode {
            case 0: right = [u, q0, v, q1]
            case 1: break
            case 2: left = [p0, p0, p0, p1]; right = [q0, q0, q0, q1]
            case 3: left = [try p.multiplying(t, t, using: &a), w, p0, p1]; right = [try q.multiplying(u, u, using: &a), v, q0, q1]
            case 4: left = [t, p0, p0, p1]; right = [u, q0, q0, q1]
            case 5: right = [u, v, q1, q1]
            case 6: left = [try p.multiplying(t, w, using: &a), w, p0, p1]
            default: break
            }
        }
        let roots = try ExactRealRootDomain(field: f, using: &a)
        let interval = try roots.domain(lower: .finite(f.integer(-1, using: &a)), upper: .finite(one), using: &a)
        let singleton = try roots.domain(lower: .finite(zero), upper: .finite(zero), using: &a)
        let csource = try c.bind(polynomials: left, domains: cs ? [interval] : [interval, mode == 6 ? singleton : interval], using: &a)
        let ssource = try s.bind(polynomials: right, domains: [interval, !cs && mode == 6 ? singleton : interval], using: &a)
        let first = try parameters.map(from: csource, using: &a), second = try parameters.map(from: ssource, using: &a)
        let compiled = try parameters.compile(kind: cs ? .curveSurface : .surfaceSurface, first: first, second: second, using: &a)
        let l = try limits()
        let result = try parameters.resolve(compiled, cellLimits: l.cells, topologyLimits: l.topology, using: &a)
        return result
    }
    public static func relation(cs: Bool, mode: Int, _ a: inout ExactScalarLedger) throws -> ExactGeometricRelation<B> {
        let raw = try original(cs: cs, mode: mode, &a)
        let result = try geometry.resolve(raw, limits: limits(), using: &a)
        return result
    }
}

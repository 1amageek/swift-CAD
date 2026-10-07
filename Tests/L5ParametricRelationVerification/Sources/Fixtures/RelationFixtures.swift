import L0
import L1
import L2
import L3
import L4
import L5

public enum RelationFixtures {
    public typealias Base = ExactRationalScalarDomain
    public typealias Field = ExactAlgebraicScalarDomain<Base>
    public typealias Cells = ExactRealCellDomain<Base>
    public typealias Domain = ExactParametricRelationDomain<Base, Cells, ExactRealTopology<Base>>
    public static var domain: Domain { .init(cells: Cells.self, topology: .init(cells: Cells.self)) }
    public static func ledger() throws -> ExactScalarLedger {
        .init(limits: try .init(work: 200_000_000, storageBytes: 700_000_000, valueDepth: 400, coefficientDepth: 400))
    }
    static func require(_ condition: Bool) throws { if !condition { throw ExactParametricRelationFailure.invalidEvidence } }
    static func field(_ a: inout ExactScalarLedger) throws -> Field {
        try .base(field: Base(), maximumExtensionLevel: 10, using: &a)
    }
    static func box(_ f: Field, _ lower: Int, _ upper: Int, _ a: inout ExactScalarLedger) throws -> ExactRealRootInterval<Field.Value> {
        let roots = try ExactRealRootDomain(field: f, using: &a)
        return try roots.domain(lower: .finite(f.integer(lower, using: &a)), upper: .finite(f.integer(upper, using: &a)), using: &a)
    }
    static func bind<C: ExactParametricRelationConstructing<Base>>(_ source: ExactRealCellSource<Base>,
        _ compiler: C, _ a: inout ExactScalarLedger) throws -> ExactParametricMap<Base> {
        try compiler.map(from: source, using: &a)
    }
    static func compile<C: ExactParametricRelationConstructing<Base>>(_ first: ExactParametricMap<Base>,
        _ second: ExactParametricMap<Base>, _ kind: ExactParametricRelationKind, _ compiler: C,
        _ a: inout ExactScalarLedger) throws -> ExactParametricRelationSource<Base> {
        try compiler.compile(kind: kind, first: first, second: second, using: &a)
    }
    static func resolve<R: ExactParametricRelationResolving<Base>>(_ source: ExactParametricRelationSource<Base>,
        _ resolver: R, _ a: inout ExactScalarLedger) throws -> ExactParametricRelation<Base> {
        try resolver.resolve(source, cellLimits: .init(maximumStoredCells: 20000, maximumRootsPerStack: 100),
            topologyLimits: .init(maximumGeneratedCells: 20000, maximumRootsPerStack: 100,
                maximumClosures: 1000, maximumAttachmentPieces: 20000, maximumComponents: 1000), using: &a)
    }
    static func member(_ coordinates: [Int], _ relation: ExactParametricRelation<Base>, _ expected: Bool,
        _ a: inout ExactScalarLedger) throws {
        let cells = try Cells(retaining: relation.original.predicate.source, using: &a)
        let f = try cells.coefficientField(of: relation.original.predicate.source, using: &a)
        let values = try coordinates.map { try f.integer($0, using: &a) }
        let point = try cells.point(field: f, coordinates: values, using: &a)
        try require(try domain.contains(point, in: relation, rootLimits: .init(maximumRoots: 100), using: &a) == expected)
    }
    static func pair(_ f: Field, mode: Int, _ a: inout ExactScalarLedger) throws -> (ExactParametricMap<Base>, ExactParametricMap<Base>) {
        let curve = try Cells(field: f, variableCount: 1, using: &a), surface = try Cells(field: f, variableCount: 2, using: &a)
        let c = curve.polynomials, s = surface.polynomials
        let t = try c.variable(0, using: &a), u = try s.variable(0, using: &a), v = try s.variable(1, using: &a)
        let cz = try c.zero(using: &a), sz = try s.zero(using: &a)
        let one = try f.integer(1, using: &a), two = try f.integer(2, using: &a), three = try f.integer(3, using: &a)
        let c1 = try c.constant(one, using: &a), s1 = try s.constant(one, using: &a)
        var left = [t, cz, try c.subtracting(c.multiplying(t, t, using: &a), c1, using: &a), c1]
        var right = [u, v, sz, s1]
        if mode == 0 {
            left = try left.map { try c.multiplying($0, c.constant(two, using: &a), using: &a) }
            right = try right.map { try s.multiplying($0, s.constant(three, using: &a), using: &a) }
        } else if mode == 1 { left = [t, cz, try c.multiplying(t, t, using: &a), c1] }
        else if mode == 2 { left = [cz, cz, t, c1]; right = [try s.subtracting(s.multiplying(u, u, using: &a), s1, using: &a), v, sz, s1] }
        else if mode == 3 { left = [cz, cz, t, t]; right = [u, v, s1, s1] }
        else if mode == 4 { left = [t, cz, c1, c1] }
        else if mode == 5 { left = [t, cz, cz, c1] }
        else if mode == 6 { left = [cz, cz, cz, cz] }
        let interval: ExactRealRootInterval<Field.Value>
        if mode == 7 {
            let roots = try ExactRealRootDomain(field: f, using: &a)
            interval = try roots.domain(lower: .finite(f.integer(-1,using:&a)), upper: .finite(f.integer(1,using:&a)), includesLower: false, includesUpper: false, using: &a)
        } else { interval = try box(f, -1, 1, &a) }
        let cs = try curve.bind(polynomials: left, domains: [interval], using: &a)
        let ss = try surface.bind(polynomials: right, domains: [interval, interval], using: &a)
        return try (bind(cs, domain, &a), bind(ss, domain, &a))
    }
    public static func csRelations() throws {
        for mode in 0...7 {
            var a = try ledger(); let f = try field(&a)
            let (first, second) = try pair(f, mode: mode, &a)
            let compiled = try compile(first, second, .curveSurface, domain, &a)
            let relation = try resolve(compiled, domain, &a)
            try require(relation.original.firstParameters == 0..<1 && relation.original.secondParameters == 1..<3)
            switch mode {
            case 0:
                try require(relation.components.count == 2 && relation.selection.cells.allSatisfy { $0.dimension == 0 })
                try member([-1,-1,0], relation, true, &a); try member([1,1,0], relation, true, &a)
                try member([0,0,0], relation, false, &a)
            case 1:
                try require(relation.components.count == 1 && relation.selection.cells.count == 1)
                try member([0,0,0], relation, true, &a)
            case 2:
                try require(relation.components.count == 2 && relation.selection.cells.count == 2)
                try member([0,-1,0], relation, true, &a); try member([0,1,0], relation, true, &a)
            case 3:
                try require(compiled.guardDivisions.count == 2 && compiled.rawEquations.count == 3)
                let cells = try Cells(retaining: compiled.predicate.source, using: &a), p = cells.polynomials
                for witness in compiled.guardDivisions {
                    let guardLaw = compiled.predicate.source.polynomials[3 + witness.guardIndex]
                    try require(try p.isZero(witness.division.remainder, using: &a))
                    try require(try p.equals(witness.dividend, p.multiplying(guardLaw, witness.division.quotient, using: &a), using: &a))
                }
                try require(relation.components.count == 2 && relation.selection.cells.allSatisfy { $0.dimension <= 1 })
                try member([0,0,0], relation, false, &a); try member([1,0,0], relation, true, &a)
                try member([-1,0,0], relation, true, &a)
            case 4, 6, 7:
                try require(relation.components.count == 0 && relation.selection.cells.isEmpty)
                try require(relation.selection.partition.storedCellCount > 0)
                try member([0,0,0], relation, false, &a)
            default:
                try require(relation.components.count == 1 && relation.selection.cells.contains { $0.dimension == 1 })
                try member([1,1,0], relation, true, &a)
            }
            print("PASS: CS case=\(mode) work=\(a.work) storage=\(a.storageBytes)")
        }
        print("PASS: weighted/repeated/multiple-UV/guard/empty/continuous CS")
    }
    public static func foldedSSI() throws {
        var a = try ledger(); let f = try field(&a), cells = try Cells(field: f, variableCount: 2, using: &a)
        let p = cells.polynomials, u = try p.variable(0, using: &a), v = try p.variable(1, using: &a)
        let source = try cells.bind(polynomials: [p.multiplying(u,u,using:&a),v,p.zero(using:&a),p.constant(f.integer(1,using:&a),using:&a)],
            domains: [box(f,-1,1,&a),box(f,-1,1,&a)], using:&a)
        let map = try bind(source, domain, &a), compiled = try compile(map,map,.surfaceSurface,domain,&a)
        let relation = try resolve(compiled,domain,&a)
        try require(relation.selection.cells.count == 45 && relation.components.count == 1)
        try require(relation.components.incidence.attachments.count == 108)
        try member([1,0,-1,0],relation,true,&a); try member([1,0,0,0],relation,false,&a)
        print("PASS: folded SSI cells=45 attachments=108 components=1 work=\(a.work) storage=\(a.storageBytes)")
    }
    public static func domainsAndLifetime() throws {
        var a = try ledger()
        let relation: ExactParametricRelation<Base>
        do {
            let f = try field(&a), c = try Cells(field:f,variableCount:1,using:&a), s = try Cells(field:f,variableCount:2,using:&a)
            let roots = try ExactRealRootDomain(field:f,using:&a)
            let line = try roots.domain(lower:.negativeInfinity,upper:.positiveInfinity,using:&a)
            let singleton = try box(f,0,0,&a)
            let first = try c.bind(polynomials:[c.polynomials.variable(0,using:&a),c.polynomials.zero(using:&a),c.polynomials.zero(using:&a),c.polynomials.constant(f.integer(1,using:&a),using:&a)],domains:[line],using:&a)
            let second = try s.bind(polynomials:[s.polynomials.variable(0,using:&a),s.polynomials.variable(1,using:&a),s.polynomials.zero(using:&a),s.polynomials.constant(f.integer(1,using:&a),using:&a)],domains:[line,singleton],using:&a)
            relation = try resolve(compile(bind(first,domain,&a),bind(second,domain,&a),.curveSurface,domain,&a),domain,&a)
        }
        var query = try ledger()
        try require(relation.components.count == 1)
        try member([100,100,0],relation,true,&query); try member([100,100,1],relation,false,&query)
        try require(relation.original.first.original.variableCount == 1 && relation.original.second.original.polynomials.count == 4)
        print("PASS: unbounded/singleton retained source and exact tuples")
    }
}

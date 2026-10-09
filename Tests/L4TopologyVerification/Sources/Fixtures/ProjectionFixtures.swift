import L0
import L1
import L2
import L3
import L4

public enum ProjectionFixtures {
    typealias Base = ExactRationalScalarDomain
    typealias Field = ExactAlgebraicScalarDomain<Base>
    typealias Cells = ExactRealCellDomain<Base>
    typealias Topology = ExactRealTopology<Base>
    static func ledger() throws -> ExactScalarLedger { .init(limits: try .init(work: 200_000_000, storageBytes: 700_000_000, valueDepth: 400, coefficientDepth: 400)) }
    static func require(_ condition: Bool) throws { if !condition { throw ExactRealTopologyFailure.invalidCoverage } }
    static func cap(_ generated: Int = 20_000, _ closures: Int = 1000, _ pieces: Int = 20_000, _ components: Int = 1000) throws -> ExactRealTopologyLimits {
        try .init(maximumGeneratedCells: generated, maximumRootsPerStack: 100, maximumClosures: closures, maximumAttachmentPieces: pieces, maximumComponents: components)
    }
    static func source(_ mode: Int, _ a: inout ExactScalarLedger) throws -> ExactRealCellSelection<Base> {
        let f = try Field.base(field: Base(), maximumExtensionLevel: 10, using: &a)
        let cells = try Cells(field: f, variableCount: 2, using: &a), p = cells.polynomials
        let x = try p.variable(0, using: &a), q = try p.variable(1, using: &a)
        let one = try p.constant(f.integer(1, using: &a), using: &a)
        let law: ExactPolynomial<Field>
        switch mode {
        case 0: law = try p.subtracting(p.multiplying(q,q,using:&a),one,using:&a)
        case 1: law = try p.subtracting(p.multiplying(x,q,using:&a),one,using:&a)
        case 2: law = x
        case 3: law = try p.subtracting(p.multiplying(q,q,using:&a),x,using:&a)
        default: law = one
        }
        let roots = try ExactRealRootDomain(field:f,using:&a)
        let line = try roots.domain(lower:.negativeInfinity,upper:.positiveInfinity,using:&a)
        let original = try cells.bind(polynomials:[law],domains:[line,line],using:&a)
        let predicate = try cells.predicate(instructions:[.sign(polynomial:0,relation:.equal)],for:original,using:&a)
        let partition = try cells.decompose(original,limits:.init(maximumStoredCells:2000,maximumRootsPerStack:100),using:&a)
        return try cells.select(partition,matching:predicate,using:&a)
    }
    static func project<P: ExactRealProjectionProducing<Base>, A: ExactScalarAdmission & ~Copyable>(
        _ selection: ExactRealCellSelection<Base>, _ k: Int, _ provider: P, _ a: inout A) throws -> ExactRealProjection<Base> {
        try provider.project(selection,retainingPrefix:k,cellLimits:.init(maximumStoredCells:2000,maximumRootsPerStack:100),topologyLimits:cap(),using:&a)
    }
    static func member(_ value: Int, _ result: ExactRealProjection<Base>, _ expected: Bool, _ a: inout ExactScalarLedger) throws {
        let cells = try Cells(retaining:result.selection.partition.source,using:&a)
        let f = try cells.coefficientField(of:result.selection.partition.source,using:&a)
        let point = try cells.point(field:f,coordinates:[f.integer(value,using:&a)],using:&a)
        let cell = try cells.locate(point,in:result.selection.partition,limits:.init(maximumRoots:100),using:&a)
        try require((cell.map { result.selection.cells.contains($0) } ?? false) == expected)
    }
    public static func geometryIndependentProjection() throws {
        let topology = Topology(cells:Cells.self)
        for mode in 0...4 {
            var a = try ledger()
            let selected = try source(mode,&a)
            let result = try project(selected,1,topology,&a)
            try require(result.coordinateCount == 1)
            switch mode {
            case 0:
                try require(selected.cells.count == 2 && result.selection.cells.count == 1 && result.components.count == 1)
                try require(result.liftedCells(forProjectedOrdinal:0)?.count == 2)
                try member(0,result,true,&a); try member(100,result,true,&a)
            case 1:
                try require(result.components.count == 2)
                try member(0,result,false,&a); try member(-1,result,true,&a); try member(1,result,true,&a)
                // q escapes to infinity at x=0. Projection must not invent that point.
            case 2:
                try require(result.components.count == 1 && result.selection.cells.count == 1)
                try require(result.selection.cells[0].dimension == 0 && selected.cells[0].dimension == 1)
                try member(0,result,true,&a); try member(1,result,false,&a)
            case 3:
                try require(result.components.count == 1)
                try member(-1,result,false,&a); try member(0,result,true,&a); try member(4,result,true,&a)
            default:
                try require(result.selection.cells.isEmpty && result.components.count == 0 && result.selection.partition.storedCellCount > 0)
                try member(0,result,false,&a)
            }
            let point = try project(selected,0,topology,&a)
            try require(point.coordinateCount == 0 && point.components.count == (mode == 4 ? 0:1))
            if mode == 0 {
                let full = try project(selected,2,topology,&a)
                try require(full.components.count == 2)
                let view = result.liftedCells(forProjectedOrdinal:0)!
                try require(view.original.cells.count == 2 && view.allSatisfy { $0.dimension == 1 })
            }
            try require(result.liftedCells(forProjectedOrdinal:-1) == nil && result.liftedCells(forProjectedOrdinal:result.selection.cells.count) == nil)
            print("PASS B2 projection case=\(mode) lifted=\(selected.cells.count) projected=\(result.selection.cells.count) components=\(result.components.count) work=\(a.work)")
        }
    }
    public static func failures() throws {
        var setup = try ledger(); let selected = try source(0,&setup), topology = Topology(cells:Cells.self)
        var measured = try ledger(); _ = try project(selected,1,topology,&measured)
        let work = measured.work, bytes = measured.storageBytes, vd = measured.valueDepth, cd = measured.coefficientDepth
        var exact = ExactScalarLedger(limits:try .init(work:work,storageBytes:bytes,valueDepth:vd,coefficientDepth:cd))
        _ = try project(selected,1,topology,&exact)
        for axis in 0..<4 {
            if axis == 2 && vd == 0 || axis == 3 && cd == 0 { continue }
            var limited = ExactScalarLedger(limits:try .init(work:axis == 0 ? work-1:work,storageBytes:axis == 1 ? bytes-1:bytes,valueDepth:axis == 2 ? vd-1:vd,coefficientDepth:axis == 3 ? cd-1:cd))
            var failed = false
            do { _ = try project(selected,1,topology,&limited) } catch { failed = true }
            try require(failed)
        }
        var cancelled = try ledger(); cancelled.cancel()
        do { _ = try project(selected,1,topology,&cancelled); throw ExactRealTopologyFailure.invalidCoverage }
        catch ExactRealTopologyFailure.scalar(.cancelled) {}
        for prefix in [-1,3] {
            do { _ = try project(selected,prefix,topology,&setup); throw ExactRealTopologyFailure.invalidCoverage }
            catch ExactRealTopologyFailure.invalidDefinition {}
        }
        for limits in [try cap(0),try cap(20_000,0),try cap(20_000,1000,20_000,0)] {
            var failed = false
            do { _ = try topology.project(selected,retainingPrefix:1,cellLimits:.init(maximumStoredCells:2000,maximumRootsPerStack:100),topologyLimits:limits,using:&setup) } catch { failed = true }
            try require(failed)
        }
        print("PASS B2 projection exact work/storage/depth caps, invalid prefix, topology caps and cancel")
    }
}

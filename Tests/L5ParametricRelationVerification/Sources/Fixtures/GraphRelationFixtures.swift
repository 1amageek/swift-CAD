import L0
import L1
import L2
import L3
import L4
import L5

public enum GraphRelationFixtures {
    typealias Base = RelationFixtures.Base
    typealias Field = RelationFixtures.Field
    typealias Cells = RelationFixtures.Cells
    static var domain: RelationFixtures.Domain { RelationFixtures.domain }
    static func require(_ condition: Bool) throws { if !condition { throw ExactParametricRelationFailure.invalidEvidence } }
    static func pair(_ mode: Int, _ a: inout ExactScalarLedger) throws -> ExactParametricGraphRelationSource<Base> {
        let f = try RelationFixtures.field(&a), ssi = mode == 5 || mode == 8
        let lc = try Cells(field:f,variableCount:ssi ? 3:1,using:&a)
        let rc = try Cells(field:f,variableCount:mode == 5 || mode == 0 ? 2:3,using:&a)
        let l = lc.polynomials, r = rc.polynomials
        let lz = try l.zero(using:&a), rz = try r.zero(using:&a)
        let lo = try l.constant(f.integer(1,using:&a),using:&a), ro = try r.constant(f.integer(1,using:&a),using:&a)
        let line = try ExactRealRootDomain(field:f,using:&a).domain(lower:.negativeInfinity,upper:.positiveInfinity,using:&a)
        let box = try RelationFixtures.box(f,-1,1,&a), point = try RelationFixtures.box(f,0,0,&a)
        var left = [lz,lz,try l.variable(0,using:&a),lo]
        var right = [try r.variable(0,using:&a),try r.variable(1,using:&a),rz,ro]
        var ld = [box], rd = mode == 0 ? [box,box]:[box,box,line]
        var li: [ExactRealCellInstruction] = [.literal(true)], ri: [ExactRealCellInstruction] = [.literal(true)]
        if ssi {
            left = [try l.variable(0,using:&a),try l.variable(1,using:&a),lz,lo]
            let q = try l.variable(2,using:&a)
            left.append(try l.subtracting(l.multiplying(q,q,using:&a),lo,using:&a))
            li = [.sign(polynomial:4,relation:.equal)]
            ld = mode == 8 ? [point,point,line]:[box,point,line]
            if mode == 8 {
                let rq = try r.variable(2,using:&a)
                right.append(try r.subtracting(r.multiplying(rq,rq,using:&a),ro,using:&a))
                ri = [.sign(polynomial:4,relation:.equal)]
                rd = [point,point,line]
            } else { rd = [box,point] }
        } else if mode != 0 {
            let q = try r.variable(2,using:&a)
            if mode == 3 { ri = [.literal(true)] }
            else {
                right.append(try r.subtracting(r.multiplying(q,q,using:&a),ro,using:&a))
                ri = [.sign(polynomial:4,relation:.equal)]
                if mode == 2 || mode == 7 { right.append(q); ri.append(.sign(polynomial:5,relation:.greater)); ri.append(.and) }
                if mode == 4 { ri = [.literal(false)] }
                if mode == 6 { right[3] = rz }
                if mode == 7 {
                    // Exact positive unit-normal offset by 1/4: XYZ/W=(u*q,v*q,1/4)/q.
                    right[0] = try r.multiplying(right[0],q,using:&a)
                    right[1] = try r.multiplying(right[1],q,using:&a)
                    right[2] = try r.constant(f.dividing(f.integer(1,using:&a),f.integer(4,using:&a),using:&a),using:&a)
                    right[3] = q
                }
            }
        }
        let ls = try lc.bind(polynomials:left,domains:ld,using:&a), rs = try rc.bind(polynomials:right,domains:rd,using:&a)
        let lp = try lc.predicate(instructions:li,for:ls,using:&a), rp = try rc.predicate(instructions:ri,for:rs,using:&a)
        let first = try domain.graph(from:lp,parameterCount:ssi ? 2:1,using:&a)
        let second = try domain.graph(from:rp,parameterCount:2,using:&a)
        return try domain.compile(kind:ssi ? .surfaceSurface:.curveSurface,first:first,second:second,using:&a)
    }
    static func resolve<A: ExactScalarAdmission & ~Copyable>(_ source: ExactParametricGraphRelationSource<Base>, _ a: inout A) throws -> ExactParametricGraphRelation<Base> {
        try domain.resolve(source,cellLimits:.init(maximumStoredCells:20_000,maximumRootsPerStack:100),
            topologyLimits:.init(maximumGeneratedCells:20_000,maximumRootsPerStack:100,maximumClosures:1000,maximumAttachmentPieces:20_000,maximumComponents:1000),using:&a)
    }
    public static func graphRelations(modes: Range<Int> = 0..<9) throws {
        for mode in modes {
            var a = try RelationFixtures.ledger()
            let compiled = try pair(mode,&a), relation = try resolve(compiled,&a)
            try require(relation.selection.partition.source.variableCount == (mode == 5 || mode == 8 ? 4:3))
            if mode == 4 || mode == 6 {
                try require(relation.selection.cells.isEmpty && relation.components.count == 0)
                try require(relation.projection.original.partition.storedCellCount > 0)
            } else {
                try require(relation.components.count == 1)
                try require(relation.selection.cells.allSatisfy { $0.dimension <= (mode == 5 ? 1:0) })
                if mode == 5 { try require(relation.selection.cells.contains { $0.dimension == 1 }) }
                let count = relation.projection.liftedCells(forProjectedOrdinal:0)!.count
                if mode == 8 { try require(count == 4) }
                else if mode == 1 || mode == 5 { try require(count == 2) }
                else { try require(count == 1) }
                if mode == 3 { try require(relation.projection.original.cells.allSatisfy { $0.dimension == 1 }) }
                if mode == 5 { try require(compiled.firstCoordinates == [0,1,4] && compiled.secondCoordinates == [2,3]) }
                if mode == 8 { try require(compiled.firstCoordinates == [0,1,4] && compiled.secondCoordinates == [2,3,5]) }
                if mode == 1 { try require(compiled.firstCoordinates == [0] && compiled.secondCoordinates == [1,2,3]) }
            }
            if mode == 7 {
                try require(compiled.guardDivisions.count == 2 && compiled.guardRemainders.count == 1)
                let lifted = try Cells(retaining:compiled.predicate.source,using:&a), p = lifted.polynomials
                for witness in compiled.guardDivisions {
                    let guardIndex = witness.guardIndex == 0 ? compiled.firstLawIndices[3] : compiled.secondLawIndices[3]
                    let guardLaw = compiled.predicate.source.polynomials[guardIndex]
                    try require(p.isZero(witness.division.remainder,using:&a))
                    try require(p.equals(witness.dividend,p.multiplying(guardLaw,witness.division.quotient,using:&a),using:&a))
                }
            }
            for witness in compiled.guardRemainders {
                let lifted = try Cells(retaining:compiled.predicate.source,using:&a), p = lifted.polynomials
                let w = compiled.predicate.source.polynomials[witness.nonzeroGuardIndex == 0 ? compiled.firstLawIndices[3] : compiled.secondLawIndices[3]]
                let g = compiled.predicate.source.polynomials[witness.equalityGuardIndex]
                try require(p.equals(witness.dividend,p.multiplying(w,witness.equation,using:&a),using:&a))
                try require(p.equals(witness.dividend,p.adding(p.multiplying(g,witness.division.quotient,using:&a),witness.division.remainder,using:&a),using:&a))
            }
            let query = try Cells(retaining:relation.selection.partition.source,using:&a)
            let qf = try query.coefficientField(of:relation.selection.partition.source,using:&a)
            let zero = try qf.integer(0,using:&a), one = try qf.integer(1,using:&a)
            var tuple = [Field.Value](repeating:zero,count:compiled.parameterCount)
            if mode == 7 { tuple[0] = try qf.dividing(one,qf.integer(4,using:&a),using:&a) }
            if mode == 5 { tuple[0] = one; tuple[2] = one }
            let point = try query.point(field:qf,coordinates:tuple,using:&a)
            let located = try query.locate(point,in:relation.selection.partition,limits:.init(maximumRoots:100),using:&a)
            try require((located.map { relation.selection.cells.contains($0) } ?? false) == (mode != 4 && mode != 6))
            if mode == 7 || mode == 5 {
                if mode == 7 { tuple[0] = zero } else { tuple[2] = try qf.negated(one,using:&a) }
                let excluded = try query.point(field:qf,coordinates:tuple,using:&a)
                let cell = try query.locate(excluded,in:relation.selection.partition,limits:.init(maximumRoots:100),using:&a)
                try require(!(cell.map { relation.selection.cells.contains($0) } ?? false))
            }
            print("PASS B2 L5 graph case=\(mode) lifted=\(relation.projection.original.cells.count) projected=\(relation.selection.cells.count) components=\(relation.components.count) work=\(a.work) storage=\(a.storageBytes)")
        }
    }
    public static func failuresAndLifetime() throws {
        var setup = try RelationFixtures.ledger()
        let original = try pair(1,&setup)
        var measured = try RelationFixtures.ledger()
        let view: ExactRealProjectionLifts<Base>
        do {
            let retained = try resolve(original,&measured)
            view = retained.projection.liftedCells(forProjectedOrdinal:0)!
        }
        let work = measured.work, bytes = measured.storageBytes, vd = measured.valueDepth, cd = measured.coefficientDepth
        var exact = ExactScalarLedger(limits:try .init(work:work,storageBytes:bytes,valueDepth:vd,coefficientDepth:cd))
        _ = try resolve(original,&exact)
        for axis in 0..<4 {
            if axis == 2 && vd == 0 || axis == 3 && cd == 0 { continue }
            var limited = ExactScalarLedger(limits:try .init(work:axis == 0 ? work-1:work,storageBytes:axis == 1 ? bytes-1:bytes,valueDepth:axis == 2 ? vd-1:vd,coefficientDepth:axis == 3 ? cd-1:cd))
            var failed = false
            do { _ = try resolve(original,&limited) }
            catch {
                if case .resourceLimit(let resource) = FailureFixtures.scalar(error) {
                    failed = resource == (axis == 0 ? .work : axis == 1 ? .storage : axis == 2 ? .valueDepth : .coefficientDepth)
                }
            }
            try require(failed)
        }
        var counter = try GraphCheckpointAdmission(); _ = try resolve(original,&counter)
        var final = try GraphCheckpointAdmission(stop:counter.checkpoints)
        do { _ = try resolve(original,&final); throw ExactParametricRelationFailure.invalidEvidence }
        catch ExactParametricRelationFailure.scalar(.cancelled) {}
        var cancelled = try RelationFixtures.ledger(); cancelled.cancel()
        do { _ = try resolve(original,&cancelled); throw ExactParametricRelationFailure.invalidEvidence }
        catch ExactParametricRelationFailure.scalar(.cancelled) {}
        for count in [0,3] {
            do { _ = try domain.graph(from:original.first.predicate,parameterCount:count,using:&setup); throw ExactParametricRelationFailure.invalidEvidence }
            catch ExactParametricRelationFailure.invalidMap {}
        }
        do { _ = try domain.compile(kind:.surfaceSurface,first:original.first,second:original.second,using:&setup); throw ExactParametricRelationFailure.invalidEvidence }
        catch ExactParametricRelationFailure.invalidKind {}
        let foreign = try pair(1,&setup)
        do { _ = try domain.compile(kind:.curveSurface,first:original.first,second:foreign.second,using:&setup); throw ExactParametricRelationFailure.invalidEvidence }
        catch ExactParametricRelationFailure.scalar(.incompatibleDomain) {}
        let offset = try pair(7,&setup)
        for negated in [false,true] {
            let cells = try Cells(retaining:offset.second.predicate.source,using:&setup)
            let program: [ExactRealCellInstruction] = negated
                ? [.sign(polynomial:4,relation:.equal),.not,.sign(polynomial:5,relation:.greater),.and]
                : [.sign(polynomial:4,relation:.equal),.literal(true),.or,.sign(polynomial:5,relation:.greater),.and]
            let predicate = try cells.predicate(instructions:program,for:offset.second.predicate.source,using:&setup)
            let graph = try domain.graph(from:predicate,parameterCount:2,using:&setup)
            let compiled = try domain.compile(kind:.curveSurface,first:offset.first,second:graph,using:&setup)
            try require(compiled.guardRemainders.isEmpty)
            let combined = try Cells(retaining:compiled.predicate.source,using:&setup), p = combined.polynomials
            try require(p.equals(compiled.rawEquations[2],compiled.predicate.source.polynomials[compiled.equationIndices.lowerBound+2],using:&setup))
            let f = try combined.coefficientField(of:compiled.predicate.source,using:&setup)
            let zero = try f.integer(0,using:&setup), two = try f.integer(2,using:&setup)
            let t = try f.dividing(f.integer(1,using:&setup),f.integer(8,using:&setup),using:&setup)
            let value = try p.evaluated(compiled.rawEquations[2],at:[t,zero,zero,two],using:&setup).value
            try require(f.sign(of:value,using:&setup) == .zero)
        }
        // A view retains its originating partition after the query result is released.
        try require(view.count == 2 && view.allSatisfy { $0.source.variableCount == 4 })
        print("PASS B2 L5 original owners, coefficient compatibility, role validation, exact caps and entry/final cancellation")
    }
}

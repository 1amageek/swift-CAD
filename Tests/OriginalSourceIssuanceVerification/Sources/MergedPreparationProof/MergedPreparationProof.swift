import CADCore
import struct CADGeometry.ScalarInterval
import struct CADGeometry.BSplineCurve3D
import struct CADGeometry.BSplineSurface3D
import struct CADGeometry.DefaultCurveSurfaceIntersector
import struct CADGeometry.DefaultSurfaceSurfaceIntersector
import struct CADGeometry.SurfaceParameterBox
import L0
import L1
import L2
import L3
import L4
import L5
import DI0
import SourceIssuer
import DI
import SourceGeometryAdapters

@main
struct NativeConsumerProof {
    typealias Field = DefaultNativeExactRelationResolver.Field
    enum Failure: Error { case incorrectEvidence }
    static func require(_ value: Bool) throws { if !value { throw Failure.incorrectEvidence } }
    static func ledger(work: Int = 20_000_000, storage: Int = 134_217_728) throws -> ExactScalarLedger {
        .init(limits: try .init(work: work, storageBytes: storage, valueDepth: 32, coefficientDepth: 32))
    }
    static func field(_ admission: inout ExactScalarLedger) throws -> Field {
        try .base(field: .init(), maximumExtensionLevel: 4, using: &admission)
    }
    static func curve() -> BSplineCurve3D {
        .init(degree: 1, knots: [0,0,1,1],
            controlPoints: [.init(x:0,y:0,z:0), .init(x:1,y:0,z:0)], weights:[1,2])
    }
    static func surface() -> BSplineSurface3D {
        .init(uDegree:1,vDegree:1,uKnots:[0,0,1,1],vKnots:[0,0,1,1],
            controlPoints:[[.init(x:0,y:0,z:0),.init(x:1,y:0,z:0)],
                [.init(x:0,y:1,z:0),.init(x:1,y:1,z:1)]],weights:[[1,2],[3,6]])
    }
    static func interval(_ value: ExactRealRootInterval<Field.Value>, lower: Double, upper: Double,
        field: Field, using admission: inout ExactScalarLedger) throws {
        guard case .finite(let lo) = value.lower, case .finite(let hi) = value.upper else {
            throw Failure.incorrectEvidence
        }
        try require(!value.isEmpty && value.includesLower && value.includesUpper)
        try require(try field.compare(lo,field.binary64(exactly:lower,using:&admission),using:&admission) == .equal)
        try require(try field.compare(hi,field.binary64(exactly:upper,using:&admission),using:&admission) == .equal)
    }
    static func main() throws {
        let resolver = DefaultNativeExactRelationResolver()
        var a = try ledger(); let f = try field(&a)
        let bound = try resolver.curveMap(curve(),selected:nil,field:f,tolerance:.standard,degree:3,using:&a)
        guard case .curve(let law) = bound.map.sourceLaw else { throw Failure.incorrectEvidence }
        try require(bound.cover.space.source.owns(law.chart))
        let covered = try resolver.curveMap(curve(),selected:try .init(lower:2,upper:3),
            field:f,tolerance:.standard,degree:3,using:&a)
        try require(covered.map.map.original.domains[0].isEmpty)
        print("PASS one original binding retains both issued source law and complete domain cover, including exclusion")
        var original = curve()
        let prepared = try resolver.curveMap(original,selected:try .init(lower:-1,upper:0.5),
            field:f,tolerance:.standard,degree:3,using:&a).map
        guard case .curve(let receipt) = prepared.sourceLaw else { throw Failure.incorrectEvidence }
        original.controlPoints[1].x = 99; original.weights[1] = 10; original.knots[2] = 4
        try require(receipt.source.original.controlPoints[1].x == 1 && receipt.source.original.weights[1] == 2)
        try require(receipt.source.original.knots[2] == 1)
        let cells = try ExactRealCellDomain<ExactRationalScalarDomain>(retaining:prepared.map.original,using:&a)
        let r = cells.polynomials, t = try r.variable(0,using:&a)
        let zero = try r.zero(using:&a), one = try r.constant(f.integer(1,using:&a),using:&a)
        let expected = [try r.scaled(t,by:f.integer(2,using:&a),using:&a),zero,zero,
            try r.adding(one,t,using:&a)]
        for axis in 0..<4 {
            try require(try r.equals(prepared.map.original.polynomials[axis],expected[axis],using:&a))
            try require(try r.equals(prepared.map.original.polynomials[axis],
                r.importing(receipt.homogeneous[axis],using:&a),using:&a))
        }
        try interval(prepared.map.original.domains[0],lower:0,upper:0.5,field:f,using:&a)
        print("PASS existing curve preparation uses common original law, all coefficients, retained COW and closed clipping")

        let singleton = try resolver.curveMap(curve(),selected:try .init(lower:1,upper:1),
            field:f,tolerance:.standard,degree:3,using:&a).map
        try interval(singleton.map.original.domains[0],lower:1,upper:1,field:f,using:&a)
        let outside = try resolver.curveMap(curve(),selected:try .init(lower:2,upper:3),
            field:f,tolerance:.standard,degree:3,using:&a).map
        try require(outside.map.original.domains[0].isEmpty)
        let full = try resolver.curveMap(curve(),selected:nil,field:f,tolerance:.standard,degree:3,using:&a).map
        try interval(full.map.original.domains[0],lower:0,upper:1,field:f,using:&a)
        print("PASS native bounds, singleton closed endpoint and disjoint selected domain remain distinct")

        let tensor = try resolver.surfaceMap(surface(),selected:try .init(u:.init(lower:0.25,upper:2),
            v:.init(lower:-1,upper:0.75)),field:f,tolerance:.standard,degree:3,using:&a).map
        guard case .surface(let source) = tensor.sourceLaw else { throw Failure.incorrectEvidence }
        let tr = try ExactRealCellDomain<ExactRationalScalarDomain>(retaining:tensor.map.original,using:&a).polynomials
        let u = try tr.variable(0,using:&a), v = try tr.variable(1,using:&a)
        let unit = try tr.constant(f.integer(1,using:&a),using:&a)
        let u2 = try tr.scaled(u,by:f.integer(2,using:&a),using:&a)
        let v3 = try tr.scaled(v,by:f.integer(3,using:&a),using:&a)
        let wu = try tr.adding(unit,u,using:&a)
        let wv = try tr.adding(unit,tr.scaled(v,by:f.integer(2,using:&a),using:&a),using:&a)
        for (axis,left,right) in [(0,u2,wv),(1,wu,v3),(2,u2,v3),(3,wu,wv)] {
            try require(try tr.equals(tensor.map.original.polynomials[axis],
                tr.multiplying(left,right,using:&a),using:&a))
            try require(try tr.equals(tensor.map.original.polynomials[axis],
                tr.importing(source.homogeneous[axis],using:&a),using:&a))
        }
        try interval(tensor.map.original.domains[0],lower:0.25,upper:1,field:f,using:&a)
        try interval(tensor.map.original.domains[1],lower:0,upper:0.75,field:f,using:&a)
        print("PASS existing surface preparation transfers weighted four tensor laws and both clipped coordinates")
        try failures(resolver)
    }
    struct CheckpointAdmission: ~Copyable, ExactScalarAdmission {
        var base: ExactScalarLedger
        var checkpoints = 0
        let cancelAt: Int?
        init(cancelAt: Int? = nil) throws {
            base = try NativeConsumerProof.ledger(); self.cancelAt = cancelAt
        }
        mutating func checkpoint() throws(ExactScalarFailure) {
            checkpoints += 1
            if checkpoints == cancelAt { throw .cancelled }
            try base.checkpoint()
        }
        mutating func consumeWork(_ units: Int) throws(ExactScalarFailure) {
            try checkpoint(); try base.consumeWork(units)
        }
        mutating func retainStorage(bytes: Int) throws(ExactScalarFailure) {
            try checkpoint(); try base.retainStorage(bytes: bytes)
        }
        mutating func visitCell(axis: ExactScalarRootAxis, depth: Int) throws(ExactScalarFailure) {
            try checkpoint(); try base.visitCell(axis: axis, depth: depth)
        }
        mutating func admitDepth(value: Int, coefficient: Int) throws(ExactScalarFailure) {
            try checkpoint(); try base.admitDepth(value: value, coefficient: coefficient)
        }
    }
    static func failures(_ resolver: DefaultNativeExactRelationResolver) throws {
        var a = try ledger(); let f = try field(&a)
        do { _ = try resolver.curveMap(curve(),selected:nil,field:f,tolerance:.standard,degree:0,using:&a)
            throw Failure.incorrectEvidence }
        catch NativeExactRelationFailure.invalidDegree {}
        var periodic = curve(); periodic.isPeriodic = true
        do { _ = try resolver.curveMap(periodic,selected:nil,field:f,tolerance:.standard,degree:3,using:&a)
            throw Failure.incorrectEvidence }
        catch NativeExactRelationFailure.unsupportedCoverage {}
        let multi = BSplineCurve3D(degree:1,knots:[0,0,1,2,2],
            controlPoints:[.init(x:0,y:0,z:0),.init(x:1,y:0,z:0),.init(x:2,y:0,z:0)],weights:[1,1,1])
        do { _ = try resolver.curveMap(multi,selected:nil,field:f,tolerance:.standard,degree:3,using:&a)
            throw Failure.incorrectEvidence }
        catch NativeExactRelationFailure.unsupportedCoverage {}
        var invalid = curve(); invalid.weights[0] = 0
        do { _ = try resolver.curveMap(invalid,selected:nil,field:f,tolerance:.standard,degree:3,using:&a)
            throw Failure.incorrectEvidence }
        catch {
            if error is Failure { throw error }
            guard case .geometry = NativeExactRelationFailure.preserving(error) else { throw error }
        }
        var malformed = surface(); malformed.controlPoints[1].removeLast()
        do { _ = try resolver.surfaceMap(malformed,selected:nil,field:f,tolerance:.standard,degree:3,using:&a)
            throw Failure.incorrectEvidence }
        catch {
            if error is Failure { throw error }
            guard case .geometry = NativeExactRelationFailure.preserving(error) else { throw error }
        }
        print("PASS invalid family inputs, degree and existing periodic/multispan coverage fail explicitly")

        var measured = try ledger()
        _ = try resolver.curveMap(curve(),selected:nil,field:f,tolerance:.standard,degree:3,using:&measured)
        let work = measured.work, bytes = measured.storageBytes
        var exact = try ledger(work:work,storage:bytes)
        _ = try resolver.curveMap(curve(),selected:nil,field:f,tolerance:.standard,degree:3,using:&exact)
        for limit in 0..<2 {
            var limited = try ledger(work:limit == 0 ? work-1 : work,storage:limit == 0 ? bytes : bytes-1)
            do { _ = try resolver.curveMap(curve(),selected:nil,field:f,tolerance:.standard,degree:3,using:&limited)
                throw Failure.incorrectEvidence }
            catch {
                switch NativeExactRelationFailure.preserving(error) {
                case .scalar(.resourceLimit(.work)) where limit == 0: break
                case .relation(.cell(.scalar(.resourceLimit(.work)))) where limit == 0: break
                case .scalar(.resourceLimit(.storage)) where limit == 1: break
                case .relation(.cell(.scalar(.resourceLimit(.storage)))) where limit == 1: break
                default: throw error
                }
            }
        }
        var cancelled = try ledger(); cancelled.cancel()
        do { _ = try resolver.curveMap(curve(),selected:nil,field:f,tolerance:.standard,degree:3,using:&cancelled)
            throw Failure.incorrectEvidence }
        catch { guard case .scalar(.cancelled) = NativeExactRelationFailure.preserving(error) else { throw error } }
        var observed = try CheckpointAdmission()
        _ = try resolver.curveMap(curve(),selected:nil,field:f,tolerance:.standard,degree:3,using:&observed)
        var finalCancelled = try CheckpointAdmission(cancelAt:observed.checkpoints)
        do { _ = try resolver.curveMap(curve(),selected:nil,field:f,tolerance:.standard,degree:3,using:&finalCancelled)
            throw Failure.incorrectEvidence }
        catch { guard case .scalar(.cancelled) = NativeExactRelationFailure.preserving(error) else { throw error } }
        try require(finalCancelled.checkpoints == observed.checkpoints)
        // Nested family/polynomial failures preserve the public scalar failure.
        guard case .scalar(.cancelled) = NativeExactRelationFailure.preserving(
            OriginalSourceIssuanceFailure.polynomial(.scalar(.cancelled))) else { throw Failure.incorrectEvidence }
        print("PASS same-ledger exact and independently insufficient budgets, entry/final cancellation and typed failure preservation")
        print("METRIC prepared weighted curve work=\(work) storageBytes=\(bytes)")
    }
}

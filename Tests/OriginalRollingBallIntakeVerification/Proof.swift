import CADCore
@testable import CADGeometry
@testable import RollingBallAdapters
import struct RollingBallAdapters.RollingBallBlendSurface3D

@main
struct RollingBallProof {
    typealias Source = OriginalRollingBallSnapshot<BSplineCurve3D>
    typealias Family = OriginalFiniteNativeRollingBallGraphs<Source>
    typealias Field = OriginalExactScalarDomain
    struct Admission: ~Copyable, ExactScalarAdmission {
        var ledger: ExactScalarLedger
        var storageCalls = 0
        let cancelAtStorage: Int?
        init(work: Int = 300_000_000, storage: Int = 1_073_741_824, cancelAtStorage: Int? = nil) throws {
            ledger = .init(limits: try .init(work: work, storageBytes: storage, valueDepth: 32, coefficientDepth: 32))
            self.cancelAtStorage = cancelAtStorage
        }
        mutating func checkpoint() throws(ExactScalarFailure) { try ledger.checkpoint() }
        mutating func consumeWork(_ units: Int) throws(ExactScalarFailure) { try ledger.consumeWork(units) }
        mutating func retainStorage(bytes: Int) throws(ExactScalarFailure) {
            try ledger.retainStorage(bytes: bytes); storageCalls += 1
            if storageCalls == cancelAtStorage { ledger.cancel() }
        }
        mutating func visitCell(axis: ExactScalarRootAxis, depth: Int) throws(ExactScalarFailure) { try ledger.visitCell(axis: axis, depth: depth) }
        mutating func admitDepth(value: Int, coefficient: Int) throws(ExactScalarFailure) { try ledger.admitDepth(value: value, coefficient: coefficient) }
    }
    static func require(_ condition: Bool, line: Int = #line) throws {
        guard condition else { print("FAIL rolling-ball line \(line)"); throw ExactScalarFailure.invalidEvidence }
    }
    static func rail(x: Double, y: Double, knot: Double, weight: Double = 1, quadratic: Bool = false) -> Curve3D {
        if quadratic {
            return .bSpline(.init(degree:2,knots:[0,0,0,knot,1,1,1],
                controlPoints:[.init(x:x,y:y,z:0),.init(x:x,y:y,z:knot/2),.init(x:x,y:y,z:(knot+1)/2),.init(x:x,y:y,z:1)],
                weights:[weight,weight,weight,weight]))
        }
        return .bSpline(.init(degree: 1, knots: [0,0,knot,1,1],
            controlPoints: [.init(x:x,y:y,z:0),.init(x:x,y:y,z:knot),.init(x:x,y:y,z:1)], weights: [weight,weight,weight]))
    }
    static func shape(degenerate: Bool = false, wrongRadius: Bool = false) -> RollingBallBlendSurface3D {
        .init(centerSpine: rail(x:0,y:0,knot:0.5), firstContact: rail(x:3,y:4,knot:0.5,weight:2,quadratic:true),
            secondContact: rail(x:3,y:degenerate ? 4 : -4,knot:0.75), radius: wrongRadius ? 6 : 5, tolerance: .standard)
    }
    static func family<A: ExactScalarAdmission & ~Copyable>(_ shape: RollingBallBlendSurface3D,
        using a: inout A) throws -> Family {
        let limits = try OriginalSourceIssuanceLimits(remainingSourceDepth: 1)
        let source = try DefaultOriginalSourceBindingIssuer(provider: OriginalRollingBallSnapshotProvider(
            child: OriginalNativeCurveFamilySnapshotProvider(tolerance: .standard))).bind(shape,limits:limits,using:&a)
        let f = try Field(maximumValueDepth:32,maximumCoefficientDepth:32,using:&a)
        let native = DefaultOriginalFiniteBSplineChartPreparer<BSplineCurve3D>()
        let c = try native.prepare(source:source.original.originalCenter,field:f,maximumCharts:2,limits:limits,using:&a)
        let x = try native.prepare(source:source.original.originalFirstContact,field:f,maximumCharts:2,limits:limits,using:&a)
        let y = try native.prepare(source:source.original.originalSecondContact,field:f,maximumCharts:2,limits:limits,using:&a)
        return try DefaultOriginalFiniteNativeRollingBallGraphPreparer<Source>().prepare(source:source,
            center:c,first:x,second:y,maximumCharts:8,limits:limits,using:&a)
    }
    static func tuple<A: ExactScalarAdmission & ~Copyable>(_ family: Family, u: Double, v: Double, using a: inout A) throws -> [Field.Value] {
        let f = family.field
        return [try f.binary64(exactly:u,using:&a),try f.binary64(exactly:v,using:&a),
            try f.integer(5,using:&a),try f.integer(5,using:&a),try f.dividing(f.integer(3,using:&a),f.integer(5,using:&a),using:&a)]
    }
    static func domainChecks(_ family: Family, using a: inout Admission) throws {
        let f = family.field
        let limits = try OriginalDomainIdentityLimits(source:.init(remainingSourceDepth:1),maximumTransportDepth:8,
            maximumCharts:8,maximumFamilies:8,maximumIdentityProofs:8)
        let issuer = DefaultOriginalNativeRollingBallDomainIssuer<Source>()
        let frame = try issuer.frame(family:family,limits:limits,using:&a)
        let full = try issuer.issue(request:frame.fullSelection(limits:limits,using:&a),family:family,limits:limits,using:&a)
        let knot = try tuple(family,u:0.5,v:0.5,using:&a)
        try require(full.liftedPositionIncidents(at:knot,limits:limits,using:&a).count == 4)
        let one = try f.integer(1,using:&a), three = try f.integer(3,using:&a)
        let third = try f.dividing(one,three,using:&a), twoThirds = try f.multiplying(third,f.integer(2,using:&a),using:&a)
        func interval(_ lower: Field.Value, _ upper: Field.Value, closed: Bool = true) throws -> ExactParameterInterval<Field.Value> {
            try .checked(field:f,lower:.finite(lower),upper:.finite(upper),includesLower:closed,includesUpper:closed,
                depth:.init(value:0,coefficient:0),using:&a)
        }
        let zero = try f.integer(0,using:&a)
        let strict = try frame.selection(intervals:[[interval(third,twoThirds,closed:false)],[interval(zero,one)]],limits:limits,using:&a)
        let selected = try issuer.issue(request:strict,family:family,limits:limits,using:&a)
        var boundary = knot; boundary[0] = third
        try require(selected.liftedPositionIncidents(at:boundary,limits:limits,using:&a).isEmpty)
        try require(selected.liftedPositionIncidents(at:knot,limits:limits,using:&a).count == 4)
        let singleton = try frame.selection(intervals:[[interval(knot[0],knot[0])],[interval(knot[1],knot[1])]],limits:limits,using:&a)
        let point = try issuer.issue(request:singleton,family:family,limits:limits,using:&a)
        try require(point.liftedPositionIncidents(at:knot,limits:limits,using:&a).count == 4)
        let disconnected = try frame.selection(intervals:[[interval(zero,third),interval(twoThirds,one)],[interval(zero,one)]],limits:limits,using:&a)
        let pieces = try issuer.issue(request:disconnected,family:family,limits:limits,using:&a)
        try require(pieces.liftedPositionIncidents(at:knot,limits:limits,using:&a).isEmpty)
        let empty = try issuer.issue(request:frame.selection(intervals:[[],[]],limits:limits,using:&a),family:family,limits:limits,using:&a)
        try require(empty.effectiveEnclosure.isEmpty && empty.liftedPositionIncidents(at:knot,limits:limits,using:&a).isEmpty)
        do { _ = try full.liftedPositionIncidents(at:[zero],limits:limits,using:&a); throw ExactScalarFailure.invalidEvidence }
        catch OriginalDomainIdentityFailure.invalidDomain {}
        let other = try self.family(shape(),using:&a)
        let foreign = try issuer.frame(family:other,limits:limits,using:&a)
        do { _ = try issuer.issue(request:foreign.fullSelection(limits:limits,using:&a),family:family,limits:limits,using:&a); throw ExactScalarFailure.invalidEvidence }
        catch OriginalDomainIdentityFailure.foreignOwner {}
        do {
            _ = try DefaultOriginalFiniteNativeRollingBallGraphPreparer<Source>().prepare(source:family.source,
                center:other.center,first:family.first,second:family.second,maximumCharts:8,limits:limits.source,using:&a)
            throw ExactScalarFailure.invalidEvidence
        } catch OriginalSourceIssuanceFailure.foreignBinding {}
        do {
            _ = try DefaultOriginalFiniteNativeRollingBallGraphPreparer<Source>().prepare(source:family.source,
                center:family.center,first:family.first,second:family.second,maximumCharts:4,limits:limits.source,using:&a)
            throw ExactScalarFailure.invalidEvidence
        } catch OriginalSourceIssuanceFailure.chartLimit {}
        let short = try OriginalDomainIdentityLimits(source:.init(remainingSourceDepth:1),maximumTransportDepth:8,
            maximumCharts:4,maximumFamilies:8,maximumIdentityProofs:8)
        do { _ = try issuer.frame(family:family,limits:short,using:&a); throw ExactScalarFailure.invalidEvidence }
        catch OriginalDomainIdentityFailure.chartLimit {}
        var cancelled = try Admission(); cancelled.ledger.cancel()
        do { _ = try empty.liftedPositionIncidents(at:knot,limits:limits,using:&cancelled); throw ExactScalarFailure.invalidEvidence }
        catch OriginalDomainIdentityFailure.scalar(.cancelled) {}
        var measured = try Admission()
        _ = try empty.liftedPositionIncidents(at:knot,limits:limits,using:&measured)
        var exact = try Admission(work:measured.ledger.work,storage:measured.ledger.storageBytes)
        try require(empty.liftedPositionIncidents(at:knot,limits:limits,using:&exact).isEmpty)
        var last = try Admission(cancelAtStorage:measured.storageCalls)
        do { _ = try empty.liftedPositionIncidents(at:knot,limits:limits,using:&last); throw ExactScalarFailure.invalidEvidence }
        catch OriginalDomainIdentityFailure.scalar(.cancelled) {}
        print("PASS rolling-ball DI: full/strict 1/3/singleton/disconnected/empty, four incidents, foreign owner, arity/chart/cancel")
    }
    static func expectedFailure(_ body: () throws -> Void, resource: ExactResource? = nil) throws {
        do { try body(); throw ExactScalarFailure.invalidEvidence }
        catch OriginalSourceIssuanceFailure.scalar(.resourceLimit(let actual)) { try require(actual == resource) }
        catch OriginalSourceIssuanceFailure.polynomial(.scalar(.resourceLimit(let actual))) { try require(actual == resource) }
        catch OriginalSourceIssuanceFailure.scalar(.cancelled) { try require(resource == nil) }
        catch OriginalSourceIssuanceFailure.polynomial(.scalar(.cancelled)) { try require(resource == nil) }
    }
    static func resources() throws {
        var measured = try Admission(); _ = try family(shape(),using:&measured)
        var exact = try Admission(work:measured.ledger.work,storage:measured.ledger.storageBytes)
        _ = try family(shape(),using:&exact)
        var work = try Admission(work:measured.ledger.work-1)
        try expectedFailure({ _ = try family(shape(),using:&work) },resource:.work)
        var storage = try Admission(storage:measured.ledger.storageBytes-1)
        try expectedFailure({ _ = try family(shape(),using:&storage) },resource:.storage)
        var entry = try Admission(); entry.ledger.cancel()
        try expectedFailure({ _ = try family(shape(),using:&entry) })
        var final = try Admission(cancelAtStorage:measured.storageCalls)
        try expectedFailure({ _ = try family(shape(),using:&final) })
        print("PASS rolling-ball source exact work/storage and one-less, entry/final callback cancel; work=\(measured.ledger.work) bytes=\(measured.ledger.storageBytes)")
    }
    static func main() throws {
        var a = try Admission()
        let original = shape(), family = try family(original,using:&a), f = family.field
        let limits = try OriginalSourceIssuanceLimits(remainingSourceDepth:1)
        try require(family.graphs.count == 5 && family.enclosingSupport.count == 2)
        try family.admitProof(limits:limits,using:&a)
        for (u,expected) in [(0.25,1),(0.5,4),(0.75,2),(1.0,1)] {
            let coordinates = try tuple(family,u:u,v:0.5,using:&a)
            var incidents = 0
            for graph in family.graphs {
                try require(graph.layout.parameters == [0,1] && graph.layout.auxiliaries == [2,3,4])
                if try graph.admits(coordinates,limits:limits,using:&a) {
                    incidents += 1
                    let d = try graph.polynomials.evaluated(graph.homogeneous[3],at:coordinates,using:&a).value
                    for axis in 0..<3 {
                        let value = try f.dividing(graph.polynomials.evaluated(graph.homogeneous[axis],at:coordinates,using:&a).value,d,using:&a)
                        let expectedValue = try f.binary64(exactly:axis == 0 ? 5 : (axis == 1 ? 0 : u),using:&a)
                        try require(f.compare(value,expectedValue,using:&a) == .equal)
                    }
                }
            }
            try require(incidents == expected)
            let point = try original.point(u:u,v:0.5)
            try require(abs(point.x-5) < 1e-12 && abs(point.y) < 1e-12 && abs(point.z-u) < 1e-12)
        }
        var negative = try tuple(family,u:0.25,v:0.5,using:&a)
        negative[4] = try f.negated(negative[4],using:&a)
        for graph in family.graphs { try require(!graph.admits(negative,limits:limits,using:&a)) }
        let degenerate = try self.family(shape(degenerate:true),using:&a)
        let invalid = try tuple(degenerate,u:0.25,v:0.5,using:&a)
        for graph in degenerate.graphs { try require(!graph.admits(invalid,limits:limits,using:&a)) }
        let wrongRadius = try self.family(shape(wrongRadius:true),using:&a)
        let wrong = try tuple(wrongRadius,u:0.25,v:0.5,using:&a)
        for graph in wrongRadius.graphs { try require(!graph.admits(wrong,limits:limits,using:&a)) }
        let varying = RollingBallBlendSurface3D(centerSpine:rail(x:0,y:0,knot:0.5),
            firstContact:.bSpline(.init(degree:1,knots:[0,0,0.5,1,1],controlPoints:[.init(x:3,y:4,z:0),.init(x:3,y:4,z:0.5),.init(x:3,y:4,z:1)],weights:[1,2,1])),
            secondContact:rail(x:3,y:-4,knot:0.75),radius:5,tolerance:.standard)
        let rational = try self.family(varying,using:&a)
        let rationalTuple = try tuple(rational,u:0.5,v:0.5,using:&a)
        var rationalIncidents = 0
        for graph in rational.graphs { if try graph.admits(rationalTuple,limits:limits,using:&a) { rationalIncidents += 1 } }
        try require(rationalIncidents == 4 && abs(varying.point(u:0.5,v:0.5).x-5) < 1e-12)
        do { _ = try varying.point(u:0.25,v:0.5); throw ExactScalarFailure.invalidEvidence }
        catch let failure as KernelError { try require(failure.code == .intersectionFailure) }
        try domainChecks(family,using:&a)
        try resources()
        do { try family.admitProof(limits:.init(remainingSourceDepth:0),using:&a); throw ExactScalarFailure.invalidEvidence }
        catch OriginalSourceIssuanceFailure.sourceDepthLimit {}
        var copyOfRail: BSplineCurve3D
        guard case .bSpline(let retained) = family.source.original.original.firstContact else { throw ExactScalarFailure.invalidEvidence }
        copyOfRail = retained; copyOfRail.controlPoints[0] = .origin
        try require(family.source.original.original.firstContact != .bSpline(copyOfRail))
        print("PASS rolling-ball original minor-arc graph, unequal child knots, four incidents, positive root and radius/degenerate refusal, COW/depth")
    }
}

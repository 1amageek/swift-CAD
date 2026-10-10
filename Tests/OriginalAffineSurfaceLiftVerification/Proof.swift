import CADCore
@testable import CADGeometry
@testable import AffineSurfaceLiftAdapters

@main
struct AffineSurfaceLiftProof {
    typealias Source = OriginalAffineSurfaceLiftSnapshot
    typealias Family = OriginalFiniteRetainedSurfaceLiftGraphs<Source>
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
    struct AssertionFailure: Error { let line: Int }
    static func require(_ condition: Bool,line: Int = #line) throws {
        guard condition else { throw AssertionFailure(line:line) }
    }
    static func shape(_ pcurve: SurfaceParameterCurve = .affine(origin:.init(x:0,y:0),direction:.init(x:1,y:1),startParameter:0,endParameter:1)) -> SurfaceLiftCurve3D {
        let stations=[0.0,0.5,1.0]
        let rows=stations.map { v in stations.map { u in Point3D(x:u,y:v,z:u+2*v) } }
        let surface=BSplineSurface3D(uDegree:1,vDegree:1,uKnots:[0,0,0.5,1,1],vKnots:[0,0,0.5,1,1],
            controlPoints:rows,weights:[[1,2,1],[2,4,2],[1,2,1]])
        return .init(surface:.bSpline(surface),parameterCurve:pcurve)
    }
    static func family<A: ExactScalarAdmission & ~Copyable>(_ original: SurfaceLiftCurve3D,using a: inout A) throws -> Family {
        let limits=try OriginalSourceIssuanceLimits(remainingSourceDepth:1)
        let f=try Field(maximumValueDepth:32,maximumCoefficientDepth:32,using:&a)
        let source=try DefaultOriginalSourceBindingIssuer(provider:OriginalAffineSurfaceLiftSnapshotProvider(field:f,tolerance:.standard))
            .bind(original,limits:limits,using:&a)
        let surface=try DefaultOriginalFiniteBSplineChartPreparer<BSplineSurface3D>().prepare(
            source:source.original.originalSurface,field:f,maximumCharts:4,limits:limits,using:&a)
        let pcurve=try DefaultOriginalFiniteRetainedCurveChartPreparer<OriginalAffinePcurveSnapshot>().prepare(
            source:source.original.originalPcurve,maximumCharts:1,limits:limits,using:&a)
        return try DefaultOriginalFiniteRetainedSurfaceLiftGraphPreparer<Source>().prepare(source:source,
            surface:surface,pcurve:pcurve,maximumCharts:4,limits:limits,using:&a)
    }
    struct RootPreparation: RationalAlgebraAdmitting {
        var work=0, storage=0
        mutating func consumeExactWork(_ count: Int) throws {
            guard count >= 0,count <= 50_000_000-work else { throw ExactScalarFailure.resourceLimit(.work) }
            work += count
        }
        mutating func retainExactStorage(_ count: Int) throws {
            guard count >= 0,count <= 50_000_000-storage else { throw ExactScalarFailure.resourceLimit(.storage) }
            storage += count
        }
        mutating func visitExactCell(depth: Int) throws {
            guard (0...32).contains(depth) else { throw ExactScalarFailure.resourceLimit(.valueDepth) }
        }
        mutating func visitCoefficientCell(depth: Int) throws {
            guard (0...32).contains(depth) else { throw ExactScalarFailure.resourceLimit(.coefficientDepth) }
        }
    }
    static func foreignField(using a: inout Admission) throws -> Field {
        // Test-only immutable quadratic witness; source preparation still uses one caller ledger.
        var preparation=RootPreparation()
        let square=try ExactBivariatePolynomial.monomial(u:2,v:0,coefficient:.one,usage:&preparation)
        let polynomial=try square.subtracting(.constant(.originalDouble(2,usage:&preparation),usage:&preparation),usage:&preparation)
        let roots=try ExactUnivariateRootIsolator().isolate(polynomial,lower:.one,
            upper:.originalDouble(2,usage:&preparation),maximumDepth:32,usage:&preparation)
        try require(roots.count == 1)
        let root=try ExactAlgebraicRealRoot(polynomial:polynomial,isolation:roots[0],usage:&preparation)
        return try Field(root:root,axis:.value,maximumValueDepth:32,maximumCoefficientDepth:32,using:&a)
    }
    static func rational<A: ExactScalarAdmission & ~Copyable>(_ n: Int,_ d: Int,field: Field,using a: inout A) throws -> Field.Value {
        try field.dividing(field.integer(n,using:&a),field.integer(d,using:&a),using:&a)
    }
    static func tuple<A: ExactScalarAdmission & ~Copyable>(_ family: Family,t: Double,uvNumerator: Int,uvDenominator: Int,
        using a: inout A) throws -> [Field.Value] {
        let f=family.field,uv=try rational(uvNumerator,uvDenominator,field:f,using:&a)
        return [try f.binary64(exactly:t,using:&a),uv,uv]
    }
    static func check(_ original: SurfaceLiftCurve3D,t: Double,u: (Int,Int),v: (Int,Int),incidents: Int,using a: inout Admission) throws {
        let family=try self.family(original,using:&a),f=family.field,limits=try OriginalSourceIssuanceLimits(remainingSourceDepth:1)
        let coordinates=[try f.binary64(exactly:t,using:&a),try rational(u.0,u.1,field:f,using:&a),try rational(v.0,v.1,field:f,using:&a)]
        // Independent closed-form rational evaluation of the fixed weighted tensor net.
        func image(_ coordinate: (Int,Int)) -> (Int,Int) {
            let (n,d)=coordinate
            return 2*n <= d ? (2*n,d+2*n):(d,3*d-2*n)
        }
        let x=image(u),y=image(v)
        let exactX=try rational(x.0,x.1,field:f,using:&a),exactY=try rational(y.0,y.1,field:f,using:&a)
        let exactZ=try f.adding(exactX,f.multiplying(f.integer(2,using:&a),exactY,using:&a),using:&a)
        let expected=[exactX,exactY,exactZ]
        var found=0
        for graph in family.graphs {
            try require(graph.layout.parameters == [0] && graph.layout.auxiliaries == [1,2])
            if try graph.admits(coordinates,limits:limits,using:&a) {
                found += 1
                let ring=graph.polynomials,d=try ring.evaluated(graph.homogeneous[3],at:coordinates,using:&a).value
                for axis in 0..<3 {
                    let actual=try f.dividing(ring.evaluated(graph.homogeneous[axis],at:coordinates,using:&a).value,d,using:&a)
                    try require(f.compare(actual,expected[axis],using:&a) == .equal)
                }
            }
        }
        try require(found == incidents)
        let point=try original.point(atNormalizedFraction:t,tolerance:.standard)
        let dx=Double(x.0)/Double(x.1),dy=Double(y.0)/Double(y.1)
        try require(abs(point.x-dx)<1e-12 && abs(point.y-dy)<1e-12 && abs(point.z-dx-2*dy)<1e-12)
    }
    static func domainChecks(_ family: Family,using a: inout Admission) throws {
        let f=family.field,limits=try OriginalDomainIdentityLimits(source:.init(remainingSourceDepth:1),maximumTransportDepth:8,
            maximumCharts:4,maximumFamilies:8,maximumIdentityProofs:8)
        let issuer=DefaultOriginalRetainedSurfaceLiftDomainIssuer<Source>()
        let frame=try issuer.frame(family:family,limits:limits,using:&a)
        let full=try issuer.issue(request:frame.fullSelection(limits:limits,using:&a),family:family,limits:limits,using:&a)
        let knot=try tuple(family,t:0.5,uvNumerator:1,uvDenominator:2,using:&a)
        try require(full.liftedPositionIncidents(at:knot,limits:limits,using:&a).count == 4)
        let zero=try f.integer(0,using:&a),one=try f.integer(1,using:&a)
        let third=try rational(1,3,field:f,using:&a),twoThirds=try rational(2,3,field:f,using:&a)
        func interval(_ lower: Field.Value,_ upper: Field.Value,closed: Bool=true) throws -> ExactParameterInterval<Field.Value> {
            try .checked(field:f,lower:.finite(lower),upper:.finite(upper),includesLower:closed,includesUpper:closed,
                depth:.init(value:0,coefficient:0),using:&a)
        }
        let strict=try issuer.issue(request:frame.selection(intervals:[[interval(third,twoThirds,closed:false)]],limits:limits,using:&a),
            family:family,limits:limits,using:&a)
        var boundary=knot;boundary[0]=third
        try require(strict.liftedPositionIncidents(at:boundary,limits:limits,using:&a).isEmpty)
        try require(strict.liftedPositionIncidents(at:knot,limits:limits,using:&a).count == 4)
        let singleton=try issuer.issue(request:frame.selection(intervals:[[interval(knot[0],knot[0])]],limits:limits,using:&a),
            family:family,limits:limits,using:&a)
        try require(singleton.liftedPositionIncidents(at:knot,limits:limits,using:&a).count == 4)
        let pieces=try issuer.issue(request:frame.selection(intervals:[[interval(zero,third),interval(twoThirds,one)]],limits:limits,using:&a),
            family:family,limits:limits,using:&a)
        try require(pieces.liftedPositionIncidents(at:knot,limits:limits,using:&a).isEmpty)
        let empty=try issuer.issue(request:frame.selection(intervals:[[]],limits:limits,using:&a),family:family,limits:limits,using:&a)
        try require(empty.effectiveEnclosure.isEmpty && empty.liftedPositionIncidents(at:knot,limits:limits,using:&a).isEmpty)
        do { _=try full.liftedPositionIncidents(at:[zero],limits:limits,using:&a);throw AssertionFailure(line:#line) }
        catch OriginalDomainIdentityFailure.invalidDomain {}
        let other=try self.family(shape(),using:&a),foreign=try issuer.frame(family:other,limits:limits,using:&a)
        do { _=try issuer.issue(request:foreign.fullSelection(limits:limits,using:&a),family:family,limits:limits,using:&a);throw AssertionFailure(line:#line) }
        catch OriginalDomainIdentityFailure.foreignOwner {}
        do {
            _=try DefaultOriginalFiniteRetainedSurfaceLiftGraphPreparer<Source>().prepare(source:family.source,
                surface:other.surface,pcurve:family.pcurve,maximumCharts:4,limits:limits.source,using:&a)
            throw AssertionFailure(line:#line)
        } catch OriginalSourceIssuanceFailure.foreignBinding {}
        do {
            _=try DefaultOriginalFiniteRetainedSurfaceLiftGraphPreparer<Source>().prepare(source:family.source,
                surface:family.surface,pcurve:family.pcurve,maximumCharts:3,limits:limits.source,using:&a)
            throw AssertionFailure(line:#line)
        } catch OriginalSourceIssuanceFailure.chartLimit {}
        var cancelled=try Admission();cancelled.ledger.cancel()
        do { _=try empty.liftedPositionIncidents(at:knot,limits:limits,using:&cancelled);throw AssertionFailure(line:#line) }
        catch OriginalDomainIdentityFailure.scalar(.cancelled) {}
        var measured=try Admission();_=try empty.liftedPositionIncidents(at:knot,limits:limits,using:&measured)
        var exact=try Admission(work:measured.ledger.work,storage:measured.ledger.storageBytes)
        try require(empty.liftedPositionIncidents(at:knot,limits:limits,using:&exact).isEmpty)
        var last=try Admission(cancelAtStorage:measured.storageCalls)
        do { _=try empty.liftedPositionIncidents(at:knot,limits:limits,using:&last);throw AssertionFailure(line:#line) }
        catch OriginalDomainIdentityFailure.scalar(.cancelled) {}
        let short=try OriginalDomainIdentityLimits(source:.init(remainingSourceDepth:1),maximumTransportDepth:8,
            maximumCharts:3,maximumFamilies:8,maximumIdentityProofs:8)
        do { _=try issuer.frame(family:family,limits:short,using:&a);throw AssertionFailure(line:#line) }
        catch OriginalDomainIdentityFailure.chartLimit {}
        do { _=try full.member(template:4,limits:limits,using:&a);throw AssertionFailure(line:#line) }
        catch OriginalDomainIdentityFailure.invalidDomain {}
        let transporter=DefaultOriginalParameterTransporter<Source,Field>()
        let wrongRole=try transporter.frame(source:family.source,field:f,
            support:[[interval(zero,one)]],semantics:[.intrinsicAngularLabel],limits:limits,using:&a)
        do { _=try issuer.issue(request:wrongRole.fullSelection(limits:limits,using:&a),family:family,limits:limits,using:&a);throw AssertionFailure(line:#line) }
        catch OriginalDomainIdentityFailure.incompatibleCoordinateSemantics {}
        let incomplete=try transporter.frame(source:family.source,field:f,
            support:[[interval(zero,knot[0])]],semantics:[.authoredScalar],limits:limits,using:&a)
        do { _=try issuer.issue(request:incomplete.fullSelection(limits:limits,using:&a),family:family,limits:limits,using:&a);throw AssertionFailure(line:#line) }
        catch OriginalDomainIdentityFailure.invalidDomain {}
        let rationalField=try Field(maximumValueDepth:32,maximumCoefficientDepth:32,using:&a)
        let half=try rational(1,2,field:rationalField,using:&a)
        try require(full.liftedPositionIncidents(at:[half,half,half],limits:limits,using:&a).count == 4)
        try require(empty.liftedPositionIncidents(at:[half,half,half],limits:limits,using:&a).isEmpty)
        let separateSurface=try DefaultOriginalFiniteBSplineChartPreparer<BSplineSurface3D>().prepare(
            source:family.surface.source,field:rationalField,maximumCharts:4,limits:limits.source,using:&a)
        let transferred=try DefaultOriginalFiniteRetainedSurfaceLiftGraphPreparer<Source>().prepare(source:family.source,
            surface:separateSurface,pcurve:family.pcurve,maximumCharts:4,limits:limits.source,using:&a)
        var transferredSides=0
        for graph in transferred.graphs {
            if try graph.admits([half,half,half],limits:limits.source,using:&a) { transferredSides += 1 }
        }
        try require(transferredSides == 4)
        let foreignField=try foreignField(using:&a)
        var invalid=knot;invalid[2]=try foreignField.generator(using:&a)
        do { _=try empty.liftedPositionIncidents(at:invalid,limits:limits,using:&a);throw AssertionFailure(line:#line) }
        catch OriginalDomainIdentityFailure.scalar(.incompatibleDomain) {}
        print("PASS surface-lift DI strict 1/3/singleton/disconnected/empty, foreign owner/field, chart/arity and empty publication cancel")
    }
    static func expectedFailure(_ body: () throws -> Void, resource: ExactResource? = nil) throws {
        do { try body(); throw AssertionFailure(line:#line) }
        // Field construction precedes the source port and reports its own typed cause.
        catch ExactScalarFailure.resourceLimit(let actual) { try require(actual == resource) }
        catch ExactScalarFailure.cancelled { try require(resource == nil) }
        catch OriginalSourceIssuanceFailure.scalar(.resourceLimit(let actual)) { try require(actual == resource) }
        catch OriginalSourceIssuanceFailure.polynomial(.scalar(.resourceLimit(let actual))) { try require(actual == resource) }
        catch OriginalSourceIssuanceFailure.scalar(.cancelled) { try require(resource == nil) }
        catch OriginalSourceIssuanceFailure.polynomial(.scalar(.cancelled)) { try require(resource == nil) }
    }
    static func resources() throws {
        var measured=try Admission();_=try family(shape(),using:&measured)
        var exact=try Admission(work:measured.ledger.work,storage:measured.ledger.storageBytes)
        _=try family(shape(),using:&exact)
        var work=try Admission(work:measured.ledger.work-1)
        try expectedFailure({_=try family(shape(),using:&work)},resource:.work)
        var storage=try Admission(storage:measured.ledger.storageBytes-1)
        try expectedFailure({_=try family(shape(),using:&storage)},resource:.storage)
        var entry=try Admission();entry.ledger.cancel()
        try expectedFailure({_=try family(shape(),using:&entry)})
        var final=try Admission(cancelAtStorage:measured.storageCalls)
        try expectedFailure({_=try family(shape(),using:&final)})
        print("PASS surface-lift exact resource limits and one-less, entry/final callback cancel; work=\(measured.ledger.work) bytes=\(measured.ledger.storageBytes)")
    }
    static func main() throws {
        var a=try Admission()
        for (t,n,d,sides) in [(0.0,0,1,1),(0.25,1,4,1),(0.5,1,2,4),(0.75,3,4,1),(1.0,1,1,1)] {
            try check(shape(),t:t,u:(n,d),v:(n,d),incidents:sides,using:&a)
        }
        let reverse=shape(.affine(origin:.init(x:1,y:1),direction:.init(x:-0.25,y:-0.25),startParameter:0,endParameter:4))
        try check(reverse,t:0.25,u:(3,4),v:(3,4),incidents:1,using:&a)
        try check(shape(.constantU(u:0.5,vStart:1,vEnd:0)),t:0.25,u:(1,2),v:(3,4),incidents:2,using:&a)
        try check(shape(.constantV(v:0.5,uStart:1,uEnd:0)),t:0.25,u:(3,4),v:(1,2),incidents:2,using:&a)
        try check(shape(.affine(origin:.init(x:-1,y:-1),direction:.init(x:0.5,y:0.5),startParameter:2,endParameter:4)),
            t:0.5,u:(1,2),v:(1,2),incidents:4,using:&a)
        let retained=try family(shape(),using:&a),limits=try OriginalSourceIssuanceLimits(remainingSourceDepth:1)
        try domainChecks(retained,using:&a)
        let precise=try family(shape(.affine(origin:.init(x:1.5,y:1.5),direction:.init(x:-1+0x1p-52,y:-1+0x1p-52),
            startParameter:1+0x1p-52,endParameter:1.5)),using:&a)
        let f=precise.field,zero=try f.integer(0,using:&a),half=try f.binary64(exactly:0.5,using:&a)
        let exactUV=try f.adding(half,f.binary64(exactly:0x1p-104,using:&a),using:&a)
        var count=0
        for graph in precise.graphs {
            if try graph.admits([zero,exactUV,exactUV],limits:limits,using:&a) { count += 1 }
            try require(!graph.admits([zero,half,half],limits:limits,using:&a))
        }
        try require(count == 1)
        try require(abs(precise.source.original.original.point(atNormalizedFraction:0,tolerance:.standard).x-0.5)<1e-12)
        let provider=OriginalAffineSurfaceLiftSnapshotProvider(field:retained.field,tolerance:.standard)
        var cancelledSource=try Admission();cancelledSource.ledger.cancel()
        do { _=try DefaultOriginalSourceBindingIssuer(provider:provider).bind(shape(),limits:limits,using:&cancelledSource);throw AssertionFailure(line:#line) }
        catch OriginalSourceIssuanceFailure.scalar(.cancelled) {}
        for input in [shape(.constantU(u:0.5,vStart:0,vEnd:0)),
            shape(.affine(origin:.init(x:0,y:0),direction:.init(x:1,y:1),startParameter:1,endParameter:0))] {
            do { _=try DefaultOriginalSourceBindingIssuer(provider:provider).bind(input,limits:limits,using:&a);throw AssertionFailure(line:#line) }
            catch OriginalSourceIssuanceFailure.invalidSource {}
        }
        let near=shape(.constantU(u:-1e-14,vStart:0,vEnd:1))
        try require(abs(near.point(atNormalizedFraction:0.5,tolerance:.standard).x)<1e-12)
        do { _=try DefaultOriginalSourceBindingIssuer(provider:provider).bind(near,limits:limits,using:&a);throw AssertionFailure(line:#line) }
        catch OriginalSourceIssuanceFailure.unsupportedRepresentation {}
        let image=BSplineCurve3D(degree:1,knots:[0,0,1,1],controlPoints:[.origin,.init(x:1,y:1,z:3)])
        let original=shape()
        let priority=SurfaceLiftCurve3D(surface:original.surface,parameterCurve:original.parameterCurve,exactBSplineImage:image)
        do { _=try DefaultOriginalSourceBindingIssuer(provider:provider).bind(priority,limits:limits,using:&a);throw AssertionFailure(line:#line) }
        catch OriginalSourceIssuanceFailure.unsupportedRepresentation {}
        let harmonic=shape(.harmonic(center:.init(x:0.5,y:0.5),cosine:.init(x:0.25,y:0),sine:.init(x:0,y:0.25),startParameter:0,endParameter:1))
        do { _=try DefaultOriginalSourceBindingIssuer(provider:provider).bind(harmonic,limits:limits,using:&a);throw AssertionFailure(line:#line) }
        catch OriginalSourceIssuanceFailure.unsupportedRepresentation {}
        do { try retained.admitProof(limits:.init(remainingSourceDepth:0),using:&a);throw AssertionFailure(line:#line) }
        catch OriginalSourceIssuanceFailure.sourceDepthLimit {}
        var copiedSurface=retained.source.original.originalSurface.original
        copiedSurface.controlPoints[0][0] = .init(x:2,y:2,z:2)
        try require(retained.source.original.original.surface != .bSpline(copiedSurface))
        try resources()
        print("PASS retained affine/constant lift, reversed traversal, exact 2^-104 distinction, original evaluator and all chart sides; source COW/lifetime/depth/unsupported guards")
    }
}

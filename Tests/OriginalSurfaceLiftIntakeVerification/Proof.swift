import CADCore
@testable import CADGeometry
@testable import SurfaceLiftAdapters

@main
struct SurfaceLiftProof {
    typealias Source = OriginalNativeSurfaceLiftSnapshot
    typealias Family = OriginalFiniteNativeSurfaceLiftGraphs<Source>
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
    static func require(_ condition: Bool, line: Int = #line) throws {
        guard condition else { print("FAIL surface-lift line \(line)"); throw AssertionFailure(line:line) }
    }
    static func shape(nonmonotone: Bool = false, constant: Bool = false) -> SurfaceLiftCurve3D {
        let stations = [0.0,0.5,1.0]
        let rows = stations.map { v in stations.map { u in Point3D(x:u,y:v,z:u+2*v) } }
        let surface = BSplineSurface3D(uDegree:1,vDegree:1,uKnots:[0,0,0.5,1,1],vKnots:[0,0,0.5,1,1],
            controlPoints:rows,weights:[[1,2,1],[2,4,2],[1,2,1]])
        let curve: BSplineCurve2D
        if nonmonotone {
            curve = .init(degree:2,knots:[2,2,2,4,4,4],
                controlPoints:[.init(x:0,y:0),.init(x:1,y:1),.init(x:0,y:0)])
        } else if constant {
            curve = .init(degree:1,knots:[2,2,3,4,4],
                controlPoints:[.init(x:0.5,y:0.5),.init(x:0.5,y:0.5),.init(x:0.5,y:0.5)])
        } else {
            curve = .init(degree:1,knots:[2,2,3,4,4],
                controlPoints:[.init(x:0,y:0),.init(x:0.5,y:0.5),.init(x:1,y:1)],weights:[1,2,1])
        }
        return .init(surface:.bSpline(surface),parameterCurve:.bSpline(curve))
    }
    static func family<A: ExactScalarAdmission & ~Copyable>(_ original: SurfaceLiftCurve3D,
        using a: inout A) throws -> Family {
        let limits = try OriginalSourceIssuanceLimits(remainingSourceDepth:1)
        let source = try DefaultOriginalSourceBindingIssuer(provider:
            OriginalNativeSurfaceLiftSnapshotProvider(tolerance:.standard)).bind(original,limits:limits,using:&a)
        let f = try Field(maximumValueDepth:32,maximumCoefficientDepth:32,using:&a)
        let surface = try DefaultOriginalFiniteBSplineChartPreparer<BSplineSurface3D>().prepare(
            source:source.original.originalSurface,field:f,maximumCharts:4,limits:limits,using:&a)
        let pcurve = try DefaultOriginalFiniteBSplineChartPreparer<BSplineCurve2D>().prepare(
            source:source.original.originalPcurve,field:f,maximumCharts:2,limits:limits,using:&a)
        return try DefaultOriginalFiniteNativeSurfaceLiftGraphPreparer<Source>().prepare(source:source,
            surface:surface,pcurve:pcurve,maximumCharts:8,limits:limits,using:&a)
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
    static func rational<A: ExactScalarAdmission & ~Copyable>(_ n: Int,_ d: Int,field: Field,
        using a: inout A) throws -> Field.Value { try field.dividing(field.integer(n,using:&a),field.integer(d,using:&a),using:&a) }
    static func tuple<A: ExactScalarAdmission & ~Copyable>(_ family: Family,t: Double,uvNumerator: Int,uvDenominator: Int,
        using a: inout A) throws -> [Field.Value] {
        let f=family.field, uv=try rational(uvNumerator,uvDenominator,field:f,using:&a)
        return [try f.binary64(exactly:t,using:&a),uv,uv]
    }
    static func checkPositions(_ family: Family,using a: inout Admission) throws {
        let f=family.field,limits=try OriginalSourceIssuanceLimits(remainingSourceDepth:1)
        for (t,un,ud,xn,xd,count) in [(0.0,0,1,0,1,1),(0.25,1,3,2,5,1),(0.5,1,2,1,2,8),(0.75,2,3,3,5,1),(1.0,1,1,1,1,1)] {
            let coordinates=try tuple(family,t:t,uvNumerator:un,uvDenominator:ud,using:&a)
            var found=0
            for graph in family.graphs {
                try require(graph.layout.parameters == [0] && graph.layout.auxiliaries == [1,2])
                if try graph.admits(coordinates,limits:limits,using:&a) {
                    found += 1
                    let ring=graph.polynomials,d=try ring.evaluated(graph.homogeneous[3],at:coordinates,using:&a).value
                    for axis in 0..<3 {
                        let actual=try f.dividing(ring.evaluated(graph.homogeneous[axis],at:coordinates,using:&a).value,d,using:&a)
                        let expected=try rational(axis == 2 ? 3*xn:xn,xd,field:f,using:&a)
                        try require(f.compare(actual,expected,using:&a) == .equal)
                    }
                }
            }
            try require(found == count)
            let point=try family.source.original.original.point(atNormalizedFraction:t,tolerance:.standard)
            let expected=Double(xn)/Double(xd)
            try require(abs(point.x-expected)<1e-12 && abs(point.y-expected)<1e-12 && abs(point.z-3*expected)<1e-12)
        }
        var wrong=try tuple(family,t:0.25,uvNumerator:1,uvDenominator:3,using:&a)
        wrong[1]=try f.integer(1,using:&a)
        for graph in family.graphs { try require(!graph.admits(wrong,limits:limits,using:&a)) }
        print("PASS surface-lift original weighted evaluation, nonnormalized pcurve transport, exact XYZ and all eight knot/corner incidents")
    }
    static func domainChecks(_ family: Family,using a: inout Admission) throws {
        let f=family.field,limits=try OriginalDomainIdentityLimits(source:.init(remainingSourceDepth:1),maximumTransportDepth:8,
            maximumCharts:8,maximumFamilies:8,maximumIdentityProofs:8)
        let issuer=DefaultOriginalNativeSurfaceLiftDomainIssuer<Source>()
        let frame=try issuer.frame(family:family,limits:limits,using:&a)
        let full=try issuer.issue(request:frame.fullSelection(limits:limits,using:&a),family:family,limits:limits,using:&a)
        let knot=try tuple(family,t:0.5,uvNumerator:1,uvDenominator:2,using:&a)
        try require(full.liftedPositionIncidents(at:knot,limits:limits,using:&a).count == 8)
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
        try require(strict.liftedPositionIncidents(at:knot,limits:limits,using:&a).count == 8)
        let singleton=try issuer.issue(request:frame.selection(intervals:[[interval(knot[0],knot[0])]],limits:limits,using:&a),
            family:family,limits:limits,using:&a)
        try require(singleton.liftedPositionIncidents(at:knot,limits:limits,using:&a).count == 8)
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
            _=try DefaultOriginalFiniteNativeSurfaceLiftGraphPreparer<Source>().prepare(source:family.source,
                surface:other.surface,pcurve:family.pcurve,maximumCharts:8,limits:limits.source,using:&a)
            throw AssertionFailure(line:#line)
        } catch OriginalSourceIssuanceFailure.foreignBinding {}
        do {
            _=try DefaultOriginalFiniteNativeSurfaceLiftGraphPreparer<Source>().prepare(source:family.source,
                surface:family.surface,pcurve:family.pcurve,maximumCharts:7,limits:limits.source,using:&a)
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
            maximumCharts:7,maximumFamilies:8,maximumIdentityProofs:8)
        do { _=try issuer.frame(family:family,limits:short,using:&a);throw AssertionFailure(line:#line) }
        catch OriginalDomainIdentityFailure.chartLimit {}
        do { _=try full.member(template:8,limits:limits,using:&a);throw AssertionFailure(line:#line) }
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
        try require(full.liftedPositionIncidents(at:[half,half,half],limits:limits,using:&a).count == 8)
        try require(empty.liftedPositionIncidents(at:[half,half,half],limits:limits,using:&a).isEmpty)
        let foreignField=try foreignField(using:&a)
        var invalid=knot;invalid[2]=try foreignField.generator(using:&a)
        do { _=try empty.liftedPositionIncidents(at:invalid,limits:limits,using:&a);throw AssertionFailure(line:#line) }
        catch OriginalDomainIdentityFailure.scalar(.incompatibleDomain) {}
        print("PASS surface-lift DI strict 1/3/singleton/disconnected/empty, foreign owner/field, chart/arity and empty publication cancel")
    }
    static func expectedFailure(_ body: () throws -> Void, resource: ExactResource? = nil) throws {
        do { try body(); throw AssertionFailure(line:#line) }
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
        let family=try family(shape(),using:&a),limits=try OriginalSourceIssuanceLimits(remainingSourceDepth:1)
        try require(family.graphs.count == 8 && family.enclosingSupport.count == 1)
        try family.admitProof(limits:limits,using:&a)
        try checkPositions(family,using:&a);try domainChecks(family,using:&a)
        let folded=try self.family(shape(nonmonotone:true),using:&a)
        for t in [0.25,0.75] {
            let coordinates=try tuple(folded,t:t,uvNumerator:3,uvDenominator:8,using:&a)
            var count=0
            for graph in folded.graphs { if try graph.admits(coordinates,limits:limits,using:&a) { count += 1 } }
            try require(count == 1)
            try require(abs(folded.source.original.original.point(atNormalizedFraction:t,tolerance:.standard).x-3.0/7.0)<1e-12)
        }
        let constant=try self.family(shape(constant:true),using:&a)
        for t in [0.25,0.5,0.75] {
            let coordinates=try tuple(constant,t:t,uvNumerator:1,uvDenominator:2,using:&a)
            var count=0
            for graph in constant.graphs { if try graph.admits(coordinates,limits:limits,using:&a) { count += 1 } }
            try require(count == (t == 0.5 ? 8:4))
        }
        do { try family.admitProof(limits:.init(remainingSourceDepth:0),using:&a);throw AssertionFailure(line:#line) }
        catch OriginalSourceIssuanceFailure.sourceDepthLimit {}
        var copyOfCurve=family.source.original.originalPcurve.original
        copyOfCurve.controlPoints[0] = .init(x:0.75,y:0.75)
        try require(family.source.original.original.parameterCurve != .bSpline(copyOfCurve))
        let original=shape()
        let unsupported=SurfaceLiftCurve3D(surface:original.surface,parameterCurve:.constantU(u:0.5,vStart:0,vEnd:1))
        do {
            _=try DefaultOriginalSourceBindingIssuer(provider:OriginalNativeSurfaceLiftSnapshotProvider(tolerance:.standard)).bind(unsupported,limits:limits,using:&a)
            throw AssertionFailure(line:#line)
        } catch OriginalSourceIssuanceFailure.unsupportedRepresentation {}
        let image=BSplineCurve3D(degree:1,knots:[0,0,1,1],controlPoints:[.origin,.init(x:1,y:1,z:3)])
        let priority=SurfaceLiftCurve3D(surface:original.surface,parameterCurve:original.parameterCurve,exactBSplineImage:image)
        do {
            _=try DefaultOriginalSourceBindingIssuer(provider:OriginalNativeSurfaceLiftSnapshotProvider(tolerance:.standard)).bind(priority,limits:limits,using:&a)
            throw AssertionFailure(line:#line)
        } catch OriginalSourceIssuanceFailure.unsupportedRepresentation {}
        var outside=family.source.original.originalPcurve.original
        outside.controlPoints[0] = .init(x:2,y:0)
        let invalidDomain=SurfaceLiftCurve3D(surface:original.surface,parameterCurve:.bSpline(outside))
        do {
            _=try DefaultOriginalSourceBindingIssuer(provider:OriginalNativeSurfaceLiftSnapshotProvider(tolerance:.standard)).bind(invalidDomain,limits:limits,using:&a)
            throw AssertionFailure(line:#line)
        } catch OriginalSourceIssuanceFailure.invalidSource {}
        var near=family.source.original.originalPcurve.original
        near.controlPoints[0] = .init(x:-1e-14,y:0)
        let numericalClamp=SurfaceLiftCurve3D(surface:original.surface,parameterCurve:.bSpline(near))
        // The legacy evaluator accepts then clamps this UV; it is not an exact lift theorem.
        try require(abs(numericalClamp.point(atNormalizedFraction:0,tolerance:.standard).x)<1e-12)
        do {
            _=try DefaultOriginalSourceBindingIssuer(provider:OriginalNativeSurfaceLiftSnapshotProvider(tolerance:.standard)).bind(numericalClamp,limits:limits,using:&a)
            throw AssertionFailure(line:#line)
        } catch OriginalSourceIssuanceFailure.unsupportedRepresentation {}
        var invalidWeights=family.source.original.originalPcurve.original
        invalidWeights.weights[0]=0
        let invalidCurve=SurfaceLiftCurve3D(surface:original.surface,parameterCurve:.bSpline(invalidWeights))
        do {
            _=try DefaultOriginalSourceBindingIssuer(provider:OriginalNativeSurfaceLiftSnapshotProvider(tolerance:.standard)).bind(invalidCurve,limits:limits,using:&a)
            throw AssertionFailure(line:#line)
        } catch OriginalSourceIssuanceFailure.sourceRejected {}
        try resources()
        print("PASS surface-lift nonmonotone duplicate XYZ, constant fibers, source lifetime/COW/depth and unsupported priority-image refusal")
    }
}

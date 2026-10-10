import CADCore
@testable import CADGeometry
@testable import RollingBallGraphAdapters

@main
struct RollingBallGraphProof {
    typealias Source=OriginalGraphRollingBallSnapshot
    typealias Evidence=OriginalRollingBallCurveGraphEvidence
    typealias Coverage=OriginalRollingBallCurveGraphCoverage
    typealias Family=OriginalFiniteRollingBallGraphs<Source,Evidence,Coverage>
    typealias Field=OriginalExactScalarDomain
    struct Admission: ~Copyable, ExactScalarAdmission {
        var ledger: ExactScalarLedger
        var storageCalls = 0
        let cancelAtStorage: Int?
        init(work: Int = 300_000_000, storage: Int = 1_073_741_824, cancelAtStorage: Int? = nil, valueDepth: Int = 32, coefficientDepth: Int = 32) throws {
            ledger = .init(limits: try .init(work: work, storageBytes: storage, valueDepth: valueDepth, coefficientDepth: coefficientDepth))
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
    static func foreignField(axis: ExactScalarRootAxis = .value,using a: inout Admission) throws -> Field {
        // Test-only immutable quadratic witness; source preparation still uses one caller ledger.
        var preparation=RootPreparation()
        let square=try ExactBivariatePolynomial.monomial(u:2,v:0,coefficient:.one,usage:&preparation)
        let polynomial=try square.subtracting(.constant(.originalDouble(2,usage:&preparation),usage:&preparation),usage:&preparation)
        let roots=try ExactUnivariateRootIsolator().isolate(polynomial,lower:.originalDouble(-2,usage:&preparation),
            upper:.originalDouble(2,usage:&preparation),maximumDepth:32,usage:&preparation)
        try require(roots.count == 2 && roots[1].isolationDepth > 0 && roots[1].lower == .zero)
        let root=try ExactAlgebraicRealRoot(polynomial:polynomial,isolation:roots[1],usage:&preparation)
        return try Field(root:root,axis:axis,maximumValueDepth:32,maximumCoefficientDepth:32,using:&a)
    }
    static func rational<A: ExactScalarAdmission & ~Copyable>(_ n: Int,_ d: Int,field: Field,using a: inout A) throws -> Field.Value {
        try field.dividing(field.integer(n,using:&a),field.integer(d,using:&a),using:&a)
    }
    static func native(_ x: Double,_ y: Double) -> Curve3D {
        .bSpline(.init(degree:1,knots:[0,0,0.5,1,1],controlPoints:[.init(x:x,y:y,z:0),.init(x:x,y:y,z:0.5),.init(x:x,y:y,z:1)]))
    }
    static func lift(_ x: Double,_ y: Double,pcurve: SurfaceParameterCurve,coarse: Bool=false) -> Curve3D {
        let stations=coarse ? [0.0,1.0]:[0.0,0.5,1.0]
        let rows=stations.map { _ in stations.map { u in Point3D(x:x,y:y,z:u) } }
        let knots=coarse ? [0.0,0.0,1.0,1.0]:[0.0,0.0,0.5,1.0,1.0]
        return .surfaceLift(.init(surface:.bSpline(.init(uDegree:1,vDegree:1,uKnots:knots,vKnots:knots,controlPoints:rows)),parameterCurve:pcurve))
    }
    static func shape(mixed: Bool=false,mode: Int=0,coarse: Bool=false,degenerate: Bool=false,radius: Double=5) -> RollingBallGraphAdapters.RollingBallBlendSurface3D {
        let affine=SurfaceParameterCurve.affine(origin:.init(x:0,y:0),direction:.init(x:1,y:0),startParameter:0,endParameter:1)
        let ordinary=SurfaceParameterCurve.bSpline(.init(degree:1,knots:[0,0,0.5,1,1],controlPoints:[.init(x:0,y:0),.init(x:0.5,y:0),.init(x:1,y:0)]))
        let special=SurfaceParameterCurve.bSpline(mode == 1 ? .init(degree:2,knots:[0,0,0,1,1,1],controlPoints:[.init(x:0,y:0),.init(x:1,y:0),.init(x:0,y:0)]):
            .init(degree:1,knots:[0,0,1,1],controlPoints:[.init(x:0.5,y:0),.init(x:0.5,y:0)]))
        let center=mixed ? native(0,0):lift(0,0,pcurve:mode == 0 ? .constantV(v:0,uStart:0,uEnd:1):special,coarse:coarse)
        return .init(centerSpine:center,firstContact:lift(3,4,pcurve:mode == 0 ? affine:special,coarse:coarse),
            secondContact:lift(3,degenerate ? 4:-4,pcurve:mode == 0 ? ordinary:special,coarse:coarse),radius:radius,tolerance:.standard)
    }
    static func family<A: ExactScalarAdmission & ~Copyable>(_ original: RollingBallGraphAdapters.RollingBallBlendSurface3D,using a: inout A) throws -> Family {
        let limits=try OriginalSourceIssuanceLimits(remainingSourceDepth:3)
        let f=try Field(maximumValueDepth:32,maximumCoefficientDepth:32,using:&a)
        let source=try DefaultOriginalSourceBindingIssuer(provider:OriginalGraphRollingBallSnapshotProvider(field:f)).bind(original,limits:limits,using:&a)
        let prepare=DefaultOriginalRollingBallCurveGraphPreparer(),children=try OriginalSourceIssuanceLimits(remainingSourceDepth:2)
        let center=try prepare.prepare(source:source.original.originalCenter,field:f,maximumCharts:8,limits:children,using:&a)
        let first=try prepare.prepare(source:source.original.originalFirstContact,field:f,maximumCharts:8,limits:children,using:&a)
        let second=try prepare.prepare(source:source.original.originalSecondContact,field:f,maximumCharts:8,limits:children,using:&a)
        return try DefaultOriginalFiniteRollingBallGraphPreparer<Source,Evidence,Coverage>().prepare(source:source,center:center,
            first:first,second:second,maximumCharts:128,limits:limits,using:&a)
    }
    static func coordinates<A: ExactScalarAdmission & ~Copyable>(field f: Field,t: Double,v: Double=0.5,uv: Double?=nil,mixed: Bool=false,
        using a: inout A) throws -> [Field.Value] {
        let u=try f.binary64(exactly:uv ?? t,using:&a),zero=try f.integer(0,using:&a)
        var tuple=[try f.binary64(exactly:t,using:&a),try f.binary64(exactly:v,using:&a)]
        if !mixed { tuple += [u,zero] }
        tuple += [u,zero,u,zero,try f.integer(5,using:&a),try f.integer(5,using:&a),try rational(3,5,field:f,using:&a)]
        return tuple
    }
    static func check(_ family: Family,t: Double,v: Double=0.5,uv: Double?=nil,mixed: Bool=false,incidents: Int,
        expected: [(Int,Int)],using a: inout Admission) throws {
        let f=family.field,tuple=try coordinates(field:f,t:t,v:v,uv:uv,mixed:mixed,using:&a)
        var found=0
        for graph in family.graphs {
            try require(graph.layout.parameters == [0,1] && graph.layout.variableCount == (mixed ? 9:11))
            if try graph.admits(tuple,limits:.init(remainingSourceDepth:3),using:&a) {
                found += 1
                let ring=graph.polynomials,d=try ring.evaluated(graph.homogeneous[3],at:tuple,using:&a).value
                for axis in 0..<3 {
                    let value=try f.dividing(ring.evaluated(graph.homogeneous[axis],at:tuple,using:&a).value,d,using:&a)
                    try require(f.compare(value,rational(expected[axis].0,expected[axis].1,field:f,using:&a),using:&a) == .equal)
                }
            }
        }
        try require(found == incidents)
        let point=try family.source.original.original.point(u:t,v:v)
        try require(abs(point.x-Double(expected[0].0)/Double(expected[0].1))<1e-12 &&
            abs(point.y-Double(expected[1].0)/Double(expected[1].1))<1e-12 &&
            abs(point.z-Double(expected[2].0)/Double(expected[2].1))<1e-12)
    }
    static func tuple<A: ExactScalarAdmission & ~Copyable>(_ family: Family,u: Double,v: Double,using a: inout A) throws -> [Field.Value] {
        try coordinates(field:family.field,t:u,v:v,using:&a)
    }
    static func domainChecks(_ family: Family, using a: inout Admission) throws {
        let f = family.field
        let limits = try OriginalDomainIdentityLimits(source:.init(remainingSourceDepth:3),maximumTransportDepth:8,
            maximumCharts:128,maximumFamilies:8,maximumIdentityProofs:8)
        let issuer = DefaultOriginalRollingBallGraphDomainIssuer<Source,Evidence,Coverage>()
        let frame = try issuer.frame(family:family,limits:limits,using:&a)
        let full = try issuer.issue(request:frame.fullSelection(limits:limits,using:&a),family:family,limits:limits,using:&a)
        let knot = try tuple(family,u:0.5,v:0.5,using:&a)
        try require(full.liftedPositionIncidents(at:knot,limits:limits,using:&a).count == 16)
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
        try require(selected.liftedPositionIncidents(at:knot,limits:limits,using:&a).count == 16)
        let singleton = try frame.selection(intervals:[[interval(knot[0],knot[0])],[interval(knot[1],knot[1])]],limits:limits,using:&a)
        let point = try issuer.issue(request:singleton,family:family,limits:limits,using:&a)
        try require(point.liftedPositionIncidents(at:knot,limits:limits,using:&a).count == 16)
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
            _ = try DefaultOriginalFiniteRollingBallGraphPreparer<Source,Evidence,Coverage>().prepare(source:family.source,
                center:other.center,first:family.first,second:family.second,maximumCharts:128,limits:limits.source,using:&a)
            throw ExactScalarFailure.invalidEvidence
        } catch OriginalSourceIssuanceFailure.foreignBinding {}
        do {
            _ = try DefaultOriginalFiniteRollingBallGraphPreparer<Source,Evidence,Coverage>().prepare(source:family.source,
                center:family.center,first:family.first,second:family.second,maximumCharts:127,limits:limits.source,using:&a)
            throw ExactScalarFailure.invalidEvidence
        } catch OriginalSourceIssuanceFailure.chartLimit {}
        let short = try OriginalDomainIdentityLimits(source:.init(remainingSourceDepth:3),maximumTransportDepth:8,
            maximumCharts:127,maximumFamilies:8,maximumIdentityProofs:8)
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
        let otherField=try Field(maximumValueDepth:32,maximumCoefficientDepth:32,using:&a)
        let compatible=try coordinates(field:otherField,t:0.5,using:&a)
        try require(full.liftedPositionIncidents(at:compatible,limits:limits,using:&a).count == 16)
        let algebraic=try foreignField(using:&a)
        var foreignTuple=knot;foreignTuple[2]=try algebraic.generator(using:&a)
        do { _=try empty.liftedPositionIncidents(at:foreignTuple,limits:limits,using:&a);throw AssertionFailure(line:#line) }
        catch OriginalDomainIdentityFailure.scalar(.incompatibleDomain) {}
        print("PASS rolling-ball DI: full/strict 1/3/singleton/disconnected/empty, sixteen incidents, foreign owner, arity/chart/cancel")
    }
    static func failure(_ body: () throws -> Void,resource: ExactResource?=nil) throws {
        do { try body();throw AssertionFailure(line:#line) }
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
        try failure({_=try family(shape(),using:&work)},resource:.work)
        var storage=try Admission(storage:measured.ledger.storageBytes-1)
        try failure({_=try family(shape(),using:&storage)},resource:.storage)
        var entry=try Admission();entry.ledger.cancel()
        try failure({_=try family(shape(),using:&entry)})
        var last=try Admission(cancelAtStorage:measured.storageCalls)
        try failure({_=try family(shape(),using:&last)})
        print("PASS generic rolling-ball exact work/storage and one-less, entry/final cancel: work=\(measured.ledger.work) bytes=\(measured.ledger.storageBytes)")
    }
    static func coefficientChecks(using a: inout Admission) throws {
        let small=try family(shape(coarse:true),using:&a),prepare=DefaultOriginalRollingBallCurveGraphPreparer()
        let childLimits=try OriginalSourceIssuanceLimits(remainingSourceDepth:2),limits=try OriginalSourceIssuanceLimits(remainingSourceDepth:3)
        let independent=try Field(maximumValueDepth:32,maximumCoefficientDepth:32,using:&a)
        let separate=try prepare.prepare(source:small.first.source,field:independent,maximumCharts:8,limits:childLimits,using:&a)
        let composed=try DefaultOriginalFiniteRollingBallGraphPreparer<Source,Evidence,Coverage>().prepare(source:small.source,
            center:small.center,first:separate,second:small.second,maximumCharts:128,limits:limits,using:&a)
        try check(composed,t:0.25,incidents:1,expected:[(5,1),(0,1),(1,4)],using:&a)
        for axis in [ExactScalarRootAxis.value,.coefficient] {
            let extensionField=try foreignField(axis:axis,using:&a)
            let inherited=try prepare.prepare(source:small.first.source,field:extensionField,maximumCharts:8,limits:childLimits,using:&a)
            let family=try DefaultOriginalFiniteRollingBallGraphPreparer<Source,Evidence,Coverage>().prepare(source:small.source,
                center:small.center,first:inherited,second:small.second,maximumCharts:128,limits:limits,using:&a)
            var low=try Admission(valueDepth:axis == .value ? 0:32,coefficientDepth:axis == .coefficient ? 0:32)
            try failure({try family.admitProof(limits:limits,using:&low)},resource:axis == .value ? .valueDepth:.coefficientDepth)
        }
        let f=small.field,original=try ExactPolynomialDomain(field:f,variableCount:2,using:&a)
        let x=try original.variable(0,using:&a),y=try original.variable(1,using:&a)
        let expression=try original.adding(original.scaled(x,by:f.integer(2,using:&a),using:&a),original.scaled(y,by:f.integer(3,using:&a),using:&a),using:&a)
        try OriginalSourceProofAdmission<Admission>.withBorrow(&a) { a in
            let target=try ExactPolynomialDomain(field:f,variableCount:4,using:&a)
            let embedded=try OriginalRollingBallGraphProducer<Source>().embedded(expression,map:[2,0],ring:target,field:f,using:&a)
            let tuple=[try f.integer(5,using:&a),try f.integer(0,using:&a),try f.integer(7,using:&a),try f.integer(0,using:&a)]
            try require(f.compare(target.evaluated(embedded,at:tuple,using:&a).value,f.integer(29,using:&a),using:&a) == .equal)
        }
        print("PASS generic rolling-ball compatible child fields, inherited value/coefficient depth and permuted variable embedding")
    }
    static func main() throws {
        var a=try Admission()
        let family=try family(shape(),using:&a),limits=try OriginalSourceIssuanceLimits(remainingSourceDepth:3)
        try require(family.graphs.count == 128)
        try check(family,t:0.25,incidents:1,expected:[(5,1),(0,1),(1,4)],using:&a)
        try check(family,t:0.5,incidents:16,expected:[(5,1),(0,1),(1,2)],using:&a)
        try check(family,t:0.75,v:0.25,incidents:1,expected:[(75,17),(40,17),(3,4)],using:&a)
        try check(family,t:0.25,v:0,incidents:1,expected:[(3,1),(4,1),(1,4)],using:&a)
        try check(family,t:0.75,v:1,incidents:1,expected:[(3,1),(-4,1),(3,4)],using:&a)
        let mixed=try self.family(shape(mixed:true),using:&a)
        try check(mixed,t:0.5,mixed:true,incidents:16,expected:[(5,1),(0,1),(1,2)],using:&a)
        for mode in [1,2] {
            let noninjective=try self.family(shape(mode:mode),using:&a)
            for t in [0.25,0.75] {
                try check(noninjective,t:t,uv:mode == 1 ? 0.375:0.5,incidents:mode == 1 ? 1:8,
                    expected:[(5,1),(0,1),mode == 1 ? (3,8):(1,2)],using:&a)
            }
        }
        let tuple=try coordinates(field:family.field,t:0.25,using:&a)
        for index in [3,5,7,8,9,10] {
            var invalid=tuple;invalid[index]=try family.field.binary64(exactly:index<8 ? 0.5:-1,using:&a)
            for graph in family.graphs { try require(!graph.admits(invalid,limits:limits,using:&a)) }
        }
        for (original,expectedFailure) in [(shape(degenerate:true),KernelErrorCode.singularSystem),(shape(radius:6),.intersectionFailure)] {
            let invalid=try self.family(original,using:&a),tuple=try coordinates(field:invalid.field,t:0.25,using:&a)
            for graph in invalid.graphs { try require(!graph.admits(tuple,limits:limits,using:&a)) }
            do { _=try original.point(u:0.25,v:0.5);throw AssertionFailure(line:#line) }
            catch let error as KernelError { try require(error.code == expectedFailure) }
        }
        try domainChecks(family,using:&a)
        try coefficientChecks(using:&a)
        do { try family.admitProof(limits:.init(remainingSourceDepth:2),using:&a);throw AssertionFailure(line:#line) }
        catch OriginalSourceIssuanceFailure.sourceDepthLimit {}
        guard case .surfaceLift(let original)=family.source.original.original.firstContact,
            case .bSpline(var copied)=original.surface else { throw AssertionFailure(line:#line) }
        copied.controlPoints[0][0] = .origin
        try require(original.surface != .bSpline(copied))
        let harmonic=SurfaceParameterCurve.harmonic(center:.init(x:0.5,y:0),cosine:.init(x:0.25,y:0),sine:.init(x:0,y:0),startParameter:0,endParameter:1)
        let unsupported=RollingBallGraphAdapters.RollingBallBlendSurface3D(centerSpine:native(0,0),firstContact:lift(3,4,pcurve:harmonic),secondContact:native(3,-4),radius:5,tolerance:.standard)
        do { _=try DefaultOriginalSourceBindingIssuer(provider:OriginalGraphRollingBallSnapshotProvider(field:family.field)).bind(unsupported,limits:limits,using:&a);throw AssertionFailure(line:#line) }
        catch OriginalSourceIssuanceFailure.unsupportedRepresentation {}
        try resources()
        print("PASS real lifted/mixed rolling-ball graphs and original evaluator, all 16 knot incidents, nonmonotone/constant fibers, child UV/positive-root guards and source lifetime/COW")
    }
}

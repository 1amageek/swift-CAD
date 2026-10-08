import CADCore
import struct CADGeometry.BSplineCurve3D
import struct CADGeometry.BSplineSurface3D
import enum CADGeometry.AnalyticSurface3D
import L0
import L1
import SourceIssuer
import SourceGeometryAdapters

@main
struct GeometryProof {
    enum Failure: Error { case incorrectEvidence }
    static func require(_ value: Bool) throws { if !value { throw Failure.incorrectEvidence } }
    static func ledger(work: Int = 20_000_000, storage: Int = 134_217_728) throws -> ExactScalarLedger {
        .init(limits: try .init(work: work, storageBytes: storage, valueDepth: 32, coefficientDepth: 32))
    }
    static func main() throws {
        let limits = try OriginalSourceIssuanceLimits(remainingSourceDepth: 0)
        var a = try ledger()
        let curves = DefaultOriginalSourceBindingIssuer(provider: OriginalBSplineCurveSnapshotProvider(tolerance: .standard))
        var curve = BSplineCurve3D(degree: 1, knots: [0,0,1,1],
            controlPoints: [.init(x: 0,y: 0,z: 0), .init(x: 1,y: 0,z: 0)], weights: [1,2])
        let binding = try curves.bind(curve, limits: limits, using: &a)
        let chart = try binding.chart(OriginalBSplineChartSelection(spans: [1]), limits: limits, using: &a)
        let law = try DefaultOriginalBSplineChartIssuer<BSplineCurve3D, ExactRationalScalarDomain>()
            .issue(source: binding, chart: chart, field: .init(), limits: limits, using: &a)
        let f = law.field, ring = law.polynomials
        let t = try ring.variable(0, using: &a)
        try require(try ring.equals(law.homogeneous[0], ring.scaled(t,
            by: f.integer(2, using: &a), using: &a), using: &a))
        try require(try ring.equals(law.denominator, ring.adding(t,
            ring.constant(f.integer(1, using: &a), using: &a), using: &a), using: &a))
        curve.controlPoints[1].x = 42; curve.weights[1] = 99; curve.knots[2] = 5
        try require(law.source.original.controlPoints[1].x == 1 && law.source.original.weights[1] == 2)
        try require(law.source.original.knots[2] == 1 && binding.sourceDepth == 0)
        print("PASS actual weighted curve law, retained COW source and zero leaf source depth")

        let surface = BSplineSurface3D(uDegree: 1, vDegree: 1,
            uKnots: [0,0,1,1], vKnots: [0,0,1,1],
            controlPoints: [[.init(x: 0,y: 0,z: 0), .init(x: 1,y: 0,z: 0)],
                [.init(x: 0,y: 1,z: 0), .init(x: 1,y: 1,z: 1)]], weights: [[1,2],[3,6]])
        let surfaces = DefaultOriginalSourceBindingIssuer(provider: OriginalBSplineSurfaceSnapshotProvider(tolerance: .standard))
        let bound = try surfaces.bind(surface, limits: limits, using: &a)
        let selected = try bound.chart(OriginalBSplineChartSelection(spans: [1,1]), limits: limits, using: &a)
        let tensor = try DefaultOriginalBSplineChartIssuer<BSplineSurface3D, ExactRationalScalarDomain>()
            .issue(source: bound, chart: selected, field: .init(), limits: limits, using: &a)
        let r = tensor.polynomials, sf = tensor.field
        let u = try r.variable(0, using: &a), v = try r.variable(1, using: &a)
        let one = try r.constant(sf.integer(1, using: &a), using: &a)
        let u2 = try r.scaled(u, by: sf.integer(2, using: &a), using: &a)
        let v3 = try r.scaled(v, by: sf.integer(3, using: &a), using: &a)
        let wu = try r.adding(one, u, using: &a)
        let wv = try r.adding(one, r.scaled(v, by: sf.integer(2, using: &a), using: &a), using: &a)
        for (axis, left, right) in [(0,u2,wv),(1,wu,v3),(2,u2,v3),(3,wu,wv)] {
            try require(try r.equals(tensor.homogeneous[axis], r.multiplying(left,right,using:&a),using:&a))
        }
        print("PASS actual weighted tensor net, U-fastest reads and complete four coefficient laws")

        var badCurve = law.source.original; badCurve.weights[0] = 0
        do { _ = try curves.bind(badCurve, limits: limits, using: &a); throw Failure.incorrectEvidence }
        catch OriginalSourceIssuanceFailure.sourceRejected {}
        var badSurface = surface; badSurface.controlPoints[1].removeLast()
        do { _ = try surfaces.bind(badSurface, limits: limits, using: &a); throw Failure.incorrectEvidence }
        catch OriginalSourceIssuanceFailure.sourceRejected {}
        var exhausted = try ledger(work: 1)
        do { _ = try curves.bind(law.source.original, limits: limits, using: &exhausted); throw Failure.incorrectEvidence }
        catch OriginalSourceIssuanceFailure.scalar(.resourceLimit(.work)) {}
        var noStorage = try ledger(storage: 0)
        do { _ = try surfaces.bind(surface, limits: limits, using: &noStorage); throw Failure.incorrectEvidence }
        catch OriginalSourceIssuanceFailure.scalar(.resourceLimit(.storage)) {}
        var cancelled = try ledger(); cancelled.cancel()
        do { _ = try curves.bind(law.source.original, limits: limits, using: &cancelled); throw Failure.incorrectEvidence }
        catch OriginalSourceIssuanceFailure.scalar(.cancelled) {}
        print("PASS actual family validation, same-ledger work/storage and entry cancellation failures")
        try actualPeriodicSources()
        try analyticImages()
        try coneImage()
    }

    static func analyticImages() throws {
        var a = try ledger()
        let limits = try OriginalSourceIssuanceLimits(remainingSourceDepth:0)
        let provider = DefaultOriginalSourceBindingIssuer(provider:OriginalAnalyticPrimitiveSnapshotProvider(tolerance:.standard))
        for primitive in [AnalyticSurface3D.sphere(center:.init(x:0,y:0,z:0),radius:2),
            .cylinder(origin:.init(x:0,y:0,z:0),axis:.unitZ,radius:2),
            .torus(center:.init(x:0,y:0,z:0),axis:.unitZ,majorRadius:3,minorRadius:1)] {
            let binding = try provider.bind(primitive,limits:limits,using:&a)
            let chart = try binding.chart(OriginalPrimitiveImageSelection(),limits:limits,using:&a)
            let law = try DefaultOriginalPrimitiveImageIssuer<OriginalAnalyticPrimitiveSnapshot,ExactRationalScalarDomain>()
                .issue(source:binding,chart:chart,field:.init(),limits:limits,using:&a)
            let r = law.polynomials, f = law.field
            let x = try r.variable(0,using:&a), y = try r.variable(1,using:&a), z = try r.variable(2,using:&a)
            let radial = try r.adding(r.multiplying(x,x,using:&a),r.multiplying(y,y,using:&a),using:&a)
            let expected: ExactPolynomial<ExactRationalScalarDomain>
            switch primitive {
            case .sphere:
                expected = try r.subtracting(r.adding(radial,r.multiplying(z,z,using:&a),using:&a),
                    r.constant(f.integer(4,using:&a),using:&a),using:&a)
            case .cylinder:
                expected = try r.subtracting(radial,r.constant(f.integer(4,using:&a),using:&a),using:&a)
            case .torus:
                let total = try r.adding(r.adding(radial,r.multiplying(z,z,using:&a),using:&a),
                    r.constant(f.integer(8,using:&a),using:&a),using:&a)
                expected = try r.subtracting(r.multiplying(total,total,using:&a),
                    r.scaled(radial,by:f.integer(36,using:&a),using:&a),using:&a)
            default: throw Failure.incorrectEvidence
            }
            try require(try r.equals(law.equation,expected,using:&a))
            try require(law.source.original.original == primitive)
        }
        do {
            _ = try provider.bind(.plane(origin:.init(x:0,y:0,z:0),normal:.unitZ),limits:limits,using:&a)
            throw Failure.incorrectEvidence
        } catch OriginalSourceIssuanceFailure.unresolvedAuthority {}
        do {
            _ = try provider.bind(.cone(apex:.init(x:0,y:0,z:0),axis:.unitZ,halfAngle:0.5),limits:limits,using:&a)
            throw Failure.incorrectEvidence
        } catch OriginalSourceIssuanceFailure.unsupportedRepresentation {}
        print("PASS actual sphere/cylinder/torus original gauge; plane authority blocked, cone routed to its physical-angle capability")
    }
    static func coneImage() throws {
        var a = try ledger()
        let limits = try OriginalSourceIssuanceLimits(remainingSourceDepth:0)
        let original = AnalyticSurface3D.cone(apex:.init(x:1,y:-2,z:3),axis:.unitZ,halfAngle:0.5)
        let provider = DefaultOriginalSourceBindingIssuer(provider:OriginalAnalyticConeSnapshotProvider(tolerance:.standard))
        let binding = try provider.bind(original,limits:limits,using:&a)
        let chart = try binding.chart(OriginalPrimitiveImageSelection(),limits:limits,using:&a)
        let field = try OriginalPhysicalAngleScalarDomain(originalRadians:0.5,using:&a)
        let law = try DefaultOriginalConeImageIssuer<OriginalAnalyticConeSnapshot,OriginalPhysicalAngleScalarDomain>()
            .issue(source:binding,chart:chart,field:field,limits:limits,using:&a)
        let r = law.polynomials, f = law.field
        let x = try r.subtracting(r.variable(0,using:&a),r.constant(f.integer(1,using:&a),using:&a),using:&a)
        let y = try r.adding(r.variable(1,using:&a),r.constant(f.integer(2,using:&a),using:&a),using:&a)
        let z = try r.subtracting(r.variable(2,using:&a),r.constant(f.integer(3,using:&a),using:&a),using:&a)
        let c = try f.cosine(using:&a), s = try f.sine(using:&a)
        let expected = try r.subtracting(r.scaled(r.adding(r.multiplying(x,x,using:&a),
            r.multiplying(y,y,using:&a),using:&a),by:f.multiplying(c,c,using:&a),using:&a),
            r.scaled(r.multiplying(z,z,using:&a),by:f.multiplying(s,s,using:&a),using:&a),using:&a)
        try require(try r.equals(law.equation,expected,using:&a))
        try require(law.source.original.original == original)
        do {
            _ = try provider.bind(.cone(apex:.init(x:0,y:0,z:0),axis:.unitZ,halfAngle:0),limits:limits,using:&a)
            throw Failure.incorrectEvidence
        } catch OriginalSourceIssuanceFailure.sourceRejected {}
        print("PASS actual physical-radian cone binding, existing original basis, full exact image law and original invalid-angle rejection")
    }

    static func actualPeriodicSources() throws {
        var a = try ledger()
        let limits = try OriginalSourceIssuanceLimits(remainingSourceDepth:0)
        let curve = BSplineCurve3D(degree:1,knots:[-1,0,1,2,3],
            controlPoints:[.init(x:0,y:0,z:0),.init(x:1,y:0,z:0),.init(x:0,y:0,z:0)],
            weights:[1,1,1],isPeriodic:true,periodicOrigin:0)
        let binding = try DefaultOriginalSourceBindingIssuer(provider:OriginalBSplineCurveSnapshotProvider(tolerance:.standard))
            .bind(curve,limits:limits,using:&a)
        let chart = try binding.chart(OriginalBSplineChartSelection(spans:[1],cycles:[1]),limits:limits,using:&a)
        let law = try DefaultOriginalBSplineChartIssuer<BSplineCurve3D,ExactRationalScalarDomain>()
            .issue(source:binding,chart:chart,field:.init(),limits:limits,using:&a)
        let f = law.field, r = law.polynomials
        try require(law.source.original.isPeriodic)
        try require(try r.equals(law.homogeneous[0],r.subtracting(r.variable(0,using:&a),
            r.constant(f.integer(2,using:&a),using:&a),using:&a),using:&a))
        try require(try f.compare(law.support[0].lower,f.integer(2,using:&a),using:&a) == .equal)
        let p00 = Point3D(x:0,y:0,z:0), p10 = Point3D(x:1,y:0,z:0)
        let p01 = Point3D(x:0,y:1,z:0), p11 = Point3D(x:1,y:1,z:0)
        let surface = BSplineSurface3D(uDegree:1,vDegree:1,uKnots:[-1,0,1,2,3],vKnots:[-1,0,1,2,3],
            controlPoints:[[p00,p10,p00],[p01,p11,p01],[p00,p10,p00]],weights:[[1,1,1],[1,1,1],[1,1,1]],
            isUPeriodic:true,isVPeriodic:true,uPeriodicOrigin:0,vPeriodicOrigin:0)
        let sb = try DefaultOriginalSourceBindingIssuer(provider:OriginalBSplineSurfaceSnapshotProvider(tolerance:.standard))
            .bind(surface,limits:limits,using:&a)
        let sc = try sb.chart(OriginalBSplineChartSelection(spans:[1,1],cycles:[1,-1]),limits:limits,using:&a)
        let sl = try DefaultOriginalBSplineChartIssuer<BSplineSurface3D,ExactRationalScalarDomain>()
            .issue(source:sb,chart:sc,field:.init(),limits:limits,using:&a)
        let sr = sl.polynomials, sf = sl.field
        try require(sl.source.original.isUPeriodic && sl.source.original.isVPeriodic)
        try require(try sr.equals(sl.homogeneous[0],sr.subtracting(sr.variable(0,using:&a),
            sr.constant(sf.integer(2,using:&a),using:&a),using:&a),using:&a))
        try require(try sr.equals(sl.homogeneous[1],sr.adding(sr.variable(1,using:&a),
            sr.constant(sf.integer(2,using:&a),using:&a),using:&a),using:&a))
        print("PASS actual periodic curve and doubly-periodic tensor providers, opposite cycle translations and exact original laws")
    }

}

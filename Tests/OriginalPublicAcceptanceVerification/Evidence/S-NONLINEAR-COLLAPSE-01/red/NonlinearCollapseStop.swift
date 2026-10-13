import CADCore
@testable import CADGeometry
import Darwin

/// Reproduces the unmodified nonlinear lift admission before any source change.
@main struct NonlinearCollapseStop {
    enum Failure: Error { case unexpectedSuccess, invalidLaw }
    static func main() throws {
        let native=BSplineSurface3D(uDegree:1,vDegree:1,uKnots:[0,0,1,1],vKnots:[0,0,1,1],
            controlPoints:[[.origin,.origin],[.init(x:0,y:1,z:0),.init(x:1,y:1,z:0)]])
        let pcurve=BSplineCurve2D(degree:2,knots:[0,0,0,1,1,1],
            controlPoints:[.init(x:1,y:0),.init(x:-1,y:0),.init(x:1,y:0)])
        let lift=SurfaceLiftCurve3D(surface:.bSpline(native),parameterCurve:.bSpline(pcurve))
        var a=ExactScalarLedger(limits:try .init(work:80_000_000,storageBytes:1_073_741_824,valueDepth:32,coefficientDepth:32))
        let f=try OriginalExactScalarDomain(maximumValueDepth:32,maximumCoefficientDepth:32,using:&a)
        let binding=try DefaultOriginalSourceBindingIssuer(provider:OriginalBSplinePcurveSnapshotProvider(tolerance:.standard))
            .bind(pcurve,limits:.init(remainingSourceDepth:0),using:&a)
        let family=try DefaultOriginalFiniteBSplineChartPreparer<BSplineCurve2D>().prepare(source:binding,
            field:f,maximumCharts:1,limits:.init(remainingSourceDepth:0),using:&a)
        guard family.laws.count==1 else { throw Failure.invalidLaw }
        let law=family.laws[0],r=law.polynomials,t=try r.variable(0,using:&a)
        let q=try r.subtracting(r.scaled(t,by:f.integer(2,using:&a),using:&a),r.constant(f.integer(1,using:&a),using:&a),using:&a)
        let expected=try r.multiplying(q,q,using:&a)
        guard try r.equals(law.homogeneous[0],expected,using:&a),try r.isZero(law.homogeneous[1],using:&a) else { throw Failure.invalidLaw }
        print("PASS actual quadratic pcurve source law a=(2T-1)^2,b0 on[0,1]");fflush(nil)
        do { try lift.validate(tolerance:.standard);throw Failure.unexpectedSuccess }
        catch GeometryError.invalidDistance(let value) {
            guard value==0 else { throw Failure.invalidLaw };print("OBSERVED PUBLIC VALIDATION GeometryError.invalidDistance(0)");fflush(nil)
        }
        do {
            _=try DefaultOriginalSourceBindingIssuer(provider:OriginalNativeSurfaceLiftSnapshotProvider(tolerance:.standard))
                .bind(lift,limits:.init(remainingSourceDepth:1),using:&a)
            throw Failure.unexpectedSuccess
        } catch OriginalSourceIssuanceFailure.invalidSource {
            print("OBSERVED SOURCE invalidSource after control-point domain test");fflush(nil)
        }
    }
}

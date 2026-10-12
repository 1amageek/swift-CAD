import CADCore
@testable import CADGeometry
import Darwin

@main struct RollingPlaneSSIStop {
    static func lift(_ x: Double, _ y: Double, _ pcurve: SurfaceParameterCurve) -> Curve3D {
        let stations = [0.0,0.5,1.0], knots = [0.0,0,0.5,1,1]
        return .surfaceLift(.init(surface:.bSpline(.init(uDegree:1,vDegree:1,uKnots:knots,vKnots:knots,
            controlPoints:stations.map { _ in stations.map { Point3D(x:x,y:y,z:$0) } })),parameterCurve:pcurve))
    }
    static func shape() -> Surface3D {
        .procedural(.rollingBall(.init(centerSpine:lift(0,0,.constantV(v:0,uStart:0,uEnd:1)),
            firstContact:lift(3,4,.affine(origin:.init(x:0,y:0),direction:.init(x:1,y:0),startParameter:0,endParameter:1)),
            secondContact:lift(3,-4,.bSpline(.init(degree:1,knots:[0,0,0.5,1,1],controlPoints:[.init(x:0,y:0),.init(x:0.5,y:0),.init(x:1,y:0)]))),radius:5,tolerance:.standard)))
    }
    static func main() {
        puts("INPUT SSI-ROLLING-BALL-PLANE-01 actual original all-lift radius5; fullUV; whole planeZ=.5");fflush(stdout)
        do {
            let result = try DefaultSurfaceSurfaceIntersector().intersectionResult(first:shape(),
                second:.plane(.init(origin:.init(x:0,y:0,z:0.5),normal:.unitZ)),options:.init(),tolerance:.standard)
            puts("SUCCESS numerical=\(result.intersections.count) retained=\(result.originalIssuedGeometricRelation != nil)")
        } catch let error as KernelError { puts("FAILURE \(error.code.rawValue) \(error.message)") }
        catch { puts("FAILURE other") }
    }
}

import CADCore
import CADGeometry
#if canImport(Darwin)
import Darwin
#elseif canImport(WASILibc)
import WASILibc
#endif

@main enum PeriodicOffsetCSStop {
    static func main() {
        let xy:[(Double,Double)] = [(0,0),(1,0),(0,1),(0,0)]
        let native = BSplineSurface3D(uDegree:1,vDegree:1,uKnots:[-1,0,1,2,3,4],vKnots:[-1,0,1,2,3,4],
            controlPoints:xy.map { v in xy.map { u in Point3D(x:u.0,y:u.1+v.0,z:v.1) } },isUPeriodic:true,isVPeriodic:true)
        let surface = Surface3D.procedural(.offset(.init(source:.bSpline(native),distance:0)))
        let point = Point3D(x:0.25,y:0.5,z:0)
        let curve = Curve3D.bSpline(.init(degree:1,knots:[0,0,1,1],controlPoints:[point,point]))
        do {
            let result = try DefaultCurveSurfaceIntersector().intersectionResult(curve:curve,surface:surface,tolerance:.standard)
            print("RETURN points=\(result.points.count) overlaps=\(result.overlaps.count) exact=\(result.originalIssuedGeometricRelation != nil) positive=\(result.hasPositiveDimensionalSolutions)")
        } catch let error as KernelError { print("STOP \(error.code.rawValue): \(error.message)");exit(2) }
        catch { print("STOP unclassified error");exit(3) }
    }
}

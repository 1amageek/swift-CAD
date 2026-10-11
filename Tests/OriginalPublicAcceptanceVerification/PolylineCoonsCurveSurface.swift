import CADCore
@testable import CADGeometry
@testable import PolylineLiftAdapters

@main struct PolylineCoonsCurveSurface {
    static func main() throws {
        var admission=try PolylineLiftProof.Admission()
        let host=try PolylineAtlasLiftProof.shape(multi:true,using:&admission).0
        let curve=Curve3D.surfaceLift(.init(surface:.procedural(.originalCoons(host)),
            parameterCurve:.polyline(PolylineLiftProof.points())))
        let plane=Surface3D.plane(Plane3D(origin:.init(x:0.5,y:0,z:0),normal:.unitX))
        do {
            let results=try DefaultCurveSurfaceIntersector().intersections(curve:curve,surface:plane,
                options:.init(),tolerance:.standard)
            print("CS-POLY-01 result count",results.count)
            for result in results {
                print("tuple",result.curveParameter,result.surfaceU,result.surfaceV,
                    result.point.x,result.point.y,result.point.z,result.originalCurveBoundary != nil)
            }
        } catch {
            print("CS-POLY-01 stopped",error)
        }
    }
}

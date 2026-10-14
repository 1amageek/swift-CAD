import CADCore
import CADGeometry
@main struct FullConeConeSSIObservation {
 static func main() throws {
  let reference=Surface3D.analytic(.cone(apex:.origin,axis:.unitZ,halfAngle:Double(bitPattern:0x3fddac670561bb50)))
  let parameterized=Surface3D.analytic(.cone(apex:.init(x:0,y:0,z:4),axis:.unitY,halfAngle:Double(bitPattern:0x3fd6f61941e4def1)))
  for reverse in [false,true] {
   let result=try DefaultSurfaceSurfaceIntersector().intersectionResult(first:reverse ? parameterized:reference,second:reverse ? reference:parameterized,tolerance:.standard)
   print("reverse",reverse,"components",result.intersections.count,"numerical",result.representation == .numericalRepresentatives)
   print("issued",result.originalIssuedGeometricRelation != nil,"exact",result.originalExactGeometricRelation != nil,"coaxial",result.originalCoaxialSurfaceRelation != nil)
  }
 }
}

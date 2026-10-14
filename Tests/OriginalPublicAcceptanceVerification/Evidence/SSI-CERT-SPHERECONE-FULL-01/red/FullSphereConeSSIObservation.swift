import CADCore
import CADGeometry
@main struct FullSphereConeSSIObservation {
 static func main() throws {
  let sphere=Surface3D.analytic(.sphere(center:.origin,radius:3))
  let cone=Surface3D.analytic(.cone(apex:.init(x:1,y:0,z:-4),axis:.unitZ,halfAngle:Double(bitPattern:0x3fddac670561bb50)))
  for reversed in [false,true] {
   let result=try DefaultSurfaceSurfaceIntersector().intersectionResult(first:reversed ? cone:sphere,second:reversed ? sphere:cone,tolerance:.standard)
   print("reversed",reversed,"components",result.intersections.count)
   print("issued",result.originalIssuedGeometricRelation != nil,"exact",result.originalExactGeometricRelation != nil,"coaxial",result.originalCoaxialSurfaceRelation != nil,"bounded",result.originalBoundedSphereConeRelation != nil)
   print("numerical",result.representation == .numericalRepresentatives)
  }
 }
}

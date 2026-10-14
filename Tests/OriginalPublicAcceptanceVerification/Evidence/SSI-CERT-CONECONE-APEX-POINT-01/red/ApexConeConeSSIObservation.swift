import CADCore
import CADGeometry
@main struct ApexConeConeSSIObservation {
 static func main() throws {
  let first=Surface3D.analytic(.cone(apex:.origin,axis:.unitZ,halfAngle:Double(bitPattern:0x3fddac670561bb50)))
  let second=Surface3D.analytic(.cone(apex:.origin,axis:.unitY,halfAngle:Double(bitPattern:0x3fd6f61941e4def1)))
  for reverse in [false,true] {
   let result=try DefaultSurfaceSurfaceIntersector().intersectionResult(first:reverse ? second:first,second:reverse ? first:second,tolerance:.standard)
   print("reverse",reverse,"components",result.intersections.count,"numerical",result.representation == .numericalRepresentatives,"issued",result.originalIssuedGeometricRelation != nil,"exact",result.originalExactGeometricRelation != nil)
  }
 }
}

import CADCore
import CADGeometry
@main struct CoincidentConeSSIObservation {
 static func main() throws {
  let cone=Surface3D.analytic(.cone(apex:.origin,axis:.unitZ,halfAngle:0.5))
  let result=try DefaultSurfaceSurfaceIntersector().intersectionResult(first:cone,second:cone,tolerance:.standard)
  print("components",result.intersections.count,"numerical",result.representation == .numericalRepresentatives,"issued",result.originalIssuedGeometricRelation != nil,"exact",result.originalExactGeometricRelation != nil)
  for value in result.intersections { if case .coincident=value { print("coincident without full UV") } }
 }
}

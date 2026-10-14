import CADCore
import CADGeometry
@main struct SphereConeNodeObservation {
 static func main() throws {
  let sphere=Surface3D.analytic(.sphere(center:.origin,radius:1))
  let cone=Surface3D.analytic(.cone(apex:.init(x:1,y:0,z:0),axis:.unitZ,halfAngle:0.5))
  for reverse in [false,true] {
   let result=try DefaultSurfaceSurfaceIntersector().intersectionResult(first:reverse ? cone:sphere,second:reverse ? sphere:cone,tolerance:.standard)
   print("reverse",reverse,"components",result.intersections.count,"numerical",result.representation == .numericalRepresentatives,"allUV",result.originalApexSphereConeRelation != nil)
  }
 }
}

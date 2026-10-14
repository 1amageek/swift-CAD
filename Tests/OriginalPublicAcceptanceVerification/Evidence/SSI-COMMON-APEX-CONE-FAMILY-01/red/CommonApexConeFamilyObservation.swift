import CADCore
import CADGeometry
@main struct CommonApexConeFamilyObservation {
 static func main() throws {
  let a=Double(bitPattern:0x3fddac670561bb50),b=Double(bitPattern:0x3fd6f61941e4def1)
  for kind in 0..<3 {
   let first=Surface3D.analytic(.cone(apex:.origin,axis:.unitZ,halfAngle:kind==0 ? 0.5:a))
   let second=Surface3D.analytic(.cone(apex:.origin,axis:kind==0 ? .unitY:.unitZ,halfAngle:kind==0 ? 0.5:kind==1 ? b:a.nextUp))
   do {
    let result=try DefaultSurfaceSurfaceIntersector().intersectionResult(first:first,second:second,tolerance:.standard)
    print("kind",kind,"components",result.intersections.count,"numerical",result.representation == .numericalRepresentatives,"allUV",result.originalCommonApexConeRelation != nil)
    for value in result.intersections { if case .coincident=value { print("coincident",kind) } }
   } catch { print("failure",kind,error) }
  }
 }
}

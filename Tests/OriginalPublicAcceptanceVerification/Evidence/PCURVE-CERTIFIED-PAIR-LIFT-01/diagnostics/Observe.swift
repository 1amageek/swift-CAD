import CADCore
import CADGeometry
import Darwin
@main struct ObserveCertifiedPairLift {
 static func main() throws {
  let cone=Surface3D.analytic(.cone(apex:.origin,axis:.unitZ,halfAngle:Double(bitPattern:0x3fddac670561bb50)))
  let cylinder=Surface3D.analytic(.cylinder(origin:.origin,axis:.unitZ,radius:1))
  let plane=Surface3D.plane(.init(origin:.origin,normal:.unitY,uDirection:.unitX))
  for positive in [false,true] {
   let source=try CertifiedConeCylinderIntersectionCurve(coneSurface:cone,cylinderSurface:cylinder,componentKind:positive ? .positiveFullBranch:.negativeFullBranch,lowerAngle:0,upperAngle:2*Double.pi,tolerance:.standard)
   let pair=try CertifiedAnalyticAnalyticIntersectionCurve(coneCylinderCurve:source,firstSurface:cone,secondSurface:cylinder,tolerance:.standard)
   for role: SurfaceIntersectionSurfaceRole in [.first,.second] {
    for reversed in [false,true] {
     let pcurve=try CertifiedAnalyticPairSurfaceParameterCurve(intersection:pair,role:role,startFraction:reversed ? 0.75:0,endFraction:reversed ? 0.25:1,tolerance:.standard)
     let curve=Curve3D.surfaceLift(.init(surface:pair.surface(for:role),parameterCurve:.certifiedAnalyticPair(pcurve)))
     print("INPUT",positive,role,reversed);fflush(nil)
     do {
      let result=try DefaultCurveSurfaceIntersector().intersectionResult(curve:curve,surface:plane,options:.init(curveRange:try .init(lower:0,upper:1)),tolerance:.standard)
      print("RESULT",result.points.count,result.overlaps.count,result.representation)
      for p in result.points {print("POINT",p.curveParameter,p.point.x,p.point.y,p.point.z)}
     } catch {print("FAILURE",error)}
     fflush(nil)
    }
   }
  }
 }
}

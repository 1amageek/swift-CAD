import CADCore
import CADGeometry
import Darwin
@main struct ObserveConeCone {
 static func main() throws {
  let alpha=atan(0.5), beta=atan(0.375)
  print("authored angle bits",String(alpha.bitPattern,radix:16),String(beta.bitPattern,radix:16))
  for kind: CertifiedConeConeIntersectionCurve.ComponentKind in [.negativeFullBranch,.positiveFullBranch] {
   let source = try CertifiedConeConeIntersectionCurve(referenceSurface:.analytic(.cone(apex:.origin,axis:.unitZ,halfAngle:alpha)),parameterizedSurface:.analytic(.cone(apex:.init(x:0,y:0,z:4),axis:.unitY,halfAngle:beta)),componentKind:kind,lowerAngle:0,upperAngle:2*Double.pi,tolerance:.standard)
   print("constructed",kind.rawValue,source.maximumResidualUpperBound)
   do {
    let result=try DefaultCurveSurfaceIntersector().intersectionResult(curve:.certifiedIntersection(.coneCone(source)),surface:.plane(.init(origin:.origin,normal:.unitX,uDirection:.unitZ)),options:.init(curveRange:try .init(lower:0,upper:1)),tolerance:.standard)
    print("public result",result.points.count,result.overlaps.count,result.representation)
    for p in result.points { print("point",p.curveParameter,p.point.x,p.point.y,p.point.z,p.surfaceU,p.surfaceV) }
   } catch { print("public failure",error) }
  }
 }
}

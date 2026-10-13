import CADCore
import CADGeometry
import CADTopology
import HashTreeCollections
@main struct CoaxialSSIArrayKernelAcceptance {
 static func main() throws {
  let cone=Surface3D.analytic(.cone(apex:.origin,axis:.unitZ,halfAngle:0.3))
  let cylinder=Surface3D.analytic(.cylinder(origin:.origin,axis:.unitZ,radius:1))
  let result=try DefaultSurfaceSurfaceIntersector().intersections(first:cone,second:cylinder,tolerance:.standard)
  let a=Face(surfaceID:SurfaceID(),loops:[]),b=Face(surfaceID:SurfaceID(),loops:[])
  let model=BRepModel(faces:[a.id:a,b.id:b])
  let pair=BooleanFacePairCandidate(targetFaceID:a.id,toolFaceID:b.id)
  for value in result {
   let graph=BooleanIntersectionGraph(facePairs:[pair],boundaryContacts:[],faceIntersections:[.init(facePair:pair,geometry:value)])
   do { try graph.validate(in:model,tolerance:.standard); fatalError("Symbolic material clipping must not become complete success.") }
   catch let e as KernelError { guard e.code == .unsupportedCapability else {throw e} }
  }
  print("PASS actual Boolean graph rejects unconverted original material refinement")
 }
}

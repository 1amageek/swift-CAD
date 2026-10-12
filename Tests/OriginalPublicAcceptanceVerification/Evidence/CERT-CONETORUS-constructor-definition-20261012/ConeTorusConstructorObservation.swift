import CADCore
import CADGeometry
import Darwin
@main struct ConeTorusConstructorObservation {
 static func main() throws {
 let cone=Surface3D.analytic(.cone(apex:.origin,axis:.unitZ,halfAngle:atan(6)))
 let torus=Surface3D.analytic(.torus(center:.origin,axis:.unitZ,majorRadius:3,minorRadius:1))
 for i in 0..<4 {
 print("START_BRANCH",i);fflush(nil)
 let value=try CertifiedGeneralConeTorusIntersectionCurve(coneSurface:cone,torusSurface:torus,branchIndex:i,tolerance:.standard)
 print("CONSTRUCTED",i,"branchCount",value.branchCount);fflush(nil)
 }
 }
}

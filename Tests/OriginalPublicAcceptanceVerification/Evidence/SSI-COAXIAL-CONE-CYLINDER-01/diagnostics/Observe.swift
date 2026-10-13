import CADCore
import CADGeometry
import Darwin
@main struct ObserveCoaxialSSI {
 static func main() throws {
  let cone=Surface3D.analytic(.cone(apex:.origin,axis:.unitZ,halfAngle:Double(bitPattern:0x3fddac670561bb50)))
  let cylinder=Surface3D.analytic(.cylinder(origin:.origin,axis:.unitZ,radius:1))
  for reversed in [false,true] {
   print("ENTRY",reversed);fflush(nil)
   do {
   let r=try DefaultSurfaceSurfaceIntersector().intersectionResult(first:reversed ? cylinder:cone,second:reversed ? cone:cylinder,tolerance:.standard)
   print("RESULT",reversed,r.intersections.count,r.representation);fflush(nil)
   for i in r.intersections {
    if case .curve(let c)=i {print("TRUTH",c.truth);let p=try c.curve.point(at:0,tolerance:.standard);print("POINT",p.x,p.y,p.z)}
   }
   } catch {print("PUBLIC FAILURE",error)}
   fflush(nil)
  }
  var a=ExactScalarLedger(limits:try .init(work:8388608,storageBytes:268435456,valueDepth:32,coefficientDepth:32))
  let f=try OriginalPhysicalAngleScalarDomain(originalRadians:Double(bitPattern:0x3fddac670561bb50),using:&a)
  let h=try f.dividing(f.cosine(using:&a),f.sine(using:&a),using:&a)
  do {print("EXACT HEIGHT VS STORED2",try f.compare(h,f.integer(2,using:&a),using:&a))}catch{print("HEIGHT COMPARISON FAILURE",error)}
  fflush(nil)
 }
}

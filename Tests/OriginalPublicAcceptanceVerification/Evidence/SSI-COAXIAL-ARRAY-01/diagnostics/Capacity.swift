import CADCore
import CADGeometry
@main struct Capacity {
 static func main() throws {
 let a=Surface3D.analytic(.cone(apex:.origin,axis:.unitZ,halfAngle:0.3))
 let b=Surface3D.analytic(.cylinder(origin:.origin,axis:.unitZ,radius:1))
 let first=try SurfaceParameterBox(u:.init(lower:0,upper:2*Double.pi*0.6),v:.init(lower:-10,upper:10))
 let second=try SurfaceParameterBox(u:.init(lower:0,upper:2*Double.pi*0.9),v:.init(lower:-10,upper:10))
 let r=try DefaultSurfaceSurfaceIntersector().intersectionResult(first:a,over:first,second:b,over:second,options:.init(),tolerance:.standard,maximumSpanCount:262144,maximumSubdivisionDepth:12,remainingSourceDepth:1,consumeWork:{})
 print("output count",r.intersections.count,"allocated capacity",r.intersections.capacity)
 }
}

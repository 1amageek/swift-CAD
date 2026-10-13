import CADCore
import CADGeometry
import CADTopology
#if canImport(Darwin)
import Darwin
#elseif canImport(WASILibc)
import WASILibc
#endif

/// Observes the exact authored folded face before changing its material consumer.
@main struct TrimmedFoldObservation {
    static func rectangle(_ u0: Double, _ u1: Double, _ v0: Double, _ v1: Double) -> [SurfaceParameterCurve] {
        [.constantV(v:v0,uStart:u0,uEnd:u1), .constantU(u:u1,vStart:v0,vEnd:v1),
         .constantV(v:v1,uStart:u1,uEnd:u0), .constantU(u:u0,vStart:v1,vEnd:v0)]
    }
    static func face() throws -> (ValidatedBRepModel, FaceID, BodyID) {
        var model = BRepModel()
        let native = BSplineSurface3D(uDegree:1,vDegree:1,uKnots:[0,0,0.5,1,1],vKnots:[0,0,1,1],
            controlPoints:[0.0,1.0].map { v in [0.0,1.0,0.0].map { x in Point3D(x:x,y:v,z:0) } })
        let support = Surface3D.bSpline(native), surfaceID = SurfaceID()
        var loops: [LoopID] = []
        for (role,curves) in [(LoopRole.outer,rectangle(0,1,0,1)), (.inner,rectangle(0.125,0.375,0.25,0.75))] {
            let vertices = try curves.map { p -> Vertex in
                let uv = try p.startParameter(tolerance:.standard)
                return Vertex(point:try support.point(u:uv.u,v:uv.v,tolerance:.standard))
            }
            var coedges: [Coedge] = []
            for i in curves.indices {
                let next = (i+1)%curves.count, id = CurveID()
                let canonical = try curves[i].reversed(tolerance:.standard)
                model.geometry.curves[id] = .surfaceLift(.init(surface:support,parameterCurve:canonical))
                let edge = Edge(curveID:id,startVertexID:vertices[next].id,endVertexID:vertices[i].id,
                    trim:.init(startParameter:0,endParameter:1))
                model.edges[edge.id] = edge
                coedges.append(.init(edgeID:edge.id,orientation:.reversed,surfaceParameterCurve:curves[i]))
            }
            for vertex in vertices { model.vertices[vertex.id] = vertex }
            let loop = Loop(role:role,coedges:coedges)
            model.loops[loop.id] = loop; loops.append(loop.id)
        }
        let face = Face(surfaceID:surfaceID,loops:loops), shell = Shell(faceIDs:[face.id])
        let body = Body(sheetShellIDs:[shell.id])
        model.geometry.surfaces[surfaceID] = support; model.faces[face.id] = face
        model.shells[shell.id] = shell; model.bodies[body.id] = body
        return (try ValidatedBRepModel(model,tolerance:.standard,validationLevel:.exact),face.id,body.id)
    }
    static func main() {
        do {
            let original = try face()
            guard original.0.validationLevel == .exact, original.0.model.faces[original.1]?.loops.count == 2 else { exit(2) }
            print("OBSERVED exact Native folded face admission succeeds with original non-symmetric hole")
        } catch let error as KernelError {
            print("OBSERVED exact Native folded face admission KernelError",error)
            exit(3)
        } catch {
            print("OBSERVED exact Native folded face admission failure",error)
            exit(4)
        }
    }
}

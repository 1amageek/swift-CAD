import CADCore
import CADGeometry
import CADTopology
import HashTreeCollections
import Synchronization
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
    static func face(outerU1: Double = 1, includeHole: Bool = true, injective: Bool = false, planar: Bool = false, duplicateFace: Bool = false) throws -> (ValidatedBRepModel, FaceID, BodyID) {
        var model = BRepModel()
        let native = BSplineSurface3D(uDegree:1,vDegree:1,uKnots:[0,0,0.5,1,1],vKnots:[0,0,1,1],
            controlPoints:[0.0,1.0].map { v in (injective ? [0.0,1.0,2.0] : [0.0,1.0,0.0]).map { x in Point3D(x:x,y:v,z:0) } })
        let support: Surface3D = planar ? .plane(.init(origin:.origin,normal:.unitZ)) : .bSpline(native)
        let surfaceID = SurfaceID()
        var loops: [LoopID] = []
        var boundaries = [(LoopRole.outer,rectangle(0,outerU1,0,1))]
        if includeHole { boundaries.append((.inner,rectangle(0.125,0.375,0.25,0.75))) }
        for (role,curves) in boundaries {
            let vertices = try curves.map { p -> Vertex in
                let uv = try p.startParameter(tolerance:.standard)
                return Vertex(point:try support.point(u:uv.u,v:uv.v,tolerance:.standard))
            }
            var coedges: [Coedge] = []
            for i in curves.indices {
                let next = (i+1)%curves.count, id = CurveID()
                let canonical = try curves[i].reversed(tolerance:.standard)
                if planar {
                    model.geometry.curves[id] = .line(.init(origin:vertices[next].point,
                        direction:vertices[i].point-vertices[next].point))
                } else {
                    model.geometry.curves[id] = .surfaceLift(.init(surface:support,parameterCurve:canonical))
                }
                let edge = Edge(curveID:id,startVertexID:vertices[next].id,endVertexID:vertices[i].id,
                    trim:.init(startParameter:0,endParameter:1))
                model.edges[edge.id] = edge
                coedges.append(.init(edgeID:edge.id,orientation:.reversed,surfaceParameterCurve:curves[i]))
            }
            for vertex in vertices { model.vertices[vertex.id] = vertex }
            let loop = Loop(role:role,coedges:coedges)
            model.loops[loop.id] = loop; loops.append(loop.id)
        }
        let face = Face(surfaceID:surfaceID,loops:loops)
        var faces = [face.id]
        if duplicateFace {
            var oppositeLoops: [LoopID] = []
            for id in loops {
                guard let original = model.loops[id] else { throw Failure() }
                let coedges = try original.coedges.reversed().map { coedge in
                    Coedge(edgeID:coedge.edgeID,
                        orientation:coedge.orientation == .forward ? .reversed:.forward,
                        surfaceParameterCurve:try coedge.surfaceParameterCurve?.reversed(tolerance:.standard))
                }
                let loop = Loop(role:original.role,coedges:coedges)
                model.loops[loop.id] = loop; oppositeLoops.append(loop.id)
            }
            let opposite = Face(surfaceID:surfaceID,loops:oppositeLoops,orientation:.reversed)
            model.faces[opposite.id] = opposite; faces.append(opposite.id)
        }
        let shell = Shell(faceIDs:faces)
        let body = Body(sheetShellIDs:[shell.id])
        model.geometry.surfaces[surfaceID] = support; model.faces[face.id] = face
        model.shells[shell.id] = shell; model.bodies[body.id] = body
        return (try ValidatedBRepModel(model,tolerance:.standard,validationLevel:.exact),face.id,body.id)
    }
    struct Failure: Error {}
    struct Counts: Sendable { var work = 0; var bytes = 0 }
    final class Counter: Sendable {
        let state = Mutex(Counts())
        let workLimit: Int, byteLimit: Int, cancelWork: Int?
        init(work: Int = 80_000_000, bytes: Int = 1_073_741_824, cancelWork: Int? = nil) {
            workLimit = work; byteLimit = bytes; self.cancelWork = cancelWork
        }
        func work() throws {
            let cancel = try state.withLock { value in
                guard value.work < workLimit else { throw ExactScalarFailure.resourceLimit(.work) }
                value.work += 1; return value.work == cancelWork
            }
            if cancel { withUnsafeCurrentTask { $0?.cancel() } }
        }
        func storage(_ count: Int) throws {
            try state.withLock { value in
                let next = value.bytes.addingReportingOverflow(count)
                guard count >= 0, !next.overflow, next.partialValue <= byteLimit else {
                    throw ExactScalarFailure.resourceLimit(.storage)
                }
                value.bytes = next.partialValue
            }
        }
        var counts: Counts { state.withLock { $0 } }
    }
    static func require(_ condition: Bool) throws { if !condition { throw Failure() } }
    static func lift(lastX: Double = 0, v: Double = 0, weighted: Bool = false) -> Curve3D {
        .surfaceLift(.init(surface:.bSpline(.init(uDegree:1,vDegree:1,
            uKnots:[0,0,0.5,1,1],vKnots:[0,0,1,1],
            controlPoints:[0.0,1.0].map { row in [0.0,1.0,lastX].map { x in .init(x:x,y:row,z:0) } },
            weights:weighted ? [[1,2,3],[1,2,3]] : [[1,1,1],[1,1,1]])),
            parameterCurve:.constantV(v:v,uStart:0,uEnd:1)))
    }
    static func classify(_ curve: Curve3D, counter: Counter? = nil, depth: Int = 16) throws -> BRepEdgeGeometryKind {
        if let counter {
            return try BRepEdgeGeometryClassifier(remainingSourceDepth:depth,
                consumeWork:{ _ in try counter.work() },consumeStorage:{ try counter.storage($0) },
                maximumAlgebraicDepth:32).kind(curve:curve,from:0,to:1,tolerance:.standard)
        }
        return try BRepEdgeGeometryClassifier(remainingSourceDepth:depth).kind(curve:curve,from:0,to:1,tolerance:.standard)
    }
    static func main() async throws {
        let original = try face()
        try require(original.0.validationLevel == .exact && original.0.model.faces[original.1]?.loops.count == 2)
        print("PASS exact Native folded face admission preserves original non-symmetric hole and reversed coedges")
        for v in [0.0,0.5,1.0] {
            try require(classify(lift(v:v)) == .closed)
            try require(classify(lift(v:v,weighted:true)) == .closed)
            try require(classify(lift(lastX:Double.leastNonzeroMagnitude,v:v)) == .open)
        }
        print("PASS exact lifted endpoints, rational weights, both outer sides and least-positive near-closure remain distinct")
        let discontinuous = Curve3D.surfaceLift(.init(surface:.bSpline(.init(uDegree:1,vDegree:1,
            uKnots:[0,0,0.5,0.5,1,1],vKnots:[0,0,1,1],
            controlPoints:[0.0,1.0].map { v in [0.0,1.0,2.0,0.0].map { x in .init(x:x,y:v,z:0) } })),
            parameterCurve:.constantV(v:0,uStart:0.5,uEnd:1)))
        do { _ = try classify(discontinuous); throw Failure() }
        catch is GeometryConversionError {}
        catch GeometryError.invalidDistance(2) {}
        print("PASS discontinuous original Native lift is rejected before position closure")
        let curve = lift(), measured = Counter()
        try require(classify(curve,counter:measured) == .closed)
        let n = measured.counts
        try require(classify(curve,counter:Counter(work:n.work,bytes:n.bytes)) == .closed)
        do { _ = try classify(curve,counter:Counter(work:n.work-1,bytes:n.bytes)); throw Failure() }
        catch ExactScalarFailure.resourceLimit(.work) {}
        do { _ = try classify(curve,counter:Counter(work:n.work,bytes:n.bytes-1)); throw Failure() }
        catch ExactScalarFailure.resourceLimit(.storage) {}
        do { _ = try classify(curve,depth:0); throw Failure() }
        catch is GeometryConversionError {}
        print("PASS caller exactN, independent workN-1/storageN-1 and source-depth refusal")
#if !hasFeature(Embedded)
        print("METRIC lifted closure",n.work,n.bytes)
#endif
        let cancelled = Task { () throws -> Bool in
            do { _ = try classify(curve,counter:Counter(cancelWork:n.work)) }
            catch is CancellationError { return true }
            return false
        }
        try require(await cancelled.value)
        print("PASS final caller callback cancellation propagates before closure publication")
        var changed = original.0.model
        guard let face = changed.faces[original.1] else { throw Failure() }
        changed.geometry.surfaces[face.surfaceID] = .plane(.init(origin:.origin,normal:.unitZ))
        try require(original.0.model.geometry.surfaces[face.surfaceID] != changed.geometry.surfaces[face.surfaceID])
        print("PASS immutable exact model survives source construction scope and COW mutation")
    }
}

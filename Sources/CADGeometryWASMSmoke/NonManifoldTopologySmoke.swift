import CADCore
import CADGeometry
import CADTopology

struct NonManifoldTopologySmoke {
    static func verify(tolerance: ModelingTolerance) throws {
        let handler: any NonManifoldTopologyHandling = DefaultNonManifoldTopologyHandler()
        let limits = try TopologyRetentionLimits(maximumTopologyRecords: 100,
            maximumWork: 2_000, maximumDiagnostics: 100)
        let points = [Point3D.origin, Point3D(x: 1, y: 0, z: 0), Point3D(x: 0, y: 1, z: 0)]
        let vertices = points.map { Vertex(point: $0) }
        let surfaceID = SurfaceID()
        let surface = Surface3D.plane(Plane3D(origin: .origin, normal: .unitZ))
        var model = BRepModel(geometry: GeometryStore(surfaces: [surfaceID: surface]),
            vertices: Dictionary(uniqueKeysWithValues: vertices.map { ($0.id, $0) }))
        var coedges: [Coedge] = []
        for index in vertices.indices {
            let start = vertices[index], end = vertices[(index + 1) % vertices.count]
            let displacement = end.point - start.point
            let curveID = CurveID()
            model.geometry.curves[curveID] = .line(Line3D(origin: start.point,
                direction: try displacement.normalized(tolerance: tolerance.distance)))
            let edge = Edge(curveID: curveID, startVertexID: start.id, endVertexID: end.id,
                trim: .init(startParameter: 0, endParameter: displacement.length))
            model.edges[edge.id] = edge
            let a = try surface.parameterProjection(of: start.point, tolerance: tolerance)
            let b = try surface.parameterProjection(of: end.point, tolerance: tolerance)
            coedges.append(Coedge(edgeID: edge.id, surfaceParameterCurve: .affine(
                origin: .init(x: a.u, y: a.v), direction: .init(x: b.u - a.u, y: b.v - a.v),
                startParameter: 0, endParameter: 1)))
        }
        var roots: [ShapeReference] = []
        for _ in 0..<3 {
            let loop = Loop(coedges: coedges)
            let face = Face(surfaceID: surfaceID, loops: [loop.id])
            model.loops[loop.id] = loop
            model.faces[face.id] = face
            roots.append(.face(face.id))
        }
        let source = Shape(root: .compound(roots), model: model)
        let retained = try handler.retain(source, limits: limits)
        try require(retained.root == source.root && retained.model == model,
            "Raw retention changed the non-manifold source.", tolerance)
        let issue = TopologyRetentionIssue.excessiveEdgeIncidence(edgeID: coedges[0].edgeID, useCount: 3)
        let report = try handler.diagnose(retained, limits: limits)
        try require(report.issues.contains(issue), "Shared-edge non-manifold incidence was missed.", tolerance)
        for bodyAdmission in [false, true] {
            do {
                if bodyAdmission { _ = try handler.admitToBRepModeling(retained, tolerance: tolerance, limits: limits) }
                else { _ = try handler.admitToShapeOperations(retained, tolerance: tolerance, limits: limits) }
                throw failure("Defective topology was admitted to modeling.", tolerance)
            } catch TopologyRetentionError.modelingAdmissionRejected(let rejected) {
                try require(rejected.issues.contains(issue), "Admission lost the diagnostic report.", tolerance)
            }
        }
        let vertex = vertices[0]
        let standalone = Shape(root: .vertex(vertex.id), model: BRepModel(vertices: [vertex.id: vertex]))
        let valid = try handler.retain(standalone, limits: limits)
        let admitted = try handler.admitToShapeOperations(valid, tolerance: tolerance, limits: limits)
        try require(admitted == standalone, "Valid dimensional admission changed its snapshot.", tolerance)
        do {
            _ = try handler.admitToBRepModeling(valid, tolerance: tolerance, limits: limits)
            throw failure("A standalone vertex became a body-owned model.", tolerance)
        } catch TopologyError.unreferencedTopology { }
        let missing = EdgeID()
        let malformed = try handler.retain(Shape(root: .edge(missing), model: BRepModel()), limits: limits)
        let malformedReport = try handler.diagnose(malformed, limits: limits)
        try require(malformedReport.issues == [.missingReference(owner: nil, target: .edge(missing))],
            "Malformed source was silently pruned.", tolerance)
        do {
            _ = try handler.retain(source, limits: .init(maximumTopologyRecords: 100,
                maximumWork: 1, maximumDiagnostics: 100))
            throw failure("Retention ignored its work bound.", tolerance)
        } catch TopologyRetentionError.resourceLimitExceeded(.work) { }
    }

    private static func require(_ condition: Bool, _ message: String, _ tolerance: ModelingTolerance) throws {
        guard condition else { throw failure(message, tolerance) }
    }

    private static func failure(_ message: String, _ tolerance: ModelingTolerance) -> KernelError {
        KernelError(phase: .topology, code: .topologyFailure, tolerance: tolerance, message: message)
    }
}

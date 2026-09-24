import CADCore
import CADGeometry
import CADIR
import CADTopology
import Testing
@testable import CADModeling

@Suite("Loft finite cap contacts")
struct LoftCapContactTests {
    @Test(.timeLimit(.minutes(1)), arguments: [false, true], [false, true])
    func coplanarSharedEdgeRequiresOppositeRegions(overlap: Bool, shared: Bool) throws {
        var context = EvaluationContext(parameters: ResolvedParameterTable(),
            brep: BRepModel(), profiles: [:], tolerance: .standard)
        func patch(_ lower: Double, _ upper: Double) -> BSplineSurface3D {
            .bilinearPatch(bottomLeft: Point3D(x: lower, y: -1, z: 0),
                bottomRight: Point3D(x: upper, y: -1, z: 0),
                topRight: Point3D(x: upper, y: 1, z: 0),
                topLeft: Point3D(x: lower, y: 1, z: 0))
        }
        func feature(_ surface: BSplineSurface3D) -> FeatureNode {
            FeatureNode(operation: .bSplineSurface(BSplineSurfaceFeature(surface: surface)),
                outputs: [FeatureOutput(role: .sheet)])
        }
        let evaluator = BSplineSurfaceFeatureEvaluator()
        let capResult = try evaluator.evaluate(feature: feature(patch(-1, 1)), context: context)
        context.brep = capResult.brep
        let cap = try #require(context.brep.faces.values.first)
        let result = try evaluator.evaluate(feature: feature(patch(1, overlap ? 0.5 : 2)), context: context)
        var model = result.brep
        let side = try #require(model.faces.values.first { $0.id != cap.id })
        let loopID = try #require(side.loops.first)
        var loop = try #require(model.loops[loopID])
        let capEdge = try #require(context.brep.edges.values.first {
            context.brep.vertices[$0.startVertexID]?.point.x == 1
                && context.brep.vertices[$0.endVertexID]?.point.x == 1
        })
        if shared {
            for index in loop.coedges.indices {
                var edge = try #require(model.edges[loop.coedges[index].edgeID])
                for vertex in context.brep.vertices.values {
                    if model.vertices[edge.startVertexID]?.point == vertex.point { edge.startVertexID = vertex.id }
                    if model.vertices[edge.endVertexID]?.point == vertex.point { edge.endVertexID = vertex.id }
                }
                model.edges[edge.id] = edge
                if Set([edge.startVertexID, edge.endVertexID]) == Set([capEdge.startVertexID, capEdge.endVertexID]) {
                    loop.coedges[index].edgeID = capEdge.id
                    if edge.startVertexID != capEdge.startVertexID {
                        loop.coedges[index].orientation = loop.coedges[index].orientation == .forward ? .reversed : .forward
                    }
                }
            }
            model.loops[loopID] = loop
        }
        model.geometry.surfaces[cap.surfaceID] = .plane(Plane3D(origin: .origin, normal: .unitZ))
        for id in cap.loops {
            var boundary = try #require(model.loops[id])
            for index in boundary.coedges.indices { boundary.coedges[index].surfaceParameterCurve = nil }
            model.loops[id] = boundary
        }
        try ExactFacePcurveBuilder().populateMissingPcurves(in: &model, tolerance: .standard)
        let builder = ExactLoftBodyBuilder(featureID: FeatureID(), context: context)
        let operation = {
            try builder.validateCapContacts(capFaceIDs: [cap.id], sideFaceIDs: [side.id],
                edgeIDs: loop.coedges.map(\.edgeID), model: model)
        }
        if shared && !overlap { try operation() }
        else { #expect(throws: KernelError.self, performing: operation) }
    }

    @Test(.timeLimit(.minutes(1)), arguments: [(0.0, 2.0), (0.0, 0.75), (4.0, 2.0)], [false, true])
    func sideInteriorIntersectionUsesFiniteCap(placement: (Double, Double), coplanar: Bool) throws {
        let (centerX, radius) = placement
        var context = EvaluationContext(parameters: ResolvedParameterTable(),
            brep: BRepModel(), profiles: [:], tolerance: .standard)
        let cap = BSplineSurface3D.bilinearPatch(
            bottomLeft: Point3D(x: centerX - radius, y: -radius, z: 0),
            bottomRight: Point3D(x: centerX + radius, y: -radius, z: 0),
            topRight: Point3D(x: centerX + radius, y: radius, z: 0),
            topLeft: Point3D(x: centerX - radius, y: radius, z: 0))
        let capResult = try BSplineSurfaceFeatureEvaluator().evaluate(
            feature: FeatureNode(operation: .bSplineSurface(BSplineSurfaceFeature(surface: cap)),
                outputs: [FeatureOutput(role: .sheet)]), context: context)
        var model = capResult.brep
        let capFace = try #require(model.faces.values.first)
        model.geometry.surfaces[capFace.surfaceID] = .plane(Plane3D(origin: .origin, normal: .unitZ))
        for loopID in capFace.loops {
            var loop = try #require(model.loops[loopID])
            for index in loop.coedges.indices { loop.coedges[index].surfaceParameterCurve = nil }
            model.loops[loopID] = loop
        }
        try ExactFacePcurveBuilder().populateMissingPcurves(in: &model, tolerance: .standard)
        context.brep = model

        // z = x^2 + y^2 - 1/4 on [-1, 1]^2. Every boundary is
        // above the cap plane, but the interior has a closed intersection.
        let scalarControls = [1.0, -1.0, 1.0]
        let controls = (0..<3).map { row in
            (0..<3).map { column in
                Point3D(x: Double(column - 1), y: Double(row - 1),
                    z: coplanar ? 0 : scalarControls[column] + scalarControls[row] - 0.25)
            }
        }
        let side = BSplineSurface3D(uDegree: 2, vDegree: 2,
            uKnots: [0, 0, 0, 1, 1, 1], vKnots: [0, 0, 0, 1, 1, 1],
            controlPoints: controls)
        let result = try BSplineSurfaceFeatureEvaluator().evaluate(
            feature: FeatureNode(operation: .bSplineSurface(BSplineSurfaceFeature(surface: side)),
                outputs: [FeatureOutput(role: .sheet)]), context: context)
        let sideID = try #require(result.brep.faces.keys.first { $0 != capFace.id })
        let edgeIDs = Array(result.brep.edges.keys)
        let builder = ExactLoftBodyBuilder(featureID: FeatureID(), context: context)
        if centerX == 0 {
            do {
                try builder.validateCapContacts(capFaceIDs: [capFace.id], sideFaceIDs: [sideID],
                    edgeIDs: edgeIDs, model: result.brep)
                Issue.record("Side-interior intersection must not be admitted.")
            } catch let error as KernelError {
                #expect(error.code == .invalidInput)
                #expect(error.message == (coplanar
                    ? "A coplanar Loft side overlaps a cap interior."
                    : "A Loft side intersects a cap interior."))
            }
        } else {
            try builder.validateCapContacts(capFaceIDs: [capFace.id], sideFaceIDs: [sideID],
                edgeIDs: edgeIDs, model: result.brep)
        }
    }
}

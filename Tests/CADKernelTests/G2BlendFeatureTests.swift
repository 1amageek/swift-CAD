import Testing
import CADCore
import CADGeometry
import CADIR
import CADTopology
@testable import CADKernel

@Suite("G2 blend feature")
struct G2BlendFeatureTests {
    @Test(.timeLimit(.minutes(1)))
    func createsValidatedQuinticSurfaceWithG2Boundaries() throws {
        var document = makeRectangleExtrudeDocument(documentUnits: .meters)
        let sourceFeatureID = try #require(document.designGraph.order.last)
        let source = try DocumentEvaluator(tolerance: .standard, artifactPolicy: .deferred).evaluate(document)
        let edgeSubshapeID = SubshapeID(
            featureID: sourceFeatureID,
            role: GeneratedSubshapeRole.edge.rawValue,
            ordinal: 0
        )
        let selected = try source.stableSubshapeReference(for: edgeSubshapeID)
        let edgeLength = try selectedEdgeLength(edgeSubshapeID, source: source)
        let sourceVolume = try source.brep.volume(tolerance: .standard)
        let distance = 0.002
        let blendID = FeatureID()
        let operation = FeatureOperation.g2Blend(G2BlendFeature(
            target: G2BlendTargetReference(featureID: sourceFeatureID),
            edges: [selected],
            distance: .constant(.length(distance, unit: .meter))
        ))
        let node = try FeatureNodeFactory.make(operation: operation, id: blendID, in: document, tolerance: .standard)
        document.designGraph.nodes[blendID] = node
        document.designGraph.order.append(blendID)
        document.designGraph.dependencies.append(DependencyEdge(source: sourceFeatureID, target: blendID))
        document.designGraph.revision = document.designGraph.revision.advanced()

        let evaluated = try DocumentEvaluator(tolerance: .standard, artifactPolicy: .deferred).evaluate(document)

        try evaluated.brep.validate(level: .volumetric, tolerance: .standard)
        #expect(evaluated.brep.faces.count == 7)
        #expect(evaluated.brep.edges.count == 15)
        #expect(evaluated.brep.vertices.count == 10)
        let blendFace = try #require(evaluated.brep.faces.values.first { face in
            if case .bSpline = evaluated.brep.geometry.surfaces[face.surfaceID] { return true }
            return false
        })
        guard case let .bSpline(surface) = evaluated.brep.geometry.surfaces[blendFace.surfaceID] else {
            Issue.record("G2 blend must generate an exact B-spline surface.")
            return
        }
        #expect(surface.uDegree == 5)
        #expect(surface.vDegree == 1)
        try verifyG2Boundaries(face: blendFace, surface: surface, model: evaluated.brep)
        let expectedRemovedArea = (113.0 / 756.0) * distance * distance
        let expectedVolume = sourceVolume - expectedRemovedArea * edgeLength
        #expect(abs(try evaluated.brep.volume(tolerance: .standard) - expectedVolume) <= 1.0e-12)
        let descendants = evaluated.lineage.values.filter {
            $0.output.featureID == blendID
                && $0.output.role == GeneratedSubshapeRole.edge.rawValue
                && $0.parents.contains(selected.subshapeID)
        }
        #expect(descendants.count == 2)
        #expect(descendants.allSatisfy { $0.relation == .split })
    }

    private func verifyG2Boundaries(
        face: Face,
        surface: BSplineSurface3D,
        model: BRepModel
    ) throws {
        let loopID = try #require(face.loops.first)
        let loop = try #require(model.loops[loopID])
        var boundaryCount = 0
        for coedge in loop.coedges {
            let edge = try #require(model.edges[coedge.edgeID])
            guard case .line = model.geometry.curves[edge.curveID],
                  let pcurve = coedge.surfaceParameterCurve else {
                continue
            }
            let parameter = try pcurve.parameter(
                atNormalizedFraction: 0.5,
                tolerance: .standard
            )
            let geometry = try surface.differentialGeometry(
                atU: parameter.u,
                v: parameter.v,
                tolerance: .standard
            )
            let blendNormal = face.orientation == .forward ? geometry.normal : -geometry.normal
            let adjacent = try #require(model.faces.values.first { candidate in
                guard candidate.id != face.id else { return false }
                return candidate.loops.contains { candidateLoopID in
                    model.loops[candidateLoopID]?.coedges.contains { $0.edgeID == coedge.edgeID } == true
                }
            })
            guard case let .plane(plane) = model.geometry.surfaces[adjacent.surfaceID] else {
                continue
            }
            let planeNormal = adjacent.orientation == .forward ? plane.normal : -plane.normal
            #expect(blendNormal.dot(planeNormal) >= 1.0 - 1.0e-10)
            #expect(abs(geometry.normalCurvatureU) <= 1.0e-10)
            boundaryCount += 1
        }
        #expect(boundaryCount == 2)
    }

    private func selectedEdgeLength(
        _ subshapeID: SubshapeID,
        source: EvaluatedDocument
    ) throws -> Double {
        guard case let .edge(edgeID) = source.subshapes[subshapeID],
              let edge = source.brep.edges[edgeID],
              let start = source.brep.vertices[edge.startVertexID],
              let end = source.brep.vertices[edge.endVertexID] else {
            throw KernelError(
                phase: .evaluation,
                code: .missingReference,
                tolerance: .standard,
                message: "G2 blend fixture edge could not be measured."
            )
        }
        return (end.point - start.point).length
    }
}

import Testing
import CADCore
import CADGeometry
import CADIR
import CADTopology
@testable import CADKernel

@Suite("Setback corner feature")
struct SetbackCornerFeatureTests {
    @Test(.timeLimit(.minutes(1)))
    func createsValidatedRollingBallCornerWithStableLineage() throws {
        var document = makeRectangleExtrudeDocument(documentUnits: .meters)
        let sourceFeatureID = try #require(document.designGraph.order.last)
        let source = try DocumentEvaluator(tolerance: .standard, artifactPolicy: .deferred).evaluate(document)
        let vertexSubshapeID = SubshapeID(
            featureID: sourceFeatureID,
            role: GeneratedSubshapeRole.vertex.rawValue,
            ordinal: 0
        )
        let selected = try source.stableSubshapeReference(for: vertexSubshapeID)
        let sourceVertexID = try sourceVertexID(subshapeID: vertexSubshapeID, source: source)
        let edgeLengths = try incidentEdgeLengths(vertexID: sourceVertexID, source: source)
        let sourceVolume = try source.brep.volume(tolerance: .standard)
        let radius = 0.002
        let cornerID = FeatureID()
        let operation = FeatureOperation.setbackCorner(SetbackCornerFeature(
            target: SetbackCornerTargetReference(featureID: sourceFeatureID),
            vertex: selected,
            radius: .constant(.length(radius, unit: .meter))
        ))
        let node = try FeatureNodeFactory.make(operation: operation, id: cornerID, in: document, tolerance: .standard)
        document.designGraph.nodes[cornerID] = node
        document.designGraph.order.append(cornerID)
        document.designGraph.dependencies.append(DependencyEdge(source: sourceFeatureID, target: cornerID))
        document.designGraph.revision = document.designGraph.revision.advanced()

        let evaluator = DocumentEvaluator(tolerance: .standard, artifactPolicy: .deferred)
        let evaluated = try evaluator.evaluate(document)
        let repeated = try evaluator.evaluate(document)

        try evaluated.brep.validate(level: .volumetric, tolerance: .standard)
        #expect(evaluated.brep.faces.count == 10)
        #expect(evaluated.brep.edges.count == 21)
        #expect(evaluated.brep.vertices.count == 13)
        #expect(evaluated.brep.loops.values.flatMap(\.coedges).allSatisfy {
            $0.surfaceParameterCurve != nil
        })
        #expect(evaluated.brep == repeated.brep)
        #expect(evaluated.subshapes == repeated.subshapes)
        #expect(evaluated.lineage == repeated.lineage)
        let sphereFace = try #require(evaluated.brep.faces.values.first { face in
            if case .analytic(.sphere) = evaluated.brep.geometry.surfaces[face.surfaceID] { return true }
            return false
        })
        let cylinderCount = evaluated.brep.faces.values.filter { face in
            if case .cylinder = evaluated.brep.geometry.surfaces[face.surfaceID] { return true }
            return false
        }.count
        #expect(cylinderCount == 3)
        try verifySphereCylinderTangency(sphereFace: sphereFace, model: evaluated.brep)
        let centralRemoved = radius * radius * radius * (1.0 - Double.pi / 6.0)
        let edgeRemoved = radius * radius * (1.0 - Double.pi / 4.0)
            * edgeLengths.reduce(0.0) { $0 + ($1 - radius) }
        let expectedVolume = sourceVolume - centralRemoved - edgeRemoved
        #expect(abs(try evaluated.brep.volume(tolerance: .standard) - expectedVolume) <= 1.0e-12)
        let vertexDescendants = evaluated.lineage.values.filter {
            $0.output.featureID == cornerID
                && $0.output.role == GeneratedSubshapeRole.vertex.rawValue
                && $0.parents.contains(selected.subshapeID)
        }
        #expect(vertexDescendants.count == 3)
        #expect(vertexDescendants.allSatisfy { $0.relation == .split })
        let crossDimensionDescendants = evaluated.lineage.values.filter {
            $0.output.featureID == cornerID
                && $0.output.role != GeneratedSubshapeRole.vertex.rawValue
                && $0.parents.contains(selected.subshapeID)
        }
        #expect(crossDimensionDescendants.isEmpty)
        do {
            _ = try evaluated.topologyReference(for: selected)
            Issue.record("A replaced corner vertex must not resolve to one setback boundary implicitly.")
        } catch let error as KernelError {
            #expect(error.code == .ambiguousSelection)
            #expect(error.subshapeID == selected.subshapeID)
        }
    }

    private func verifySphereCylinderTangency(
        sphereFace: Face,
        model: BRepModel
    ) throws {
        let sphereSurface = try #require(model.geometry.surfaces[sphereFace.surfaceID])
        let loopID = try #require(sphereFace.loops.first)
        let loop = try #require(model.loops[loopID])
        #expect(loop.coedges.count == 3)
        for coedge in loop.coedges {
            let spherePcurve = try #require(coedge.surfaceParameterCurve)
            let sphereParameter = try spherePcurve.parameter(
                atNormalizedFraction: 0.5,
                tolerance: .standard
            )
            let sphereGeometry = try sphereSurface.differentialGeometry(
                atU: sphereParameter.u,
                v: sphereParameter.v,
                tolerance: .standard
            )
            let adjacent = try #require(model.faces.values.first { candidate in
                guard candidate.id != sphereFace.id else { return false }
                return candidate.loops.contains { candidateLoopID in
                    model.loops[candidateLoopID]?.coedges.contains { $0.edgeID == coedge.edgeID } == true
                }
            })
            guard let cylinderSurface = model.geometry.surfaces[adjacent.surfaceID],
                  case .cylinder = cylinderSurface else {
                Issue.record("Every spherical setback boundary must adjoin a cylinder.")
                continue
            }
            let adjacentLoopID = try #require(adjacent.loops.first)
            let adjacentLoop = try #require(model.loops[adjacentLoopID])
            let adjacentCoedge = try #require(adjacentLoop.coedges.first { $0.edgeID == coedge.edgeID })
            let cylinderPcurve = try #require(adjacentCoedge.surfaceParameterCurve)
            let cylinderParameter = try cylinderPcurve.parameter(
                atNormalizedFraction: 0.5,
                tolerance: .standard
            )
            let cylinderGeometry = try cylinderSurface.differentialGeometry(
                atU: cylinderParameter.u,
                v: cylinderParameter.v,
                tolerance: .standard
            )
            let sphereNormal = sphereFace.orientation == .forward
                ? sphereGeometry.normal
                : -sphereGeometry.normal
            let cylinderNormal = adjacent.orientation == .forward
                ? cylinderGeometry.normal
                : -cylinderGeometry.normal
            #expect(sphereNormal.dot(cylinderNormal) >= 1.0 - 1.0e-10)
        }
    }

    private func sourceVertexID(
        subshapeID: SubshapeID,
        source: EvaluatedDocument
    ) throws -> VertexID {
        guard case let .vertex(vertexID) = source.subshapes[subshapeID] else {
            throw KernelError(
                phase: .evaluation,
                code: .missingReference,
                tolerance: .standard,
                message: "Setback fixture vertex could not be resolved."
            )
        }
        return vertexID
    }

    private func incidentEdgeLengths(
        vertexID: VertexID,
        source: EvaluatedDocument
    ) throws -> [Double] {
        try source.brep.edges.values.compactMap { edge in
            guard edge.startVertexID == vertexID || edge.endVertexID == vertexID else { return nil }
            let otherID = edge.startVertexID == vertexID ? edge.endVertexID : edge.startVertexID
            let start = try #require(source.brep.vertices[vertexID])
            let end = try #require(source.brep.vertices[otherID])
            return (end.point - start.point).length
        }
    }
}

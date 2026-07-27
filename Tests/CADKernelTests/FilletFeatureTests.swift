import Testing
import CADCore
import CADGeometry
import CADIR
import CADTopology
@testable import CADKernel

@Suite("Fillet feature")
struct FilletFeatureTests {
    @Test(.timeLimit(.minutes(1)))
    func createsValidatedQuarterCylinderAndSplitLineage() throws {
        var document = makeRectangleExtrudeDocument(documentUnits: .meters)
        let sourceFeatureID = try #require(document.designGraph.order.last)
        let source = try DocumentEvaluator(tolerance: .standard, artifactPolicy: .deferred).evaluate(document)
        let selectedID = SubshapeID(
            featureID: sourceFeatureID,
            role: GeneratedSubshapeRole.edge.rawValue,
            ordinal: 0
        )
        let selected = try source.stableSubshapeReference(for: selectedID)
        let edgeLength = try selectedEdgeLength(selectedID, source: source)
        let sourceVolume = try source.brep.volume(tolerance: .standard)
        let radius = 0.002
        let filletID = FeatureID()
        let operation = FeatureOperation.fillet(FilletFeature(
            target: FilletTargetReference(featureID: sourceFeatureID),
            edges: [selected],
            radius: .constant(.length(radius, unit: .meter))
        ))
        let node = try FeatureNodeFactory.make(operation: operation, id: filletID, in: document, tolerance: .standard)
        document.designGraph.nodes[filletID] = node
        document.designGraph.order.append(filletID)
        document.designGraph.dependencies.append(DependencyEdge(source: sourceFeatureID, target: filletID))
        document.designGraph.revision = document.designGraph.revision.advanced()

        let evaluator = DocumentEvaluator(tolerance: .standard, artifactPolicy: .deferred)
        let evaluated = try evaluator.evaluate(document)
        let repeated = try evaluator.evaluate(document)

        try evaluated.brep.validate(level: .volumetric, tolerance: .standard)
        #expect(evaluated.brep.faces.count == 7)
        #expect(evaluated.brep.edges.count == 15)
        #expect(evaluated.brep.vertices.count == 10)
        #expect(evaluated.brep.loops.values.flatMap(\.coedges).allSatisfy {
            $0.surfaceParameterCurve != nil
        })
        #expect(evaluated.brep == repeated.brep)
        #expect(evaluated.subshapes == repeated.subshapes)
        #expect(evaluated.lineage == repeated.lineage)
        let cylinders = evaluated.brep.faces.values.filter { face in
            guard let surface = evaluated.brep.geometry.surfaces[face.surfaceID] else { return false }
            if case .cylinder = surface { return true }
            return false
        }
        #expect(cylinders.count == 1)
        let cylinderFace = try #require(cylinders.first)
        try verifyG1Tangency(of: cylinderFace, in: evaluated.brep)
        let expectedVolume = sourceVolume
            - radius * radius * (1.0 - Double.pi / 4.0) * edgeLength
        #expect(abs(try evaluated.brep.volume(tolerance: .standard) - expectedVolume) <= 1.0e-12)
        let descendants = evaluated.lineage.values.filter {
            $0.output.featureID == filletID
                && $0.output.role == GeneratedSubshapeRole.edge.rawValue
                && $0.parents.contains(selected.subshapeID)
        }
        #expect(descendants.count == 2)
        #expect(descendants.allSatisfy { $0.relation == .split })
        do {
            _ = try evaluated.topologyReference(for: selected)
            Issue.record("A replaced sharp edge must not resolve to one fillet boundary implicitly.")
        } catch let error as KernelError {
            #expect(error.code == .ambiguousSelection)
            #expect(error.subshapeID == selected.subshapeID)
        }
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
                message: "Fillet fixture edge could not be measured."
            )
        }
        return (end.point - start.point).length
    }

    private func verifyG1Tangency(
        of cylinderFace: Face,
        in model: BRepModel
    ) throws {
        let cylinderSurface = try #require(model.geometry.surfaces[cylinderFace.surfaceID])
        let loopID = try #require(cylinderFace.loops.first)
        let loop = try #require(model.loops[loopID])
        var verifiedBoundaryCount = 0
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
            let cylinderGeometry = try cylinderSurface.differentialGeometry(
                atU: parameter.u,
                v: parameter.v,
                tolerance: .standard
            )
            let cylinderNormal = cylinderFace.orientation == .forward
                ? cylinderGeometry.normal
                : -cylinderGeometry.normal
            let adjacent = try #require(model.faces.values.first { candidate in
                guard candidate.id != cylinderFace.id else { return false }
                return candidate.loops.contains { candidateLoopID in
                    model.loops[candidateLoopID]?.coedges.contains {
                        $0.edgeID == coedge.edgeID
                    } == true
                }
            })
            guard case let .plane(plane) = model.geometry.surfaces[adjacent.surfaceID] else {
                continue
            }
            let planeNormal = adjacent.orientation == .forward ? plane.normal : -plane.normal
            #expect(cylinderNormal.dot(planeNormal) >= 1.0 - 1.0e-10)
            verifiedBoundaryCount += 1
        }
        #expect(verifiedBoundaryCount == 2)
    }
}

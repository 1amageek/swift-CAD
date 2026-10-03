import Testing
import CADCore
import CADIR
import CADTopology
@testable import CADKernel

@Suite("Shell feature")
struct ShellFeatureTests {
    @Test(.timeLimit(.minutes(1)))
    func createsValidatedOpenFaceUniformShell() throws {
        var document = makeRectangleExtrudeDocument(documentUnits: .meters)
        let sourceFeatureID = try #require(document.designGraph.order.last)
        let source = try DocumentEvaluator(tolerance: .standard, artifactPolicy: .deferred).evaluate(document)
        let removedFaceID = SubshapeID(
            featureID: sourceFeatureID,
            role: GeneratedSubshapeRole.startFace.rawValue,
            ordinal: 0
        )
        let removedFace = try source.stableSubshapeReference(for: removedFaceID)
        let sourceVolume = try source.brep.volume(tolerance: .standard)
        let thickness = 0.002
        let shellID = FeatureID()
        // Walled inside: a negative thickness, as Plasticity's sign has it.
        let operation = FeatureOperation.shell(ShellFeature(
            target: ShellTargetReference(featureID: sourceFeatureID),
            removedFaces: [removedFace],
            thickness: .constant(.length(-thickness, unit: .meter))
        ))
        let node = try FeatureNodeFactory.make(operation: operation, id: shellID, in: document, tolerance: .standard)
        document.designGraph.nodes[shellID] = node
        document.designGraph.order.append(shellID)
        document.designGraph.dependencies.append(DependencyEdge(source: sourceFeatureID, target: shellID))
        document.designGraph.revision = document.designGraph.revision.advanced()

        let evaluator = DocumentEvaluator(tolerance: .standard, artifactPolicy: .deferred)
        let evaluated = try evaluator.evaluate(document)
        let repeated = try evaluator.evaluate(document)

        try evaluated.brep.validate(level: .volumetric, tolerance: .standard)
        #expect(evaluated.brep.bodies.count == 1)
        #expect(evaluated.brep.shells.count == 1)
        // The outer and the cavity's five faces, and the opened face left as the rim around the
        // opening.
        #expect(evaluated.brep.faces.count == 11)
        #expect(evaluated.brep.edges.count == 24)
        #expect(evaluated.brep.vertices.count == 16)
        #expect(evaluated.brep.loops.values.flatMap(\.coedges).allSatisfy {
            $0.surfaceParameterCurve != nil
        })
        #expect(evaluated.brep == repeated.brep)
        #expect(evaluated.subshapes == repeated.subshapes)
        #expect(evaluated.lineage == repeated.lineage)
        let cavityVolume = (0.040 - 2.0 * thickness)
            * (0.020 - 2.0 * thickness)
            * (0.010 - thickness)
        #expect(abs(try evaluated.brep.volume(tolerance: .standard) - (sourceVolume - cavityVolume)) <= 1.0e-12)
        // The opened face's only descendant is the rim face it leaves.
        let descendants = evaluated.lineage.values.filter {
            $0.output.featureID == shellID && $0.parents.contains(removedFace.subshapeID)
        }
        let faceDescendants = descendants.filter {
            if case .face = evaluated.subshapes[$0.output] { return true }
            return false
        }
        #expect(faceDescendants.count == 1)
        #expect(faceDescendants.count == descendants.count)
        // The opened face resolves to the rim it leaves.
        guard case .face = try evaluated.topologyReference(for: removedFace) else {
            Issue.record("An opened face must resolve to the rim it leaves.")
            return
        }
    }
}

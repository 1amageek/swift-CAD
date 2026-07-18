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
        let operation = FeatureOperation.shell(ShellFeature(
            target: ShellTargetReference(featureID: sourceFeatureID),
            removedFaces: [removedFace],
            thickness: .constant(.length(thickness, unit: .meter))
        ))
        let node = try FeatureNodeFactory.make(operation: operation, id: shellID, in: document, tolerance: .standard)
        document.designGraph.nodes[shellID] = node
        document.designGraph.order.append(shellID)
        document.designGraph.dependencies.append(DependencyEdge(source: sourceFeatureID, target: shellID))
        document.designGraph.revision = document.designGraph.revision.advanced()

        let evaluated = try DocumentEvaluator(tolerance: .standard, artifactPolicy: .deferred).evaluate(document)

        try evaluated.brep.validate(level: .volumetric, tolerance: .standard)
        #expect(evaluated.brep.bodies.count == 1)
        #expect(evaluated.brep.shells.count == 1)
        #expect(evaluated.brep.faces.count == 14)
        #expect(evaluated.brep.edges.count == 28)
        #expect(evaluated.brep.vertices.count == 16)
        #expect(evaluated.brep.loops.values.flatMap(\.coedges).allSatisfy {
            $0.surfaceParameterCurve != nil
        })
        let cavityVolume = (0.040 - 2.0 * thickness)
            * (0.020 - 2.0 * thickness)
            * (0.010 - thickness)
        #expect(abs(try evaluated.brep.volume(tolerance: .standard) - (sourceVolume - cavityVolume)) <= 1.0e-12)
        let removedFaceDescendants = evaluated.lineage.values.filter {
            $0.output.featureID == shellID
                && $0.output.role == GeneratedSubshapeRole.face.rawValue
                && $0.parents.contains(removedFace.subshapeID)
        }
        #expect(removedFaceDescendants.count == 4)
        #expect(removedFaceDescendants.allSatisfy { $0.relation == .merged })
        let crossDimensionDescendants = evaluated.lineage.values.filter {
            $0.output.featureID == shellID
                && $0.output.role != GeneratedSubshapeRole.face.rawValue
                && $0.parents.contains(removedFace.subshapeID)
        }
        #expect(crossDimensionDescendants.isEmpty)
    }
}

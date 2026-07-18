import CADCore
import CADIR
import CADTopology
import Testing
@testable import CADKernel

@Suite("Face Knife Feature")
struct FaceKnifeFeatureTests {
    @Test(.timeLimit(.minutes(1)))
    func splitsConcaveLoopWithDeterministicTargetFaceLineage() throws {
        var document = makeRectangleExtrudeDocument(documentUnits: .meters)
        let sourceFeatureID = try #require(document.designGraph.order.last)
        let source = try DocumentEvaluator(tolerance: .standard).evaluate(document)
        let knifeFeatureID = FeatureID()
        let sourceFaceSubshapeID = SubshapeID(
            featureID: sourceFeatureID,
            role: GeneratedSubshapeRole.startFace.rawValue,
            ordinal: 0
        )
        let sourceBodySubshapeID = SubshapeID(
            featureID: sourceFeatureID,
            role: GeneratedSubshapeRole.body.rawValue,
            ordinal: 0
        )
        let knifeFeature = FeatureNode(
            id: knifeFeatureID,
            operation: .faceKnife(FaceKnifeFeature(
                target: FaceKnifeTargetReference(featureID: sourceFeatureID),
                face: try source.stableSubshapeReference(for: sourceFaceSubshapeID),
                loop: [
                    Point3D(x: -0.012, y: -0.006, z: 0.0),
                    Point3D(x: 0.012, y: -0.006, z: 0.0),
                    Point3D(x: 0.004, y: 0.0, z: 0.0),
                    Point3D(x: 0.012, y: 0.006, z: 0.0),
                    Point3D(x: -0.012, y: 0.006, z: 0.0),
                ]
            )),
            inputs: [FeatureInput(featureID: sourceFeatureID, role: .target)],
            outputs: [FeatureOutput(role: .body)]
        )
        document.designGraph.nodes[knifeFeatureID] = knifeFeature
        document.designGraph.order.append(knifeFeatureID)
        document.designGraph.dependencies.append(DependencyEdge(
            source: sourceFeatureID,
            target: knifeFeatureID
        ))
        document.designGraph.revision = document.designGraph.revision.advanced()

        let evaluated = try DocumentEvaluator(tolerance: .standard).evaluate(document)
        let repeated = try DocumentEvaluator(tolerance: .standard).evaluate(document)
        let centerFaceSubshapeID = SubshapeID(
            featureID: knifeFeatureID,
            role: "faceKnife.centerFace",
            ordinal: 0
        )
        let ringFaceSubshapeID = SubshapeID(
            featureID: knifeFeatureID,
            role: "faceKnife.ringFace",
            ordinal: 0
        )
        let bodySubshapeID = SubshapeID(
            featureID: knifeFeatureID,
            role: GeneratedSubshapeRole.body.rawValue,
            ordinal: 0
        )
        let knifeEdgeIDs: Set<EdgeID> = Set(evaluated.subshapes.entries.compactMap {
            subshapeID,
            reference in
            guard subshapeID.featureID == knifeFeatureID,
                  subshapeID.role == "faceKnife.knifeEdge",
                  case let .edge(edgeID) = reference else {
                return nil
            }
            return edgeID
        })
        let knifeEdgeUses = evaluated.brep.loops.values
            .flatMap(\.edges)
            .filter { knifeEdgeIDs.contains($0.edgeID) }
        let outputLineage = evaluated.lineage.values.filter {
            $0.output.featureID == knifeFeatureID
        }

        #expect(evaluated.brep.faces.count == 7)
        #expect(evaluated.brep.edges.count == 17)
        #expect(evaluated.brep.vertices.count == 13)
        #expect(evaluated.subshapes.entries[sourceFaceSubshapeID] == nil)
        #expect(evaluated.subshapes.entries[sourceBodySubshapeID] == nil)
        #expect(evaluated.subshapes.entries.keys.contains {
            $0.featureID == knifeFeatureID && $0.role.hasPrefix("faceKnife.carried")
        } == false)
        #expect(knifeEdgeIDs.count == 5)
        #expect(knifeEdgeUses.count == 10)
        #expect(knifeEdgeUses.allSatisfy { coedge in
            guard let parameterCurve = coedge.surfaceParameterCurve,
                  case .affine = parameterCurve else {
                return false
            }
            return true
        })
        #expect(outputLineage.count == 13)
        #expect(outputLineage.filter { $0.relation == .generated }.count == 10)
        #expect(outputLineage.filter { $0.relation == .split }.count == 2)
        #expect(outputLineage.filter { $0.relation == .preserved }.count == 1)
        #expect(evaluated.lineage[centerFaceSubshapeID]?.parents == [sourceFaceSubshapeID])
        #expect(evaluated.lineage[centerFaceSubshapeID]?.relation == .split)
        #expect(evaluated.lineage[ringFaceSubshapeID]?.parents == [sourceFaceSubshapeID])
        #expect(evaluated.lineage[ringFaceSubshapeID]?.relation == .split)
        #expect(evaluated.lineage[bodySubshapeID]?.parents == [sourceBodySubshapeID])
        #expect(evaluated.lineage[bodySubshapeID]?.relation == .preserved)
        #expect(evaluated.brep == repeated.brep)
        #expect(evaluated.subshapes == repeated.subshapes)
        #expect(evaluated.lineage == repeated.lineage)
        #expect(abs(try evaluated.brep.volume(tolerance: .standard) - source.brep.volume(tolerance: .standard)) <= 1.0e-12)
        try evaluated.brep.validate(level: .exact, tolerance: .standard)
        try evaluated.brep.validate(level: .volumetric, tolerance: .standard)
    }
}

import CADCore
import Foundation
import Testing
@testable import CADIR

@Suite("Modeling Feature Schema")
struct ModelingFeatureSchemaTests {
    @Test(.timeLimit(.minutes(1)))
    func rejectsUnknownFieldsAcrossSewnAndPatternRequests() throws {
        let sourceID = FeatureID()
        let pathID = FeatureID()
        let edge = try stableEdge(featureID: sourceID)
        let vertex = stableVertex(featureID: sourceID)
        let face = stableFace(featureID: sourceID)

        try expectUnknownFieldRejected(ChamferFeature.self, value: ChamferFeature(
            target: ChamferTargetReference(featureID: sourceID),
            edges: [edge],
            distance: .constant(.length(0.002, unit: .meter))
        ))
        try expectUnknownFieldRejected(FilletFeature.self, value: FilletFeature(
            target: FilletTargetReference(featureID: sourceID),
            edges: [edge],
            radius: .constant(.length(0.002, unit: .meter))
        ))
        try expectUnknownFieldRejected(G2BlendFeature.self, value: G2BlendFeature(
            target: G2BlendTargetReference(featureID: sourceID),
            edges: [edge],
            distance: .constant(.length(0.002, unit: .meter))
        ))
        try expectUnknownFieldRejected(SetbackCornerFeature.self, value: SetbackCornerFeature(
            target: SetbackCornerTargetReference(featureID: sourceID),
            vertex: vertex,
            radius: .constant(.length(0.002, unit: .meter))
        ))
        try expectUnknownFieldRejected(ShellFeature.self, value: ShellFeature(
            target: ShellTargetReference(featureID: sourceID),
            removedFaces: [face],
            thickness: .constant(.length(0.002, unit: .meter))
        ))
        try expectUnknownFieldRejected(ThickenFeature.self, value: ThickenFeature(
            target: ThickenTargetReference(featureID: sourceID),
            thickness: .constant(.length(0.002, unit: .meter)),
            side: .symmetric
        ))
        try expectUnknownFieldRejected(LinearPatternFeature.self, value: LinearPatternFeature(
            target: PatternTargetReference(featureID: sourceID),
            direction: .unitX,
            spacing: .constant(.length(0.060, unit: .meter)),
            count: 2
        ))
        try expectUnknownFieldRejected(RadialPatternFeature.self, value: RadialPatternFeature(
            target: PatternTargetReference(featureID: sourceID),
            axisOrigin: .origin,
            axisDirection: .unitZ,
            angularSpacing: .constant(.angle(.pi / 2.0, unit: .radian)),
            count: 2
        ))
        try expectUnknownFieldRejected(GridPatternFeature.self, value: GridPatternFeature(
            target: PatternTargetReference(featureID: sourceID),
            firstDirection: .unitX,
            firstSpacing: .constant(.length(0.060, unit: .meter)),
            firstCount: 2,
            secondDirection: .unitY,
            secondSpacing: .constant(.length(0.040, unit: .meter)),
            secondCount: 2
        ))
        try expectUnknownFieldRejected(CurveDrivenPatternFeature.self, value: CurveDrivenPatternFeature(
            target: PatternTargetReference(featureID: sourceID),
            path: CurveDrivenPatternPathReference(featureID: pathID),
            anchor: .origin,
            referenceDirection: .unitX,
            count: 2
        ))
    }

    @Test(.timeLimit(.minutes(1)))
    func rejectsUnknownFieldsAcrossFeatureIDReferences() throws {
        let featureID = FeatureID()
        try expectUnknownFieldRejected(
            ChamferTargetReference.self,
            value: ChamferTargetReference(featureID: featureID)
        )
        try expectUnknownFieldRejected(
            FilletTargetReference.self,
            value: FilletTargetReference(featureID: featureID)
        )
        try expectUnknownFieldRejected(
            G2BlendTargetReference.self,
            value: G2BlendTargetReference(featureID: featureID)
        )
        try expectUnknownFieldRejected(
            SetbackCornerTargetReference.self,
            value: SetbackCornerTargetReference(featureID: featureID)
        )
        try expectUnknownFieldRejected(
            ShellTargetReference.self,
            value: ShellTargetReference(featureID: featureID)
        )
        try expectUnknownFieldRejected(
            ThickenTargetReference.self,
            value: ThickenTargetReference(featureID: featureID)
        )
        try expectUnknownFieldRejected(
            PatternTargetReference.self,
            value: PatternTargetReference(featureID: featureID)
        )
        try expectUnknownFieldRejected(
            CurveDrivenPatternPathReference.self,
            value: CurveDrivenPatternPathReference(featureID: featureID)
        )
    }

    private func stableEdge(featureID: FeatureID) throws -> StableSubshapeReference {
        StableSubshapeReference(
            subshapeID: SubshapeID(featureID: featureID, role: "edge", ordinal: 0),
            geometrySignature: try .lineEdge(
                startPoint: .origin,
                endPoint: Point3D(x: 1.0, y: 0.0, z: 0.0)
            )
        )
    }

    private func stableVertex(featureID: FeatureID) -> StableSubshapeReference {
        StableSubshapeReference(
            subshapeID: SubshapeID(featureID: featureID, role: "vertex", ordinal: 0),
            geometrySignature: .vertex(point: .origin)
        )
    }

    private func stableFace(featureID: FeatureID) -> StableSubshapeReference {
        StableSubshapeReference(
            subshapeID: SubshapeID(featureID: featureID, role: "face", ordinal: 0),
            geometrySignature: .untrimmedPlane(origin: .origin)
        )
    }

    private func expectUnknownFieldRejected<Value: Codable>(
        _ type: Value.Type,
        value: Value
    ) throws {
        let encoded = try JSONEncoder().encode(value)
        guard var object = try JSONSerialization.jsonObject(with: encoded) as? [String: Any] else {
            Issue.record("Expected an encoded modeling request object.")
            return
        }
        object["legacyPersistentName"] = "legacy"
        let legacySchema = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        #expect(throws: DecodingError.self) {
            _ = try JSONDecoder().decode(type, from: legacySchema)
        }
    }
}

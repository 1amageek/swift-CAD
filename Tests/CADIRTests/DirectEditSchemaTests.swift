import CADCore
import CADGeometry
import Foundation
import Testing
@testable import CADIR

@Suite("Direct Edit Schema")
struct DirectEditSchemaTests {
    @Test(.timeLimit(.minutes(1)))
    func rejectsUnknownFieldsAcrossDirectEditRequests() throws {
        let sourceID = FeatureID()
        let targetID = FeatureID()
        let face = stableReference(featureID: sourceID, role: "face")
        let edge = stableReference(featureID: sourceID, role: "edge")
        let vertex = stableReference(featureID: sourceID, role: "vertex")
        let translation = DirectMoveVector(
            direction: .unitX,
            distance: .constant(.length(0.005, unit: .meter))
        )

        try expectUnknownFieldRejected(FaceMoveFeature.self, value: FaceMoveFeature(
            target: FaceMoveTargetReference(featureID: sourceID),
            face: face,
            translation: translation
        ))
        try expectUnknownFieldRejected(FaceOffsetFeature.self, value: FaceOffsetFeature(
            target: FaceOffsetTargetReference(featureID: sourceID),
            face: face,
            distance: .constant(.length(0.005, unit: .meter))
        ))
        try expectUnknownFieldRejected(EdgeMoveFeature.self, value: EdgeMoveFeature(
            target: EdgeMoveTargetReference(featureID: sourceID),
            edge: edge,
            translation: translation
        ))
        try expectUnknownFieldRejected(VertexMoveFeature.self, value: VertexMoveFeature(
            target: VertexMoveTargetReference(featureID: sourceID),
            vertex: vertex,
            translation: translation
        ))
        try expectUnknownFieldRejected(SurfaceOffsetFeature.self, value: SurfaceOffsetFeature(
            target: surfaceOperationTargetReference(featureID: sourceID),
            distance: .constant(.length(0.005, unit: .meter))
        ))
        try expectUnknownFieldRejected(SurfaceTrimFeature.self, value: SurfaceTrimFeature(
            target: surfaceOperationTargetReference(featureID: sourceID),
            loops: [SurfaceTrimLoop(
                role: .outer,
                parameterCurves: [
                    .constantV(v: -0.005, uStart: -0.010, uEnd: 0.010),
                    .constantU(u: 0.010, vStart: -0.005, vEnd: 0.005),
                    .constantV(v: 0.005, uStart: 0.010, uEnd: -0.010),
                    .constantU(u: -0.010, vStart: 0.005, vEnd: -0.005),
                ]
            )]
        ))
        try expectUnknownFieldRejected(SurfaceExtendFeature.self, value: SurfaceExtendFeature(
            target: surfaceOperationTargetReference(featureID: sourceID),
            uDomain: .closed(-0.020, 0.020),
            vDomain: .closed(-0.010, 0.010)
        ))
        try expectUnknownFieldRejected(SurfaceMatchFeature.self, value: SurfaceMatchFeature(
            source: surfaceOperationTargetReference(featureID: sourceID),
            target: surfaceOperationTargetReference(featureID: targetID),
            sourceParameter: SurfaceParameter(u: 0.0, v: 0.0),
            targetParameter: SurfaceParameter(u: 0.0, v: 0.0),
            continuity: .positional
        ))
    }

    @Test(.timeLimit(.minutes(1)))
    func rejectsUnknownFieldsInSharedDirectEditValues() throws {
        try expectUnknownFieldRejected(DirectMoveVector.self, value: DirectMoveVector(
            direction: .unitX,
            distance: .constant(.length(0.005, unit: .meter))
        ))
        try expectUnknownFieldRejected(
            SurfaceOperationTargetReference.self,
            value: surfaceOperationTargetReference(featureID: FeatureID())
        )
    }

    @Test(.timeLimit(.minutes(1)))
    func surfaceOperationTargetRequiresAnExplicitFaceReference() throws {
        let featureID = FeatureID()
        let nonFaceTarget = SurfaceOperationTargetReference(
            featureID: featureID,
            face: StableSubshapeReference(
                subshapeID: SubshapeID(
                    featureID: featureID,
                    role: "vertex",
                    ordinal: 0
                ),
                geometrySignature: .vertex(point: .origin)
            )
        )
        #expect(throws: KernelError.self) {
            try nonFaceTarget.validate()
        }

        let encoded = try JSONEncoder().encode(
            surfaceOperationTargetReference(featureID: featureID)
        )
        guard var object = try JSONSerialization.jsonObject(
            with: encoded
        ) as? [String: Any] else {
            Issue.record("Expected an encoded surface operation target.")
            return
        }
        object.removeValue(forKey: "face")
        let missingFace = try JSONSerialization.data(
            withJSONObject: object,
            options: [.sortedKeys]
        )
        #expect(throws: DecodingError.self) {
            _ = try JSONDecoder().decode(
                SurfaceOperationTargetReference.self,
                from: missingFace
            )
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func surfaceExtendRejectsRemovedPhysicalDistanceSchema() throws {
        let feature = SurfaceExtendFeature(
            target: surfaceOperationTargetReference(featureID: FeatureID()),
            uDomain: .closed(-0.1, 1.1),
            vDomain: .closed(-0.2, 1.2)
        )
        let encoded = try JSONEncoder().encode(feature)
        guard var object = try JSONSerialization.jsonObject(
            with: encoded
        ) as? [String: Any] else {
            Issue.record("Expected an encoded surface extend object.")
            return
        }
        object.removeValue(forKey: "uDomain")
        object.removeValue(forKey: "vDomain")
        object["distances"] = [
            "lowerU": ["kind": "constant"],
            "upperU": ["kind": "constant"],
            "lowerV": ["kind": "constant"],
            "upperV": ["kind": "constant"],
        ]
        let removedSchema = try JSONSerialization.data(
            withJSONObject: object,
            options: [.sortedKeys]
        )

        #expect(throws: DecodingError.self) {
            _ = try JSONDecoder().decode(
                SurfaceExtendFeature.self,
                from: removedSchema
            )
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func surfaceTrimRejectsRemovedRectangularDomainSchema() throws {
        let feature = SurfaceTrimFeature(
            target: surfaceOperationTargetReference(featureID: FeatureID()),
            loops: [SurfaceTrimLoop(
                role: .outer,
                parameterCurves: [
                    .constantV(v: 0.2, uStart: 0.1, uEnd: 0.9),
                    .constantU(u: 0.9, vStart: 0.2, vEnd: 0.8),
                    .constantV(v: 0.8, uStart: 0.9, uEnd: 0.1),
                    .constantU(u: 0.1, vStart: 0.8, vEnd: 0.2),
                ]
            )]
        )
        let encoded = try JSONEncoder().encode(feature)
        guard var object = try JSONSerialization.jsonObject(
            with: encoded
        ) as? [String: Any] else {
            Issue.record("Expected an encoded surface trim object.")
            return
        }
        object.removeValue(forKey: "loops")
        object["uDomain"] = [
            "kind": "closed",
            "lowerBound": 0.1,
            "upperBound": 0.9,
        ]
        object["vDomain"] = [
            "kind": "closed",
            "lowerBound": 0.2,
            "upperBound": 0.8,
        ]
        let removedSchema = try JSONSerialization.data(
            withJSONObject: object,
            options: [.sortedKeys]
        )

        #expect(throws: DecodingError.self) {
            _ = try JSONDecoder().decode(
                SurfaceTrimFeature.self,
                from: removedSchema
            )
        }
    }

    private func stableReference(
        featureID: FeatureID,
        role: String
    ) -> StableSubshapeReference {
        StableSubshapeReference(
            subshapeID: SubshapeID(featureID: featureID, role: role, ordinal: 0),
            geometrySignature: .vertex(point: .origin)
        )
    }

    private func expectUnknownFieldRejected<Value: Codable>(
        _ type: Value.Type,
        value: Value
    ) throws {
        let encoded = try JSONEncoder().encode(value)
        guard var object = try JSONSerialization.jsonObject(with: encoded) as? [String: Any] else {
            Issue.record("Expected an encoded direct edit object.")
            return
        }
        object["legacyPersistentName"] = "legacy"
        let legacySchema = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        #expect(throws: DecodingError.self) {
            _ = try JSONDecoder().decode(type, from: legacySchema)
        }
    }
}

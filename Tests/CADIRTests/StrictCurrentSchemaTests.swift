import Foundation
import Testing
import CADCore
@testable import CADIR

@Suite("Strict current CADIR schema")
struct StrictCurrentSchemaTests {
    @Test(.timeLimit(.minutes(1)))
    func documentRequiresSelectionDimensions() throws {
        var object = try encodedObject(CADDocument(units: .meters))
        _ = object.removeValue(forKey: "selectionDimensions")

        try expectDecodingFailure(CADDocument.self, from: object)
    }

    @Test(.timeLimit(.minutes(1)))
    func sweepRequiresEveryCanonicallyEncodedField() throws {
        let feature = SweepFeature(
            sections: [.profile(ProfileReference(featureID: FeatureID()))],
            path: SweepPathReference(featureID: FeatureID())
        )
        for key in ["guides", "targets", "options"] {
            var object = try encodedObject(feature)
            _ = object.removeValue(forKey: key)
            try expectDecodingFailure(SweepFeature.self, from: object)
        }

        var sectionObject = try encodedObject(
            SweepSectionReference.profile(ProfileReference(featureID: FeatureID()))
        )
        _ = sectionObject.removeValue(forKey: "profileIndex")
        try expectDecodingFailure(SweepSectionReference.self, from: sectionObject)

        var optionsObject = try encodedObject(SweepOptions())
        _ = optionsObject.removeValue(forKey: "guideMethod")
        try expectDecodingFailure(SweepOptions.self, from: optionsObject)
    }

    @Test(.timeLimit(.minutes(1)))
    func loftRequiresEveryCanonicallyEncodedField() throws {
        let feature = LoftFeature(sections: [
            LoftSectionReference(profile: ProfileReference(featureID: FeatureID())),
            LoftSectionReference(profile: ProfileReference(featureID: FeatureID())),
        ])
        var featureObject = try encodedObject(feature)
        _ = featureObject.removeValue(forKey: "guides")
        try expectDecodingFailure(LoftFeature.self, from: featureObject)

        var sectionObject = try encodedObject(feature.sections[0])
        _ = sectionObject.removeValue(forKey: "smoothTangentMode")
        try expectDecodingFailure(LoftSectionReference.self, from: sectionObject)

        for key in ["closesSectionLoop", "surfaceMode", "smoothTangentScale"] {
            var optionsObject = try encodedObject(LoftOptions())
            _ = optionsObject.removeValue(forKey: key)
            try expectDecodingFailure(LoftOptions.self, from: optionsObject)
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func nestedSchemaObjectsRejectUnknownFields() throws {
        try expectUnknownFieldFailure(
            ProfileReference.self,
            value: ProfileReference(featureID: FeatureID())
        )
        try expectUnknownFieldFailure(
            SweepPathReference.self,
            value: SweepPathReference(featureID: FeatureID())
        )
        try expectUnknownFieldFailure(
            SweepGuideReference.self,
            value: SweepGuideReference(featureID: FeatureID())
        )
        try expectUnknownFieldFailure(
            SweepTargetReference.self,
            value: SweepTargetReference(featureID: FeatureID())
        )
        try expectUnknownFieldFailure(
            LoftGuideReference.self,
            value: LoftGuideReference(featureID: FeatureID())
        )
        try expectUnknownFieldFailure(
            Mesh.self,
            value: Mesh(positions: [.origin], normals: [], indices: [])
        )
    }

    private func expectUnknownFieldFailure<Value: Codable>(
        _ type: Value.Type,
        value: Value
    ) throws {
        var object = try encodedObject(value)
        object["removedDevelopmentField"] = true
        try expectDecodingFailure(type, from: object)
    }

    private func encodedObject<Value: Encodable>(_ value: Value) throws -> [String: Any] {
        let data = try JSONEncoder().encode(value)
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw StrictCurrentSchemaTestError.expectedObject
        }
        return object
    }

    private func expectDecodingFailure<Value: Decodable>(
        _ type: Value.Type,
        from object: [String: Any]
    ) throws {
        let data = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(type, from: data)
        }
    }
}

private enum StrictCurrentSchemaTestError: Error {
    case expectedObject
}

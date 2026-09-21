import CADCore
import Foundation
import Testing
@testable import CADIR

@Suite("Extrude Result Kind Schema")
struct ExtrudeResultKindSchemaTests {
    @Test(.timeLimit(.minutes(1)))
    func solidExtrudeOmitsResultKindSoEarlierDocumentsStayByteIdentical() throws {
        let feature = ExtrudeFeature(
            profile: ProfileReference(featureID: FeatureID()),
            distance: .constant(.length(60.0, unit: .millimeter))
        )

        let data = try JSONEncoder().encode(feature)
        let object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])

        #expect(feature.resultKind == .solid)
        #expect(object["resultKind"] == nil)
    }

    @Test(.timeLimit(.minutes(1)))
    func omittedResultKindDecodesAsSolid() throws {
        let feature = ExtrudeFeature(
            profile: ProfileReference(featureID: FeatureID()),
            distance: .constant(.length(60.0, unit: .millimeter))
        )
        let data = try JSONEncoder().encode(feature)

        let decoded = try JSONDecoder().decode(ExtrudeFeature.self, from: data)

        #expect(decoded.resultKind == .solid)
        #expect(decoded == feature)
    }

    @Test(.timeLimit(.minutes(1)))
    func sheetResultKindRoundTrips() throws {
        let feature = ExtrudeFeature(
            profile: ProfileReference(featureID: FeatureID()),
            distance: .constant(.length(60.0, unit: .millimeter)),
            resultKind: .sheet
        )

        let data = try JSONEncoder().encode(feature)
        let object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let decoded = try JSONDecoder().decode(ExtrudeFeature.self, from: data)

        #expect(object["resultKind"] as? String == "sheet")
        #expect(decoded.resultKind == .sheet)
        #expect(decoded == feature)
    }

    @Test(.timeLimit(.minutes(1)))
    func solidExtrudeAcceptsBodyOutput() throws {
        var document = try documentWithProfileSource()
        let sketchID = try #require(document.designGraph.order.first)

        let extrudeID = try document.appendFeature(
            extrudeNode(profileSource: sketchID, resultKind: .solid, outputRole: .body),
            tolerance: .standard
        )

        #expect(document.designGraph.order == [sketchID, extrudeID])
    }

    @Test(.timeLimit(.minutes(1)))
    func sheetExtrudeAcceptsSheetOutput() throws {
        var document = try documentWithProfileSource()
        let sketchID = try #require(document.designGraph.order.first)

        let extrudeID = try document.appendFeature(
            extrudeNode(profileSource: sketchID, resultKind: .sheet, outputRole: .sheet),
            tolerance: .standard
        )

        #expect(document.designGraph.order == [sketchID, extrudeID])
    }

    @Test(.timeLimit(.minutes(1)))
    func solidExtrudeRejectsSheetOutput() throws {
        var document = try documentWithProfileSource()
        let sketchID = try #require(document.designGraph.order.first)
        let before = document.designGraph

        #expect(throws: FeatureEvaluationError.self) {
            try document.appendFeature(
                extrudeNode(profileSource: sketchID, resultKind: .solid, outputRole: .sheet),
                tolerance: .standard
            )
        }
        #expect(document.designGraph.order == before.order)
        #expect(document.designGraph.revision == before.revision)
    }

    @Test(.timeLimit(.minutes(1)))
    func sheetExtrudeRejectsBodyOutput() throws {
        var document = try documentWithProfileSource()
        let sketchID = try #require(document.designGraph.order.first)
        let before = document.designGraph

        #expect(throws: FeatureEvaluationError.self) {
            try document.appendFeature(
                extrudeNode(profileSource: sketchID, resultKind: .sheet, outputRole: .body),
                tolerance: .standard
            )
        }
        #expect(document.designGraph.order == before.order)
        #expect(document.designGraph.revision == before.revision)
    }

    private func documentWithProfileSource() throws -> CADDocument {
        var document = CADDocument(units: .meters)
        try document.appendFeature(
            FeatureNode(
                operation: .sketch(Sketch(plane: .xy)),
                outputs: [FeatureOutput(role: .profile)]
            ),
            tolerance: .standard
        )
        return document
    }

    private func extrudeNode(
        profileSource: FeatureID,
        resultKind: ExtrudeResultKind,
        outputRole: FeaturePort
    ) -> FeatureNode {
        FeatureNode(
            operation: .extrude(ExtrudeFeature(
                profile: ProfileReference(featureID: profileSource),
                distance: .constant(.length(60.0, unit: .millimeter)),
                resultKind: resultKind
            )),
            inputs: [FeatureInput(featureID: profileSource, role: .profile)],
            outputs: [FeatureOutput(role: outputRole)]
        )
    }
}

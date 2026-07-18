import Foundation
import Testing
import CADCore
import CADIR
import CADKernel
import SwiftCAD

@Suite("Primitive command parity")
struct PrimitiveCommandParityTests {
    @Test(.timeLimit(.minutes(1)))
    func builderAndCodableCommandProduceIdenticalPrimitiveDocument() throws {
        var builder = DocumentBuilder(units: .meters, tolerance: .standard)
        let radiusID = builder.lengthParameter(named: "radius", 2.0, .meter)
        let featureID = try builder.sphere(
            placement: PrimitivePlacement(
                origin: Point3D(x: 1.0, y: 2.0, z: 3.0),
                axis: .unitY,
                referenceDirection: .unitX
            ),
            radius: .reference(radiusID),
            named: "Placed sphere"
        )
        let builderDocument = try builder.build(name: "Primitive parity")
        let featureNode = try #require(builderDocument.designGraph.nodes[featureID])

        let parameter = try #require(builderDocument.parameters.parameters[radiusID])
        let commands: [CADCommand] = [
            .upsertParameter(parameter),
            .appendFeature(FeatureRequest(
                id: featureNode.id,
                name: featureNode.name,
                operation: featureNode.operation
            )),
        ]
        let editor = DocumentEditor()
        var commandDocument = CADDocument(
            units: .meters,
            metadata: DocumentMetadata(name: "Primitive parity")
        )
        for command in commands {
            let data = try JSONEncoder().encode(command)
            let decoded = try JSONDecoder().decode(CADCommand.self, from: data)
            #expect(decoded == command)
            commandDocument = try editor.apply(decoded, to: commandDocument, tolerance: .standard)
        }

        #expect(try commandDocument.sourceFingerprint(tolerance: .standard) == builderDocument.sourceFingerprint(tolerance: .standard))
        let evaluator = DocumentEvaluator(tolerance: .standard, artifactPolicy: .deferred)
        let builderResult = try evaluator.evaluate(builderDocument)
        let commandResult = try evaluator.evaluate(commandDocument)
        #expect(builderResult.brep == commandResult.brep)
        #expect(builderResult.subshapes == commandResult.subshapes)
        #expect(builderResult.lineage == commandResult.lineage)
        #expect(try builderResult.brep.volume(tolerance: .standard) == commandResult.brep.volume(tolerance: .standard))
    }

    @Test(.timeLimit(.minutes(1)))
    func primitiveSchemaRejectsUnknownFields() throws {
        let feature = PrimitiveFeature(definition: .torus(TorusPrimitive(
            majorRadius: .constant(.length(4.0, unit: .meter)),
            minorRadius: .constant(.length(1.0, unit: .meter))
        )))
        let encoded = try JSONEncoder().encode(feature)
        var object = try #require(
            JSONSerialization.jsonObject(with: encoded) as? [String: Any]
        )
        object["legacyPrimitiveName"] = "torus"
        let invalid = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])

        #expect(throws: DecodingError.self) {
            _ = try JSONDecoder().decode(PrimitiveFeature.self, from: invalid)
        }
    }
}

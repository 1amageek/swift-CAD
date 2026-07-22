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
        for primitive in PrimitiveCommandCase.allCases {
            var builder = DocumentBuilder(units: .meters, tolerance: .standard)
            let primaryID = try builder.lengthParameter(named: "primary", 4.0, .meter)
            let secondaryID = try builder.lengthParameter(named: "secondary", 1.0, .meter)
            let featureID = try primitive.append(
                to: &builder,
                primary: .reference(primaryID),
                secondary: .reference(secondaryID)
            )
            let documentName = "Primitive parity \(primitive.rawValue)"
            let builderDocument = try builder.build(name: documentName)
            let featureNode = try #require(builderDocument.designGraph.nodes[featureID])

            let parameters = builderDocument.parameters.parameters.values.sorted {
                $0.name < $1.name
            }
            let commands = parameters.map(CADCommand.upsertParameter) + [
                .appendFeature(FeatureRequest(
                    id: featureNode.id,
                    name: featureNode.name,
                    operation: featureNode.operation
                )),
            ]
            let editor = DocumentEditor()
            var commandDocument = CADDocument(
                units: .meters,
                metadata: DocumentMetadata(name: documentName)
            )
            for command in commands {
                let data = try JSONEncoder().encode(command)
                let decoded = try JSONDecoder().decode(CADCommand.self, from: data)
                #expect(decoded == command)
                commandDocument = try editor.apply(
                    decoded,
                    to: commandDocument,
                    tolerance: .standard
                )
            }

            #expect(
                try commandDocument.sourceFingerprint(tolerance: .standard)
                    == builderDocument.sourceFingerprint(tolerance: .standard)
            )
            let evaluator = DocumentEvaluator(
                tolerance: .standard,
                artifactPolicy: .deferred
            )
            let builderResult = try evaluator.evaluate(builderDocument)
            let commandResult = try evaluator.evaluate(commandDocument)
            #expect(builderResult.brep == commandResult.brep)
            #expect(builderResult.subshapes == commandResult.subshapes)
            #expect(builderResult.lineage == commandResult.lineage)
            #expect(
                try builderResult.brep.volume(tolerance: .standard)
                    == commandResult.brep.volume(tolerance: .standard)
            )
        }
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

    private enum PrimitiveCommandCase: String, CaseIterable {
        case box
        case cylinder
        case cone
        case sphere
        case torus

        func append(
            to builder: inout DocumentBuilder,
            primary: CADExpression,
            secondary: CADExpression
        ) throws -> FeatureID {
            let placement = PrimitivePlacement(
                origin: Point3D(x: 1.0, y: 2.0, z: 3.0),
                axis: .unitY,
                referenceDirection: .unitX
            )
            switch self {
            case .box:
                return try builder.box(
                    placement: placement,
                    width: primary,
                    depth: secondary,
                    height: primary,
                    named: "Placed box"
                )
            case .cylinder:
                return try builder.cylinder(
                    placement: placement,
                    radius: secondary,
                    height: primary,
                    named: "Placed cylinder"
                )
            case .cone:
                return try builder.cone(
                    placement: placement,
                    baseRadius: secondary,
                    height: primary,
                    named: "Placed cone"
                )
            case .sphere:
                return try builder.sphere(
                    placement: placement,
                    radius: primary,
                    named: "Placed sphere"
                )
            case .torus:
                return try builder.torus(
                    placement: placement,
                    majorRadius: primary,
                    minorRadius: secondary,
                    named: "Placed torus"
                )
            }
        }
    }
}

import Foundation
import Testing
@testable import CADCore

@Suite("CADCore")
struct CADCoreTests {
    @Test(.timeLimit(.minutes(1)))
    func lengthQuantitiesUseInternalMeters() {
        let quantity = Quantity.length(40.0, unit: .millimeter)
        #expect(quantity.kind == .length)
        #expect(abs(quantity.value - 0.04) < 1.0e-12)
        #expect(abs(LengthUnit.millimeter.fromInternal(quantity.value) - 40.0) < 1.0e-12)
        #expect(abs(LengthUnit.kilometer.toInternal(1.5) - 1_500.0) < 1.0e-12)
    }

    @Test(.timeLimit(.minutes(1)))
    func taggedIDRoundTripsAsStableUUIDString() throws {
        let id = ParameterID()
        let data = try JSONEncoder().encode(id)
        let decoded = try JSONDecoder().decode(ParameterID.self, from: data)
        #expect(decoded == id)
    }

    @Test(.timeLimit(.minutes(1)))
    func documentRevisionRejectsNegativeValues() {
        #expect(throws: SchemaError.self) {
            try DocumentRevision(-1).validate()
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func documentRevisionRejectsNonAdvanceableValues() {
        #expect(throws: SchemaError.self) {
            try DocumentRevision(Int.max).validate()
        }

        let advanced = DocumentRevision(Int.max).advanced()
        #expect(throws: SchemaError.self) {
            try advanced.validate()
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func expressionUsesStableKindDiscriminator() throws {
        let expression = CADExpression.constant(.length(10.0, unit: .millimeter))
        let data = try JSONEncoder().encode(expression)
        let json = try #require(String(data: data, encoding: .utf8))
        #expect(json.contains("\"kind\":\"constant\""))
    }

    @Test(.timeLimit(.minutes(1)))
    func expressionDecoderRejectsInactivePayloadKeys() throws {
        let expression = CADExpression.constant(.length(10.0, unit: .millimeter))
        var object = try jsonObject(from: JSONEncoder().encode(expression))
        object["parameterID"] = ParameterID().description
        let data = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        var objectWithUnknownKey = try jsonObject(from: JSONEncoder().encode(expression))
        objectWithUnknownKey["unexpected"] = true
        let unknownKeyData = try JSONSerialization.data(withJSONObject: objectWithUnknownKey, options: [.sortedKeys])

        #expect(throws: DecodingError.self) {
            _ = try JSONDecoder().decode(CADExpression.self, from: data)
        }
        #expect(throws: DecodingError.self) {
            _ = try JSONDecoder().decode(CADExpression.self, from: unknownKeyData)
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func matrixRejectsInvalidElementCountWithTypedError() {
        #expect(throws: GeometryError.self) {
            _ = try Matrix4x4(values: [1.0, 2.0, 3.0])
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func matrixRejectsNonFiniteElements() throws {
        var values = Matrix4x4.identity.values
        values[3] = .nan

        #expect(throws: GeometryError.self) {
            _ = try Matrix4x4(values: values)
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func transformValidationRejectsMutatedNonFiniteMatrix() {
        var matrix = Matrix4x4.identity
        matrix.values[15] = .infinity
        let transform = Transform3D(matrix: matrix)

        #expect(throws: GeometryError.self) {
            try transform.validate()
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func quantitiesRejectNonFiniteValues() {
        #expect(throws: UnitError.self) {
            try Quantity.scalar(.nan).validate()
        }
        #expect(throws: UnitError.self) {
            try Quantity.length(.infinity, unit: .meter).validate()
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func unitSystemsValidateSupportedCases() throws {
        for lengthUnit in LengthUnit.allCases {
            for angleUnit in AngleUnit.allCases {
                try UnitSystem(length: lengthUnit, angle: angleUnit).validate()
            }
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func cadIdentifierRulesAcceptStableAPINames() throws {
        try CADIdentifierRules.validate("width")
        try CADIdentifierRules.validate("_profile1")
        #expect(CADIdentifierRules.isValid("height_2"))
    }

    @Test(.timeLimit(.minutes(1)))
    func cadIdentifierRulesRejectAmbiguousNames() {
        #expect(throws: ParameterError.self) {
            try CADIdentifierRules.validate("")
        }
        #expect(throws: ParameterError.self) {
            try CADIdentifierRules.validate("bad name")
        }
        #expect(throws: ParameterError.self) {
            try CADIdentifierRules.validate("1width")
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func modelingToleranceRejectsNonFiniteAndNonPositiveValues() {
        #expect(throws: GeometryError.self) {
            try ModelingTolerance(distance: .nan, angle: 1.0e-9).validate()
        }
        #expect(throws: GeometryError.self) {
            try ModelingTolerance(distance: 0.0, angle: 1.0e-9).validate()
        }
        #expect(throws: GeometryError.self) {
            try ModelingTolerance(distance: 1.0e-6, angle: -.infinity).validate()
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func vectorNormalizationRejectsNonFiniteComponents() {
        #expect(throws: GeometryError.self) {
            _ = try Vector3D(x: .infinity, y: 0.0, z: 0.0).normalized(tolerance: 1.0e-9)
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func vectorNormalizationRejectsInvalidTolerance() {
        #expect(throws: GeometryError.self) {
            _ = try Vector3D.unitX.normalized(tolerance: .nan)
        }
        #expect(throws: GeometryError.self) {
            _ = try Vector3D.unitX.normalized(tolerance: 0.0)
        }
        #expect(throws: GeometryError.self) {
            _ = try Vector3D.zero.normalized(tolerance: -1.0)
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func vectorNormalizationHandlesLargeFiniteComponents() throws {
        let normalized = try Vector3D(x: Double.greatestFiniteMagnitude, y: 0.0, z: 0.0)
            .normalized(tolerance: 1.0e-9)

        #expect(normalized == .unitX)
    }

    @Test(.timeLimit(.minutes(1)))
    func vectorNormalizationRejectsUnrepresentableLength() {
        #expect(throws: GeometryError.self) {
            _ = try Vector3D(
                x: Double.greatestFiniteMagnitude,
                y: Double.greatestFiniteMagnitude,
                z: 0.0
            ).normalized(tolerance: 1.0e-9)
        }
    }
}

private func jsonObject(from data: Data) throws -> [String: Any] {
    guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
        throw SchemaError.invalidPackage("Expected JSON object fixture.")
    }
    return object
}

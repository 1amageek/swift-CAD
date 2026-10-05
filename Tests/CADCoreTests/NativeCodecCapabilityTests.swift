#if !hasFeature(Embedded)
import CADCore
import Foundation
import Testing

@Suite("NativeCodecCapability")
struct NativeCodecCapabilityTests {
    @Test(.timeLimit(.minutes(1)))
    func literalCoordinatesAndMatrixRetainNativeWire() throws {
        try wire(Point2D(x: 1.25, y: -2.5), #"{"x":1.25,"y":-2.5}"#)
        try wire(Point3D(x: 1.25, y: -2.5, z: 3.75), #"{"x":1.25,"y":-2.5,"z":3.75}"#)
        try wire(Vector3D(x: 1.25, y: -2.5, z: 3.75), #"{"x":1.25,"y":-2.5,"z":3.75}"#)
        try wire(Matrix4x4.identity, "[1,0,0,0,0,1,0,0,0,0,1,0,0,0,0,1]")
        try wire(Transform3D.identity, #"{"matrix":[1,0,0,0,0,1,0,0,0,0,1,0,0,0,0,1]}"#)
    }

    @Test(.timeLimit(.minutes(1)))
    func literalScalarRecordsAndRawEnumsRetainNativeWire() throws {
        // This literal is independent of the active development schema policy.
        try wire(SchemaVersion(major: 2, minor: 3, patch: 4), #"{"major":2,"minor":3,"patch":4}"#)
        try wire(DocumentRevision(7), #"{"value":7}"#)
        try wire(Quantity(value: 1.25, kind: .length), #"{"value":1.25,"kind":"length"}"#)
        try wire(UnitSystem(length: .inch, angle: .degree), #"{"length":"inch","angle":"degree"}"#)
        try wire(ModelingTolerance(distance: 0.125, angle: 0.25, relative: 0.5),
            #"{"distance":0.125,"angle":0.25,"relative":0.5}"#)
        try wire(MeshArtifactPurpose(rawValue: "literal"), #""literal""#)
        try wire(KernelPhase.classification, #""classification""#)
        try wire(KernelErrorCode.nonDiscreteIntersection, #""nonDiscreteIntersection""#)
        try wire(KernelFailureCategory.nonDiscreteResult, #""nonDiscreteResult""#)
        try wire(TessellationResource.byteCount, #""byteCount""#)
    }

    @Test(.timeLimit(.minutes(1)))
    func explicitExpressionKindsAndOperandsRetainNativeWire() throws {
        try wire(CADExpression.hypot(.constant(.scalar(3)), .constant(.scalar(4))),
            #"{"kind":"hypot","left":{"kind":"constant","quantity":{"value":3,"kind":"scalar"}},"right":{"kind":"constant","quantity":{"value":4,"kind":"scalar"}}}"#)
        try wire(CADExpression.variable("distance", .length),
            #"{"kind":"variable","name":"distance","quantityKind":"length"}"#)
        try wire(CADExpression.sin(.constant(.angle(0.25, unit: .radian))),
            #"{"kind":"sin","argument":{"kind":"constant","quantity":{"value":0.25,"kind":"angle"}}}"#)
        let parameter = ParameterID(identity)
        try wire(CADExpression.reference(parameter),
            #"{"kind":"reference","parameterID":"00112233-4455-4677-8899-AABBCCDDEEFF"}"#)
        try wire(CADExpression.bezierNaturalExtension(
            coordinates: [.constant(.length(0, unit: .meter)), .constant(.length(0, unit: .meter)),
                          .constant(.length(1, unit: .meter)), .constant(.length(0, unit: .meter))],
            length: .constant(.length(2, unit: .meter)), coordinateIndex: 0),
            #"{"kind":"bezierNaturalExtension","coordinates":[{"kind":"constant","quantity":{"value":0,"kind":"length"}},{"kind":"constant","quantity":{"value":0,"kind":"length"}},{"kind":"constant","quantity":{"value":1,"kind":"length"}},{"kind":"constant","quantity":{"value":0,"kind":"length"}}],"length":{"kind":"constant","quantity":{"value":2,"kind":"length"}},"coordinateIndex":0}"#)
    }

    @Test(.timeLimit(.minutes(1)))
    func explicitShapeKindsAndStrictInactiveKeysRetainNativeWire() throws {
        try wire(BezierExtensionShape.arc(spanCount: 2), #"{"kind":"arc","spanCount":2}"#)
        try wire(BezierExtensionShape.soft(spanCount: 3), #"{"kind":"soft","spanCount":3}"#)
        try wire(BezierExtensionShape.reflective(degree: 3, coversCurve: true),
            #"{"kind":"reflective","degree":3,"coversCurve":true}"#)
        do {
            _ = try JSONDecoder().decode(BezierExtensionShape.self,
                from: Data(#"{"kind":"arc","spanCount":2,"coversCurve":true}"#.utf8))
            Issue.record("Inactive shape payload must be refused.")
        } catch DecodingError.dataCorrupted(let context) {
            #expect(context.codingPath.last?.stringValue == "coversCurve")
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func malformedNativeWireRetainsTypedFailureClassification() throws {
        do {
            _ = try JSONDecoder().decode(Matrix4x4.self, from: Data("[1,2,3]".utf8))
            Issue.record("Malformed matrix must fail actual decode-time validation.")
        } catch let error as GeometryError {
            #expect(error == .invalidMatrixElementCount(3))
        }
        do {
            _ = try JSONDecoder().decode(CADExpression.self, from: Data(
                #"{"kind":"constant","quantity":{"value":1,"kind":"scalar"},"unexpected":true}"#.utf8))
            Issue.record("Unexpected expression payload must fail strict decoding.")
        } catch DecodingError.dataCorrupted(let context) {
            #expect(context.codingPath.last?.stringValue == "unexpected")
            #expect(KernelError.wrapping(DecodingError.dataCorrupted(context),
                phase: .validation, tolerance: .standard).code == .invalidInput)
        }
        do {
            _ = try JSONDecoder().decode(CADExpression.self, from: Data(#"{"kind":"unknown"}"#.utf8))
            Issue.record("Unknown expression discriminator must fail decoding.")
        } catch DecodingError.dataCorrupted(let context) {
            #expect(context.codingPath.last?.stringValue == "kind")
        }
        do {
            _ = try JSONEncoder().encode(Point3D(x: .nan, y: 0, z: 0))
            Issue.record("Nonfinite numeric wire must fail encoding.")
        } catch EncodingError.invalidValue(let value, let context) {
            #expect(KernelError.wrapping(EncodingError.invalidValue(value, context),
                phase: .validation, tolerance: .standard).code == .invalidInput)
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func originalLineageErrorAndCapabilityRecordsRetainNativeWire() throws {
        let source = SubshapeID(featureID: FeatureID(identity), role: "source", ordinal: 0)
        let output = SubshapeID(featureID: FeatureID(identity), role: "result", ordinal: 1)
        let lineage = TopologyLineage(output: output, parents: [source], relation: .preserved)
        try wire(lineage,
            #"{"output":{"featureID":"00112233-4455-4677-8899-AABBCCDDEEFF","role":"result","ordinal":1},"parents":[{"featureID":"00112233-4455-4677-8899-AABBCCDDEEFF","role":"source","ordinal":0}],"relation":"preserved"}"#)
        #expect(lineage.isStructurallyValid)
        let error = KernelError(phase: .topology, code: .nonManifoldResult,
            featureID: source.featureID, subshapeID: source, residual: 0.5,
            tolerance: ModelingTolerance(distance: 0.125, angle: 0.25, relative: 0.5), message: "literal")
        try wire(error,
            #"{"phase":"topology","code":"nonManifoldResult","featureID":"00112233-4455-4677-8899-AABBCCDDEEFF","subshapeID":{"featureID":"00112233-4455-4677-8899-AABBCCDDEEFF","role":"source","ordinal":0},"residual":0.5,"tolerance":{"distance":0.125,"angle":0.25,"relative":0.5},"message":"literal"}"#)
        #expect(error.category == .invalidTopology)
        #expect(error.errorDescription == "literal")
        let capability = KernelCapability(id: "CAP-1", operation: "wire", status: .partial,
            topology: .anyBRep, acceptedInputs: ["input"], exactOutputs: ["output"],
            failureCodes: [.unsupportedCapability],
            tolerance: ModelingTolerance(distance: 0.125, angle: 0.25, relative: 0.5),
            publicAPIs: ["operation"], testFixtures: ["literal"])
        let limitation = KernelDomainLimitation(id: "LIMIT-1", operations: ["wire"],
            dimensions: [.representation], condition: "literal", sourcePath: "Sources/Owner.swift", sourceLine: 1)
        let capabilityLiteral = #"{"id":"CAP-1","operation":"wire","status":"partial","topology":"anyBRep","acceptedInputs":["input"],"exactOutputs":["output"],"failureCodes":["unsupportedCapability"],"tolerance":{"distance":0.125,"angle":0.25,"relative":0.5},"publicAPIs":["operation"],"testFixtures":["literal"]}"#
        let limitationLiteral = #"{"id":"LIMIT-1","operations":["wire"],"dimensions":["representation"],"condition":"literal","sourcePath":"Sources/Owner.swift","sourceLine":1}"#
        let catalog = KernelCapabilityCatalog(capabilities: [capability], knownLimitations: [limitation])
        try catalog.validate()
        try wire(catalog, "{\"capabilities\":[\(capabilityLiteral)],\"knownLimitations\":[\(limitationLiteral)]}")
        let domain = try catalog.domain(operation: "wire")
        try wire(domain, "{\"capability\":\(capabilityLiteral),\"knownLimitations\":[\(limitationLiteral)]}")
        #expect(domain.limitations(affecting: .representation) == [limitation])
    }

    private var identity: PortableIdentity128 {
        PortableIdentity128(high: 0x0011_2233_4455_4677, low: 0x8899_AABB_CCDD_EEFF)
    }

    private func wire<Value: Codable & Equatable>(_ value: Value, _ literal: String) throws {
        let expected = Data(literal.utf8)
        #expect(try normalized(JSONEncoder().encode(value)) == normalized(expected))
        #expect(try JSONDecoder().decode(Value.self, from: expected) == value)
    }

    private func normalized(_ data: Data) throws -> Data {
        let object = try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
        return try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys, .fragmentsAllowed])
    }
}
#endif

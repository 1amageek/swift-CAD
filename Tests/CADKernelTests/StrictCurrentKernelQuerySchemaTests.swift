import Foundation
import Testing
import CADCore
import CADIR
@testable import CADKernel

@Suite("Strict current kernel query schema")
struct StrictCurrentKernelQuerySchemaTests {
    @Test(.timeLimit(.minutes(1)))
    func snapRequestRequiresOptionsAndRejectsUnknownFields() throws {
        let request = SnapQueryRequest(point: .origin)

        var missingOptions = try encodedObject(request)
        _ = missingOptions.removeValue(forKey: "options")
        try expectDecodingFailure(SnapQueryRequest.self, from: missingOptions)

        var unknownField = try encodedObject(request)
        unknownField["removedDevelopmentField"] = true
        try expectDecodingFailure(SnapQueryRequest.self, from: unknownField)
    }

    @Test(.timeLimit(.minutes(1)))
    func projectionQueryRequiresStrictProofResourceLimits() throws {
        let request = ProjectionQuery(
            point: .origin,
            target: .curve(CurveOutputReference(featureID: FeatureID()))
        )

        var missingLimits = try encodedObject(request)
        _ = missingLimits.removeValue(forKey: "resourceLimits")
        try expectDecodingFailure(ProjectionQuery.self, from: missingLimits)

        var removedSamplingContract = try encodedObject(request)
        removedSamplingContract["sampleCount"] = 9
        try expectDecodingFailure(ProjectionQuery.self, from: removedSamplingContract)

        var nestedUnknownField = try encodedObject(request)
        var limits = try #require(nestedUnknownField["resourceLimits"] as? [String: Any])
        limits["legacyFallbackCount"] = 9
        nestedUnknownField["resourceLimits"] = limits
        try expectDecodingFailure(ProjectionQuery.self, from: nestedUnknownField)
    }

    @Test(.timeLimit(.minutes(1)))
    func projectionResourceLimitsRejectUnsupportedBudgets() throws {
        let limits = ProjectionResourceLimits(maximumSubdivisionCells: 1_048_577)

        #expect(throws: KernelError.self) {
            try limits.validate(tolerance: .standard)
        }
    }

    @Test
    func kernelQueryResultRejectsUnknownFieldsAndMissingPayloads() throws {
        try expectDecodingFailure(
            KernelQueryResult.self,
            from: ["kind": "lineage", "lineage": NSNull(), "legacy": true]
        )
        try expectDecodingFailure(
            KernelQueryResult.self,
            from: ["kind": "lineage"]
        )
    }

    @Test
    func kernelQueryResultRejectsUnconvergedProjectionAsSuccess() throws {
        let reference = CurveParameterReference(
            curve: CurveOutputReference(featureID: FeatureID()),
            parameter: 0.5
        )
        let queryPoint = CurveQueryPoint(
            reference: reference,
            point: .origin,
            tangent: Vector3D.unitX,
            curvature: 0.0,
            isExact: true
        )
        let result = KernelQueryResult.projection(.curveClosest(
            CurveProjectionResult(
                sourcePoint: Point3D(x: 0.0, y: 1.0, z: 0.0),
                queryPoint: queryPoint,
                iterations: 32,
                converged: false
            )
        ))

        #expect(throws: KernelError.self) {
            try result.validate()
        }
        #expect(throws: KernelError.self) {
            _ = try JSONEncoder().encode(result)
        }
    }

    private func encodedObject<Value: Encodable>(_ value: Value) throws -> [String: Any] {
        let data = try JSONEncoder().encode(value)
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw StrictCurrentKernelQuerySchemaTestError.expectedObject
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

private enum StrictCurrentKernelQuerySchemaTestError: Error {
    case expectedObject
}

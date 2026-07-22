import Foundation
import Testing
import CADCore
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

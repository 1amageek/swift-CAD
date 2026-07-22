import Foundation
import Testing
import CADCore
@testable import CADTopology

@Suite("Strict current topology schema")
struct StrictCurrentTopologySchemaTests {
    @Test(.timeLimit(.minutes(1)))
    func bodyRequiresKindAndRejectsUnknownFields() throws {
        let body = Body(shellIDs: [ShellID()])

        var missingKind = try encodedObject(body)
        _ = missingKind.removeValue(forKey: "kind")
        try expectDecodingFailure(Body.self, from: missingKind)

        var unknownField = try encodedObject(body)
        unknownField["removedDevelopmentField"] = true
        try expectDecodingFailure(Body.self, from: unknownField)
    }

    @Test(.timeLimit(.minutes(1)))
    func validationRequestUsesOnlyTheCurrentStrictSchema() throws {
        let request = BRepValidationRequest(scopes: [.references, .loops])
        try expectRoundTrip(request)

        var missingScopes = try encodedObject(request)
        _ = missingScopes.removeValue(forKey: "scopes")
        try expectDecodingFailure(BRepValidationRequest.self, from: missingScopes)

        var unknownField = try encodedObject(request)
        unknownField["legacyValidationLevel"] = "exact"
        try expectDecodingFailure(BRepValidationRequest.self, from: unknownField)
    }

    @Test(.timeLimit(.minutes(1)))
    func repairRequestUsesOnlyTheCurrentStrictNestedSchema() throws {
        let request = BRepRepairRequest(
            actions: [.deduplicateOwnershipReferences, .pruneUnreferencedTopology],
            validationRequest: BRepValidationRequest(scopes: [.references])
        )
        try expectRoundTrip(request)

        var missingActions = try encodedObject(request)
        _ = missingActions.removeValue(forKey: "actions")
        try expectDecodingFailure(BRepRepairRequest.self, from: missingActions)

        var unknownField = try encodedObject(request)
        unknownField["automaticallyHeal"] = true
        try expectDecodingFailure(BRepRepairRequest.self, from: unknownField)

        var nestedUnknownField = try encodedObject(request)
        var validation = try #require(
            nestedUnknownField["validationRequest"] as? [String: Any]
        )
        validation["legacyValidationLevel"] = "exact"
        nestedUnknownField["validationRequest"] = validation
        try expectDecodingFailure(BRepRepairRequest.self, from: nestedUnknownField)
    }

    @Test(.timeLimit(.minutes(1)))
    func completeBRepValueHierarchyRejectsUnknownFields() throws {
        let vertexID = VertexID()
        let secondVertexID = VertexID()
        let curveID = CurveID()
        let edgeID = EdgeID()
        let loopID = LoopID()
        let surfaceID = SurfaceID()
        let faceID = FaceID()
        let values: [AnyStrictTopologyValue] = [
            AnyStrictTopologyValue(GeometryStore()),
            AnyStrictTopologyValue(Vertex(id: vertexID, point: .origin)),
            AnyStrictTopologyValue(Edge(
                id: edgeID,
                curveID: curveID,
                startVertexID: vertexID,
                endVertexID: secondVertexID,
                trim: CurveTrim(startParameter: 0.0, endParameter: 1.0)
            )),
            AnyStrictTopologyValue(Coedge(edgeID: edgeID)),
            AnyStrictTopologyValue(Loop(id: loopID, coedges: [Coedge(edgeID: edgeID)])),
            AnyStrictTopologyValue(Face(
                id: faceID,
                surfaceID: surfaceID,
                loops: [loopID]
            )),
            AnyStrictTopologyValue(Shell(faceIDs: [faceID])),
            AnyStrictTopologyValue(CurveTrim(
                startParameter: 0.0,
                endParameter: 1.0
            )),
            AnyStrictTopologyValue(BRepModel()),
        ]

        for value in values {
            try value.expectUnknownFieldRejected()
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func brepModelRejectsUnknownFieldsInsideNestedGeometryStore() throws {
        let model = BRepModel()
        try expectRoundTrip(model)
        var object = try encodedObject(model)
        var geometry = try #require(object["geometry"] as? [String: Any])
        geometry["legacyMeshCache"] = [String: Any]()
        object["geometry"] = geometry

        try expectDecodingFailure(BRepModel.self, from: object)
    }

    @Test(.timeLimit(.minutes(1)))
    func edgeRejectsRemovedSurfaceApproximationTolerance() throws {
        let edge = Edge(
            curveID: CurveID(),
            startVertexID: VertexID(),
            endVertexID: VertexID(),
            trim: CurveTrim(startParameter: 0.0, endParameter: 1.0)
        )
        var object = try encodedObject(edge)
        object["surfaceApproximationTolerance"] = 1.0e-5

        try expectDecodingFailure(Edge.self, from: object)
    }

    private func encodedObject<Value: Encodable>(_ value: Value) throws -> [String: Any] {
        let data = try JSONEncoder().encode(value)
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw StrictCurrentTopologySchemaTestError.expectedObject
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

    private func expectRoundTrip<Value: Codable & Equatable>(_ value: Value) throws {
        let data = try JSONEncoder().encode(value)
        let decoded = try JSONDecoder().decode(Value.self, from: data)
        #expect(decoded == value)
    }

    private struct AnyStrictTopologyValue {
        private let assertion: () throws -> Void

        init<Value: Codable>(_ value: Value) {
            assertion = {
                let data = try JSONEncoder().encode(value)
                guard var object = try JSONSerialization.jsonObject(with: data)
                    as? [String: Any] else {
                    throw StrictCurrentTopologySchemaTestError.expectedObject
                }
                object["removedDevelopmentField"] = true
                let mutated = try JSONSerialization.data(
                    withJSONObject: object,
                    options: [.sortedKeys]
                )
                #expect(throws: DecodingError.self) {
                    try JSONDecoder().decode(Value.self, from: mutated)
                }
            }
        }

        func expectUnknownFieldRejected() throws {
            try assertion()
        }
    }

    private enum StrictCurrentTopologySchemaTestError: Error {
        case expectedObject
    }
}

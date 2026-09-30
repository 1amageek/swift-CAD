import Foundation
import CADCore

public struct CADDocumentSourceFingerprint: Codable, Hashable, Sendable {
    public var algorithm: String
    public var value: String

    public init(algorithm: String, value: String) {
        self.algorithm = algorithm
        self.value = value
    }
}

public extension CADDocument {
    func sourceFingerprint(tolerance: ModelingTolerance) throws -> CADDocumentSourceFingerprint {
        try ValidatedCADDocument(self, tolerance: tolerance).sourceFingerprint()
    }
}

public extension ValidatedCADDocument {
    /// The document's source fingerprint, computed on first use and kept by this validated
    /// document and every copy of it: the document it validated never changes, so the
    /// evaluation engine, a cache seed and a freshness check reading the same validated
    /// document hash it once.
    func sourceFingerprint() throws -> CADDocumentSourceFingerprint {
        try sourceFingerprintMemo.value {
            let payload = try CADDocumentSourceFingerprintPayload(document: document)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            let data = try encoder.encode(payload)
            return CADDocumentSourceFingerprint(
                algorithm: "sha256-cad-source-dev",
                value: SHA256Digest.hexDigest(for: data)
            )
        }
    }
}

private struct CADDocumentSourceFingerprintPayload: Encodable {
    var schemaVersion: SchemaVersion
    var units: UnitSystem
    var parameters: ParameterTableFingerprint
    var designGraph: DesignGraphFingerprint
    var selectionDimensions: [SelectionDimension]

    init(document: CADDocument) throws {
        schemaVersion = document.schemaVersion
        units = document.units
        parameters = ParameterTableFingerprint(table: document.parameters)
        designGraph = try DesignGraphFingerprint(graph: document.designGraph)
        selectionDimensions = try document.selectionDimensions.sortedByStableEncoding()
    }
}

private struct ParameterTableFingerprint: Encodable {
    var parameters: [ParameterFingerprint]

    init(table: ParameterTable) {
        parameters = table.parameters
            .sorted { $0.key.description < $1.key.description }
            .map { ParameterFingerprint(id: $0.key, parameter: $0.value) }
    }
}

private struct ParameterFingerprint: Encodable {
    var tableID: String
    var id: String
    var name: String
    var expression: CADExpression
    var kind: QuantityKind

    init(id tableID: ParameterID, parameter: Parameter) {
        self.tableID = tableID.description
        id = parameter.id.description
        name = parameter.name
        expression = parameter.expression
        kind = parameter.kind
    }
}

private struct DesignGraphFingerprint: Encodable {
    var order: [String]
    var dependencies: [DependencyFingerprint]
    var nodes: [FeatureNodeFingerprint]

    init(graph: DesignGraph) throws {
        order = graph.order.map(\.description)
        dependencies = graph.dependencies
            .map(DependencyFingerprint.init)
            .sorted { lhs, rhs in
                if lhs.source != rhs.source {
                    return lhs.source < rhs.source
                }
                return lhs.target < rhs.target
            }
        nodes = try graph.nodes
            .sorted { $0.key.description < $1.key.description }
            .map { try FeatureNodeFingerprint(tableID: $0.key, node: $0.value) }
    }
}

private struct DependencyFingerprint: Encodable {
    var source: String
    var target: String

    init(_ dependency: DependencyEdge) {
        source = dependency.source.description
        target = dependency.target.description
    }
}

private struct FeatureNodeFingerprint: Encodable {
    var tableID: String
    var id: String
    var name: String?
    var operation: FeatureOperationFingerprint
    var inputs: [FeatureInput]
    var outputs: [FeatureOutput]
    var isSuppressed: Bool

    init(tableID: FeatureID, node: FeatureNode) throws {
        self.tableID = tableID.description
        id = node.id.description
        name = node.name
        operation = try FeatureOperationFingerprint(operation: node.operation)
        inputs = node.inputs
        outputs = node.outputs
        isSuppressed = node.isSuppressed
    }
}

/// Encodes the feature payload through `FeatureOperation`'s own Codable
/// conformance so the fingerprint frame stays small: keeping forty inline
/// optional payload fields plus a monolithic initializer overflowed worker
/// thread stacks on payload-rich documents.
private struct FeatureOperationFingerprint: Encodable {
    var kind: String
    var sketch: SketchFingerprint? = nil
    var operation: FeatureOperation? = nil

    init(operation: FeatureOperation) throws {
        if case let .sketch(sketch) = operation {
            kind = "sketch"
            self.sketch = try SketchFingerprint(sketch: sketch)
        } else {
            kind = "operation"
            self.operation = operation
        }
    }
}

private struct SketchFingerprint: Encodable {
    var id: String
    var plane: SketchPlane
    var entities: [SketchEntityFingerprint]
    var constraints: [SketchConstraint]
    var dimensions: [SketchDimension]

    init(sketch: Sketch) throws {
        id = sketch.id.description
        plane = sketch.plane
        entities = sketch.entities
            .sorted { $0.key.description < $1.key.description }
            .map { SketchEntityFingerprint(id: $0.key, entity: $0.value) }
        constraints = try sketch.constraints.sortedByStableEncoding()
        dimensions = try sketch.dimensions.sortedByStableEncoding()
    }
}

private struct SketchEntityFingerprint: Encodable {
    var id: String
    var entity: SketchEntity

    init(id: SketchEntityID, entity: SketchEntity) {
        self.id = id.description
        self.entity = entity
    }
}

private extension Array where Element: Encodable {
    func sortedByStableEncoding() throws -> [Element] {
        try map { element in
            (try stableJSONString(for: element), element)
        }
        .sorted { $0.0 < $1.0 }
        .map(\.1)
    }
}

private func stableJSONString<T: Encodable>(for value: T) throws -> String {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    let data = try encoder.encode(value)
    guard let string = String(data: data, encoding: .utf8) else {
        throw SchemaError.invalidMetadata("Canonical source fingerprint payload is not UTF-8.")
    }
    return string
}

import Foundation
import CADCore
import CADIR

public struct NativePackageStore: Sendable {
    private let tolerance: ModelingTolerance

    public init(tolerance: ModelingTolerance) {
        self.tolerance = tolerance
    }

    public func writePackage(for document: CADDocument, to sink: any ByteSink) throws {
        try document.validate(tolerance: tolerance)
        let encoder = nativePackageJSONEncoder()

        let manifest = NativePackageManifest(
            format: "swiftcad.package",
            schemaVersion: document.schemaVersion,
            documentPath: "document.json",
            createdAt: document.metadata.createdAt,
            updatedAt: document.metadata.updatedAt
        )

        let manifestData = try encoder.encode(manifest)
        let documentData = try canonicalNativeDocumentJSONData(from: encoder.encode(document))
        try StoredZipArchive.write(entries: [
            StoredZipArchive.Entry(path: "manifest.json", data: manifestData),
            StoredZipArchive.Entry(path: "document.json", data: documentData)
        ], to: sink)
    }

    public func loadDocument(from source: any ByteSource) throws -> CADDocument {
        do {
            return try StoredZipArchive.withBorrowedEntries(from: source) { entries in
                try loadDocument(fromPackageEntries: entries)
            }
        } catch let error as ZipArchiveError {
            throw SchemaError.invalidPackage("Invalid native ZIP package: \(error).")
        } catch {
            throw error
        }
    }

    private func loadDocument(fromPackageEntries entries: [String: Data]) throws -> CADDocument {
        try validateNativePackageEntries(entries)
        guard let manifestData = entries["manifest.json"],
              let documentData = entries["document.json"] else {
            throw SchemaError.invalidPackage("Missing manifest.json or document.json.")
        }
        try validateNativePackageJSONShape(manifestData: manifestData, documentData: documentData)

        let decoder = nativePackageJSONDecoder()
        let manifest: NativePackageManifest
        do {
            manifest = try decoder.decode(NativePackageManifest.self, from: manifestData)
        } catch {
            throw SchemaError.invalidPackage("Manifest JSON is invalid: \(error).")
        }
        guard manifest.format == "swiftcad.package" else {
            throw SchemaError.invalidPackage("Invalid package format.")
        }
        guard manifest.documentPath == "document.json" else {
            throw SchemaError.invalidPackage("Unsupported document path.")
        }
        let decodedDocument: CADDocument
        do {
            let decodableDocumentData = try canonicalNativeDocumentJSONData(from: documentData)
            decodedDocument = try decoder.decode(CADDocument.self, from: decodableDocumentData)
        } catch {
            throw SchemaError.invalidPackage("Document JSON is invalid: \(error).")
        }
        let document = decodedDocument
        guard manifest.schemaVersion == document.schemaVersion else {
            throw SchemaError.invalidPackage("Manifest schema version does not match document schema version.")
        }
        try document.validate(tolerance: tolerance)
        try validateManifest(manifest, matches: document)
        return document
    }

    public func save(_ document: CADDocument, to url: URL) throws {
        do {
            try writeFileAtomically(to: url) { sink in
                try writePackage(for: document, to: sink)
            }
        } catch let error as ByteSinkError {
            throw ExportError.fileWriteFailure(error.localizedDescription)
        }
    }

    public func load(from url: URL) throws -> CADDocument {
        do {
            return try loadDocument(from: MappedFileByteSource(url: url))
        } catch let error as ByteSourceError {
            throw ImportError.fileReadFailure(error.localizedDescription)
        } catch {
            throw error
        }
    }
}

private struct NativePackageManifest: Codable, Sendable {
    var format: String
    var schemaVersion: SchemaVersion
    var documentPath: String
    var createdAt: Date
    var updatedAt: Date
}

private func nativePackageJSONEncoder() -> JSONEncoder {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    encoder.dateEncodingStrategy = .custom { date, encoder in
        var container = encoder.singleValueContainer()
        try container.encode(date.timeIntervalSinceReferenceDate)
    }
    return encoder
}

private func nativePackageJSONDecoder() -> JSONDecoder {
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .custom { decoder in
        try decodeNativePackageDate(from: decoder)
    }
    return decoder
}

private func canonicalNativeDocumentJSONData(from data: Data) throws -> Data {
    guard var object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
        throw SchemaError.invalidPackage("Document JSON must be an object.")
    }
    try sortNativeDynamicObjectField(at: ["parameters", "parameters"][...], in: &object)
    try sortNativeDynamicObjectField(at: ["designGraph", "nodes"][...], in: &object)
    try sortNativeSketchEntityFields(in: &object)
    return try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])
}

private func sortNativeDynamicObjectField(at path: ArraySlice<String>, in object: inout [String: Any]) throws {
    guard let key = path.first else {
        throw SchemaError.invalidPackage("Expected native dynamic object path.")
    }
    if path.count == 1 {
        guard let value = object[key] else {
            return
        }
        object[key] = try sortedNativeDynamicObjectValue(value, path: key)
        return
    }
    guard var nestedObject = object[key] as? [String: Any] else {
        return
    }
    try sortNativeDynamicObjectField(at: path.dropFirst(), in: &nestedObject)
    object[key] = nestedObject
}

private struct NativeDynamicJSONPair {
    var key: String
    var logicalKey: String
    var value: Any
}

private func sortedNativeDynamicObjectValue(_ value: Any, path: String) throws -> Any {
    if let dictionary = value as? [String: Any] {
        let entries = try dictionary.map { key, value in
            NativeDynamicJSONPair(
                key: key,
                logicalKey: try canonicalNativeDynamicDictionaryKey(key, path: path),
                value: value
            )
        }
        var sortedPairs: [Any] = []
        for entry in entries.sorted(by: { $0.logicalKey < $1.logicalKey }) {
            sortedPairs.append(entry.key)
            sortedPairs.append(entry.value)
        }
        return sortedPairs
    }
    guard let pairs = value as? [Any] else {
        return value
    }
    guard pairs.count.isMultiple(of: 2) else {
        throw SchemaError.invalidPackage("Native \(path) dictionary must contain key/value pairs.")
    }
    var entries: [NativeDynamicJSONPair] = []
    var valueIndex = 1
    while valueIndex < pairs.count {
        guard let key = pairs[valueIndex - 1] as? String else {
            throw SchemaError.invalidPackage("Native \(path) dictionary key must be a string.")
        }
        entries.append(NativeDynamicJSONPair(
            key: key,
            logicalKey: try canonicalNativeDynamicDictionaryKey(key, path: path),
            value: pairs[valueIndex]
        ))
        valueIndex += 2
    }
    var sortedPairs: [Any] = []
    for entry in entries.sorted(by: { $0.logicalKey < $1.logicalKey }) {
        sortedPairs.append(entry.key)
        sortedPairs.append(entry.value)
    }
    return sortedPairs
}

private func sortNativeSketchEntityFields(in document: inout [String: Any]) throws {
    guard var designGraph = document["designGraph"] as? [String: Any] else {
        return
    }
    if var nodes = designGraph["nodes"] as? [Any] {
        var valueIndex = 1
        while valueIndex < nodes.count {
            if var node = nodes[valueIndex] as? [String: Any] {
                try sortNativeSketchEntityField(in: &node)
                nodes[valueIndex] = node
            }
            valueIndex += 2
        }
        designGraph["nodes"] = nodes
    } else if var nodes = designGraph["nodes"] as? [String: Any] {
        for key in nodes.keys {
            if var node = nodes[key] as? [String: Any] {
                try sortNativeSketchEntityField(in: &node)
                nodes[key] = node
            }
        }
        designGraph["nodes"] = nodes
    }
    document["designGraph"] = designGraph
}

private func sortNativeSketchEntityField(in node: inout [String: Any]) throws {
    guard var operation = node["operation"] as? [String: Any],
          var sketch = operation["sketch"] as? [String: Any],
          let entities = sketch["entities"] else {
        return
    }
    sketch["entities"] = try sortedNativeDynamicObjectValue(
        entities,
        path: "document.designGraph.nodes.operation.sketch.entities"
    )
    operation["sketch"] = sketch
    node["operation"] = operation
}

private func decodeNativePackageDate(from decoder: Decoder) throws -> Date {
    let container = try decoder.singleValueContainer()
    let value = try container.decode(Double.self)
    guard value.isFinite else {
        throw DecodingError.dataCorruptedError(
            in: container,
            debugDescription: "Native package date timestamp must be finite reference-date seconds."
        )
    }
    return Date(timeIntervalSinceReferenceDate: value)
}

private let supportedNativeManifestKeys: Set<String> = [
    "format",
    "schemaVersion",
    "documentPath",
    "createdAt",
    "updatedAt"
]

private let supportedNativeDocumentKeys: Set<String> = [
    "id",
    "schemaVersion",
    "units",
    "parameters",
    "designGraph",
    "selectionDimensions",
    "metadata"
]

private let supportedNativePackageEntries: Set<String> = [
    "manifest.json",
    "document.json"
]

private func validateManifest(_ manifest: NativePackageManifest, matches document: CADDocument) throws {
    let created = manifest.createdAt.timeIntervalSinceReferenceDate
    let updated = manifest.updatedAt.timeIntervalSinceReferenceDate
    guard created.isFinite, updated.isFinite else {
        throw SchemaError.invalidPackage("Manifest timestamps must be finite.")
    }
    guard manifest.updatedAt >= manifest.createdAt else {
        throw SchemaError.invalidPackage("Manifest updatedAt must not be earlier than createdAt.")
    }
    guard manifest.createdAt == document.metadata.createdAt,
          manifest.updatedAt == document.metadata.updatedAt else {
        throw SchemaError.invalidPackage("Manifest timestamps do not match document metadata.")
    }
}

private func validateNativePackageEntries(_ entries: [String: Data]) throws {
    let unsupportedEntries = Set(entries.keys).subtracting(supportedNativePackageEntries)
    guard unsupportedEntries.isEmpty else {
        let entry = unsupportedEntries.sorted().first ?? "unknown"
        throw SchemaError.invalidPackage("Unsupported native package entry \(entry).")
    }
}

private func validateNativePackageJSONShape(manifestData: Data, documentData: Data) throws {
    let manifest = try nativeJSONObject(from: manifestData, name: "Manifest")
    try validateNativeManifestObject(manifest)

    let document = try nativeJSONObject(from: documentData, name: "Document")
    try validateNativeDocumentObject(document)
}

private func validateNativeManifestObject(_ object: [String: Any]) throws {
    try rejectUnsupportedNativeKeys(
        in: object,
        supportedKeys: supportedNativeManifestKeys,
        objectName: "manifest"
    )
    try validateObjectField("schemaVersion", in: object, path: "manifest.schemaVersion", using: validateSchemaVersionObject)
}

private func validateNativeDocumentObject(_ object: [String: Any]) throws {
    try rejectUnsupportedNativeKeys(in: object, supportedKeys: supportedNativeDocumentKeys, objectName: "document")
    try validateObjectField("schemaVersion", in: object, path: "document.schemaVersion", using: validateSchemaVersionObject)
    try validateObjectField("units", in: object, path: "document.units", using: validateUnitSystemObject)
    try validateObjectField("parameters", in: object, path: "document.parameters", using: validateParameterTableObject)
    try validateObjectField("designGraph", in: object, path: "document.designGraph", using: validateDesignGraphObject)
    try validateArrayField(
        "selectionDimensions",
        in: object,
        path: "document.selectionDimensions",
        using: validateSelectionDimensionObject
    )
    try validateObjectField("metadata", in: object, path: "document.metadata", using: validateDocumentMetadataObject)
}

private func validateSchemaVersionObject(_ object: [String: Any], path: String) throws {
    try rejectUnsupportedNativeKeys(in: object, supportedKeys: ["major", "minor", "patch"], objectName: path)
}

private func validateDocumentRevisionObject(_ object: [String: Any], path: String) throws {
    try rejectUnsupportedNativeKeys(in: object, supportedKeys: ["value"], objectName: path)
}

private func validateUnitSystemObject(_ object: [String: Any], path: String) throws {
    try rejectUnsupportedNativeKeys(in: object, supportedKeys: ["length", "angle"], objectName: path)
}

private func validateDocumentMetadataObject(_ object: [String: Any], path: String) throws {
    try rejectUnsupportedNativeKeys(in: object, supportedKeys: ["name", "createdAt", "updatedAt"], objectName: path)
}

private func validateParameterTableObject(_ object: [String: Any], path: String) throws {
    try rejectUnsupportedNativeKeys(in: object, supportedKeys: ["parameters", "revision"], objectName: path)
    try validateDynamicObjectField("parameters", in: object, path: "\(path).parameters", using: validateParameterObject)
    try validateObjectField("revision", in: object, path: "\(path).revision", using: validateDocumentRevisionObject)
}

private func validateParameterObject(_ object: [String: Any], path: String) throws {
    try rejectUnsupportedNativeKeys(in: object, supportedKeys: ["id", "name", "expression", "kind"], objectName: path)
    try validateObjectField("expression", in: object, path: "\(path).expression", using: validateExpressionObject)
}

private func validateExpressionObject(_ object: [String: Any], path: String) throws {
    try rejectUnsupportedNativeKeys(
        in: object,
        supportedKeys: ["kind", "quantity", "parameterID", "name", "quantityKind", "left", "right", "argument"],
        objectName: path
    )
    try validateObjectField("quantity", in: object, path: "\(path).quantity", using: validateQuantityObject)
    try validateObjectField("left", in: object, path: "\(path).left", using: validateExpressionObject)
    try validateObjectField("right", in: object, path: "\(path).right", using: validateExpressionObject)
    try validateObjectField("argument", in: object, path: "\(path).argument", using: validateExpressionObject)
}

private func validateQuantityObject(_ object: [String: Any], path: String) throws {
    try rejectUnsupportedNativeKeys(in: object, supportedKeys: ["value", "kind"], objectName: path)
}

private func validateDesignGraphObject(_ object: [String: Any], path: String) throws {
    try rejectUnsupportedNativeKeys(
        in: object,
        supportedKeys: ["nodes", "order", "dependencies", "revision"],
        objectName: path
    )
    try validateDynamicObjectField("nodes", in: object, path: "\(path).nodes", using: validateFeatureNodeObject)
    try validateArrayField("dependencies", in: object, path: "\(path).dependencies", using: validateDependencyEdgeObject)
    try validateObjectField("revision", in: object, path: "\(path).revision", using: validateDocumentRevisionObject)
}

private func validateDependencyEdgeObject(_ object: [String: Any], path: String) throws {
    try rejectUnsupportedNativeKeys(in: object, supportedKeys: ["source", "target"], objectName: path)
}

private func validateFeatureNodeObject(_ object: [String: Any], path: String) throws {
    try rejectUnsupportedNativeKeys(
        in: object,
        supportedKeys: ["id", "name", "operation", "inputs", "outputs", "isSuppressed"],
        objectName: path
    )
    try validateObjectField("operation", in: object, path: "\(path).operation", using: validateFeatureOperationObject)
    try validateArrayField("inputs", in: object, path: "\(path).inputs", using: validateFeatureInputObject)
    try validateArrayField("outputs", in: object, path: "\(path).outputs", using: validateFeatureOutputObject)
}

private func validateFeatureInputObject(_ object: [String: Any], path: String) throws {
    try rejectUnsupportedNativeKeys(in: object, supportedKeys: ["featureID", "role"], objectName: path)
}

private func validateFeatureOutputObject(_ object: [String: Any], path: String) throws {
    try rejectUnsupportedNativeKeys(in: object, supportedKeys: ["role"], objectName: path)
}

private func validateFeatureOperationObject(_ object: [String: Any], path: String) throws {
    try rejectUnsupportedNativeKeys(
        in: object,
        supportedKeys: Set(["kind"]).union(
            FeatureOperationKind.allCases.map(\.rawValue)
        ),
        objectName: path
    )
    try validateObjectField("sketch", in: object, path: "\(path).sketch", using: validateSketchObject)
    try validateObjectField("primitive", in: object, path: "\(path).primitive", using: validatePrimitiveFeatureObject)
    try validateObjectField("extrude", in: object, path: "\(path).extrude", using: validateExtrudeFeatureObject)
    try validateObjectField("revolve", in: object, path: "\(path).revolve", using: validateRevolveFeatureObject)
    try validateObjectField("sweep", in: object, path: "\(path).sweep", using: validateSweepFeatureObject)
    try validateObjectField("loft", in: object, path: "\(path).loft", using: validateLoftFeatureObject)
    try validateObjectField("boolean", in: object, path: "\(path).boolean", using: validateBooleanFeatureObject)
    try validateObjectField("polySpline", in: object, path: "\(path).polySpline", using: validatePolySplineFeatureObject)
    try validateObjectField("bSplineSurface", in: object, path: "\(path).bSplineSurface", using: validateBSplineSurfaceFeatureObject)
    try validateObjectField(
        "patchSurface",
        in: object,
        path: "\(path).patchSurface",
        using: validatePatchSurfaceFeatureObject
    )
    try validateObjectField("faceLoopOffset", in: object, path: "\(path).faceLoopOffset", using: validateFaceLoopOffsetFeatureObject)
    try validateObjectField("edgeOffset", in: object, path: "\(path).edgeOffset", using: validateEdgeOffsetFeatureObject)
    try validateObjectField("faceKnife", in: object, path: "\(path).faceKnife", using: validateFaceKnifeFeatureObject)
    try validateObjectField("faceDelete", in: object, path: "\(path).faceDelete", using: validateFaceDeleteFeatureObject)
    try validateObjectField("faceDraft", in: object, path: "\(path).faceDraft", using: validateFaceDraftFeatureObject)
    try validateObjectField("faceOffset", in: object, path: "\(path).faceOffset", using: validateFaceOffsetFeatureObject)
    try validateObjectField("faceMove", in: object, path: "\(path).faceMove", using: validateFaceMoveFeatureObject)
    try validateObjectField("edgeMove", in: object, path: "\(path).edgeMove", using: validateEdgeMoveFeatureObject)
    try validateObjectField("vertexMove", in: object, path: "\(path).vertexMove", using: validateVertexMoveFeatureObject)
    try validateObjectField("linearPattern", in: object, path: "\(path).linearPattern", using: validateLinearPatternFeatureObject)
    try validateObjectField("radialPattern", in: object, path: "\(path).radialPattern", using: validateRadialPatternFeatureObject)
    try validateObjectField("gridPattern", in: object, path: "\(path).gridPattern", using: validateGridPatternFeatureObject)
    try validateObjectField("curveDrivenPattern", in: object, path: "\(path).curveDrivenPattern", using: validateCurveDrivenPatternFeatureObject)
    try validateObjectField("mirror", in: object, path: "\(path).mirror", using: validateMirrorFeatureObject)
    try validateObjectField("joinBodies", in: object, path: "\(path).joinBodies", using: validateJoinBodiesFeatureObject)
    try validateObjectField("unjoinBody", in: object, path: "\(path).unjoinBody", using: validateUnjoinBodyFeatureObject)
    try validateObjectField("chamfer", in: object, path: "\(path).chamfer", using: validateChamferFeatureObject)
    try validateObjectField("fillet", in: object, path: "\(path).fillet", using: validateFilletFeatureObject)
    try validateObjectField("g2Blend", in: object, path: "\(path).g2Blend", using: validateG2BlendFeatureObject)
    try validateObjectField("setbackCorner", in: object, path: "\(path).setbackCorner", using: validateSetbackCornerFeatureObject)
    try validateObjectField("shell", in: object, path: "\(path).shell", using: validateShellFeatureObject)
    try validateObjectField("thicken", in: object, path: "\(path).thicken", using: validateThickenFeatureObject)
    try validateObjectField("bridgeCurve", in: object, path: "\(path).bridgeCurve", using: validateBridgeCurveFeatureObject)
    try validateObjectField("bridgeSurface", in: object, path: "\(path).bridgeSurface", using: validateBridgeSurfaceFeatureObject)
    try validateObjectField("curveEdit", in: object, path: "\(path).curveEdit", using: validateCurveEditFeatureObject)
    try validateObjectField("curveOffset", in: object, path: "\(path).curveOffset", using: validateCurveOffsetFeatureObject)
    try validateObjectField("projectCurve", in: object, path: "\(path).projectCurve", using: validateProjectCurveFeatureObject)
    try validateObjectField("curveTrim", in: object, path: "\(path).curveTrim", using: validateCurveTrimFeatureObject)
    try validateObjectField("curveExtend", in: object, path: "\(path).curveExtend", using: validateCurveExtendFeatureObject)
    try validateObjectField("curveMatch", in: object, path: "\(path).curveMatch", using: validateCurveMatchFeatureObject)
    try validateObjectField("surfaceOffset", in: object, path: "\(path).surfaceOffset", using: validateSurfaceOffsetFeatureObject)
    try validateObjectField("surfaceTrim", in: object, path: "\(path).surfaceTrim", using: validateSurfaceTrimFeatureObject)
    try validateObjectField("surfaceExtend", in: object, path: "\(path).surfaceExtend", using: validateSurfaceExtendFeatureObject)
    try validateObjectField("surfaceMatch", in: object, path: "\(path).surfaceMatch", using: validateSurfaceMatchFeatureObject)
}

private func validatePrimitiveFeatureObject(_ object: [String: Any], path: String) throws {
    try rejectUnsupportedNativeKeys(
        in: object,
        supportedKeys: ["definition"],
        objectName: path
    )
    try validateObjectField(
        "definition",
        in: object,
        path: "\(path).definition",
        using: validatePrimitiveDefinitionObject
    )
}

private func validatePrimitiveDefinitionObject(_ object: [String: Any], path: String) throws {
    try rejectUnsupportedNativeKeys(
        in: object,
        supportedKeys: ["kind", "box", "cylinder", "cone", "sphere", "torus"],
        objectName: path
    )
    try validateObjectField("box", in: object, path: "\(path).box", using: validateBoxPrimitiveObject)
    try validateObjectField(
        "cylinder",
        in: object,
        path: "\(path).cylinder",
        using: validateCylinderPrimitiveObject
    )
    try validateObjectField("cone", in: object, path: "\(path).cone", using: validateConePrimitiveObject)
    try validateObjectField(
        "sphere",
        in: object,
        path: "\(path).sphere",
        using: validateSpherePrimitiveObject
    )
    try validateObjectField("torus", in: object, path: "\(path).torus", using: validateTorusPrimitiveObject)
}

private func validateBoxPrimitiveObject(_ object: [String: Any], path: String) throws {
    try rejectUnsupportedNativeKeys(
        in: object,
        supportedKeys: ["placement", "width", "depth", "height"],
        objectName: path
    )
    try validatePrimitivePlacementField(in: object, path: path)
    try validateObjectField("width", in: object, path: "\(path).width", using: validateExpressionObject)
    try validateObjectField("depth", in: object, path: "\(path).depth", using: validateExpressionObject)
    try validateObjectField("height", in: object, path: "\(path).height", using: validateExpressionObject)
}

private func validateCylinderPrimitiveObject(_ object: [String: Any], path: String) throws {
    try rejectUnsupportedNativeKeys(
        in: object,
        supportedKeys: ["placement", "radius", "height"],
        objectName: path
    )
    try validatePrimitivePlacementField(in: object, path: path)
    try validateObjectField("radius", in: object, path: "\(path).radius", using: validateExpressionObject)
    try validateObjectField("height", in: object, path: "\(path).height", using: validateExpressionObject)
}

private func validateConePrimitiveObject(_ object: [String: Any], path: String) throws {
    try rejectUnsupportedNativeKeys(
        in: object,
        supportedKeys: ["placement", "baseRadius", "height"],
        objectName: path
    )
    try validatePrimitivePlacementField(in: object, path: path)
    try validateObjectField(
        "baseRadius",
        in: object,
        path: "\(path).baseRadius",
        using: validateExpressionObject
    )
    try validateObjectField("height", in: object, path: "\(path).height", using: validateExpressionObject)
}

private func validateSpherePrimitiveObject(_ object: [String: Any], path: String) throws {
    try rejectUnsupportedNativeKeys(
        in: object,
        supportedKeys: ["placement", "radius"],
        objectName: path
    )
    try validatePrimitivePlacementField(in: object, path: path)
    try validateObjectField("radius", in: object, path: "\(path).radius", using: validateExpressionObject)
}

private func validateTorusPrimitiveObject(_ object: [String: Any], path: String) throws {
    try rejectUnsupportedNativeKeys(
        in: object,
        supportedKeys: ["placement", "majorRadius", "minorRadius"],
        objectName: path
    )
    try validatePrimitivePlacementField(in: object, path: path)
    try validateObjectField(
        "majorRadius",
        in: object,
        path: "\(path).majorRadius",
        using: validateExpressionObject
    )
    try validateObjectField(
        "minorRadius",
        in: object,
        path: "\(path).minorRadius",
        using: validateExpressionObject
    )
}

private func validatePrimitivePlacementField(in object: [String: Any], path: String) throws {
    try validateObjectField(
        "placement",
        in: object,
        path: "\(path).placement",
        using: validatePrimitivePlacementObject
    )
}

private func validatePrimitivePlacementObject(_ object: [String: Any], path: String) throws {
    try rejectUnsupportedNativeKeys(
        in: object,
        supportedKeys: ["origin", "axis", "referenceDirection"],
        objectName: path
    )
    try validateObjectField("origin", in: object, path: "\(path).origin", using: validatePoint3DObject)
    try validateObjectField("axis", in: object, path: "\(path).axis", using: validateVector3DObject)
    try validateObjectField(
        "referenceDirection",
        in: object,
        path: "\(path).referenceDirection",
        using: validateVector3DObject
    )
}

private func validateSketchObject(_ object: [String: Any], path: String) throws {
    try rejectUnsupportedNativeKeys(
        in: object,
        supportedKeys: ["id", "plane", "entities", "entityOrder", "constraints", "dimensions"],
        objectName: path
    )
    try validateObjectField("plane", in: object, path: "\(path).plane", using: validateSketchPlaneObject)
    try validateDynamicObjectField("entities", in: object, path: "\(path).entities", using: validateSketchEntityObject)
    try validateArrayField("constraints", in: object, path: "\(path).constraints", using: validateSketchConstraintObject)
    try validateArrayField("dimensions", in: object, path: "\(path).dimensions", using: validateSketchDimensionObject)
}

private func validateSketchPlaneObject(_ object: [String: Any], path: String) throws {
    try rejectUnsupportedNativeKeys(in: object, supportedKeys: ["kind", "plane"], objectName: path)
    try validateObjectField("plane", in: object, path: "\(path).plane", using: validatePlane3DObject)
}

private func validateSketchEntityObject(_ object: [String: Any], path: String) throws {
    try rejectUnsupportedNativeKeys(
        in: object,
        supportedKeys: ["kind", "point", "line", "circle", "arc", "spline"],
        objectName: path
    )
    try validateObjectField("point", in: object, path: "\(path).point", using: validateSketchPointObject)
    try validateObjectField("line", in: object, path: "\(path).line", using: validateSketchLineObject)
    try validateObjectField("circle", in: object, path: "\(path).circle", using: validateSketchCircleObject)
    try validateObjectField("arc", in: object, path: "\(path).arc", using: validateSketchArcObject)
    try validateObjectField("spline", in: object, path: "\(path).spline", using: validateSketchSplineObject)
}

private func validateSketchPointObject(_ object: [String: Any], path: String) throws {
    try rejectUnsupportedNativeKeys(in: object, supportedKeys: ["x", "y"], objectName: path)
    try validateObjectField("x", in: object, path: "\(path).x", using: validateExpressionObject)
    try validateObjectField("y", in: object, path: "\(path).y", using: validateExpressionObject)
}

private func validateSketchLineObject(_ object: [String: Any], path: String) throws {
    try rejectUnsupportedNativeKeys(in: object, supportedKeys: ["start", "end"], objectName: path)
    try validateObjectField("start", in: object, path: "\(path).start", using: validateSketchPointObject)
    try validateObjectField("end", in: object, path: "\(path).end", using: validateSketchPointObject)
}

private func validateSketchCircleObject(_ object: [String: Any], path: String) throws {
    try rejectUnsupportedNativeKeys(in: object, supportedKeys: ["center", "radius"], objectName: path)
    try validateObjectField("center", in: object, path: "\(path).center", using: validateSketchPointObject)
    try validateObjectField("radius", in: object, path: "\(path).radius", using: validateExpressionObject)
}

private func validateSketchArcObject(_ object: [String: Any], path: String) throws {
    try rejectUnsupportedNativeKeys(
        in: object,
        supportedKeys: ["center", "radius", "startAngle", "endAngle"],
        objectName: path
    )
    try validateObjectField("center", in: object, path: "\(path).center", using: validateSketchPointObject)
    try validateObjectField("radius", in: object, path: "\(path).radius", using: validateExpressionObject)
    try validateObjectField("startAngle", in: object, path: "\(path).startAngle", using: validateExpressionObject)
    try validateObjectField("endAngle", in: object, path: "\(path).endAngle", using: validateExpressionObject)
}

private func validateSketchSplineObject(_ object: [String: Any], path: String) throws {
    try rejectUnsupportedNativeKeys(
        in: object,
        supportedKeys: ["controlPoints", "isClosed"],
        objectName: path
    )
    try validateArrayField("controlPoints", in: object, path: "\(path).controlPoints", using: validateSketchPointObject)
}

private func validateSketchReferenceObject(_ object: [String: Any], path: String) throws {
    try rejectUnsupportedNativeKeys(
        in: object,
        supportedKeys: ["kind", "entityID", "controlPointIndex"],
        objectName: path
    )
}

private func validateSketchConstraintObject(_ object: [String: Any], path: String) throws {
    try rejectUnsupportedNativeKeys(
        in: object,
        supportedKeys: ["kind", "first", "second", "entityID", "controlPointIndex", "tangency", "splineLineTangency", "splineEndpointTangency"],
        objectName: path
    )
    try validateObjectField("first", in: object, path: "\(path).first", using: validateSketchReferenceObject)
    try validateObjectField("second", in: object, path: "\(path).second", using: validateSketchReferenceObject)
    try validateObjectField("tangency", in: object, path: "\(path).tangency", using: validateSketchTangencyObject)
    try validateObjectField(
        "splineLineTangency",
        in: object,
        path: "\(path).splineLineTangency",
        using: validateSketchSplineLineTangencyObject
    )
    try validateObjectField(
        "splineEndpointTangency",
        in: object,
        path: "\(path).splineEndpointTangency",
        using: validateSketchSplineEndpointTangencyObject
    )
}

private func validateSketchTangencyObject(_ object: [String: Any], path: String) throws {
    try rejectUnsupportedNativeKeys(
        in: object,
        supportedKeys: ["kind", "line", "circular", "side", "first", "second", "contact"],
        objectName: path
    )
}

private func validateSketchSplineLineTangencyObject(_ object: [String: Any], path: String) throws {
    try rejectUnsupportedNativeKeys(
        in: object,
        supportedKeys: ["splineEndpoint", "line", "orientation"],
        objectName: path
    )
    try validateObjectField(
        "splineEndpoint",
        in: object,
        path: "\(path).splineEndpoint",
        using: validateSketchSplineEndpointReferenceObject
    )
}

private func validateSketchSplineEndpointTangencyObject(_ object: [String: Any], path: String) throws {
    try rejectUnsupportedNativeKeys(
        in: object,
        supportedKeys: ["first", "second", "orientation"],
        objectName: path
    )
    try validateObjectField(
        "first",
        in: object,
        path: "\(path).first",
        using: validateSketchSplineEndpointReferenceObject
    )
    try validateObjectField(
        "second",
        in: object,
        path: "\(path).second",
        using: validateSketchSplineEndpointReferenceObject
    )
}

private func validateSketchSplineEndpointReferenceObject(_ object: [String: Any], path: String) throws {
    try rejectUnsupportedNativeKeys(
        in: object,
        supportedKeys: ["splineID", "endpoint"],
        objectName: path
    )
}

private func validateSketchDimensionObject(_ object: [String: Any], path: String) throws {
    try rejectUnsupportedNativeKeys(in: object, supportedKeys: ["kind", "from", "to", "entityID", "value"], objectName: path)
    try validateObjectField("from", in: object, path: "\(path).from", using: validateSketchReferenceObject)
    try validateObjectField("to", in: object, path: "\(path).to", using: validateSketchReferenceObject)
    try validateObjectField("value", in: object, path: "\(path).value", using: validateExpressionObject)
}

private func validateSelectionDimensionObject(_ object: [String: Any], path: String) throws {
    try rejectUnsupportedNativeKeys(
        in: object,
        supportedKeys: ["id", "name", "kind", "first", "second", "target"],
        objectName: path
    )
    try validateObjectField("first", in: object, path: "\(path).first", using: validateSelectionReferenceObject)
    try validateObjectField("second", in: object, path: "\(path).second", using: validateSelectionReferenceObject)
    try validateObjectField("target", in: object, path: "\(path).target", using: validateExpressionObject)
}

private func validateSelectionReferenceObject(_ object: [String: Any], path: String) throws {
    try rejectUnsupportedNativeKeys(
        in: object,
        supportedKeys: ["kind", "subshape", "edge", "curve", "sketchPoint", "surface"],
        objectName: path
    )
    try validateObjectField(
        "subshape",
        in: object,
        path: "\(path).subshape",
        using: validateStableSubshapeReferenceObject
    )
    try validateObjectField("edge", in: object, path: "\(path).edge", using: validateEdgeSubobjectReferenceObject)
    try validateObjectField("curve", in: object, path: "\(path).curve", using: validateCurveSubobjectReferenceObject)
    try validateObjectField("sketchPoint", in: object, path: "\(path).sketchPoint", using: validateSketchPointSelectionReferenceObject)
    try validateObjectField("surface", in: object, path: "\(path).surface", using: validateSurfaceSubobjectReferenceObject)
}

private func validateSketchPointSelectionReferenceObject(_ object: [String: Any], path: String) throws {
    try rejectUnsupportedNativeKeys(in: object, supportedKeys: ["featureID", "entityID"], objectName: path)
}

private func validateEdgeSubobjectReferenceObject(_ object: [String: Any], path: String) throws {
    try rejectUnsupportedNativeKeys(
        in: object,
        supportedKeys: ["kind", "whole", "parameter"],
        objectName: path
    )
    try validateObjectField("whole", in: object, path: "\(path).whole", using: validateEdgeReferenceObject)
    try validateObjectField("parameter", in: object, path: "\(path).parameter", using: validateEdgeParameterReferenceObject)
}

private func validateEdgeReferenceObject(_ object: [String: Any], path: String) throws {
    try rejectUnsupportedNativeKeys(in: object, supportedKeys: ["subshape"], objectName: path)
    try validateObjectField(
        "subshape",
        in: object,
        path: "\(path).subshape",
        using: validateStableSubshapeReferenceObject
    )
}

private func validateEdgeParameterReferenceObject(_ object: [String: Any], path: String) throws {
    try rejectUnsupportedNativeKeys(in: object, supportedKeys: ["edge", "parameter"], objectName: path)
    try validateObjectField("edge", in: object, path: "\(path).edge", using: validateEdgeReferenceObject)
}

private func validateCurveSubobjectReferenceObject(_ object: [String: Any], path: String) throws {
    try rejectUnsupportedNativeKeys(
        in: object,
        supportedKeys: ["kind", "whole", "parameter", "span", "controlPoint", "knot"],
        objectName: path
    )
    try validateObjectField("whole", in: object, path: "\(path).whole", using: validateCurveOutputReferenceObject)
    try validateObjectField("parameter", in: object, path: "\(path).parameter", using: validateCurveParameterReferenceObject)
    try validateObjectField("span", in: object, path: "\(path).span", using: validateCurveSpanReferenceObject)
    try validateObjectField(
        "controlPoint",
        in: object,
        path: "\(path).controlPoint",
        using: validateCurveControlPointReferenceObject
    )
    try validateObjectField("knot", in: object, path: "\(path).knot", using: validateCurveKnotReferenceObject)
}

private func validateCurveOutputReferenceObject(_ object: [String: Any], path: String) throws {
    try rejectUnsupportedNativeKeys(in: object, supportedKeys: ["featureID", "curveIndex"], objectName: path)
}

private func validateCurveParameterReferenceObject(_ object: [String: Any], path: String) throws {
    try rejectUnsupportedNativeKeys(in: object, supportedKeys: ["curve", "parameter"], objectName: path)
    try validateObjectField("curve", in: object, path: "\(path).curve", using: validateCurveOutputReferenceObject)
}

private func validateCurveSpanReferenceObject(_ object: [String: Any], path: String) throws {
    try rejectUnsupportedNativeKeys(in: object, supportedKeys: ["curve", "spanIndex"], objectName: path)
    try validateObjectField("curve", in: object, path: "\(path).curve", using: validateCurveOutputReferenceObject)
}

private func validateCurveControlPointReferenceObject(_ object: [String: Any], path: String) throws {
    try rejectUnsupportedNativeKeys(in: object, supportedKeys: ["curve", "controlPointIndex"], objectName: path)
    try validateObjectField("curve", in: object, path: "\(path).curve", using: validateCurveOutputReferenceObject)
}

private func validateCurveKnotReferenceObject(_ object: [String: Any], path: String) throws {
    try rejectUnsupportedNativeKeys(in: object, supportedKeys: ["curve", "knotIndex"], objectName: path)
    try validateObjectField("curve", in: object, path: "\(path).curve", using: validateCurveOutputReferenceObject)
}

private func validateSurfaceSubobjectReferenceObject(_ object: [String: Any], path: String) throws {
    try rejectUnsupportedNativeKeys(
        in: object,
        supportedKeys: ["kind", "whole", "parameter", "span", "controlPoint", "knot", "trim", "trimSpan", "trimKnot"],
        objectName: path
    )
    try validateObjectField("whole", in: object, path: "\(path).whole", using: validateSurfaceReferenceObject)
    try validateObjectField("parameter", in: object, path: "\(path).parameter", using: validateSurfaceParameterReferenceObject)
    try validateObjectField("span", in: object, path: "\(path).span", using: validateSurfaceSpanReferenceObject)
    try validateObjectField(
        "controlPoint",
        in: object,
        path: "\(path).controlPoint",
        using: validateSurfaceControlPointReferenceObject
    )
    try validateObjectField("knot", in: object, path: "\(path).knot", using: validateSurfaceKnotReferenceObject)
    try validateObjectField("trim", in: object, path: "\(path).trim", using: validateSurfaceTrimReferenceObject)
    try validateObjectField("trimSpan", in: object, path: "\(path).trimSpan", using: validateSurfaceTrimSpanReferenceObject)
    try validateObjectField("trimKnot", in: object, path: "\(path).trimKnot", using: validateSurfaceTrimKnotReferenceObject)
}

private func validateSurfaceReferenceObject(_ object: [String: Any], path: String) throws {
    try rejectUnsupportedNativeKeys(in: object, supportedKeys: ["subshape"], objectName: path)
    try validateObjectField(
        "subshape",
        in: object,
        path: "\(path).subshape",
        using: validateStableSubshapeReferenceObject
    )
}

private func validateStableSubshapeReferenceObject(_ object: [String: Any], path: String) throws {
    try rejectUnsupportedNativeKeys(
        in: object,
        supportedKeys: ["subshapeID", "geometrySignature"],
        objectName: path
    )
    try validateObjectField("subshapeID", in: object, path: "\(path).subshapeID") { value, valuePath in
        try rejectUnsupportedNativeKeys(
            in: value,
            supportedKeys: ["featureID", "role", "ordinal"],
            objectName: valuePath
        )
    }
    try validateObjectField(
        "geometrySignature",
        in: object,
        path: "\(path).geometrySignature",
        using: validateSubshapeGeometrySignatureObject
    )
}

private func validateSubshapeGeometrySignatureObject(_ object: [String: Any], path: String) throws {
    guard let kind = object["kind"] as? String else {
        throw ImportError.invalidData("\(path).kind must be a string.")
    }
    switch kind {
    case "body":
        try rejectUnsupportedNativeKeys(
            in: object,
            supportedKeys: ["kind", "body"],
            objectName: path
        )
        try validateObjectField("body", in: object, path: "\(path).body") { _, _ in }
    case "vertex":
        try rejectUnsupportedNativeKeys(in: object, supportedKeys: ["kind", "point"], objectName: path)
        try validateObjectField("point", in: object, path: "\(path).point", using: validatePoint3DObject)
    case "edge":
        try rejectUnsupportedNativeKeys(
            in: object,
            supportedKeys: ["kind", "edge"],
            objectName: path
        )
        try validateObjectField("edge", in: object, path: "\(path).edge") { _, _ in }
    case "face":
        try rejectUnsupportedNativeKeys(
            in: object,
            supportedKeys: ["kind", "face"],
            objectName: path
        )
        try validateObjectField("face", in: object, path: "\(path).face") { _, _ in }
    default:
        throw ImportError.invalidData("\(path).kind is unsupported.")
    }
}

private func validateSurfaceParameterReferenceObject(_ object: [String: Any], path: String) throws {
    try rejectUnsupportedNativeKeys(in: object, supportedKeys: ["surface", "u", "v"], objectName: path)
    try validateObjectField("surface", in: object, path: "\(path).surface", using: validateSurfaceReferenceObject)
}

private func validateSurfaceSpanReferenceObject(_ object: [String: Any], path: String) throws {
    try rejectUnsupportedNativeKeys(in: object, supportedKeys: ["surface", "direction", "spanIndex"], objectName: path)
    try validateObjectField("surface", in: object, path: "\(path).surface", using: validateSurfaceReferenceObject)
}

private func validateSurfaceControlPointReferenceObject(_ object: [String: Any], path: String) throws {
    try rejectUnsupportedNativeKeys(in: object, supportedKeys: ["surface", "uIndex", "vIndex"], objectName: path)
    try validateObjectField("surface", in: object, path: "\(path).surface", using: validateSurfaceReferenceObject)
}

private func validateSurfaceKnotReferenceObject(_ object: [String: Any], path: String) throws {
    try rejectUnsupportedNativeKeys(in: object, supportedKeys: ["surface", "direction", "knotIndex"], objectName: path)
    try validateObjectField("surface", in: object, path: "\(path).surface", using: validateSurfaceReferenceObject)
}

private func validateSurfaceTrimReferenceObject(_ object: [String: Any], path: String) throws {
    try rejectUnsupportedNativeKeys(in: object, supportedKeys: ["surface", "loopIndex", "edgeIndex"], objectName: path)
    try validateObjectField("surface", in: object, path: "\(path).surface", using: validateSurfaceReferenceObject)
}

private func validateSurfaceTrimSpanReferenceObject(_ object: [String: Any], path: String) throws {
    try rejectUnsupportedNativeKeys(in: object, supportedKeys: ["trim", "spanIndex"], objectName: path)
    try validateObjectField("trim", in: object, path: "\(path).trim", using: validateSurfaceTrimReferenceObject)
}

private func validateSurfaceTrimKnotReferenceObject(_ object: [String: Any], path: String) throws {
    try rejectUnsupportedNativeKeys(in: object, supportedKeys: ["trim", "knotIndex"], objectName: path)
    try validateObjectField("trim", in: object, path: "\(path).trim", using: validateSurfaceTrimReferenceObject)
}

private func validateExtrudeFeatureObject(_ object: [String: Any], path: String) throws {
    try rejectUnsupportedNativeKeys(
        in: object,
        supportedKeys: ["profile", "distance", "direction", "operation"],
        objectName: path
    )
    try validateObjectField("profile", in: object, path: "\(path).profile", using: validateProfileReferenceObject)
    try validateObjectField("distance", in: object, path: "\(path).distance", using: validateExpressionObject)
    try validateObjectField("direction", in: object, path: "\(path).direction", using: validateExtrudeDirectionObject)
}

private func validateRevolveFeatureObject(_ object: [String: Any], path: String) throws {
    try rejectUnsupportedNativeKeys(
        in: object,
        supportedKeys: ["profile", "axis", "angle", "operation"],
        objectName: path
    )
    try validateObjectField("profile", in: object, path: "\(path).profile", using: validateProfileReferenceObject)
    try validateObjectField("axis", in: object, path: "\(path).axis", using: validateRevolveAxisObject)
    try validateObjectField("angle", in: object, path: "\(path).angle", using: validateExpressionObject)
}

private func validateRevolveAxisObject(_ object: [String: Any], path: String) throws {
    try rejectUnsupportedNativeKeys(in: object, supportedKeys: ["origin", "direction"], objectName: path)
    try validateObjectField("origin", in: object, path: "\(path).origin", using: validatePoint3DObject)
    try validateObjectField("direction", in: object, path: "\(path).direction", using: validateVector3DObject)
}

private func validatePolySplineFeatureObject(_ object: [String: Any], path: String) throws {
    try rejectUnsupportedNativeKeys(
        in: object,
        supportedKeys: ["sourceMesh", "options", "controlPointOverrides"],
        objectName: path
    )
    try validateObjectField("sourceMesh", in: object, path: "\(path).sourceMesh", using: validateMeshObject)
    try validateObjectField("options", in: object, path: "\(path).options", using: validatePolySplineOptionsObject)
    try validateArrayField(
        "controlPointOverrides",
        in: object,
        path: "\(path).controlPointOverrides",
        using: validatePolySplineControlPointOverrideObject
    )
}

private func validateMeshObject(_ object: [String: Any], path: String) throws {
    try rejectUnsupportedNativeKeys(
        in: object,
        supportedKeys: ["positions", "normals", "indices", "textureCoordinates", "vertexColors", "material"],
        objectName: path
    )
    try validateArrayField("positions", in: object, path: "\(path).positions", using: validatePoint3DObject)
    try validateArrayField("normals", in: object, path: "\(path).normals", using: validateVector3DObject)
    try validateArrayField("textureCoordinates", in: object, path: "\(path).textureCoordinates", using: validatePoint2DObject)
    try validateArrayField("vertexColors", in: object, path: "\(path).vertexColors", using: validateColorRGBAObject)
}

private func validatePoint2DObject(_ object: [String: Any], path: String) throws {
    try rejectUnsupportedNativeKeys(in: object, supportedKeys: ["x", "y"], objectName: path)
}

private func validateColorRGBAObject(_ object: [String: Any], path: String) throws {
    try rejectUnsupportedNativeKeys(in: object, supportedKeys: ["r", "g", "b", "a"], objectName: path)
}

private func validatePolySplineOptionsObject(_ object: [String: Any], path: String) throws {
    try rejectUnsupportedNativeKeys(
        in: object,
        supportedKeys: ["roundedCorners", "mergePatches", "interpolateBoundaryExactly"],
        objectName: path
    )
}

private func validatePolySplineControlPointOverrideObject(_ object: [String: Any], path: String) throws {
    try rejectUnsupportedNativeKeys(
        in: object,
        supportedKeys: ["patchID", "uIndex", "vIndex", "point", "weight"],
        objectName: path
    )
    try validateObjectField("point", in: object, path: "\(path).point", using: validatePoint3DObject)
}

private func validateBSplineSurfaceFeatureObject(_ object: [String: Any], path: String) throws {
    try rejectUnsupportedNativeKeys(
        in: object,
        supportedKeys: ["surface", "material", "parameterDomain"],
        objectName: path
    )
    try validateObjectField("surface", in: object, path: "\(path).surface", using: validateBSplineSurfaceObject)
    try validateObjectField("parameterDomain", in: object, path: "\(path).parameterDomain", using: validateSurfaceParameterDomain2DObject)
}

private func validatePatchSurfaceFeatureObject(_ object: [String: Any], path: String) throws {
    try rejectUnsupportedNativeKeys(
        in: object,
        supportedKeys: [
            "vMinimumBoundary",
            "vMaximumBoundary",
            "uMinimumBoundary",
            "uMaximumBoundary",
            "vMinimumOrientation",
            "vMaximumOrientation",
            "uMinimumOrientation",
            "uMaximumOrientation",
            "material",
        ],
        objectName: path
    )
    try validateObjectField(
        "vMinimumBoundary",
        in: object,
        path: "\(path).vMinimumBoundary",
        using: validateBSplineCurve3DObject
    )
    try validateObjectField(
        "vMaximumBoundary",
        in: object,
        path: "\(path).vMaximumBoundary",
        using: validateBSplineCurve3DObject
    )
    try validateObjectField(
        "uMinimumBoundary",
        in: object,
        path: "\(path).uMinimumBoundary",
        using: validateBSplineCurve3DObject
    )
    try validateObjectField(
        "uMaximumBoundary",
        in: object,
        path: "\(path).uMaximumBoundary",
        using: validateBSplineCurve3DObject
    )
}

private func validateBSplineSurfaceObject(_ object: [String: Any], path: String) throws {
    try rejectUnsupportedNativeKeys(
        in: object,
        supportedKeys: ["uDegree", "vDegree", "uKnots", "vKnots", "controlPoints", "weights"],
        objectName: path
    )
}

private func validateSurfaceParameterDomain2DObject(_ object: [String: Any], path: String) throws {
    try rejectUnsupportedNativeKeys(
        in: object,
        supportedKeys: ["uLowerBound", "uUpperBound", "vLowerBound", "vUpperBound"],
        objectName: path
    )
}

private func validateSurfaceParameterCurveObject(_ object: [String: Any], path: String) throws {
    guard let kind = object["kind"] as? String else {
        throw SchemaError.invalidPackage(
            "Native \(path).kind must declare a surface-parameter curve representation."
        )
    }
    switch kind {
    case "affine":
        try rejectUnsupportedNativeKeys(
            in: object,
            supportedKeys: ["kind", "origin", "direction", "startParameter", "endParameter"],
            objectName: path
        )
        try validateObjectField("origin", in: object, path: "\(path).origin", using: validatePoint2DObject)
        try validateObjectField("direction", in: object, path: "\(path).direction", using: validatePoint2DObject)
    case "constantU":
        try rejectUnsupportedNativeKeys(
            in: object,
            supportedKeys: ["kind", "u", "vStart", "vEnd"],
            objectName: path
        )
    case "constantV":
        try rejectUnsupportedNativeKeys(
            in: object,
            supportedKeys: ["kind", "v", "uStart", "uEnd"],
            objectName: path
        )
    case "harmonic":
        try rejectUnsupportedNativeKeys(
            in: object,
            supportedKeys: [
                "kind", "center", "cosine", "sine",
                "startParameter", "endParameter",
            ],
            objectName: path
        )
        try validateObjectField("center", in: object, path: "\(path).center", using: validatePoint2DObject)
        try validateObjectField("cosine", in: object, path: "\(path).cosine", using: validatePoint2DObject)
        try validateObjectField("sine", in: object, path: "\(path).sine", using: validatePoint2DObject)
    case "polyline":
        try rejectUnsupportedNativeKeys(
            in: object,
            supportedKeys: ["kind", "points"],
            objectName: path
        )
        try validateArrayField(
            "points",
            in: object,
            path: "\(path).points",
            using: validateSurfaceParameterObject
        )
    case "bSpline":
        try rejectUnsupportedNativeKeys(
            in: object,
            supportedKeys: ["kind", "bSpline"],
            objectName: path
        )
        try validateObjectField(
            "bSpline",
            in: object,
            path: "\(path).bSpline",
            using: validateBSplineCurve2DObject
        )
    case "certifiedImplicit":
        try rejectUnsupportedNativeKeys(
            in: object,
            supportedKeys: ["kind", "certifiedImplicit"],
            objectName: path
        )
        try validateObjectField(
            "certifiedImplicit",
            in: object,
            path: "\(path).certifiedImplicit",
            using: validateCertifiedImplicitSurfaceParameterCurveObject
        )
    case "certifiedAnalyticImplicit":
        try rejectUnsupportedNativeKeys(
            in: object,
            supportedKeys: ["kind", "certifiedAnalyticImplicit"],
            objectName: path
        )
        try validateObjectField(
            "certifiedAnalyticImplicit",
            in: object,
            path: "\(path).certifiedAnalyticImplicit",
            using: validateCertifiedAnalyticImplicitSurfaceParameterCurveObject
        )
    case "certifiedAnalyticPair":
        try rejectUnsupportedNativeKeys(
            in: object,
            supportedKeys: ["kind", "certifiedAnalyticPair"],
            objectName: path
        )
        try validateObjectField(
            "certifiedAnalyticPair",
            in: object,
            path: "\(path).certifiedAnalyticPair",
            using: validateCertifiedAnalyticPairSurfaceParameterCurveObject
        )
    case "sphericalGreatCircle":
        try rejectUnsupportedNativeKeys(
            in: object,
            supportedKeys: [
                "kind", "cosine", "sine", "startParameter", "endParameter",
            ],
            objectName: path
        )
        try validateObjectField("cosine", in: object, path: "\(path).cosine", using: validateVector3DObject)
        try validateObjectField("sine", in: object, path: "\(path).sine", using: validateVector3DObject)
    case "projectedAnalytic":
        try rejectUnsupportedNativeKeys(
            in: object,
            supportedKeys: ["kind", "projectedAnalytic"],
            objectName: path
        )
        try validateObjectField(
            "projectedAnalytic",
            in: object,
            path: "\(path).projectedAnalytic",
            using: validateProjectedAnalyticSurfaceParameterCurveObject
        )
    default:
        throw SchemaError.invalidPackage(
            "Native \(path).kind \(kind) is not a supported surface-parameter curve representation."
        )
    }
}

private func validateBSplineCurve2DObject(_ object: [String: Any], path: String) throws {
    try rejectUnsupportedNativeKeys(
        in: object,
        supportedKeys: ["degree", "knots", "controlPoints", "weights"],
        objectName: path
    )
    try validateArrayField(
        "controlPoints",
        in: object,
        path: "\(path).controlPoints",
        using: validatePoint2DObject
    )
}

private func validateCertifiedImplicitSurfaceParameterCurveObject(
    _ object: [String: Any],
    path: String
) throws {
    try rejectUnsupportedNativeKeys(
        in: object,
        supportedKeys: ["intersection", "role", "startFraction", "endFraction"],
        objectName: path
    )
}

private func validateCertifiedAnalyticImplicitSurfaceParameterCurveObject(
    _ object: [String: Any],
    path: String
) throws {
    try rejectUnsupportedNativeKeys(
        in: object,
        supportedKeys: ["intersection", "startFraction", "endFraction"],
        objectName: path
    )
}

private func validateCertifiedAnalyticPairSurfaceParameterCurveObject(
    _ object: [String: Any],
    path: String
) throws {
    try rejectUnsupportedNativeKeys(
        in: object,
        supportedKeys: ["intersection", "role", "startFraction", "endFraction"],
        objectName: path
    )
}

private func validateProjectedAnalyticSurfaceParameterCurveObject(
    _ object: [String: Any],
    path: String
) throws {
    try rejectUnsupportedNativeKeys(
        in: object,
        supportedKeys: [
            "curve", "surface", "startParameter", "endParameter",
            "certificationTolerance",
        ],
        objectName: path
    )
    try validateObjectField(
        "certificationTolerance",
        in: object,
        path: "\(path).certificationTolerance",
        using: validateModelingToleranceObject
    )
}

private func validateModelingToleranceObject(_ object: [String: Any], path: String) throws {
    try rejectUnsupportedNativeKeys(
        in: object,
        supportedKeys: ["distance", "angle", "relative"],
        objectName: path
    )
}

private func validateSweepFeatureObject(_ object: [String: Any], path: String) throws {
    try rejectUnsupportedNativeKeys(
        in: object,
        supportedKeys: ["sections", "path", "guides", "targets", "options"],
        objectName: path
    )
    try validateArrayField("sections", in: object, path: "\(path).sections", using: validateSweepSectionReferenceObject)
    try validateObjectField("path", in: object, path: "\(path).path", using: validateSweepPathReferenceObject)
    try validateArrayField("guides", in: object, path: "\(path).guides", using: validateSweepGuideReferenceObject)
    try validateArrayField("targets", in: object, path: "\(path).targets", using: validateSweepTargetReferenceObject)
    try validateObjectField("options", in: object, path: "\(path).options", using: validateSweepOptionsObject)
}

private func validateSweepSectionReferenceObject(_ object: [String: Any], path: String) throws {
    try rejectUnsupportedNativeKeys(
        in: object,
        supportedKeys: ["kind", "featureID", "profileIndex"],
        objectName: path
    )
    guard let kind = object["kind"] as? String else {
        throw SchemaError.invalidPackage("Native \(path).kind must declare profile or curve.")
    }
    guard let featureID = object["featureID"] as? String,
          UUID(uuidString: featureID) != nil else {
        throw SchemaError.invalidPackage("Native \(path).featureID must be a UUID string.")
    }
    switch kind {
    case "profile":
        guard let index = object["profileIndex"] as? Int,
              index >= 0 else {
            throw SchemaError.invalidPackage("Native \(path).profileIndex must be a non-negative integer.")
        }
    case "curve":
        guard object["profileIndex"] == nil else {
            throw SchemaError.invalidPackage("Native \(path).profileIndex is only valid for profile sections.")
        }
    default:
        throw SchemaError.invalidPackage("Native \(path).kind must be profile or curve.")
    }
}

private func validateProfileReferenceObject(_ object: [String: Any], path: String) throws {
    try rejectUnsupportedNativeKeys(in: object, supportedKeys: ["featureID", "profileIndex"], objectName: path)
}

private func validateSweepPathReferenceObject(_ object: [String: Any], path: String) throws {
    try rejectUnsupportedNativeKeys(in: object, supportedKeys: ["featureID"], objectName: path)
}

private func validateSweepGuideReferenceObject(_ object: [String: Any], path: String) throws {
    try rejectUnsupportedNativeKeys(in: object, supportedKeys: ["featureID"], objectName: path)
}

private func validateSweepTargetReferenceObject(_ object: [String: Any], path: String) throws {
    try rejectUnsupportedNativeKeys(in: object, supportedKeys: ["featureID"], objectName: path)
}

private func validateBooleanFeatureObject(_ object: [String: Any], path: String) throws {
    try rejectUnsupportedNativeKeys(
        in: object,
        supportedKeys: ["targets", "tool", "operation", "keepTools"],
        objectName: path
    )
    try validateArrayField("targets", in: object, path: "\(path).targets", using: validateBooleanTargetReferenceObject)
    try validateObjectField("tool", in: object, path: "\(path).tool", using: validateBooleanToolReferenceObject)
}

private func validateBooleanTargetReferenceObject(_ object: [String: Any], path: String) throws {
    try rejectUnsupportedNativeKeys(in: object, supportedKeys: ["featureID"], objectName: path)
}

private func validateBooleanToolReferenceObject(_ object: [String: Any], path: String) throws {
    try rejectUnsupportedNativeKeys(in: object, supportedKeys: ["featureID"], objectName: path)
}

private func validateFaceLoopOffsetFeatureObject(_ object: [String: Any], path: String) throws {
    try rejectUnsupportedNativeKeys(
        in: object,
        supportedKeys: ["target", "face", "distance"],
        objectName: path
    )
    try validateObjectField("target", in: object, path: "\(path).target", using: validateFaceLoopOffsetTargetReferenceObject)
    try validateObjectField(
        "face",
        in: object,
        path: "\(path).face",
        using: validateStableSubshapeReferenceObject
    )
    try validateObjectField("distance", in: object, path: "\(path).distance", using: validateExpressionObject)
}

private func validateFaceLoopOffsetTargetReferenceObject(_ object: [String: Any], path: String) throws {
    try rejectUnsupportedNativeKeys(in: object, supportedKeys: ["featureID"], objectName: path)
}

private func validateFaceKnifeFeatureObject(_ object: [String: Any], path: String) throws {
    try rejectUnsupportedNativeKeys(
        in: object,
        supportedKeys: ["target", "face", "loop"],
        objectName: path
    )
    try validateObjectField("target", in: object, path: "\(path).target", using: validateFaceKnifeTargetReferenceObject)
    try validateObjectField(
        "face",
        in: object,
        path: "\(path).face",
        using: validateStableSubshapeReferenceObject
    )
    try validateArrayField("loop", in: object, path: "\(path).loop", using: validatePoint3DObject)
}

private func validateFaceKnifeTargetReferenceObject(_ object: [String: Any], path: String) throws {
    try rejectUnsupportedNativeKeys(in: object, supportedKeys: ["featureID"], objectName: path)
}

private func validateFaceDeleteFeatureObject(_ object: [String: Any], path: String) throws {
    try rejectUnsupportedNativeKeys(
        in: object,
        supportedKeys: ["target", "faces"],
        objectName: path
    )
    try validateObjectField("target", in: object, path: "\(path).target", using: validateFaceDeleteTargetReferenceObject)
    try validateArrayField(
        "faces",
        in: object,
        path: "\(path).faces",
        using: validateStableSubshapeReferenceObject
    )
}

private func validateFaceDeleteTargetReferenceObject(_ object: [String: Any], path: String) throws {
    try rejectUnsupportedNativeKeys(in: object, supportedKeys: ["featureID"], objectName: path)
}

private func validateFaceDraftFeatureObject(_ object: [String: Any], path: String) throws {
    try rejectUnsupportedNativeKeys(
        in: object,
        supportedKeys: ["target", "faces", "neutralFace", "angle"],
        objectName: path
    )
    try validateObjectField("target", in: object, path: "\(path).target", using: validateFaceDraftTargetReferenceObject)
    try validateArrayField(
        "faces",
        in: object,
        path: "\(path).faces",
        using: validateStableSubshapeReferenceObject
    )
    try validateObjectField(
        "neutralFace",
        in: object,
        path: "\(path).neutralFace",
        using: validateStableSubshapeReferenceObject
    )
    try validateObjectField("angle", in: object, path: "\(path).angle", using: validateExpressionObject)
}

private func validateFaceDraftTargetReferenceObject(_ object: [String: Any], path: String) throws {
    try rejectUnsupportedNativeKeys(in: object, supportedKeys: ["featureID"], objectName: path)
}

private func validateFaceMoveFeatureObject(_ object: [String: Any], path: String) throws {
    try rejectUnsupportedNativeKeys(
        in: object,
        supportedKeys: ["target", "face", "translation"],
        objectName: path
    )
    try validateObjectField("target", in: object, path: "\(path).target", using: validateFaceMoveTargetReferenceObject)
    try validateObjectField("face", in: object, path: "\(path).face", using: validateStableSubshapeReferenceObject)
    try validateObjectField("translation", in: object, path: "\(path).translation", using: validateDirectMoveVectorObject)
}

private func validateFaceMoveTargetReferenceObject(_ object: [String: Any], path: String) throws {
    try rejectUnsupportedNativeKeys(in: object, supportedKeys: ["featureID"], objectName: path)
}

private func validateFaceOffsetFeatureObject(_ object: [String: Any], path: String) throws {
    try rejectUnsupportedNativeKeys(
        in: object,
        supportedKeys: ["target", "face", "distance"],
        objectName: path
    )
    try validateObjectField("target", in: object, path: "\(path).target", using: validateFaceOffsetTargetReferenceObject)
    try validateObjectField("face", in: object, path: "\(path).face", using: validateStableSubshapeReferenceObject)
    try validateObjectField("distance", in: object, path: "\(path).distance", using: validateExpressionObject)
}

private func validateFaceOffsetTargetReferenceObject(_ object: [String: Any], path: String) throws {
    try rejectUnsupportedNativeKeys(in: object, supportedKeys: ["featureID"], objectName: path)
}

private func validateEdgeMoveFeatureObject(_ object: [String: Any], path: String) throws {
    try rejectUnsupportedNativeKeys(
        in: object,
        supportedKeys: ["target", "edge", "translation"],
        objectName: path
    )
    try validateObjectField("target", in: object, path: "\(path).target", using: validateEdgeMoveTargetReferenceObject)
    try validateObjectField("edge", in: object, path: "\(path).edge", using: validateStableSubshapeReferenceObject)
    try validateObjectField("translation", in: object, path: "\(path).translation", using: validateDirectMoveVectorObject)
}

private func validateEdgeMoveTargetReferenceObject(_ object: [String: Any], path: String) throws {
    try rejectUnsupportedNativeKeys(in: object, supportedKeys: ["featureID"], objectName: path)
}

private func validateVertexMoveFeatureObject(_ object: [String: Any], path: String) throws {
    try rejectUnsupportedNativeKeys(
        in: object,
        supportedKeys: ["target", "vertex", "translation"],
        objectName: path
    )
    try validateObjectField("target", in: object, path: "\(path).target", using: validateVertexMoveTargetReferenceObject)
    try validateObjectField("vertex", in: object, path: "\(path).vertex", using: validateStableSubshapeReferenceObject)
    try validateObjectField("translation", in: object, path: "\(path).translation", using: validateDirectMoveVectorObject)
}

private func validateVertexMoveTargetReferenceObject(_ object: [String: Any], path: String) throws {
    try rejectUnsupportedNativeKeys(in: object, supportedKeys: ["featureID"], objectName: path)
}

private func validateLinearPatternFeatureObject(_ object: [String: Any], path: String) throws {
    try rejectUnsupportedNativeKeys(
        in: object,
        supportedKeys: ["target", "direction", "spacing", "count"],
        objectName: path
    )
    try validateObjectField("target", in: object, path: "\(path).target", using: validatePatternTargetReferenceObject)
    try validateObjectField("direction", in: object, path: "\(path).direction", using: validateVector3DObject)
    try validateObjectField("spacing", in: object, path: "\(path).spacing", using: validateExpressionObject)
}

private func validatePatternTargetReferenceObject(_ object: [String: Any], path: String) throws {
    try rejectUnsupportedNativeKeys(in: object, supportedKeys: ["featureID"], objectName: path)
}

private func validateRadialPatternFeatureObject(_ object: [String: Any], path: String) throws {
    try rejectUnsupportedNativeKeys(
        in: object,
        supportedKeys: ["target", "axisOrigin", "axisDirection", "angularSpacing", "count"],
        objectName: path
    )
    try validateObjectField("target", in: object, path: "\(path).target", using: validatePatternTargetReferenceObject)
    try validateObjectField("axisOrigin", in: object, path: "\(path).axisOrigin", using: validatePoint3DObject)
    try validateObjectField("axisDirection", in: object, path: "\(path).axisDirection", using: validateVector3DObject)
    try validateObjectField("angularSpacing", in: object, path: "\(path).angularSpacing", using: validateExpressionObject)
}

private func validateGridPatternFeatureObject(_ object: [String: Any], path: String) throws {
    try rejectUnsupportedNativeKeys(
        in: object,
        supportedKeys: [
            "target",
            "firstDirection",
            "firstSpacing",
            "firstCount",
            "secondDirection",
            "secondSpacing",
            "secondCount",
        ],
        objectName: path
    )
    try validateObjectField("target", in: object, path: "\(path).target", using: validatePatternTargetReferenceObject)
    try validateObjectField("firstDirection", in: object, path: "\(path).firstDirection", using: validateVector3DObject)
    try validateObjectField("firstSpacing", in: object, path: "\(path).firstSpacing", using: validateExpressionObject)
    try validateObjectField("secondDirection", in: object, path: "\(path).secondDirection", using: validateVector3DObject)
    try validateObjectField("secondSpacing", in: object, path: "\(path).secondSpacing", using: validateExpressionObject)
}

private func validateCurveDrivenPatternFeatureObject(_ object: [String: Any], path: String) throws {
    try rejectUnsupportedNativeKeys(
        in: object,
        supportedKeys: ["target", "path", "anchor", "referenceDirection", "count"],
        objectName: path
    )
    try validateObjectField("target", in: object, path: "\(path).target", using: validatePatternTargetReferenceObject)
    try validateObjectField("path", in: object, path: "\(path).path", using: validateCurveDrivenPatternPathReferenceObject)
    try validateObjectField("anchor", in: object, path: "\(path).anchor", using: validatePoint3DObject)
    try validateObjectField("referenceDirection", in: object, path: "\(path).referenceDirection", using: validateVector3DObject)
}

private func validateCurveDrivenPatternPathReferenceObject(_ object: [String: Any], path: String) throws {
    try rejectUnsupportedNativeKeys(in: object, supportedKeys: ["featureID"], objectName: path)
}

private func validateMirrorFeatureObject(_ object: [String: Any], path: String) throws {
    try rejectUnsupportedNativeKeys(
        in: object,
        supportedKeys: ["target", "planeOrigin", "planeNormal"],
        objectName: path
    )
    try validateObjectField("target", in: object, path: "\(path).target", using: validatePatternTargetReferenceObject)
    try validateObjectField("planeOrigin", in: object, path: "\(path).planeOrigin", using: validatePoint3DObject)
    try validateObjectField("planeNormal", in: object, path: "\(path).planeNormal", using: validateVector3DObject)
}

private func validateJoinBodiesFeatureObject(_ object: [String: Any], path: String) throws {
    try rejectUnsupportedNativeKeys(in: object, supportedKeys: ["targets"], objectName: path)
    try validateArrayField("targets", in: object, path: "\(path).targets", using: validatePatternTargetReferenceObject)
}

private func validateUnjoinBodyFeatureObject(_ object: [String: Any], path: String) throws {
    try rejectUnsupportedNativeKeys(in: object, supportedKeys: ["target"], objectName: path)
    try validateObjectField("target", in: object, path: "\(path).target", using: validatePatternTargetReferenceObject)
}

private func validateDirectMoveVectorObject(_ object: [String: Any], path: String) throws {
    try rejectUnsupportedNativeKeys(
        in: object,
        supportedKeys: ["direction", "distance"],
        objectName: path
    )
    try validateObjectField("direction", in: object, path: "\(path).direction", using: validateVector3DObject)
    try validateObjectField("distance", in: object, path: "\(path).distance", using: validateExpressionObject)
}

private func validateChamferFeatureObject(_ object: [String: Any], path: String) throws {
    try rejectUnsupportedNativeKeys(
        in: object,
        supportedKeys: ["target", "edges", "distance"],
        objectName: path
    )
    try validateObjectField("target", in: object, path: "\(path).target", using: validateChamferTargetReferenceObject)
    try validateArrayField(
        "edges",
        in: object,
        path: "\(path).edges",
        using: validateStableSubshapeReferenceObject
    )
    try validateObjectField("distance", in: object, path: "\(path).distance", using: validateExpressionObject)
}

private func validateChamferTargetReferenceObject(_ object: [String: Any], path: String) throws {
    try rejectUnsupportedNativeKeys(in: object, supportedKeys: ["featureID"], objectName: path)
}

private func validateFilletFeatureObject(_ object: [String: Any], path: String) throws {
    try rejectUnsupportedNativeKeys(
        in: object,
        supportedKeys: ["target", "edges", "radius"],
        objectName: path
    )
    try validateObjectField("target", in: object, path: "\(path).target", using: validateFilletTargetReferenceObject)
    try validateArrayField(
        "edges",
        in: object,
        path: "\(path).edges",
        using: validateStableSubshapeReferenceObject
    )
    try validateObjectField("radius", in: object, path: "\(path).radius", using: validateExpressionObject)
}

private func validateFilletTargetReferenceObject(_ object: [String: Any], path: String) throws {
    try rejectUnsupportedNativeKeys(in: object, supportedKeys: ["featureID"], objectName: path)
}

private func validateG2BlendFeatureObject(_ object: [String: Any], path: String) throws {
    try rejectUnsupportedNativeKeys(
        in: object,
        supportedKeys: ["target", "edges", "distance"],
        objectName: path
    )
    try validateObjectField("target", in: object, path: "\(path).target", using: validateG2BlendTargetReferenceObject)
    try validateArrayField(
        "edges",
        in: object,
        path: "\(path).edges",
        using: validateStableSubshapeReferenceObject
    )
    try validateObjectField("distance", in: object, path: "\(path).distance", using: validateExpressionObject)
}

private func validateG2BlendTargetReferenceObject(_ object: [String: Any], path: String) throws {
    try rejectUnsupportedNativeKeys(in: object, supportedKeys: ["featureID"], objectName: path)
}

private func validateSetbackCornerFeatureObject(_ object: [String: Any], path: String) throws {
    try rejectUnsupportedNativeKeys(
        in: object,
        supportedKeys: ["target", "vertex", "radius"],
        objectName: path
    )
    try validateObjectField("target", in: object, path: "\(path).target", using: validateSetbackCornerTargetReferenceObject)
    try validateObjectField("vertex", in: object, path: "\(path).vertex", using: validateStableSubshapeReferenceObject)
    try validateObjectField("radius", in: object, path: "\(path).radius", using: validateExpressionObject)
}

private func validateSetbackCornerTargetReferenceObject(_ object: [String: Any], path: String) throws {
    try rejectUnsupportedNativeKeys(in: object, supportedKeys: ["featureID"], objectName: path)
}

private func validateShellFeatureObject(_ object: [String: Any], path: String) throws {
    try rejectUnsupportedNativeKeys(
        in: object,
        supportedKeys: ["target", "removedFaces", "thickness"],
        objectName: path
    )
    try validateObjectField("target", in: object, path: "\(path).target", using: validateShellTargetReferenceObject)
    try validateArrayField(
        "removedFaces",
        in: object,
        path: "\(path).removedFaces",
        using: validateStableSubshapeReferenceObject
    )
    try validateObjectField("thickness", in: object, path: "\(path).thickness", using: validateExpressionObject)
}

private func validateShellTargetReferenceObject(_ object: [String: Any], path: String) throws {
    try rejectUnsupportedNativeKeys(in: object, supportedKeys: ["featureID"], objectName: path)
}

private func validateThickenFeatureObject(_ object: [String: Any], path: String) throws {
    try rejectUnsupportedNativeKeys(
        in: object,
        supportedKeys: ["target", "thickness", "side"],
        objectName: path
    )
    try validateObjectField("target", in: object, path: "\(path).target", using: validateThickenTargetReferenceObject)
    try validateObjectField("thickness", in: object, path: "\(path).thickness", using: validateExpressionObject)
}

private func validateThickenTargetReferenceObject(_ object: [String: Any], path: String) throws {
    try rejectUnsupportedNativeKeys(in: object, supportedKeys: ["featureID"], objectName: path)
}

private func validateEdgeOffsetFeatureObject(_ object: [String: Any], path: String) throws {
    try rejectUnsupportedNativeKeys(
        in: object,
        supportedKeys: [
            "target",
            "edge",
            "supportFace",
            "distance",
            "isSymmetric",
        ],
        objectName: path
    )
    try validateObjectField("target", in: object, path: "\(path).target", using: validateEdgeOffsetTargetReferenceObject)
    try validateObjectField(
        "edge",
        in: object,
        path: "\(path).edge",
        using: validateStableSubshapeReferenceObject
    )
    try validateObjectField(
        "supportFace",
        in: object,
        path: "\(path).supportFace",
        using: validateStableSubshapeReferenceObject
    )
    try validateObjectField("distance", in: object, path: "\(path).distance", using: validateExpressionObject)
}

private func validateEdgeOffsetTargetReferenceObject(_ object: [String: Any], path: String) throws {
    try rejectUnsupportedNativeKeys(in: object, supportedKeys: ["featureID"], objectName: path)
}

private func validateBridgeCurveFeatureObject(_ object: [String: Any], path: String) throws {
    try rejectUnsupportedNativeKeys(
        in: object,
        supportedKeys: ["start", "end", "continuityTolerances"],
        objectName: path
    )
    try validateObjectField("start", in: object, path: "\(path).start", using: validateBridgeCurveEndpointObject)
    try validateObjectField("end", in: object, path: "\(path).end", using: validateBridgeCurveEndpointObject)
    try validateObjectField(
        "continuityTolerances",
        in: object,
        path: "\(path).continuityTolerances",
        using: validateCurveContinuityTolerancesObject
    )
}

private func validateBridgeCurveEndpointObject(_ object: [String: Any], path: String) throws {
    try rejectUnsupportedNativeKeys(
        in: object,
        supportedKeys: ["curve", "end", "orientation", "requiredLevel", "derivativeMagnitude"],
        objectName: path
    )
    try validateObjectField(
        "curve",
        in: object,
        path: "\(path).curve",
        using: validateCurveOutputReferenceObject
    )
}

private func validateBridgeSurfaceFeatureObject(_ object: [String: Any], path: String) throws {
    try rejectUnsupportedNativeKeys(
        in: object,
        supportedKeys: ["startBoundary", "endBoundary", "endOrientation", "material"],
        objectName: path
    )
    try validateObjectField(
        "startBoundary",
        in: object,
        path: "\(path).startBoundary",
        using: validateBSplineCurve3DObject
    )
    try validateObjectField(
        "endBoundary",
        in: object,
        path: "\(path).endBoundary",
        using: validateBSplineCurve3DObject
    )
}

private func validateCurveEditFeatureObject(_ object: [String: Any], path: String) throws {
    try rejectUnsupportedNativeKeys(
        in: object,
        supportedKeys: ["source", "edits"],
        objectName: path
    )
    try validateObjectField("source", in: object, path: "\(path).source", using: validateCurveOutputReferenceObject)
    try validateArrayField("edits", in: object, path: "\(path).edits", using: validateCurveEditObject)
}

private func validateCurveOffsetFeatureObject(_ object: [String: Any], path: String) throws {
    try rejectUnsupportedNativeKeys(
        in: object,
        supportedKeys: ["source", "distance", "planeNormal", "side"],
        objectName: path
    )
    try validateObjectField("source", in: object, path: "\(path).source", using: validateCurveOutputReferenceObject)
    try validateObjectField("distance", in: object, path: "\(path).distance", using: validateExpressionObject)
    try validateObjectField("planeNormal", in: object, path: "\(path).planeNormal", using: validateVector3DObject)
}

private func validateProjectCurveFeatureObject(_ object: [String: Any], path: String) throws {
    try rejectUnsupportedNativeKeys(
        in: object,
        supportedKeys: ["source", "planeOrigin", "planeNormal", "direction"],
        objectName: path
    )
    try validateObjectField("source", in: object, path: "\(path).source", using: validateCurveOutputReferenceObject)
    try validateObjectField("planeOrigin", in: object, path: "\(path).planeOrigin", using: validatePoint3DObject)
    try validateObjectField("planeNormal", in: object, path: "\(path).planeNormal", using: validateVector3DObject)
    try validateObjectField("direction", in: object, path: "\(path).direction", using: validateVector3DObject)
}

private func validateCurveTrimFeatureObject(_ object: [String: Any], path: String) throws {
    try rejectUnsupportedNativeKeys(
        in: object,
        supportedKeys: ["source", "domain"],
        objectName: path
    )
    try validateObjectField("source", in: object, path: "\(path).source", using: validateCurveOutputReferenceObject)
    try validateObjectField("domain", in: object, path: "\(path).domain", using: validateParameterDomainObject)
}

private func validateCurveExtendFeatureObject(_ object: [String: Any], path: String) throws {
    try rejectUnsupportedNativeKeys(
        in: object,
        supportedKeys: ["source", "end", "distance"],
        objectName: path
    )
    try validateObjectField("source", in: object, path: "\(path).source", using: validateCurveOutputReferenceObject)
    try validateObjectField("distance", in: object, path: "\(path).distance", using: validateExpressionObject)
}

private func validateCurveMatchFeatureObject(_ object: [String: Any], path: String) throws {
    try rejectUnsupportedNativeKeys(
        in: object,
        supportedKeys: ["source", "sourceEnd", "target", "targetEnd", "targetOrientation", "continuity"],
        objectName: path
    )
    try validateObjectField("source", in: object, path: "\(path).source", using: validateCurveOutputReferenceObject)
    try validateObjectField("target", in: object, path: "\(path).target", using: validateCurveOutputReferenceObject)
}

private func validateSurfaceOffsetFeatureObject(_ object: [String: Any], path: String) throws {
    try rejectUnsupportedNativeKeys(
        in: object,
        supportedKeys: ["target", "distance"],
        objectName: path
    )
    try validateObjectField("target", in: object, path: "\(path).target", using: validateSurfaceOperationTargetReferenceObject)
    try validateObjectField("distance", in: object, path: "\(path).distance", using: validateExpressionObject)
}

private func validateSurfaceTrimFeatureObject(_ object: [String: Any], path: String) throws {
    try rejectUnsupportedNativeKeys(
        in: object,
        supportedKeys: ["target", "loops"],
        objectName: path
    )
    try validateObjectField("target", in: object, path: "\(path).target", using: validateSurfaceOperationTargetReferenceObject)
    try validateArrayField(
        "loops",
        in: object,
        path: "\(path).loops",
        using: validateSurfaceTrimLoopObject
    )
}

private func validateSurfaceTrimLoopObject(_ object: [String: Any], path: String) throws {
    try rejectUnsupportedNativeKeys(
        in: object,
        supportedKeys: ["role", "parameterCurves"],
        objectName: path
    )
    try validateArrayField(
        "parameterCurves",
        in: object,
        path: "\(path).parameterCurves",
        using: validateSurfaceParameterCurveObject
    )
}

private func validateSurfaceExtendFeatureObject(_ object: [String: Any], path: String) throws {
    try rejectUnsupportedNativeKeys(
        in: object,
        supportedKeys: ["target", "uDomain", "vDomain"],
        objectName: path
    )
    try validateObjectField("target", in: object, path: "\(path).target", using: validateSurfaceOperationTargetReferenceObject)
    try validateObjectField("uDomain", in: object, path: "\(path).uDomain", using: validateParameterDomainObject)
    try validateObjectField("vDomain", in: object, path: "\(path).vDomain", using: validateParameterDomainObject)
}

private func validateSurfaceMatchFeatureObject(_ object: [String: Any], path: String) throws {
    try rejectUnsupportedNativeKeys(
        in: object,
        supportedKeys: ["source", "target", "sourceParameter", "targetParameter", "normalAlignment", "continuity"],
        objectName: path
    )
    try validateObjectField("source", in: object, path: "\(path).source", using: validateSurfaceOperationTargetReferenceObject)
    try validateObjectField("target", in: object, path: "\(path).target", using: validateSurfaceOperationTargetReferenceObject)
    try validateObjectField("sourceParameter", in: object, path: "\(path).sourceParameter", using: validateSurfaceParameterObject)
    try validateObjectField("targetParameter", in: object, path: "\(path).targetParameter", using: validateSurfaceParameterObject)
}

private func validateSurfaceParameterObject(_ object: [String: Any], path: String) throws {
    try rejectUnsupportedNativeKeys(in: object, supportedKeys: ["u", "v"], objectName: path)
}

private func validateSurfaceOperationTargetReferenceObject(_ object: [String: Any], path: String) throws {
    try rejectUnsupportedNativeKeys(
        in: object,
        supportedKeys: ["featureID", "face"],
        objectName: path
    )
    try validateObjectField(
        "face",
        in: object,
        path: "\(path).face",
        using: validateStableSubshapeReferenceObject
    )
}

private func validateCurveEditObject(_ object: [String: Any], path: String) throws {
    try rejectUnsupportedNativeKeys(
        in: object,
        supportedKeys: ["kind", "controlPoint", "knot", "weight"],
        objectName: path
    )
    try validateObjectField(
        "controlPoint",
        in: object,
        path: "\(path).controlPoint",
        using: validateCurveControlPointEditObject
    )
    try validateObjectField("knot", in: object, path: "\(path).knot", using: validateCurveKnotEditObject)
    try validateObjectField("weight", in: object, path: "\(path).weight", using: validateCurveWeightEditObject)
}

private func validateCurveControlPointEditObject(_ object: [String: Any], path: String) throws {
    try rejectUnsupportedNativeKeys(in: object, supportedKeys: ["target", "point"], objectName: path)
    try validateObjectField("target", in: object, path: "\(path).target", using: validateCurveControlPointReferenceObject)
    try validateObjectField("point", in: object, path: "\(path).point", using: validatePoint3DObject)
}

private func validateCurveKnotEditObject(_ object: [String: Any], path: String) throws {
    try rejectUnsupportedNativeKeys(in: object, supportedKeys: ["target", "value"], objectName: path)
    try validateObjectField("target", in: object, path: "\(path).target", using: validateCurveKnotReferenceObject)
}

private func validateCurveWeightEditObject(_ object: [String: Any], path: String) throws {
    try rejectUnsupportedNativeKeys(in: object, supportedKeys: ["target", "value"], objectName: path)
    try validateObjectField("target", in: object, path: "\(path).target", using: validateCurveControlPointReferenceObject)
}

private func validateParameterDomainObject(_ object: [String: Any], path: String) throws {
    try rejectUnsupportedNativeKeys(
        in: object,
        supportedKeys: ["kind", "lowerBound", "upperBound", "period"],
        objectName: path
    )
}

private func validateCurve3DObject(_ object: [String: Any], path: String) throws {
    try rejectUnsupportedNativeKeys(
        in: object,
        supportedKeys: ["kind", "line", "circle", "bSpline"],
        objectName: path
    )
    try validateObjectField("line", in: object, path: "\(path).line", using: validateLine3DObject)
    try validateObjectField("circle", in: object, path: "\(path).circle", using: validateCircle3DObject)
    try validateObjectField("bSpline", in: object, path: "\(path).bSpline", using: validateBSplineCurve3DObject)
}

private func validateLine3DObject(_ object: [String: Any], path: String) throws {
    try rejectUnsupportedNativeKeys(in: object, supportedKeys: ["origin", "direction"], objectName: path)
    try validateObjectField("origin", in: object, path: "\(path).origin", using: validatePoint3DObject)
    try validateObjectField("direction", in: object, path: "\(path).direction", using: validateVector3DObject)
}

private func validateCircle3DObject(_ object: [String: Any], path: String) throws {
    try rejectUnsupportedNativeKeys(in: object, supportedKeys: ["center", "normal", "radius"], objectName: path)
    try validateObjectField("center", in: object, path: "\(path).center", using: validatePoint3DObject)
    try validateObjectField("normal", in: object, path: "\(path).normal", using: validateVector3DObject)
}

private func validateBSplineCurve3DObject(_ object: [String: Any], path: String) throws {
    try rejectUnsupportedNativeKeys(
        in: object,
        supportedKeys: ["degree", "knots", "controlPoints", "weights"],
        objectName: path
    )
    try validateArrayField("controlPoints", in: object, path: "\(path).controlPoints", using: validatePoint3DObject)
}

private func validateCurveContinuityTolerancesObject(_ object: [String: Any], path: String) throws {
    try rejectUnsupportedNativeKeys(
        in: object,
        supportedKeys: ["positionDistance", "tangentAngle", "curvatureVector"],
        objectName: path
    )
}

private func validateSweepOptionsObject(_ object: [String: Any], path: String) throws {
    try rejectUnsupportedNativeKeys(
        in: object,
        supportedKeys: [
            "twistAngle",
            "endScale",
            "alignment",
            "distanceFraction",
            "cornerStyle",
            "guideMethod",
            "booleanOperation",
            "keepTools",
            "simplify",
            "resultKind",
        ],
        objectName: path
    )
    try validateObjectField("twistAngle", in: object, path: "\(path).twistAngle", using: validateExpressionObject)
    try validateObjectField("endScale", in: object, path: "\(path).endScale", using: validateExpressionObject)
    try validateObjectField("distanceFraction", in: object, path: "\(path).distanceFraction", using: validateExpressionObject)
}

private func validateLoftFeatureObject(_ object: [String: Any], path: String) throws {
    try rejectUnsupportedNativeKeys(
        in: object,
        supportedKeys: ["sections", "guides", "options"],
        objectName: path
    )
    try validateArrayField("sections", in: object, path: "\(path).sections", using: validateLoftSectionReferenceObject)
    if object["guides"] != nil {
        try validateArrayField("guides", in: object, path: "\(path).guides", using: validateLoftGuideReferenceObject)
    }
    try validateObjectField("options", in: object, path: "\(path).options", using: validateLoftOptionsObject)
}

private func validateLoftGuideReferenceObject(_ object: [String: Any], path: String) throws {
    try rejectUnsupportedNativeKeys(
        in: object,
        supportedKeys: ["featureID"],
        objectName: path
    )
}

private func validateLoftSectionReferenceObject(_ object: [String: Any], path: String) throws {
    try rejectUnsupportedNativeKeys(
        in: object,
        supportedKeys: ["profile", "startSampleIndex", "smoothTangentScale", "smoothTangentMode"],
        objectName: path
    )
    try validateObjectField("profile", in: object, path: "\(path).profile", using: validateProfileReferenceObject)
    if let value = object["startSampleIndex"] {
        guard let index = value as? Int,
              index >= 0 else {
            throw SchemaError.invalidPackage("Native \(path).startSampleIndex must be a non-negative integer.")
        }
    }
    if let value = object["smoothTangentScale"] {
        guard isFinitePositiveJSONNumber(value) else {
            throw SchemaError.invalidPackage("Native \(path).smoothTangentScale must be a finite positive number.")
        }
    }
    try validateLoftOptionString(
        "smoothTangentMode",
        in: object,
        path: "\(path).smoothTangentMode",
        supportedValues: ["automatic", "zero"]
    )
}

private func validateLoftOptionsObject(_ object: [String: Any], path: String) throws {
    try rejectUnsupportedNativeKeys(
        in: object,
        supportedKeys: ["resultKind", "sectionMatching", "closesSectionLoop", "surfaceMode", "smoothTangentScale"],
        objectName: path
    )
    try validateLoftOptionString(
        "resultKind",
        in: object,
        path: "\(path).resultKind",
        supportedValues: ["sheet", "solid"]
    )
    try validateLoftOptionString(
        "sectionMatching",
        in: object,
        path: "\(path).sectionMatching",
        supportedValues: ["byBoundaryProgress"]
    )
    if let value = object["closesSectionLoop"],
       (value as? Bool) == nil {
        throw SchemaError.invalidPackage("Native \(path).closesSectionLoop must be a boolean.")
    }
    if object["surfaceMode"] != nil {
        try validateLoftOptionString(
            "surfaceMode",
            in: object,
            path: "\(path).surfaceMode",
            supportedValues: ["ruled", "smooth"]
        )
    }
    if let value = object["smoothTangentScale"] {
        guard isFinitePositiveJSONNumber(value) else {
            throw SchemaError.invalidPackage("Native \(path).smoothTangentScale must be a finite positive number.")
        }
    }
}

private func isFinitePositiveJSONNumber(_ value: Any) -> Bool {
    guard let number = value as? NSNumber else {
        return false
    }
    let typeEncoding = String(cString: number.objCType)
    guard typeEncoding != "c", typeEncoding != "B" else {
        return false
    }
    return number.doubleValue.isFinite && number.doubleValue > 0.0
}

private func validateLoftOptionString(
    _ key: String,
    in object: [String: Any],
    path: String,
    supportedValues: Set<String>
) throws {
    guard let value = object[key],
          !(value is NSNull) else {
        return
    }
    guard let string = value as? String,
          supportedValues.contains(string) else {
        throw SchemaError.invalidPackage(
            "Native \(path) must be one of \(supportedValues.sorted().joined(separator: ", "))."
        )
    }
}

private func validateExtrudeDirectionObject(_ object: [String: Any], path: String) throws {
    try rejectUnsupportedNativeKeys(in: object, supportedKeys: ["kind", "vector"], objectName: path)
    try validateObjectField("vector", in: object, path: "\(path).vector", using: validateVector3DObject)
}

private func validatePlane3DObject(_ object: [String: Any], path: String) throws {
    try rejectUnsupportedNativeKeys(in: object, supportedKeys: ["origin", "normal"], objectName: path)
    try validateObjectField("origin", in: object, path: "\(path).origin", using: validatePoint3DObject)
    try validateObjectField("normal", in: object, path: "\(path).normal", using: validateVector3DObject)
}

private func validatePoint3DObject(_ object: [String: Any], path: String) throws {
    try rejectUnsupportedNativeKeys(in: object, supportedKeys: ["x", "y", "z"], objectName: path)
}

private func validateVector3DObject(_ object: [String: Any], path: String) throws {
    try rejectUnsupportedNativeKeys(in: object, supportedKeys: ["x", "y", "z"], objectName: path)
}

private func nativeJSONObject(from data: Data, name: String) throws -> [String: Any] {
    do {
        try rejectDuplicateJSONKeys(in: data, name: name)
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw SchemaError.invalidPackage("\(name) JSON must be an object.")
        }
        return object
    } catch let error as SchemaError {
        throw error
    } catch {
        throw SchemaError.invalidPackage("\(name) JSON is invalid: \(error).")
    }
}

private func rejectUnsupportedNativeKeys(
    in object: [String: Any],
    supportedKeys: Set<String>,
    objectName: String
) throws {
    let unsupportedKeys = Set(object.keys).subtracting(supportedKeys)
    guard unsupportedKeys.isEmpty else {
        let key = unsupportedKeys.sorted().first ?? "unknown"
        throw SchemaError.invalidPackage("Unsupported native \(objectName) field \(key).")
    }
}

private func validateObjectField(
    _ key: String,
    in object: [String: Any],
    path: String,
    using validator: ([String: Any], String) throws -> Void
) throws {
    guard let value = object[key],
          !(value is NSNull),
          let nestedObject = value as? [String: Any] else {
        return
    }
    try validator(nestedObject, path)
}

private func validateDynamicObjectField(
    _ key: String,
    in object: [String: Any],
    path: String,
    using validator: ([String: Any], String) throws -> Void
) throws {
    guard let value = object[key],
          !(value is NSNull) else {
        return
    }
    if let nestedObject = value as? [String: Any] {
        try validateDynamicObjectDictionary(nestedObject, path: path, using: validator)
        return
    }
    if let nestedArray = value as? [Any] {
        try validateDynamicObjectPairs(nestedArray, path: path, using: validator)
    }
}

private func validateDynamicObjectDictionary(
    _ dictionary: [String: Any],
    path: String,
    using validator: ([String: Any], String) throws -> Void
) throws {
    var logicalKeys: Set<String> = []
    for nestedKey in dictionary.keys.sorted() {
        let logicalKey = try canonicalNativeDynamicDictionaryKey(nestedKey, path: path)
        guard logicalKeys.insert(logicalKey).inserted else {
            throw SchemaError.invalidPackage("Duplicate native \(path) dictionary key \(nestedKey).")
        }
        guard let valueObject = dictionary[nestedKey] as? [String: Any] else {
            continue
        }
        try validator(valueObject, "\(path).\(nestedKey)")
    }
}

private func validateDynamicObjectPairs(
    _ pairs: [Any],
    path: String,
    using validator: ([String: Any], String) throws -> Void
) throws {
    guard pairs.count.isMultiple(of: 2) else {
        throw SchemaError.invalidPackage("Native \(path) dictionary must contain key/value pairs.")
    }
    var valueIndex = 1
    var pairIndex = 0
    var keys: Set<String> = []
    while valueIndex < pairs.count {
        guard let key = pairs[valueIndex - 1] as? String,
              !key.isEmpty else {
            throw SchemaError.invalidPackage("Native \(path) dictionary key \(pairIndex) must be a string.")
        }
        let logicalKey = try canonicalNativeDynamicDictionaryKey(key, path: path)
        guard keys.insert(logicalKey).inserted else {
            throw SchemaError.invalidPackage("Duplicate native \(path) dictionary key \(key).")
        }
        guard let valueObject = pairs[valueIndex] as? [String: Any] else {
            valueIndex += 2
            pairIndex += 1
            continue
        }
        try validator(valueObject, "\(path)[\(pairIndex)]")
        valueIndex += 2
        pairIndex += 1
    }
}

private func canonicalNativeDynamicDictionaryKey(_ key: String, path: String) throws -> String {
    guard let uuid = UUID(uuidString: key) else {
        throw SchemaError.invalidPackage("Native \(path) dictionary key \(key) must be a UUID string.")
    }
    return uuid.uuidString
}

private func validateArrayField(
    _ key: String,
    in object: [String: Any],
    path: String,
    using validator: ([String: Any], String) throws -> Void
) throws {
    guard let value = object[key],
          !(value is NSNull),
          let array = value as? [Any] else {
        return
    }
    for (index, element) in array.enumerated() {
        guard let elementObject = element as? [String: Any] else {
            continue
        }
        try validator(elementObject, "\(path)[\(index)]")
    }
}

private func rejectDuplicateJSONKeys(in data: Data, name: String) throws {
    guard let text = String(data: data, encoding: .utf8) else {
        throw SchemaError.invalidPackage("\(name) JSON is not UTF-8.")
    }
    do {
        var scanner = JSONDuplicateKeyScanner(text: text)
        try scanner.validate()
    } catch let error as SchemaError {
        throw error
    } catch {
        throw SchemaError.invalidPackage("\(name) JSON is invalid: \(error).")
    }
}

private struct JSONDuplicateKeyScanner {
    var text: String
    var index: String.Index

    init(text: String) {
        self.text = text
        self.index = text.startIndex
    }

    mutating func validate() throws {
        skipWhitespace()
        try parseValue()
        skipWhitespace()
        guard index == text.endIndex else {
            throw SchemaError.invalidPackage("JSON contains trailing content.")
        }
    }

    private mutating func parseValue() throws {
        skipWhitespace()
        guard index < text.endIndex else {
            throw SchemaError.invalidPackage("JSON value is missing.")
        }
        let character = text[index]
        if character == "{" {
            try parseObject()
        } else if character == "[" {
            try parseArray()
        } else if character == "\"" {
            _ = try parseString()
        } else if character == "-" || character.isNumber {
            try parseNumber()
        } else if text[index...].hasPrefix("true") {
            advance(count: 4)
        } else if text[index...].hasPrefix("false") {
            advance(count: 5)
        } else if text[index...].hasPrefix("null") {
            advance(count: 4)
        } else {
            throw SchemaError.invalidPackage("JSON value is invalid.")
        }
    }

    private mutating func parseObject() throws {
        try consume("{")
        skipWhitespace()
        if consumeIfPresent("}") {
            return
        }
        var keys: Set<String> = []
        while true {
            skipWhitespace()
            guard index < text.endIndex, text[index] == "\"" else {
                throw SchemaError.invalidPackage("JSON object key is missing.")
            }
            let key = try parseString()
            guard keys.insert(key).inserted else {
                throw SchemaError.invalidPackage("Duplicate JSON key \(key).")
            }
            skipWhitespace()
            try consume(":")
            try parseValue()
            skipWhitespace()
            if consumeIfPresent("}") {
                return
            }
            try consume(",")
        }
    }

    private mutating func parseArray() throws {
        try consume("[")
        skipWhitespace()
        if consumeIfPresent("]") {
            return
        }
        while true {
            try parseValue()
            skipWhitespace()
            if consumeIfPresent("]") {
                return
            }
            try consume(",")
        }
    }

    private mutating func parseString() throws -> String {
        try consume("\"")
        var output = ""
        while index < text.endIndex {
            let character = text[index]
            index = text.index(after: index)
            if character == "\"" {
                return output
            }
            if character == "\\" {
                output.append(try parseEscapedCharacter())
            } else {
                output.append(character)
            }
        }
        throw SchemaError.invalidPackage("JSON string is unterminated.")
    }

    private mutating func parseEscapedCharacter() throws -> String {
        guard index < text.endIndex else {
            throw SchemaError.invalidPackage("JSON escape is unterminated.")
        }
        let character = text[index]
        index = text.index(after: index)
        switch character {
        case "\"":
            return "\""
        case "\\":
            return "\\"
        case "/":
            return "/"
        case "b":
            return "\u{08}"
        case "f":
            return "\u{0c}"
        case "n":
            return "\n"
        case "r":
            return "\r"
        case "t":
            return "\t"
        case "u":
            let first = try parseUnicodeEscapeValue()
            if (0xD800...0xDBFF).contains(first) {
                try consume("\\")
                try consume("u")
                let second = try parseUnicodeEscapeValue()
                guard (0xDC00...0xDFFF).contains(second) else {
                    throw SchemaError.invalidPackage("JSON unicode surrogate pair is invalid.")
                }
                let value = 0x10000 + ((first - 0xD800) << 10) + (second - 0xDC00)
                guard let scalar = UnicodeScalar(value) else {
                    throw SchemaError.invalidPackage("JSON unicode scalar is invalid.")
                }
                return String(scalar)
            }
            guard !(0xDC00...0xDFFF).contains(first),
                  let scalar = UnicodeScalar(first) else {
                throw SchemaError.invalidPackage("JSON unicode scalar is invalid.")
            }
            return String(scalar)
        default:
            throw SchemaError.invalidPackage("JSON escape is invalid.")
        }
    }

    private mutating func parseUnicodeEscapeValue() throws -> UInt32 {
        var value: UInt32 = 0
        for _ in 0..<4 {
            guard index < text.endIndex,
                  let digit = text[index].hexDigitValue else {
                throw SchemaError.invalidPackage("JSON unicode escape is invalid.")
            }
            value = value * 16 + UInt32(digit)
            index = text.index(after: index)
        }
        return value
    }

    private mutating func parseNumber() throws {
        if consumeIfPresent("-") {
            guard index < text.endIndex else {
                throw SchemaError.invalidPackage("JSON number is invalid.")
            }
        }
        try parseIntegerPart()
        if consumeIfPresent(".") {
            try parseRequiredDigits()
        }
        if consumeIfPresent("e") || consumeIfPresent("E") {
            _ = consumeIfPresent("+") || consumeIfPresent("-")
            try parseRequiredDigits()
        }
    }

    private mutating func parseIntegerPart() throws {
        guard index < text.endIndex else {
            throw SchemaError.invalidPackage("JSON number is invalid.")
        }
        if text[index] == "0" {
            index = text.index(after: index)
            return
        }
        guard ("1"..."9").contains(text[index]) else {
            throw SchemaError.invalidPackage("JSON number is invalid.")
        }
        while index < text.endIndex, text[index].isNumber {
            index = text.index(after: index)
        }
    }

    private mutating func parseRequiredDigits() throws {
        var hasDigit = false
        while index < text.endIndex, text[index].isNumber {
            hasDigit = true
            index = text.index(after: index)
        }
        guard hasDigit else {
            throw SchemaError.invalidPackage("JSON number is invalid.")
        }
    }

    private mutating func skipWhitespace() {
        while index < text.endIndex, text[index].isWhitespace {
            index = text.index(after: index)
        }
    }

    private mutating func consume(_ expected: Character) throws {
        guard index < text.endIndex, text[index] == expected else {
            throw SchemaError.invalidPackage("JSON expected \(expected).")
        }
        index = text.index(after: index)
    }

    private mutating func consumeIfPresent(_ expected: Character) -> Bool {
        guard index < text.endIndex, text[index] == expected else {
            return false
        }
        index = text.index(after: index)
        return true
    }

    private mutating func advance(count: Int) {
        for _ in 0..<count {
            index = text.index(after: index)
        }
    }
}

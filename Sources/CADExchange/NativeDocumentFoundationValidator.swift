import Foundation
import CADCore

/// Strict native-wire admission for CADIR's document foundation component.
func validateNativeDocumentFoundationObject(_ object: [String: Any], path: String) throws {
    try foundationKeys(object, allowed: ["attributes"], path: path)
    guard let attributes = object["attributes"] as? [[String: Any]] else {
        throw SchemaError.invalidPackage("\(path).attributes must be an array of records.")
    }
    for (index, record) in attributes.enumerated() {
        try Task.checkCancellation()
        let recordPath = "\(path).attributes[\(index)]"
        try foundationKeys(record, allowed: ["id", "name", "owner", "value"], path: recordPath)
        try foundationReference(foundationObject(record["owner"], path: "\(recordPath).owner"), path: "\(recordPath).owner")
        let value = try foundationObject(record["value"], path: "\(recordPath).value")
        guard let kind = value["kind"] as? String,
              ["boolean", "integer", "real", "text", "quantity", "integers", "reals", "texts", "bytes", "reference", "references", "subshapeReference", "subshapeReferences"].contains(kind) else {
            throw SchemaError.invalidPackage("Unknown document attribute value kind at \(recordPath).value.")
        }
        try foundationKeys(value, allowed: ["kind", kind], path: "\(recordPath).value")
        guard value[kind] != nil else { throw SchemaError.invalidPackage("Attribute payload is missing at \(recordPath).value.") }
        if kind == "subshapeReference" {
            try validateStableSubshapeReferenceObject(foundationObject(value[kind], path: "\(recordPath).value.subshapeReference"), path: "\(recordPath).value.subshapeReference")
        } else if kind == "subshapeReferences" {
            guard let references = value[kind] as? [[String: Any]] else { throw SchemaError.invalidPackage("Subshape witnesses must be an array.") }
            for (index, reference) in references.enumerated() {
                try Task.checkCancellation()
                try validateStableSubshapeReferenceObject(reference, path: "\(recordPath).value.subshapeReferences[\(index)]")
            }
        } else if kind == "quantity" {
            try foundationKeys(foundationObject(value[kind], path: "\(recordPath).value.quantity"), allowed: ["value", "kind"], path: "\(recordPath).value.quantity")
        } else if kind == "reference" {
            try foundationReference(foundationObject(value[kind], path: "\(recordPath).value.reference"), path: "\(recordPath).value.reference")
        } else if kind == "references" {
            guard let references = value[kind] as? [[String: Any]] else { throw SchemaError.invalidPackage("Attribute references must be an array.") }
            for reference in references { try Task.checkCancellation(); try foundationReference(reference, path: "\(recordPath).value.references") }
        }
    }
}

private func foundationReference(_ object: [String: Any], path: String) throws {
    try foundationKeys(object, allowed: ["documentID", "target"], path: path)
    let target = try foundationObject(object["target"], path: "\(path).target")
    guard let kind = target["kind"] as? String else { throw SchemaError.invalidPackage("Persistent target kind is missing at \(path).") }
    let allowed: Set<String>
    switch kind {
    case "document": allowed = ["kind"]
    case "feature": allowed = ["kind", "featureID"]
    case "parameter": allowed = ["kind", "parameterID"]
    case "attribute": allowed = ["kind", "attributeID"]
    default: throw SchemaError.invalidPackage("Unknown persistent target kind at \(path).")
    }
    try foundationKeys(target, allowed: allowed, path: "\(path).target")
}

private func foundationObject(_ value: Any?, path: String) throws -> [String: Any] {
    guard let object = value as? [String: Any] else { throw SchemaError.invalidPackage("\(path) must be an object.") }
    return object
}

private func foundationKeys(_ object: [String: Any], allowed: Set<String>, path: String) throws {
    if let key = object.keys.sorted().first(where: { !allowed.contains($0) }) {
        throw SchemaError.invalidPackage("Unsupported attribute key \(path).\(key).")
    }
}

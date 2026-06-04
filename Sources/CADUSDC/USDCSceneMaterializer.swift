import CADUSD
import Foundation

struct USDCSceneMaterializer {
    private let crate: USDCCrateFile

    init(crate: USDCCrateFile) {
        self.crate = crate
    }

    func readScene() throws -> USDScene {
        let tokens = try crate.readTokens()
        let strings = try crate.readStrings()
        let paths = try crate.readPaths()
        let specs = try crate.readSpecs()
        let fields = try crate.readFields()
        let fieldSetIndexes = try crate.readFieldSetIndexes()
        let valueDecoder = USDCCrateValueDecoder(crate: crate, tokens: tokens, strings: strings)

        let specsByPath = try buildSpecsByPath(
            specs: specs,
            paths: paths,
            fields: fields,
            fieldSetIndexes: fieldSetIndexes,
            tokens: tokens
        )

        let rootFields = specsByPath["/"]?.fields ?? [:]
        let defaultPrim = try rootFields["defaultPrim"].map { try valueDecoder.readStringLike($0) }
        let metersPerUnit = try rootFields["metersPerUnit"].map { try valueDecoder.readDouble($0) } ?? 1
        guard metersPerUnit.isFinite, metersPerUnit > 0 else {
            throw USDImportError.invalidData("USDC metersPerUnit must be a positive finite value.")
        }
        let upAxisToken = try rootFields["upAxis"].map { try valueDecoder.readStringLike($0) }
        let upAxis: USDUpAxis
        if let upAxisToken {
            guard let parsed = USDUpAxis(rawValue: upAxisToken) else {
                throw USDImportError.invalidData("Unsupported USDC upAxis \(upAxisToken).")
            }
            upAxis = parsed
        } else {
            upAxis = .y
        }

        let meshes = try materializeMeshes(specsByPath: specsByPath, valueDecoder: valueDecoder)
        guard !meshes.isEmpty else {
            throw USDImportError.invalidData("USDC scene contains no Mesh prims.")
        }
        return USDScene(defaultPrim: defaultPrim, metersPerUnit: metersPerUnit, upAxis: upAxis, meshes: meshes)
    }

    private func buildSpecsByPath(
        specs: [USDCCrateSpec],
        paths: [String],
        fields: [USDCCrateField],
        fieldSetIndexes: [UInt32],
        tokens: [String]
    ) throws -> [String: USDCSpecRecord] {
        var records: [String: USDCSpecRecord] = [:]
        for spec in specs {
            let path = paths[Int(spec.pathIndex)]
            let fieldIndexes = try fieldIndexesForSpec(spec, fieldSetIndexes: fieldSetIndexes)
            var fieldReps: [String: USDCCrateValueRep] = [:]
            for fieldIndex in fieldIndexes {
                guard fieldIndex < UInt32(fields.count) else {
                    throw USDImportError.invalidData("USDC spec references a field outside FIELDS.")
                }
                let field = fields[Int(fieldIndex)]
                guard field.tokenIndex < UInt32(tokens.count) else {
                    throw USDImportError.invalidData("USDC field references a token outside TOKENS.")
                }
                let fieldName = tokens[Int(field.tokenIndex)]
                guard fieldReps[fieldName] == nil else {
                    throw USDImportError.invalidData("USDC spec contains duplicate field \(fieldName).")
                }
                fieldReps[fieldName] = field.valueRep
            }
            records[path] = USDCSpecRecord(specType: spec.specType, fields: fieldReps)
        }
        return records
    }

    private func fieldIndexesForSpec(_ spec: USDCCrateSpec, fieldSetIndexes: [UInt32]) throws -> [UInt32] {
        var index = Int(spec.fieldSetIndex)
        guard index < fieldSetIndexes.count else {
            throw USDImportError.invalidData("USDC spec field set index is outside FIELDSETS.")
        }
        var fieldIndexes: [UInt32] = []
        while index < fieldSetIndexes.count {
            let fieldIndex = fieldSetIndexes[index]
            index += 1
            if fieldIndex == UInt32.max {
                return fieldIndexes
            }
            fieldIndexes.append(fieldIndex)
        }
        throw USDImportError.invalidData("USDC spec field set is unterminated.")
    }

    private func materializeMeshes(
        specsByPath: [String: USDCSpecRecord],
        valueDecoder: USDCCrateValueDecoder
    ) throws -> [USDMesh] {
        var meshes: [USDMesh] = []
        let meshPrimPaths = try specsByPath.keys.sorted().filter { path in
            guard let record = specsByPath[path], record.specType == .prim else {
                return false
            }
            guard let typeNameRep = record.fields["typeName"] else {
                return false
            }
            if let specifierRep = record.fields["specifier"], try !isDefSpecifier(specifierRep) {
                return false
            }
            return try valueDecoder.readStringLike(typeNameRep) == "Mesh"
        }

        for meshPath in meshPrimPaths {
            let attributeRecords = attributeRecords(forPrimPath: meshPath, specsByPath: specsByPath)
            let points = try requiredPointArray(
                named: "points",
                attributeRecords: attributeRecords,
                valueDecoder: valueDecoder
            )
            let faceVertexCounts = try requiredIntArray(
                named: "faceVertexCounts",
                attributeRecords: attributeRecords,
                valueDecoder: valueDecoder
            )
            let faceVertexIndices = try requiredIntArray(
                named: "faceVertexIndices",
                attributeRecords: attributeRecords,
                valueDecoder: valueDecoder
            )
            let subdivisionScheme = try optionalString(
                named: "subdivisionScheme",
                attributeRecords: attributeRecords,
                valueDecoder: valueDecoder
            )
            if let subdivisionScheme, subdivisionScheme != "none" {
                throw USDImportError.unsupportedFeature("Only subdivisionScheme = \"none\" is supported.")
            }
            meshes.append(USDMesh(
                name: primName(from: meshPath),
                points: points,
                faceVertexCounts: faceVertexCounts,
                faceVertexIndices: faceVertexIndices,
                subdivisionScheme: subdivisionScheme
            ))
        }
        return meshes
    }

    private func attributeRecords(
        forPrimPath primPath: String,
        specsByPath: [String: USDCSpecRecord]
    ) -> [String: USDCSpecRecord] {
        let prefix = "\(primPath)."
        var attributes: [String: USDCSpecRecord] = [:]
        for (path, record) in specsByPath where record.specType == .attribute && path.hasPrefix(prefix) {
            let name = String(path.dropFirst(prefix.count))
            if !name.contains("/") && !name.contains(".") {
                attributes[name] = record
            }
        }
        return attributes
    }

    private func requiredPointArray(
        named name: String,
        attributeRecords: [String: USDCSpecRecord],
        valueDecoder: USDCCrateValueDecoder
    ) throws -> [USDPoint3D] {
        guard let defaultValue = attributeRecords[name]?.fields["default"] else {
            throw USDImportError.missingRequiredField(name)
        }
        let points = try valueDecoder.readPointArray(defaultValue)
        guard !points.isEmpty else {
            throw USDImportError.invalidData("USDC Mesh \(name) contains no points.")
        }
        return points
    }

    private func requiredIntArray(
        named name: String,
        attributeRecords: [String: USDCSpecRecord],
        valueDecoder: USDCCrateValueDecoder
    ) throws -> [Int] {
        guard let defaultValue = attributeRecords[name]?.fields["default"] else {
            throw USDImportError.missingRequiredField(name)
        }
        let values = try valueDecoder.readIntArray(defaultValue)
        guard !values.isEmpty else {
            throw USDImportError.invalidData("USDC Mesh \(name) is empty.")
        }
        return values
    }

    private func optionalString(
        named name: String,
        attributeRecords: [String: USDCSpecRecord],
        valueDecoder: USDCCrateValueDecoder
    ) throws -> String? {
        guard let defaultValue = attributeRecords[name]?.fields["default"] else {
            return nil
        }
        return try valueDecoder.readStringLike(defaultValue)
    }

    private func primName(from path: String) -> String? {
        guard path != "/", let slash = path.lastIndex(of: "/") else {
            return nil
        }
        return String(path[path.index(after: slash)...])
    }

    private func isDefSpecifier(_ valueRep: USDCCrateValueRep) throws -> Bool {
        guard valueRep.type == .specifier, valueRep.isInlined, !valueRep.isArray else {
            throw USDImportError.invalidData("USDC specifier field is malformed.")
        }
        return valueRep.payload == 0
    }
}

private struct USDCSpecRecord {
    var specType: USDCCrateSpecType
    var fields: [String: USDCCrateValueRep]
}

import CADUSD

struct USDCLayerReader {
    private let crate: USDCCrateFile

    init(crate: USDCCrateFile) {
        self.crate = crate
    }

    func readLayer() throws -> USDCLayer {
        let tokens = try crate.readTokens()
        let strings = try crate.readStrings()
        let paths = try crate.readPaths()
        let specs = try crate.readSpecs()
        let fields = try crate.readFields()
        let fieldSetIndexes = try crate.readFieldSetIndexes()
        let valueDecoder = USDCCrateValueDecoder(crate: crate, tokens: tokens, strings: strings)
        let records = try buildLayerRecords(
            specs: specs,
            paths: paths,
            fields: fields,
            fieldSetIndexes: fieldSetIndexes,
            tokens: tokens,
            valueDecoder: valueDecoder
        )

        let rootFields = records.first { $0.path == "/" }?.fields ?? [:]
        let defaultPrim = try rootFields["defaultPrim"].map { try valueDecoder.readStringLike($0) }
        let metersPerUnit = try rootFields["metersPerUnit"].map { try valueDecoder.readDouble($0) }
        let upAxisToken = try rootFields["upAxis"].map { try valueDecoder.readStringLike($0) }
        let upAxis: USDUpAxis?
        if let upAxisToken {
            guard let parsed = USDUpAxis(rawValue: upAxisToken) else {
                throw USDImportError.invalidData("Unsupported USDC upAxis \(upAxisToken).")
            }
            upAxis = parsed
        } else {
            upAxis = nil
        }

        let layerSpecs = records.map { record in
            USDCLayerSpec(
                path: record.path,
                specType: record.specType,
                specifier: record.specifier,
                typeName: record.typeName,
                fieldNames: record.fields.keys.sorted()
            )
        }
        return USDCLayer(
            defaultPrim: defaultPrim,
            metersPerUnit: metersPerUnit,
            upAxis: upAxis,
            specs: layerSpecs
        )
    }

    private func buildLayerRecords(
        specs: [USDCCrateSpec],
        paths: [String],
        fields: [USDCCrateField],
        fieldSetIndexes: [UInt32],
        tokens: [String],
        valueDecoder: USDCCrateValueDecoder
    ) throws -> [USDCLayerRecord] {
        try specs.sorted { lhs, rhs in
            lhs.pathIndex < rhs.pathIndex
        }.map { spec in
            guard spec.pathIndex < UInt32(paths.count) else {
                throw USDImportError.invalidData("USDC spec references a path outside PATHS.")
            }
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
            return USDCLayerRecord(
                path: path,
                specType: spec.specType,
                fields: fieldReps,
                specifier: try specifier(from: fieldReps["specifier"]),
                typeName: try fieldReps["typeName"].map { try valueDecoder.readStringLike($0) }
            )
        }
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

    private func specifier(from valueRep: USDCCrateValueRep?) throws -> USDCPrimSpecifier? {
        guard let valueRep else {
            return nil
        }
        guard valueRep.type == .specifier, valueRep.isInlined, !valueRep.isArray else {
            throw USDImportError.invalidData("USDC specifier field is malformed.")
        }
        return USDCPrimSpecifier(payload: valueRep.payload)
    }
}

private struct USDCLayerRecord {
    var path: String
    var specType: USDCCrateSpecType
    var fields: [String: USDCCrateValueRep]
    var specifier: USDCPrimSpecifier?
    var typeName: String?
}

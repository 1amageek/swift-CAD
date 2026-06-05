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
            let transform = try worldTransform(
                forPrimPath: meshPath,
                specsByPath: specsByPath,
                valueDecoder: valueDecoder
            )
            let transformedPoints = try points.map { try transform.transform($0) }
            let normals = try optionalPointArray(
                named: "normals",
                attributeRecords: attributeRecords,
                valueDecoder: valueDecoder
            ) ?? []
            let transformedNormals = try normals.map { try transform.transformNormal($0) }
            let normalsInterpolation = try optionalMetadataString(
                named: "interpolation",
                record: attributeRecords["normals"],
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
            let orientation = try optionalOrientation(
                attributeRecords: attributeRecords,
                valueDecoder: valueDecoder
            )
            let subdivisionScheme = try optionalString(
                named: "subdivisionScheme",
                attributeRecords: attributeRecords,
                valueDecoder: valueDecoder
            )
            let extent = try optionalPointArray(
                named: "extent",
                attributeRecords: attributeRecords,
                valueDecoder: valueDecoder
            )
            if let extent, extent.count != 2 {
                throw USDImportError.invalidData("USDC Mesh extent must contain exactly two points.")
            }
            meshes.append(USDMesh(
                name: primName(from: meshPath),
                points: transformedPoints,
                faceVertexCounts: faceVertexCounts,
                faceVertexIndices: faceVertexIndices,
                normals: transformedNormals,
                normalsInterpolation: normalsInterpolation,
                orientation: orientation,
                subdivisionScheme: subdivisionScheme,
                extent: extent
            ))
        }
        return meshes
    }

    private func worldTransform(
        forPrimPath primPath: String,
        specsByPath: [String: USDCSpecRecord],
        valueDecoder: USDCCrateValueDecoder
    ) throws -> USDCMatrix4x4 {
        var transform = USDCMatrix4x4.identity
        var currentPath: String? = primPath
        while let path = currentPath, path != "/" {
            if let record = specsByPath[path], record.specType == .prim {
                let localTransform = try localTransform(
                    forPrimPath: path,
                    specsByPath: specsByPath,
                    valueDecoder: valueDecoder
                )
                transform = transform.concatenating(localTransform.matrix)
                if localTransform.resetsParentStack {
                    break
                }
            }
            currentPath = parentPrimPath(from: path)
        }
        return transform
    }

    private func localTransform(
        forPrimPath primPath: String,
        specsByPath: [String: USDCSpecRecord],
        valueDecoder: USDCCrateValueDecoder
    ) throws -> USDCLocalTransform {
        let attributeRecords = attributeRecords(forPrimPath: primPath, specsByPath: specsByPath)
        guard let xformOpOrderRep = attributeRecords["xformOpOrder"]?.fields["default"] else {
            return USDCLocalTransform(matrix: .identity, resetsParentStack: false)
        }
        let xformOpOrder = try valueDecoder.readTokenArray(xformOpOrderRep)
        var transform = USDCMatrix4x4.identity
        var resetsParentStack = false
        for opName in xformOpOrder.reversed() {
            if opName == "!resetXformStack!" {
                resetsParentStack = true
                break
            }
            let orderedOp = orderedXformOperationName(from: opName)
            guard let opRecord = attributeRecords[orderedOp.attributeName] else {
                continue
            }
            let opTransform = try self.transform(
                forXformOp: orderedOp.attributeName,
                record: opRecord,
                valueDecoder: valueDecoder
            )
            let effectiveTransform = orderedOp.isInverted ? try opTransform.inverted() : opTransform
            transform = transform.concatenating(effectiveTransform)
        }
        return USDCLocalTransform(matrix: transform, resetsParentStack: resetsParentStack)
    }

    private func orderedXformOperationName(from opName: String) -> (attributeName: String, isInverted: Bool) {
        let prefix = "!invert!"
        guard opName.hasPrefix(prefix) else {
            return (opName, false)
        }
        var attributeName = String(opName.dropFirst(prefix.count))
        if attributeName.hasPrefix(":") {
            attributeName.removeFirst()
        }
        return (attributeName, true)
    }

    private func transform(
        forXformOp opName: String,
        record: USDCSpecRecord,
        valueDecoder: USDCCrateValueDecoder
    ) throws -> USDCMatrix4x4 {
        guard let defaultValue = try resolvedValueRep(record: record, valueDecoder: valueDecoder) else {
            throw USDImportError.invalidData("USDC xform op \(opName) has no default value.")
        }
        guard let operationType = xformOperationType(from: opName) else {
            throw USDImportError.invalidData("USDC xform op \(opName) is malformed.")
        }
        switch operationType {
        case "translate":
            return .translation(try valueDecoder.readVector3(defaultValue))
        case "translateX":
            return .translation(USDCVector3D(x: try valueDecoder.readDouble(defaultValue), y: 0, z: 0))
        case "translateY":
            return .translation(USDCVector3D(x: 0, y: try valueDecoder.readDouble(defaultValue), z: 0))
        case "translateZ":
            return .translation(USDCVector3D(x: 0, y: 0, z: try valueDecoder.readDouble(defaultValue)))
        case "scale":
            return .scale(try valueDecoder.readVector3(defaultValue))
        case "scaleX":
            return .scale(USDCVector3D(x: try valueDecoder.readDouble(defaultValue), y: 1, z: 1))
        case "scaleY":
            return .scale(USDCVector3D(x: 1, y: try valueDecoder.readDouble(defaultValue), z: 1))
        case "scaleZ":
            return .scale(USDCVector3D(x: 1, y: 1, z: try valueDecoder.readDouble(defaultValue)))
        case "rotateX":
            return try .rotationX(angleInDegrees: valueDecoder.readDouble(defaultValue))
        case "rotateY":
            return try .rotationY(angleInDegrees: valueDecoder.readDouble(defaultValue))
        case "rotateZ":
            return try .rotationZ(angleInDegrees: valueDecoder.readDouble(defaultValue))
        case "rotateXYZ", "rotateXZY", "rotateYXZ", "rotateYZX", "rotateZXY", "rotateZYX":
            let order = String(operationType.dropFirst("rotate".count))
            return try .eulerRotation(order: order, anglesInDegrees: valueDecoder.readVector3(defaultValue))
        case "orient":
            return try valueDecoder.readQuaternion(defaultValue).rotationMatrix()
        case "transform":
            return try valueDecoder.readMatrix4x4(defaultValue)
        default:
            throw USDImportError.unsupportedFeature("USDC xform op \(operationType) is not supported yet.")
        }
    }

    private func xformOperationType(from opName: String) -> String? {
        let prefix = "xformOp:"
        guard opName.hasPrefix(prefix) else {
            return nil
        }
        let suffixStart = opName.index(opName.startIndex, offsetBy: prefix.count)
        return opName[suffixStart...].split(separator: ":", maxSplits: 1).first.map(String.init)
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
        guard
            let record = attributeRecords[name],
            let defaultValue = try resolvedValueRep(record: record, valueDecoder: valueDecoder)
        else {
            throw USDImportError.missingRequiredField(name)
        }
        let points = try valueDecoder.readPointArray(defaultValue)
        guard !points.isEmpty else {
            throw USDImportError.invalidData("USDC Mesh \(name) contains no points.")
        }
        return points
    }

    private func optionalPointArray(
        named name: String,
        attributeRecords: [String: USDCSpecRecord],
        valueDecoder: USDCCrateValueDecoder
    ) throws -> [USDPoint3D]? {
        guard
            let record = attributeRecords[name],
            let defaultValue = try resolvedValueRep(record: record, valueDecoder: valueDecoder)
        else {
            return nil
        }
        return try valueDecoder.readPointArray(defaultValue)
    }

    private func requiredIntArray(
        named name: String,
        attributeRecords: [String: USDCSpecRecord],
        valueDecoder: USDCCrateValueDecoder
    ) throws -> [Int] {
        guard
            let record = attributeRecords[name],
            let defaultValue = try resolvedValueRep(record: record, valueDecoder: valueDecoder)
        else {
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
        guard
            let record = attributeRecords[name],
            let defaultValue = try resolvedValueRep(record: record, valueDecoder: valueDecoder)
        else {
            return nil
        }
        return try valueDecoder.readStringLike(defaultValue)
    }

    private func optionalOrientation(
        attributeRecords: [String: USDCSpecRecord],
        valueDecoder: USDCCrateValueDecoder
    ) throws -> USDOrientation? {
        guard let value = try optionalString(
            named: "orientation",
            attributeRecords: attributeRecords,
            valueDecoder: valueDecoder
        ) else {
            return nil
        }
        guard let orientation = USDOrientation(rawValue: value) else {
            throw USDImportError.invalidData("Unsupported USDC orientation \(value).")
        }
        return orientation
    }

    private func optionalMetadataString(
        named name: String,
        record: USDCSpecRecord?,
        valueDecoder: USDCCrateValueDecoder
    ) throws -> String? {
        guard let valueRep = record?.fields[name] else {
            return nil
        }
        guard !valueDecoder.isBlockedValue(valueRep) else {
            return nil
        }
        return try valueDecoder.readStringLike(valueRep)
    }

    private func resolvedValueRep(
        record: USDCSpecRecord,
        valueDecoder: USDCCrateValueDecoder
    ) throws -> USDCCrateValueRep? {
        if let defaultValue = record.fields["default"] {
            if valueDecoder.isValueBlock(defaultValue) {
                return nil
            }
            if !valueDecoder.isAnimationBlock(defaultValue) {
                return defaultValue
            }
        }
        if let timeSamples = record.fields["timeSamples"] {
            return try valueDecoder.readFirstUnblockedTimeSampleValueRep(timeSamples)
        }
        return nil
    }

    private func primName(from path: String) -> String? {
        guard path != "/", let slash = path.lastIndex(of: "/") else {
            return nil
        }
        return String(path[path.index(after: slash)...])
    }

    private func parentPrimPath(from path: String) -> String? {
        guard path != "/" else {
            return nil
        }
        guard let slash = path.lastIndex(of: "/") else {
            return nil
        }
        if slash == path.startIndex {
            return "/"
        }
        return String(path[..<slash])
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

private struct USDCLocalTransform {
    var matrix: USDCMatrix4x4
    var resetsParentStack: Bool
}

import Foundation

public struct USDAReader: USDSceneReader {
    public init() {}

    public func read(from data: Data) throws -> USDScene {
        guard let text = String(data: data, encoding: .utf8) else {
            throw USDImportError.invalidData("USDA data is not UTF-8.")
        }
        return try read(text)
    }

    public func read(_ text: String) throws -> USDScene {
        guard text.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("#usda") else {
            throw USDImportError.invalidData("USDA data is missing the #usda signature.")
        }
        let metersPerUnit = try parseRequiredDouble(named: "metersPerUnit", in: text)
        guard metersPerUnit.isFinite, metersPerUnit > 0 else {
            throw USDImportError.invalidData("USDA metersPerUnit must be a positive finite value.")
        }
        let upAxis = try parseUpAxis(in: text)
        let defaultPrim = try parseOptionalString(named: "defaultPrim", in: text)
        let meshes = try parseMeshes(in: text)
        guard !meshes.isEmpty else {
            throw USDImportError.invalidData("USDA scene contains no Mesh prims.")
        }
        return USDScene(defaultPrim: defaultPrim, metersPerUnit: metersPerUnit, upAxis: upAxis, meshes: meshes)
    }

    private func parseMeshes(in text: String) throws -> [USDMesh] {
        try parseMeshes(in: text, inheritedTransform: .identity)
    }

    private func parseMeshes(
        in text: String,
        inheritedTransform: USDTransformMatrix4x4
    ) throws -> [USDMesh] {
        var meshes: [USDMesh] = []
        let prims = try parseDirectPrims(in: text)
        for prim in prims {
            let directBody = try directAttributeText(from: prim.body)
            let localTransform = try parseLocalTransform(in: directBody)
            let primTransform = localTransform.resetsParentStack
                ? localTransform.matrix
                : localTransform.matrix.concatenating(inheritedTransform)
            if prim.typeName == "Mesh" {
                meshes.append(try materializeMesh(
                    prim: prim,
                    directBody: directBody,
                    transform: primTransform
                ))
            }
            meshes.append(contentsOf: try parseMeshes(
                in: prim.body,
                inheritedTransform: primTransform
            ))
        }
        return meshes
    }

    private func materializeMesh(
        prim: USDAPrim,
        directBody: String,
        transform: USDTransformMatrix4x4
    ) throws -> USDMesh {
        let points = try parsePointArray(named: "points", in: directBody)
        let transformedPoints = try points.map { try transform.transform($0) }
        let counts = try parseIntArray(named: "faceVertexCounts", in: directBody)
        let indices = try parseIntArray(named: "faceVertexIndices", in: directBody)
        let normals = try parseOptionalPointArray(named: "normals", in: directBody) ?? []
        let transformedNormals = try normals.map { try transform.transformNormal($0) }
        let normalsInterpolation = try parseOptionalAttributeMetadataString(
            attributeName: "normals",
            metadataName: "interpolation",
            in: directBody
        )
        let orientation = try parseOptionalOrientation(in: directBody)
        let subdivisionScheme = try parseOptionalString(named: "subdivisionScheme", in: directBody)
        let textureCoordinates = try parseOptionalTextureCoordinates(in: directBody)
        let displayColor = try parseOptionalDisplayColor(in: directBody)
        let displayOpacity = try parseOptionalDisplayOpacity(in: directBody)
        if let textureCoordinates {
            try textureCoordinates.validate(pointCount: transformedPoints.count, faceVertexCounts: counts)
        }
        if let displayColor {
            try displayColor.validate(pointCount: transformedPoints.count, faceVertexCounts: counts)
        }
        if let displayOpacity {
            try displayOpacity.validate(pointCount: transformedPoints.count, faceVertexCounts: counts)
        }
        let extent = try parseOptionalPointArray(named: "extent", in: directBody)
        if let extent, extent.count != 2 {
            throw USDImportError.invalidData("USDA extent must contain exactly two points.")
        }
        return USDMesh(
            name: prim.name,
            points: transformedPoints,
            faceVertexCounts: counts,
            faceVertexIndices: indices,
            normals: transformedNormals,
            normalsInterpolation: normalsInterpolation,
            orientation: orientation,
            subdivisionScheme: subdivisionScheme,
            textureCoordinates: textureCoordinates,
            displayColor: displayColor,
            displayOpacity: displayOpacity,
            extent: extent
        )
    }

    private func parseDirectPrims(in text: String) throws -> [USDAPrim] {
        var prims: [USDAPrim] = []
        var searchIndex = text.startIndex
        while let defIndex = nextDirectDef(in: text, from: searchIndex) {
            let prim = try parsePrim(at: defIndex, in: text)
            prims.append(prim)
            searchIndex = prim.fullRange.upperBound
        }
        return prims
    }

    private func directAttributeText(from text: String) throws -> String {
        var output = ""
        var searchIndex = text.startIndex
        while let defIndex = nextDirectDef(in: text, from: searchIndex) {
            output += String(text[searchIndex..<defIndex])
            let prim = try parsePrim(at: defIndex, in: text)
            searchIndex = prim.fullRange.upperBound
        }
        output += String(text[searchIndex..<text.endIndex])
        return output
    }

    private func nextDirectDef(in text: String, from startIndex: String.Index) -> String.Index? {
        var index = startIndex
        var bracketDepth = 0
        var parenthesisDepth = 0
        var isInsideString = false
        while index < text.endIndex {
            let character = text[index]
            if !isInsideString, character == "#" {
                skipLineComment(in: text, index: &index)
                continue
            }
            if character == "\"" {
                isInsideString.toggle()
            } else if !isInsideString {
                if character == "[" {
                    bracketDepth += 1
                } else if character == "]" {
                    bracketDepth = max(0, bracketDepth - 1)
                } else if character == "(" {
                    parenthesisDepth += 1
                } else if character == ")" {
                    parenthesisDepth = max(0, parenthesisDepth - 1)
                } else if bracketDepth == 0,
                          parenthesisDepth == 0,
                          isDefKeyword(at: index, in: text) {
                    return index
                }
            }
            index = text.index(after: index)
        }
        return nil
    }

    private func parsePrim(at defIndex: String.Index, in text: String) throws -> USDAPrim {
        var cursor = text.index(defIndex, offsetBy: 3)
        skipWhitespace(in: text, index: &cursor)
        var typeName: String?
        let name: String?
        if cursor < text.endIndex, text[cursor] == "\"" {
            let quoted = try parseQuotedString(startingAt: cursor, in: text)
            name = quoted.value
            cursor = quoted.endIndex
        } else {
            let typeStart = cursor
            while cursor < text.endIndex,
                  !text[cursor].isWhitespace,
                  text[cursor] != "\"",
                  text[cursor] != "(",
                  text[cursor] != "{" {
                cursor = text.index(after: cursor)
            }
            guard typeStart < cursor else {
                throw USDImportError.invalidData("USDA prim declaration is missing a type name.")
            }
            typeName = String(text[typeStart..<cursor])
            skipWhitespace(in: text, index: &cursor)
            guard cursor < text.endIndex, text[cursor] == "\"" else {
                throw USDImportError.invalidData("USDA prim declaration is missing a quoted name.")
            }
            let quoted = try parseQuotedString(startingAt: cursor, in: text)
            name = quoted.value
            cursor = quoted.endIndex
        }
        guard let openBrace = text[cursor...].firstIndex(of: "{") else {
            throw USDImportError.invalidData("USDA prim is missing an opening brace.")
        }
        let closeBrace = try matchingBrace(startingAt: openBrace, in: text)
        let body = String(text[text.index(after: openBrace)..<closeBrace])
        return USDAPrim(
            typeName: typeName,
            name: name,
            body: body,
            fullRange: defIndex..<text.index(after: closeBrace)
        )
    }

    private func parseQuotedString(
        startingAt quoteStart: String.Index,
        in text: String
    ) throws -> (value: String, endIndex: String.Index) {
        guard quoteStart < text.endIndex, text[quoteStart] == "\"" else {
            throw USDImportError.invalidData("USDA string is missing an opening quote.")
        }
        guard let quoteEnd = text[text.index(after: quoteStart)...].firstIndex(of: "\"") else {
            throw USDImportError.invalidData("USDA string is unterminated.")
        }
        return (
            String(text[text.index(after: quoteStart)..<quoteEnd]),
            text.index(after: quoteEnd)
        )
    }

    private func isDefKeyword(at index: String.Index, in text: String) -> Bool {
        guard text[index...].hasPrefix("def") else {
            return false
        }
        let keywordEnd = text.index(index, offsetBy: 3)
        let hasLeadingBoundary: Bool
        if index == text.startIndex {
            hasLeadingBoundary = true
        } else {
            let previous = text[text.index(before: index)]
            hasLeadingBoundary = previous.isWhitespace || previous == "{" || previous == "}" || previous == ";"
        }
        let hasTrailingBoundary = keywordEnd == text.endIndex || text[keywordEnd].isWhitespace
        return hasLeadingBoundary && hasTrailingBoundary
    }

    private func skipWhitespace(in text: String, index: inout String.Index) {
        while index < text.endIndex, text[index].isWhitespace {
            index = text.index(after: index)
        }
    }

    private func skipLineComment(in text: String, index: inout String.Index) {
        while index < text.endIndex, text[index] != "\n" {
            index = text.index(after: index)
        }
    }

    private func parseRequiredDouble(named name: String, in text: String) throws -> Double {
        let pattern = "\\b\(NSRegularExpression.escapedPattern(for: name))\\s*=\\s*([-+0-9.eE]+)"
        let match = try firstMatch(pattern: pattern, in: text)
        guard let match else {
            throw USDImportError.missingRequiredField(name)
        }
        guard let value = Double(match) else {
            throw USDImportError.invalidData("USDA \(name) is not a valid number.")
        }
        return value
    }

    private func parseUpAxis(in text: String) throws -> USDUpAxis {
        guard let value = try parseOptionalString(named: "upAxis", in: text) else {
            return .y
        }
        guard let axis = USDUpAxis(rawValue: value) else {
            throw USDImportError.invalidData("Unsupported USDA upAxis \(value).")
        }
        return axis
    }

    private func parseOptionalOrientation(in text: String) throws -> USDOrientation? {
        guard let value = try parseOptionalString(named: "orientation", in: text) else {
            return nil
        }
        guard let orientation = USDOrientation(rawValue: value) else {
            throw USDImportError.invalidData("Unsupported USDA orientation \(value).")
        }
        return orientation
    }

    private func parseLocalTransform(in text: String) throws -> USDALocalTransform {
        guard let xformOpOrder = try parseOptionalTokenArray(named: "xformOpOrder", in: text) else {
            return USDALocalTransform(matrix: .identity, resetsParentStack: false)
        }
        var transform = USDTransformMatrix4x4.identity
        var resetsParentStack = false
        for opName in xformOpOrder.reversed() {
            if opName == "!resetXformStack!" {
                resetsParentStack = true
                break
            }
            let orderedOp = orderedXformOperationName(from: opName)
            guard attributeNameRange(named: orderedOp.attributeName, in: text) != nil else {
                continue
            }
            let opTransform = try self.transform(forXformOp: orderedOp.attributeName, in: text)
            let effectiveTransform = orderedOp.isInverted ? try opTransform.inverted() : opTransform
            transform = transform.concatenating(effectiveTransform)
        }
        return USDALocalTransform(matrix: transform, resetsParentStack: resetsParentStack)
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

    private func transform(forXformOp opName: String, in text: String) throws -> USDTransformMatrix4x4 {
        guard let operationType = xformOperationType(from: opName) else {
            throw USDImportError.invalidData("USDA xform op \(opName) is malformed.")
        }
        switch operationType {
        case "translate":
            return .translation(try parseRequiredVector3(named: opName, in: text))
        case "translateX":
            return .translation(USDTransformVector3D(x: try parseRequiredScalar(named: opName, in: text), y: 0, z: 0))
        case "translateY":
            return .translation(USDTransformVector3D(x: 0, y: try parseRequiredScalar(named: opName, in: text), z: 0))
        case "translateZ":
            return .translation(USDTransformVector3D(x: 0, y: 0, z: try parseRequiredScalar(named: opName, in: text)))
        case "scale":
            return .scale(try parseRequiredVector3(named: opName, in: text))
        case "scaleX":
            return .scale(USDTransformVector3D(x: try parseRequiredScalar(named: opName, in: text), y: 1, z: 1))
        case "scaleY":
            return .scale(USDTransformVector3D(x: 1, y: try parseRequiredScalar(named: opName, in: text), z: 1))
        case "scaleZ":
            return .scale(USDTransformVector3D(x: 1, y: 1, z: try parseRequiredScalar(named: opName, in: text)))
        case "rotateX":
            return try .rotationX(angleInDegrees: parseRequiredScalar(named: opName, in: text))
        case "rotateY":
            return try .rotationY(angleInDegrees: parseRequiredScalar(named: opName, in: text))
        case "rotateZ":
            return try .rotationZ(angleInDegrees: parseRequiredScalar(named: opName, in: text))
        case "rotateXYZ", "rotateXZY", "rotateYXZ", "rotateYZX", "rotateZXY", "rotateZYX":
            let order = String(operationType.dropFirst("rotate".count))
            return try .eulerRotation(order: order, anglesInDegrees: parseRequiredVector3(named: opName, in: text))
        case "orient":
            return try parseRequiredQuaternion(named: opName, in: text).rotationMatrix()
        case "transform":
            return try parseRequiredMatrix4x4(named: opName, in: text)
        default:
            throw USDImportError.unsupportedFeature("USDA xform op \(operationType) is not supported yet.")
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

    private func parseOptionalString(named name: String, in text: String) throws -> String? {
        let pattern = "\\b\(NSRegularExpression.escapedPattern(for: name))\\s*=\\s*\"([^\"]*)\""
        return try firstMatch(pattern: pattern, in: text)
    }

    private func parseOptionalTokenArray(named name: String, in text: String) throws -> [String]? {
        guard let body = try optionalBracketArrayBody(named: name, in: text) else {
            return nil
        }
        let expression = try NSRegularExpression(pattern: "\"([^\"]*)\"")
        let range = NSRange(body.startIndex..<body.endIndex, in: body)
        return expression.matches(in: body, range: range).compactMap { match in
            guard let tokenRange = Range(match.range(at: 1), in: body) else {
                return nil
            }
            return String(body[tokenRange])
        }
    }

    private func parseOptionalTextureCoordinates(in text: String) throws -> USDTextureCoordinatePrimvar? {
        guard let values = try parseOptionalPoint2Array(named: "primvars:st", in: text) else {
            return nil
        }
        let indices = try parseOptionalIntArray(named: "primvars:st:indices", in: text)
        let interpolation = try parseOptionalAttributeMetadataString(
            attributeName: "primvars:st",
            metadataName: "interpolation",
            in: text
        )
        return USDTextureCoordinatePrimvar(values: values, indices: indices, interpolation: interpolation)
    }

    private func parseOptionalDisplayColor(in text: String) throws -> USDDisplayColorPrimvar? {
        guard let values = try parseOptionalColorArray(named: "primvars:displayColor", in: text) else {
            return nil
        }
        let indices = try parseOptionalIntArray(named: "primvars:displayColor:indices", in: text)
        let interpolation = try parseOptionalAttributeMetadataString(
            attributeName: "primvars:displayColor",
            metadataName: "interpolation",
            in: text
        )
        return USDDisplayColorPrimvar(values: values, indices: indices, interpolation: interpolation)
    }

    private func parseOptionalDisplayOpacity(in text: String) throws -> USDDisplayOpacityPrimvar? {
        guard let values = try parseOptionalDoubleArray(named: "primvars:displayOpacity", in: text) else {
            return nil
        }
        let indices = try parseOptionalIntArray(named: "primvars:displayOpacity:indices", in: text)
        let interpolation = try parseOptionalAttributeMetadataString(
            attributeName: "primvars:displayOpacity",
            metadataName: "interpolation",
            in: text
        )
        return USDDisplayOpacityPrimvar(values: values, indices: indices, interpolation: interpolation)
    }

    private func parseOptionalAttributeMetadataString(
        attributeName: String,
        metadataName: String,
        in text: String
    ) throws -> String? {
        guard let nameRange = attributeNameRange(named: attributeName, in: text) else {
            return nil
        }
        guard let openBracket = text[nameRange.upperBound...].firstIndex(of: "[") else {
            return nil
        }
        let closeBracket = try matchingBracket(startingAt: openBracket, in: text)
        var metadataIndex = text.index(after: closeBracket)
        while metadataIndex < text.endIndex, text[metadataIndex].isWhitespace {
            metadataIndex = text.index(after: metadataIndex)
        }
        guard metadataIndex < text.endIndex, text[metadataIndex] == "(" else {
            return nil
        }
        let closeParenthesis = try matchingParenthesis(startingAt: metadataIndex, in: text)
        let metadataBody = String(text[text.index(after: metadataIndex)..<closeParenthesis])
        return try parseOptionalString(named: metadataName, in: metadataBody)
    }

    private func parsePointArray(named name: String, in text: String) throws -> [USDPoint3D] {
        let body = try bracketArrayBody(named: name, in: text)
        return try parsePointTuples(named: name, in: body)
    }

    private func parseOptionalPointArray(named name: String, in text: String) throws -> [USDPoint3D]? {
        guard let body = try optionalBracketArrayBody(named: name, in: text) else {
            return nil
        }
        return try parsePointTuples(named: name, in: body)
    }

    private func parseOptionalPoint2Array(named name: String, in text: String) throws -> [USDPoint2D]? {
        guard let body = try optionalBracketArrayBody(named: name, in: text) else {
            return nil
        }
        return try parsePoint2Tuples(named: name, in: body)
    }

    private func parseOptionalColorArray(named name: String, in text: String) throws -> [USDColorRGB]? {
        guard let body = try optionalBracketArrayBody(named: name, in: text) else {
            return nil
        }
        return try parseColorTuples(named: name, in: body)
    }

    private func parseOptionalDoubleArray(named name: String, in text: String) throws -> [Double]? {
        guard let body = try optionalBracketArrayBody(named: name, in: text) else {
            return nil
        }
        return try parseDoubleTokens(named: name, in: body)
    }

    private func parseRequiredScalar(named name: String, in text: String) throws -> Double {
        guard let nameRange = attributeNameRange(named: name, in: text) else {
            throw USDImportError.missingRequiredField(name)
        }
        guard let equalSign = text[nameRange.upperBound...].firstIndex(of: "=") else {
            throw USDImportError.invalidData("USDA \(name) is missing an assignment.")
        }
        var valueStart = text.index(after: equalSign)
        skipWhitespace(in: text, index: &valueStart)
        var valueEnd = valueStart
        while valueEnd < text.endIndex {
            let character = text[valueEnd]
            if character.isWhitespace
                || character == ","
                || character == ")"
                || character == "]"
                || character == "("
                || character == "{" {
                break
            }
            valueEnd = text.index(after: valueEnd)
        }
        guard valueStart < valueEnd,
              let value = Double(text[valueStart..<valueEnd]),
              value.isFinite else {
            throw USDImportError.invalidData("USDA \(name) contains a non-finite number.")
        }
        return value
    }

    private func parseRequiredVector3(named name: String, in text: String) throws -> USDTransformVector3D {
        let values = try parseRequiredTuple(named: name, expectedCount: 3, in: text)
        return USDTransformVector3D(x: values[0], y: values[1], z: values[2])
    }

    private func parseRequiredQuaternion(named name: String, in text: String) throws -> USDTransformQuaternion {
        let values = try parseRequiredTuple(named: name, expectedCount: 4, in: text)
        return USDTransformQuaternion(
            real: values[0],
            imaginaryX: values[1],
            imaginaryY: values[2],
            imaginaryZ: values[3]
        )
    }

    private func parseRequiredMatrix4x4(named name: String, in text: String) throws -> USDTransformMatrix4x4 {
        let values = try parseRequiredTuple(named: name, expectedCount: 16, in: text)
        return USDTransformMatrix4x4(values: values)
    }

    private func parseRequiredTuple(
        named name: String,
        expectedCount: Int,
        in text: String
    ) throws -> [Double] {
        guard let nameRange = attributeNameRange(named: name, in: text) else {
            throw USDImportError.missingRequiredField(name)
        }
        guard let equalSign = text[nameRange.upperBound...].firstIndex(of: "=") else {
            throw USDImportError.invalidData("USDA \(name) is missing an assignment.")
        }
        guard let openParenthesis = text[equalSign...].firstIndex(of: "(") else {
            throw USDImportError.invalidData("USDA \(name) is missing an opening parenthesis.")
        }
        let closeParenthesis = try matchingParenthesis(startingAt: openParenthesis, in: text)
        let body = String(text[text.index(after: openParenthesis)..<closeParenthesis])
        let values = try parseDoubleLiterals(named: name, in: body)
        guard values.count == expectedCount else {
            throw USDImportError.invalidData("USDA \(name) tuple contains \(values.count) values.")
        }
        return values
    }

    private func parsePointTuples(named name: String, in body: String) throws -> [USDPoint3D] {
        let expression = try NSRegularExpression(pattern: "\\(([^)]*)\\)")
        let range = NSRange(body.startIndex..<body.endIndex, in: body)
        let matches = expression.matches(in: body, range: range)
        guard !matches.isEmpty else {
            throw USDImportError.invalidData("USDA \(name) contains no point tuples.")
        }
        return try matches.map { match in
            let tuple = String(body[Range(match.range(at: 1), in: body)!])
            let parts = tuple.split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            guard parts.count == 3,
                  let x = Double(parts[0]),
                  let y = Double(parts[1]),
                  let z = Double(parts[2]),
                  x.isFinite,
                  y.isFinite,
                  z.isFinite else {
                throw USDImportError.invalidData("USDA point tuple is malformed.")
            }
            return USDPoint3D(x: x, y: y, z: z)
        }
    }

    private func parsePoint2Tuples(named name: String, in body: String) throws -> [USDPoint2D] {
        let expression = try NSRegularExpression(pattern: "\\(([^)]*)\\)")
        let range = NSRange(body.startIndex..<body.endIndex, in: body)
        let matches = expression.matches(in: body, range: range)
        guard !matches.isEmpty else {
            throw USDImportError.invalidData("USDA \(name) contains no point tuples.")
        }
        return try matches.map { match in
            let tuple = String(body[Range(match.range(at: 1), in: body)!])
            let parts = tuple.split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            guard parts.count == 2,
                  let x = Double(parts[0]),
                  let y = Double(parts[1]),
                  x.isFinite,
                  y.isFinite else {
                throw USDImportError.invalidData("USDA point2 tuple is malformed.")
            }
            return USDPoint2D(x: x, y: y)
        }
    }

    private func parseColorTuples(named name: String, in body: String) throws -> [USDColorRGB] {
        let expression = try NSRegularExpression(pattern: "\\(([^)]*)\\)")
        let range = NSRange(body.startIndex..<body.endIndex, in: body)
        let matches = expression.matches(in: body, range: range)
        guard !matches.isEmpty else {
            throw USDImportError.invalidData("USDA \(name) contains no color tuples.")
        }
        return try matches.map { match in
            let tuple = String(body[Range(match.range(at: 1), in: body)!])
            let parts = tuple.split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            guard parts.count == 3,
                  let r = Double(parts[0]),
                  let g = Double(parts[1]),
                  let b = Double(parts[2]),
                  r.isFinite,
                  g.isFinite,
                  b.isFinite else {
                throw USDImportError.invalidData("USDA color tuple is malformed.")
            }
            return USDColorRGB(r: r, g: g, b: b)
        }
    }

    private func parseIntArray(named name: String, in text: String) throws -> [Int] {
        let body = try bracketArrayBody(named: name, in: text)
        return try parseIntTokens(named: name, in: body)
    }

    private func parseOptionalIntArray(named name: String, in text: String) throws -> [Int]? {
        guard let body = try optionalBracketArrayBody(named: name, in: text) else {
            return nil
        }
        return try parseIntTokens(named: name, in: body)
    }

    private func parseIntTokens(named name: String, in body: String) throws -> [Int] {
        let tokens = body.split { character in
            character == "," || character.isWhitespace || character.isNewline
        }
        guard !tokens.isEmpty else {
            throw USDImportError.invalidData("USDA \(name) is empty.")
        }
        return try tokens.map { token in
            guard let value = Int(token) else {
                throw USDImportError.invalidData("USDA \(name) contains a non-integer value.")
            }
            return value
        }
    }

    private func parseDoubleTokens(named name: String, in body: String) throws -> [Double] {
        let tokens = body.split { character in
            character == "," || character.isWhitespace || character.isNewline
        }
        guard !tokens.isEmpty else {
            throw USDImportError.invalidData("USDA \(name) is empty.")
        }
        return try tokens.map { token in
            guard let value = Double(token), value.isFinite else {
                throw USDImportError.invalidData("USDA \(name) contains a non-finite number.")
            }
            return value
        }
    }

    private func parseDoubleLiterals(named name: String, in body: String) throws -> [Double] {
        let pattern = "[-+]?(?:\\d+(?:\\.\\d*)?|\\.\\d+)(?:[eE][-+]?\\d+)?"
        let expression = try NSRegularExpression(pattern: pattern)
        let range = NSRange(body.startIndex..<body.endIndex, in: body)
        let matches = expression.matches(in: body, range: range)
        guard !matches.isEmpty else {
            throw USDImportError.invalidData("USDA \(name) is empty.")
        }
        return try matches.map { match in
            guard let valueRange = Range(match.range, in: body),
                  let value = Double(body[valueRange]),
                  value.isFinite else {
                throw USDImportError.invalidData("USDA \(name) contains a non-finite number.")
            }
            return value
        }
    }

    private func bracketArrayBody(named name: String, in text: String) throws -> String {
        guard let nameRange = attributeNameRange(named: name, in: text) else {
            throw USDImportError.missingRequiredField(name)
        }
        return try bracketArrayBody(after: nameRange.upperBound, named: name, in: text)
    }

    private func optionalBracketArrayBody(named name: String, in text: String) throws -> String? {
        guard let nameRange = attributeNameRange(named: name, in: text) else {
            return nil
        }
        return try bracketArrayBody(after: nameRange.upperBound, named: name, in: text)
    }

    private func bracketArrayBody(after index: String.Index, named name: String, in text: String) throws -> String {
        guard let openBracket = text[index...].firstIndex(of: "[") else {
            throw USDImportError.invalidData("USDA \(name) is missing an opening bracket.")
        }
        let closeBracket = try matchingBracket(startingAt: openBracket, in: text)
        return String(text[text.index(after: openBracket)..<closeBracket])
    }

    private func attributeNameRange(named name: String, in text: String) -> Range<String.Index>? {
        var searchRange = text.startIndex..<text.endIndex
        while let range = text.range(of: name, range: searchRange) {
            let hasValidLeadingBoundary: Bool
            if range.lowerBound == text.startIndex {
                hasValidLeadingBoundary = true
            } else {
                let previous = text[text.index(before: range.lowerBound)]
                hasValidLeadingBoundary = previous.isWhitespace || previous == "]" || previous == "(" || previous == ","
            }

            let hasValidTrailingBoundary: Bool
            if range.upperBound == text.endIndex {
                hasValidTrailingBoundary = true
            } else {
                let next = text[range.upperBound]
                hasValidTrailingBoundary = next.isWhitespace || next == "=" || next == "[" || next == "("
            }

            if hasValidLeadingBoundary && hasValidTrailingBoundary {
                return range
            }
            searchRange = range.upperBound..<text.endIndex
        }
        return nil
    }

    private func matchingBrace(startingAt openBrace: String.Index, in text: String) throws -> String.Index {
        try matchingDelimiter(startingAt: openBrace, open: "{", close: "}", in: text)
    }

    private func matchingBracket(startingAt openBracket: String.Index, in text: String) throws -> String.Index {
        try matchingDelimiter(startingAt: openBracket, open: "[", close: "]", in: text)
    }

    private func matchingParenthesis(startingAt openParenthesis: String.Index, in text: String) throws -> String.Index {
        try matchingDelimiter(startingAt: openParenthesis, open: "(", close: ")", in: text)
    }

    private func matchingDelimiter(
        startingAt openIndex: String.Index,
        open: Character,
        close: Character,
        in text: String
    ) throws -> String.Index {
        var depth = 0
        var index = openIndex
        var isInsideString = false
        while index < text.endIndex {
            let character = text[index]
            if character == "\"" {
                isInsideString.toggle()
            } else if !isInsideString, character == open {
                depth += 1
            } else if !isInsideString, character == close {
                depth -= 1
                if depth == 0 {
                    return index
                }
            }
            index = text.index(after: index)
        }
        throw USDImportError.invalidData("USDA delimiter is unterminated.")
    }

    private func firstMatch(pattern: String, in text: String) throws -> String? {
        let expression = try NSRegularExpression(pattern: pattern)
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = expression.firstMatch(in: text, range: range),
              match.numberOfRanges > 1,
              let valueRange = Range(match.range(at: 1), in: text) else {
            return nil
        }
        return String(text[valueRange])
    }
}

private struct USDAPrim {
    var typeName: String?
    var name: String?
    var body: String
    var fullRange: Range<String.Index>
}

private struct USDALocalTransform {
    var matrix: USDTransformMatrix4x4
    var resetsParentStack: Bool
}

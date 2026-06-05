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
        var meshes: [USDMesh] = []
        var searchIndex = text.startIndex
        while let meshRange = text.range(of: "def Mesh", range: searchIndex..<text.endIndex) {
            let name = try parsePrimName(after: meshRange.upperBound, in: text)
            guard let openBrace = text[meshRange.upperBound...].firstIndex(of: "{") else {
                throw USDImportError.invalidData("USDA Mesh prim is missing an opening brace.")
            }
            let closeBrace = try matchingBrace(startingAt: openBrace, in: text)
            let body = String(text[text.index(after: openBrace)..<closeBrace])
            let points = try parsePointArray(named: "points", in: body)
            let counts = try parseIntArray(named: "faceVertexCounts", in: body)
            let indices = try parseIntArray(named: "faceVertexIndices", in: body)
            let normals = try parseOptionalPointArray(named: "normals", in: body) ?? []
            let normalsInterpolation = try parseOptionalAttributeMetadataString(
                attributeName: "normals",
                metadataName: "interpolation",
                in: body
            )
            let orientation = try parseOptionalOrientation(in: body)
            let subdivisionScheme = try parseOptionalString(named: "subdivisionScheme", in: body)
            let textureCoordinates = try parseOptionalTextureCoordinates(in: body)
            if let textureCoordinates {
                try textureCoordinates.validate(pointCount: points.count, faceVertexCounts: counts)
            }
            let extent = try parseOptionalPointArray(named: "extent", in: body)
            if let extent, extent.count != 2 {
                throw USDImportError.invalidData("USDA extent must contain exactly two points.")
            }
            meshes.append(USDMesh(
                name: name,
                points: points,
                faceVertexCounts: counts,
                faceVertexIndices: indices,
                normals: normals,
                normalsInterpolation: normalsInterpolation,
                orientation: orientation,
                subdivisionScheme: subdivisionScheme,
                textureCoordinates: textureCoordinates,
                extent: extent
            ))
            searchIndex = text.index(after: closeBrace)
        }
        return meshes
    }

    private func parsePrimName(after index: String.Index, in text: String) throws -> String? {
        guard let quoteStart = text[index...].firstIndex(of: "\"") else {
            return nil
        }
        guard let quoteEnd = text[text.index(after: quoteStart)...].firstIndex(of: "\"") else {
            throw USDImportError.invalidData("USDA prim name is unterminated.")
        }
        return String(text[text.index(after: quoteStart)..<quoteEnd])
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

    private func parseOptionalString(named name: String, in text: String) throws -> String? {
        let pattern = "\\b\(NSRegularExpression.escapedPattern(for: name))\\s*=\\s*\"([^\"]*)\""
        return try firstMatch(pattern: pattern, in: text)
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

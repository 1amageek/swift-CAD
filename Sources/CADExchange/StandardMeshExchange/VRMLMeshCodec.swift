import Foundation
import CADCore
import CADIR

extension StandardMeshExchange {
    func readVRML(_ data: Data, resources: inout ExchangeResourceAccountant) throws -> ImportedExchangeModel {
        try resources.recordBytes(data.count, label: "VRML text storage")
        guard let text = String(data: data, encoding: .utf8),
              text.hasPrefix("#VRML V2.0 utf8") else { throw ImportError.unsupportedVersion("Only VRML97 UTF-8 is supported.") }
        var parser = try VRMLParser(text: text, resources: &resources)
        var roots: [VRMLNode] = []
        while !parser.isAtEnd { roots.append(try parser.node(depth: 1, resources: &resources)) }
        var meshes: [BodyID: Mesh] = [:]
        func visit(_ node: VRMLNode, placement: MeshPlacement, depth: Int) throws {
            try resources.checkTime()
            try resources.recordEntities()
            try resources.validateNestingDepth(depth)
            switch node.kind {
            case "Group", "Transform":
                let allowed: Set<String> = node.kind == "Group" ? ["children", "bboxCenter", "bboxSize"] : ["children", "translation", "rotation", "scale", "center", "scaleOrientation", "bboxCenter", "bboxSize"]
                try node.admit(allowed)
                var local = MeshPlacement.identity
                if node.kind == "Transform" {
                    let t = try node.vector("translation", fallback: [0, 0, 0])
                    let c = try node.vector("center", fallback: [0, 0, 0])
                    let r = try node.vector("rotation", fallback: [0, 0, 1, 0])
                    let sr = try node.vector("scaleOrientation", fallback: [0, 0, 1, 0])
                    let s = try node.vector("scale", fallback: [1, 1, 1])
                    guard s.allSatisfy({ $0 > 0 }) else { throw ImportError.invalidData("VRML scale must be positive.") }
                    var inverseSR = sr; inverseSR[3] = -sr[3]
                    local = MeshPlacement.translation(t).multiplied(by: .translation(c))
                        .multiplied(by: try .axisAngle(r)).multiplied(by: try .axisAngle(sr))
                        .multiplied(by: .scale(s)).multiplied(by: try .axisAngle(inverseSR))
                        .multiplied(by: .translation(c.map { -$0 }))
                }
                for child in try node.children() { try visit(child, placement: placement.multiplied(by: local), depth: depth + 1) }
            case "Shape":
                try node.admit(["geometry", "appearance"])
                if let appearance = node.fields["appearance"], !appearance.isNull { throw ImportError.unsupportedFeature("VRML appearance/material semantics cannot be retained by Mesh.") }
                guard let geometry = node.child("geometry"), geometry.kind == "IndexedFaceSet" else { throw ImportError.unsupportedFeature("VRML Shape requires IndexedFaceSet geometry.") }
                let mesh = try vrmlIndexedFaceSet(geometry, resources: &resources)
                try meshStorageAdmission(vertexCount: mesh.positions.count, indexCount: mesh.indices.count, resources: &resources)
                meshes[BodyID()] = try placement.applying(to: mesh, tolerance: tolerance)
            default: throw ImportError.unsupportedFeature("Unsupported VRML scene node \(node.kind).")
            }
        }
        for root in roots { try visit(root, placement: .identity, depth: 1) }
        guard !meshes.isEmpty else { throw ImportError.invalidData("VRML scene contains no mesh geometry.") }
        return ImportedExchangeModel(format: .vrml, meshes: meshes, units: .meters)
    }

    func vrmlIndexedFaceSet(_ node: VRMLNode, resources: inout ExchangeResourceAccountant) throws -> Mesh {
        try node.admit(["coord", "coordIndex", "normal", "normalIndex", "normalPerVertex", "color", "colorIndex", "colorPerVertex", "texCoord", "texCoordIndex", "ccw", "solid", "convex", "creaseAngle"])
        guard try node.boolean("solid", fallback: true), try node.scalar("creaseAngle", fallback: 0) == 0 else {
            throw ImportError.unsupportedFeature("VRML double-sided/implicit smooth-normal semantics cannot be preserved.")
        }
        let ccw = try node.boolean("ccw", fallback: true)
        let normalPerVertex = try node.boolean("normalPerVertex", fallback: true)
        let colorPerVertex = try node.boolean("colorPerVertex", fallback: true)
        guard let coordinate = node.child("coord"), coordinate.kind == "Coordinate" else { throw ImportError.invalidData("VRML mesh requires Coordinate.") }
        try coordinate.admit(["point"])
        let xyz = try coordinate.numbers("point")
        guard !xyz.isEmpty, xyz.count.isMultiple(of: 3) else { throw ImportError.invalidData("VRML coordinate dimension mismatch.") }
        let points = stride(from: 0, to: xyz.count, by: 3).map { Point3D(x: xyz[$0], y: xyz[$0 + 1], z: xyz[$0 + 2]) }
        func values(_ field: String, kind: String, array: String, components: Int) throws -> [[Double]] {
            guard let child = node.child(field) else {
                if let raw = node.fields[field], !raw.isNull { throw ImportError.invalidData("Invalid VRML attribute node.") }
                return []
            }
            guard child.kind == kind else { throw ImportError.unsupportedFeature("Unsupported VRML \(field) node.") }
            try child.admit([array])
            let values = try child.numbers(array)
            guard values.count.isMultiple(of: components) else { throw ImportError.invalidData("VRML attribute dimension mismatch.") }
            return stride(from: 0, to: values.count, by: components).map { Array(values[$0..<($0 + components)]) }
        }
        let normals = try values("normal", kind: "Normal", array: "vector", components: 3)
        let colors = try values("color", kind: "Color", array: "color", components: 3)
        let uv = try values("texCoord", kind: "TextureCoordinate", array: "point", components: 2)
        let faces = try vrmlFaces(node.integers("coordIndex"), allowEmpty: false)
        let normalIndices = try node.integers("normalIndex")
        let colorIndices = try node.integers("colorIndex")
        let uvIndices = try node.integers("texCoordIndex")
        guard !normals.isEmpty || normalIndices.isEmpty,
              !colors.isEmpty || colorIndices.isEmpty,
              !uv.isEmpty || uvIndices.isEmpty else { throw ImportError.invalidData("VRML attribute indices lack values.") }
        let normalFaces = normalPerVertex ? try vrmlFaces(normalIndices, allowEmpty: true) : []
        let colorFaces = colorPerVertex ? try vrmlFaces(colorIndices, allowEmpty: true) : []
        let uvFaces = try vrmlFaces(uvIndices, allowEmpty: true)
        for layout in [normalFaces, colorFaces, uvFaces] where !layout.isEmpty {
            guard layout.count == faces.count, zip(layout, faces).allSatisfy({ $0.count == $1.count }) else { throw ImportError.invalidData("VRML independently indexed attributes disagree with faces.") }
        }
        for (indices, perVertex) in [(normalIndices, normalPerVertex), (colorIndices, colorPerVertex)] where !perVertex && !indices.isEmpty {
            guard indices.count == faces.count, indices.allSatisfy({ $0 >= 0 }) else { throw ImportError.invalidData("VRML per-face attribute indices are invalid.") }
        }
        var result = Mesh()
        var referenced = Set<Int>()
        let triangulator = ExchangePolygonTriangulator()
        for (faceIndex, face) in faces.enumerated() {
            try resources.recordIterations(meshResourceProduct(face.count, face.count, format: .vrml))
            guard face.allSatisfy({ points.indices.contains($0) }) else { throw ImportError.invalidData("VRML coordIndex out of range.") }
            referenced.formUnion(face)
            let triangles = try triangulator.triangles(for: face.map { points[$0] }, tolerance: tolerance)
            let corners = try meshResourceProduct(triangles.count, 3, format: .vrml)
            try meshStorageAdmission(vertexCount: corners, indexCount: corners, resources: &resources)
            func attributeIndex(_ layouts: [[Int]], raw: [Int], perVertex: Bool, corner: Int, valueCount: Int) throws -> Int {
                let index = perVertex ? (layouts.isEmpty ? face[corner] : layouts[faceIndex][corner]) : (raw.isEmpty ? faceIndex : raw[faceIndex])
                guard index >= 0, index < valueCount else { throw ImportError.invalidData("VRML attribute index out of range.") }
                return index
            }
            for triangle in triangles {
                for corner in ccw ? [triangle.0, triangle.1, triangle.2] : [triangle.0, triangle.2, triangle.1] {
                    guard UInt64(result.positions.count) < UInt64(UInt32.max) else { throw ImportError.invalidData("VRML vertex index overflow.") }
                    result.indices.append(UInt32(result.positions.count))
                    result.positions.append(points[face[corner]])
                    if !normals.isEmpty {
                        let v = normals[try attributeIndex(normalFaces, raw: normalIndices, perVertex: normalPerVertex, corner: corner, valueCount: normals.count)]
                        let n = Vector3D(x: v[0], y: v[1], z: v[2])
                        guard n.length > 0, n.length.isFinite else { throw ImportError.invalidData("Invalid VRML normal.") }
                        result.normals.append(n / n.length)
                    }
                    if !colors.isEmpty {
                        let c = colors[try attributeIndex(colorFaces, raw: colorIndices, perVertex: colorPerVertex, corner: corner, valueCount: colors.count)]
                        result.vertexColors.append(ColorRGBA(r: c[0], g: c[1], b: c[2], a: 1))
                    }
                    if !uv.isEmpty {
                        let t = uv[try attributeIndex(uvFaces, raw: uvIndices, perVertex: true, corner: corner, valueCount: uv.count)]
                        result.textureCoordinates.append(Point2D(x: t[0], y: t[1]))
                    }
                }
            }
        }
        guard referenced.count == points.count else { throw ImportError.unsupportedFeature("Unreferenced VRML coordinates would be lost.") }
        try validateImportedMesh(result, formatName: "VRML", tolerance: tolerance)
        return result
    }

    func writeVRML(_ meshes: [Mesh], resources: inout ExchangeResourceAccountant) throws -> Data {
        var output = Data()
        try meshBoundedAppend("#VRML V2.0 utf8\n", to: &output, resources: &resources)
        for mesh in meshes {
            guard mesh.vertexColors.allSatisfy({ $0.a == 1 }) else { throw ExportError.unsupportedFeature("VRML Color cannot preserve vertex alpha.") }
            try meshBoundedAppend("Shape { geometry IndexedFaceSet { solid TRUE ccw TRUE\ncoord Coordinate { point [\n", to: &output, resources: &resources)
            for p in mesh.positions { try meshBoundedAppend("\(p.x) \(p.y) \(p.z),\n", to: &output, resources: &resources) }
            try meshBoundedAppend("] }\ncoordIndex [\n", to: &output, resources: &resources)
            for i in stride(from: 0, to: mesh.indices.count, by: 3) { try meshBoundedAppend("\(mesh.indices[i]) \(mesh.indices[i+1]) \(mesh.indices[i+2]) -1,\n", to: &output, resources: &resources) }
            try meshBoundedAppend("]\n", to: &output, resources: &resources)
            if !mesh.normals.isEmpty {
                try meshBoundedAppend("normalPerVertex TRUE normal Normal { vector [\n", to: &output, resources: &resources)
                for n in mesh.normals { try meshBoundedAppend("\(n.x) \(n.y) \(n.z),\n", to: &output, resources: &resources) }
                try meshBoundedAppend("] }\n", to: &output, resources: &resources)
            }
            if !mesh.textureCoordinates.isEmpty {
                try meshBoundedAppend("texCoord TextureCoordinate { point [\n", to: &output, resources: &resources)
                for t in mesh.textureCoordinates { try meshBoundedAppend("\(t.x) \(t.y),\n", to: &output, resources: &resources) }
                try meshBoundedAppend("] }\n", to: &output, resources: &resources)
            }
            if !mesh.vertexColors.isEmpty {
                try meshBoundedAppend("colorPerVertex TRUE color Color { color [\n", to: &output, resources: &resources)
                for c in mesh.vertexColors { try meshBoundedAppend("\(c.r) \(c.g) \(c.b),\n", to: &output, resources: &resources) }
                try meshBoundedAppend("] }\n", to: &output, resources: &resources)
            }
            try meshBoundedAppend("} }\n", to: &output, resources: &resources)
        }
        return output
    }
}

private indirect enum VRMLValue {
    case tokens([String])
    case node(VRMLNode)
    case nodes([VRMLNode])
    case null
    var isNull: Bool { if case .null = self { return true }; return false }
}

struct VRMLNode {
    let kind: String
    fileprivate var fields: [String: VRMLValue]
    func admit(_ allowed: Set<String>) throws {
        if let field = fields.keys.first(where: { !allowed.contains($0) }) { throw ImportError.unsupportedFeature("Unrepresented VRML field \(field).") }
    }
    func child(_ key: String) -> VRMLNode? { if case .node(let node) = fields[key] { return node }; return nil }
    func children() throws -> [VRMLNode] {
        if fields["children"] == nil { return [] }
        if case .nodes(let nodes) = fields["children"] { return nodes }
        throw ImportError.invalidData("Invalid VRML children.")
    }
    func numbers(_ key: String) throws -> [Double] {
        guard let value = fields[key] else { return [] }
        guard case .tokens(let tokens) = value else { throw ImportError.invalidData("Invalid VRML numeric field.") }
        return try tokens.map { token in
            guard let v = Double(token), v.isFinite else { throw ImportError.invalidData("Invalid VRML number.") }; return v
        }
    }
    func integers(_ key: String) throws -> [Int] {
        try numbers(key).map { v in
            guard v >= -1, v < Double(Int.max), v.rounded(.towardZero) == v else { throw ImportError.invalidData("Invalid VRML index.") }; return Int(v)
        }
    }
    func vector(_ key: String, fallback: [Double]) throws -> [Double] {
        if fields[key] == nil { return fallback }
        let v = try numbers(key)
        guard v.count == fallback.count else { throw ImportError.invalidData("Invalid VRML vector dimension.") }; return v
    }
    func scalar(_ key: String, fallback: Double) throws -> Double { try vector(key, fallback: [fallback])[0] }
    func boolean(_ key: String, fallback: Bool) throws -> Bool {
        guard let value = fields[key] else { return fallback }
        guard case .tokens(let tokens) = value, tokens.count == 1, ["TRUE", "FALSE"].contains(tokens[0]) else { throw ImportError.invalidData("Invalid VRML boolean.") }
        return tokens[0] == "TRUE"
    }
}

private func vrmlFaces(_ values: [Int], allowEmpty: Bool) throws -> [[Int]] {
    if values.isEmpty, allowEmpty { return [] }
    var faces: [[Int]] = []; var current: [Int] = []
    for i in values {
        if i == -1 {
            guard current.count >= 3 else { throw ImportError.invalidData("VRML polygon has fewer than three vertices.") }
            faces.append(current); current = []
        } else { current.append(i) }
    }
    if !current.isEmpty {
        guard current.count >= 3 else { throw ImportError.invalidData("VRML polygon is incomplete.") }; faces.append(current)
    }
    guard !faces.isEmpty else { throw ImportError.invalidData("VRML mesh contains no faces.") }; return faces
}

private struct VRMLParser {
    var tokens: [String] = []
    var index = 0
    var definitions: [String: VRMLNode] = [:]
    var isAtEnd: Bool { index == tokens.count }
    init(text: String, resources: inout ExchangeResourceAccountant) throws {
        var token = "", comment = false
        func flush() throws {
            if !token.isEmpty {
                try resources.recordEntities(); try resources.recordBytes(token.utf8.count + 24, label: "VRML token storage")
                tokens.append(token); token = ""
            }
        }
        for character in text {
            try resources.recordIterations()
            if comment { if character.isNewline { comment = false }; continue }
            if character == "#" { try flush(); comment = true }
            else if character.isWhitespace || character == "," { try flush() }
            else if ["{", "}", "[", "]"].contains(character) { try flush(); try resources.recordEntities(); tokens.append(String(character)) }
            else { token.append(character) }
        }
        try flush()
    }
    mutating func take() throws -> String {
        guard tokens.indices.contains(index) else { throw ImportError.invalidData("Incomplete VRML node.") }
        defer { index += 1 }; return tokens[index]
    }
    mutating func expect(_ value: String) throws {
        guard try take() == value else { throw ImportError.invalidData("Expected VRML \(value).") }
    }
    mutating func node(depth: Int, resources: inout ExchangeResourceAccountant) throws -> VRMLNode {
        try resources.validateNestingDepth(depth); try resources.recordIterations()
        var kind = try take()
        var definition: String?
        if kind == "USE" {
            let name = try take()
            guard let node = definitions[name] else { throw ImportError.invalidData("Unknown or recursive VRML USE.") }; return node
        }
        if kind == "DEF" {
            definition = try take(); kind = try take()
            guard definitions[definition!] == nil else { throw ImportError.invalidData("Duplicate VRML DEF.") }
        }
        guard ["Group", "Transform", "Shape", "IndexedFaceSet", "Coordinate", "Normal", "Color", "TextureCoordinate"].contains(kind) else {
            throw ImportError.unsupportedFeature("Unsupported VRML node \(kind).")
        }
        try expect("{")
        var fields: [String: VRMLValue] = [:]
        while tokens.indices.contains(index), tokens[index] != "}" {
            let key = try take()
            guard fields[key] == nil else { throw ImportError.invalidData("Duplicate VRML field.") }
            if ["coord", "normal", "color", "texCoord", "geometry", "appearance"].contains(key), !(kind == "Color" && key == "color") {
                if tokens.indices.contains(index), tokens[index] == "NULL" { index += 1; fields[key] = .null }
                else { fields[key] = .node(try node(depth: depth + 1, resources: &resources)) }
            } else if key == "children" {
                var children: [VRMLNode] = []
                if tokens.indices.contains(index), tokens[index] == "[" {
                    index += 1
                    while tokens.indices.contains(index), tokens[index] != "]" { children.append(try node(depth: depth + 1, resources: &resources)) }
                    try expect("]")
                } else { children.append(try node(depth: depth + 1, resources: &resources)) }
                fields[key] = .nodes(children)
            } else {
                var values: [String] = []
                if tokens.indices.contains(index), tokens[index] == "[" {
                    index += 1
                    while tokens.indices.contains(index), tokens[index] != "]" { values.append(try take()) }
                    try expect("]")
                } else {
                    let count: Int
                    if ["translation", "scale", "center", "bboxCenter", "bboxSize"].contains(key) { count = 3 }
                    else if ["rotation", "scaleOrientation"].contains(key) { count = 4 }
                    else if ["ccw", "solid", "convex", "normalPerVertex", "colorPerVertex", "creaseAngle"].contains(key) { count = 1 }
                    else { throw ImportError.unsupportedFeature("Unsupported VRML field \(key).") }
                    for _ in 0..<count { values.append(try take()) }
                }
                fields[key] = .tokens(values)
            }
        }
        try expect("}")
        let result = VRMLNode(kind: kind, fields: fields)
        if let definition { definitions[definition] = result }
        return result
    }
}

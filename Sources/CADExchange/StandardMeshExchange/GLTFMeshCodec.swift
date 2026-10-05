import Foundation
import CoreFoundation
import CADCore
import CADIR

extension StandardMeshExchange {
    func readGLTF(_ data: Data, format: ExchangeFileFormat,
                  resolver: (any StandardMeshBufferResolving)?,
                  resources: inout ExchangeResourceAccountant) throws -> ImportedExchangeModel {
        var json = data
        var bin: Data?
        if format == .glb {
            guard data.count >= 20,
                  try meshUInt(data, offset: 0, width: 4) == 0x46546c67,
                  try meshUInt(data, offset: 4, width: 4) == 2,
                  try meshUInt(data, offset: 8, width: 4) == UInt64(data.count) else {
                throw ImportError.invalidData("Invalid GLB 2 header or length.")
            }
            var offset = 12
            var chunk = 0
            while offset < data.count {
                try resources.recordIterations()
                let length = Int(try meshUInt(data, offset: offset, width: 4))
                let kind = try meshUInt(data, offset: offset + 4, width: 4)
                guard length.isMultiple(of: 4), length <= data.count - offset - 8 else {
                    throw ImportError.invalidData("Invalid GLB chunk length.")
                }
                try resources.recordBytes(length, label: "GLB chunk storage")
                let content = data.subdata(in: (offset + 8)..<(offset + 8 + length))
                if chunk == 0, kind == 0x4e4f534a { json = content }
                else if chunk == 1, kind == 0x004e4942 { bin = content }
                else { throw ImportError.unsupportedFeature("Unknown or reordered GLB chunk.") }
                chunk += 1
                offset += 8 + length
            }
        }
        try admitMeshJSON(json, resources: &resources)
        try resources.recordBytes(json.count, label: "JSON string storage")
        let raw: Any
        do { raw = try JSONSerialization.jsonObject(with: json) }
        catch { throw ImportError.invalidData("Malformed glTF JSON: \(error.localizedDescription)") }
        guard let root = raw as? [String: Any], let asset = root["asset"] as? [String: Any],
              asset["version"] as? String == "2.0" else {
            throw ImportError.unsupportedVersion("Only glTF 2.0 is supported.")
        }
        try meshUnsupportedKeys(root, allowed: ["asset", "buffers", "bufferViews", "accessors", "meshes", "nodes", "scenes", "scene"])
        try meshUnsupportedKeys(asset, allowed: ["version", "minVersion", "generator", "copyright"])
        if let version = asset["minVersion"] as? String, version != "2.0" {
            throw ImportError.unsupportedVersion(version)
        }
        let bufferObjects = try meshObjects(root["buffers"], label: "buffers")
        var buffers: [Data] = []
        for (i, object) in bufferObjects.enumerated() {
            try resources.checkTime()
            try meshUnsupportedKeys(object, allowed: ["byteLength", "uri", "name"])
            let length = try meshInteger(object["byteLength"], label: "buffer byteLength")
            guard length > 0, length <= resources.limits.maximumBytes - resources.byteCount else {
                throw exchangeResourceLimitError(format: format, detail: "buffer allocation exceeds the byte limit.")
            }
            let buffer: Data
            if let uri = object["uri"] as? String {
                if uri.hasPrefix("data:") {
                    guard let comma = uri.firstIndex(of: ","),
                          ["data:application/octet-stream;base64", "data:application/gltf-buffer;base64"].contains(String(uri[..<comma])) else {
                        throw ImportError.unsupportedFeature("Unsupported glTF data URI encoding.")
                    }
                    let encoded = uri[uri.index(after: comma)...]
                    guard encoded.utf8.count <= ((length + 2) / 3) * 4,
                          let decoded = Data(base64Encoded: String(encoded)), decoded.count == length else {
                        throw ImportError.invalidData("glTF data URI length does not match buffer byteLength.")
                    }
                    buffer = decoded
                } else {
                    guard let resolver else { throw ImportError.resourceUnavailable("External glTF buffer requires a resolver.") }
                    buffer = try resolver.readBuffer(uri: uri, maximumBytes: length)
                }
                guard buffer.count == length else { throw ImportError.invalidData("glTF external buffer length mismatch.") }
            } else {
                guard i == 0, let bin, bin.count >= length, bin.count - length <= 3 else {
                    throw ImportError.invalidData("glTF buffer has no valid BIN chunk or URI.")
                }
                buffer = bin.prefix(length)
            }
            try resources.recordBytes(buffer.count, label: "decoded buffers")
            buffers.append(buffer)
        }
        if bin != nil, bufferObjects.first?["uri"] != nil {
            throw ImportError.invalidData("GLB BIN chunk is not referenced by its first buffer.")
        }
        let views = try meshObjects(root["bufferViews"], label: "bufferViews")
        let accessors = try meshObjects(root["accessors"], label: "accessors")
        let sourceObjects = try meshObjects(root["meshes"], label: "meshes")
        guard !sourceObjects.isEmpty else { throw ImportError.invalidData("glTF contains no meshes.") }
        var sourceMeshes: [[Mesh]] = []
        for object in sourceObjects {
            try meshUnsupportedKeys(object, allowed: ["primitives", "name"])
            let primitives = try meshObjects(object["primitives"], label: "primitives")
            guard !primitives.isEmpty else { throw ImportError.invalidData("glTF mesh contains no primitives.") }
            var meshes: [Mesh] = []
            for primitive in primitives {
                try meshUnsupportedKeys(primitive, allowed: ["attributes", "indices", "mode"])
                guard try meshInteger(primitive["mode"], label: "mode", default: 4) == 4 else {
                    throw ImportError.unsupportedFeature("Only glTF TRIANGLES primitives are supported.")
                }
                guard let attributes = primitive["attributes"] as? [String: Any], attributes["POSITION"] != nil else {
                    throw ImportError.invalidData("glTF primitive requires POSITION attributes.")
                }
                try meshUnsupportedKeys(attributes, allowed: ["POSITION", "NORMAL", "TEXCOORD_0", "COLOR_0"])
                let positions = try gltfAccessor(attributes["POSITION"], semantic: "POSITION", accessors: accessors,
                                                 views: views, buffers: buffers, resources: &resources)
                let normals = try attributes["NORMAL"].map {
                    try gltfAccessor($0, semantic: "NORMAL", accessors: accessors, views: views, buffers: buffers, resources: &resources)
                } ?? []
                let uv = try attributes["TEXCOORD_0"].map {
                    try gltfAccessor($0, semantic: "TEXCOORD_0", accessors: accessors, views: views, buffers: buffers, resources: &resources)
                } ?? []
                let colors = try attributes["COLOR_0"].map {
                    try gltfAccessor($0, semantic: "COLOR_0", accessors: accessors, views: views, buffers: buffers, resources: &resources)
                } ?? []
                let indexValues = try primitive["indices"].map {
                    try gltfAccessor($0, semantic: "indices", accessors: accessors, views: views, buffers: buffers, resources: &resources)
                }
                let vertexCount = positions.count
                let indexCount = indexValues?.count ?? vertexCount
                try meshStorageAdmission(vertexCount: vertexCount, indexCount: indexCount, resources: &resources)
                guard indexCount > 0, indexCount.isMultiple(of: 3),
                      normals.isEmpty || normals.count == vertexCount,
                      uv.isEmpty || uv.count == vertexCount,
                      colors.isEmpty || colors.count == vertexCount else {
                    throw ImportError.invalidData("glTF primitive attribute/index counts disagree.")
                }
                let indices = try (indexValues ?? (0..<vertexCount).map { [Double($0)] }).map { values -> UInt32 in
                    guard values[0] < Double(vertexCount), values[0] <= Double(UInt32.max) else {
                        throw ImportError.invalidData("glTF index is out of bounds.")
                    }
                    return UInt32(values[0])
                }
                let mesh = Mesh(positions: positions.map { Point3D(x: $0[0], y: $0[1], z: $0[2]) },
                                normals: try normals.map { v in
                                    let n = Vector3D(x: v[0], y: v[1], z: v[2])
                                    guard abs(n.length - 1) < 1e-3 else { throw ImportError.invalidData("glTF NORMAL is not unit length.") }
                                    return n / n.length
                                }, indices: indices,
                                textureCoordinates: uv.map { Point2D(x: $0[0], y: $0[1]) },
                                vertexColors: colors.map { ColorRGBA(r: $0[0], g: $0[1], b: $0[2], a: $0.count == 4 ? $0[3] : 1) })
                try validateImportedMesh(mesh, formatName: "glTF", tolerance: tolerance)
                meshes.append(mesh)
            }
            sourceMeshes.append(meshes)
        }
        let nodes = try meshObjects(root["nodes"], label: "nodes", optional: true)
        let scenes = try meshObjects(root["scenes"], label: "scenes", optional: true)
        guard scenes.count <= 1 else { throw ImportError.unsupportedFeature("Multiple glTF scenes cannot be preserved by static mesh exchange.") }
        var result: [BodyID: Mesh] = [:]
        if nodes.isEmpty, scenes.isEmpty {
            for meshes in sourceMeshes { for mesh in meshes { result[BodyID()] = mesh } }
        } else {
            guard scenes.count == 1, try meshInteger(root["scene"], label: "scene", default: 0) == 0 else {
                throw ImportError.invalidData("glTF nodes require a single static scene.")
            }
            try meshUnsupportedKeys(scenes[0], allowed: ["nodes", "name"])
            guard let roots = scenes[0]["nodes"] as? [Any] else { throw ImportError.invalidData("glTF scene requires root nodes.") }
            var visited = Set<Int>()
            var usedMeshes = Set<Int>()
            func visit(_ rawIndex: Any, parent: MeshPlacement, depth: Int) throws {
                try resources.checkTime()
                try resources.validateNestingDepth(depth)
                let i = try meshInteger(rawIndex, label: "node")
                guard nodes.indices.contains(i), visited.insert(i).inserted else { throw ImportError.invalidData("glTF node cycle, duplicate parent or invalid index.") }
                let node = nodes[i]
                try meshUnsupportedKeys(node, allowed: ["mesh", "children", "matrix", "translation", "rotation", "scale", "name"])
                let placement: MeshPlacement
                if node["matrix"] != nil {
                    guard node["translation"] == nil, node["rotation"] == nil, node["scale"] == nil else {
                        throw ImportError.invalidData("glTF matrix and TRS cannot coexist.")
                    }
                    placement = MeshPlacement(values: try meshDoubles(node["matrix"], count: 16))
                    let v = placement.values
                    let axes = [Vector3D(x: v[0], y: v[1], z: v[2]), Vector3D(x: v[4], y: v[5], z: v[6]), Vector3D(x: v[8], y: v[9], z: v[10])]
                    guard axes.allSatisfy({ $0.length.isFinite && $0.length > 0 }),
                          abs(axes[0].dot(axes[1])) <= 1e-8 * axes[0].length * axes[1].length,
                          abs(axes[0].dot(axes[2])) <= 1e-8 * axes[0].length * axes[2].length,
                          abs(axes[1].dot(axes[2])) <= 1e-8 * axes[1].length * axes[2].length else {
                        throw ImportError.invalidData("glTF matrix is not decomposable into TRS.")
                    }
                } else {
                    placement = MeshPlacement.translation(try meshDoubles(node["translation"], count: 3, fallback: [0, 0, 0]))
                        .multiplied(by: try MeshPlacement.quaternion(meshDoubles(node["rotation"], count: 4, fallback: [0, 0, 0, 1])))
                        .multiplied(by: MeshPlacement.scale(try meshDoubles(node["scale"], count: 3, fallback: [1, 1, 1])))
                }
                let world = parent.multiplied(by: placement)
                if let rawMesh = node["mesh"] {
                    let m = try meshInteger(rawMesh, label: "mesh")
                    guard sourceMeshes.indices.contains(m) else { throw ImportError.invalidData("glTF node mesh is out of range.") }
                    usedMeshes.insert(m)
                    for mesh in sourceMeshes[m] {
                        try meshStorageAdmission(vertexCount: mesh.positions.count, indexCount: mesh.indices.count, resources: &resources)
                        try resources.recordIterations(mesh.positions.count + mesh.indices.count)
                        result[BodyID()] = try world.applying(to: mesh, tolerance: tolerance)
                    }
                }
                if let rawChildren = node["children"] {
                    guard let children = rawChildren as? [Any] else { throw ImportError.invalidData("Invalid glTF children.") }
                    for child in children { try visit(child, parent: world, depth: depth + 1) }
                }
            }
            for root in roots { try visit(root, parent: .identity, depth: 1) }
            guard visited.count == nodes.count, usedMeshes.count == sourceMeshes.count else {
                throw ImportError.unsupportedFeature("Unplaced glTF nodes or meshes would be lost.")
            }
        }
        guard !result.isEmpty else { throw ImportError.invalidData("glTF scene contains no geometry.") }
        return ImportedExchangeModel(format: format, meshes: result, units: .meters)
    }

    func writeGLTF(_ meshes: [Mesh], format: ExchangeFileFormat,
                   resources: inout ExchangeResourceAccountant) throws -> Data {
        var binary = Data()
        var views: [[String: Any]] = []
        var accessors: [[String: Any]] = []
        var objects: [[String: Any]] = []
        func attribute(_ values: [[Double]], type: String, position: Bool = false) throws -> Int {
            let count = values.count
            let components = type == "VEC2" ? 2 : (type == "VEC4" ? 4 : 3)
            try resources.recordBytes(count * components * 4, label: "binary output")
            let offset = binary.count
            for v in values {
                try resources.recordIterations()
                for value in v { try meshAppendFloat(value, to: &binary) }
            }
            let view = views.count
            views.append(["buffer": 0, "byteOffset": offset, "byteLength": binary.count - offset, "target": 34962])
            var accessor: [String: Any] = ["bufferView": view, "componentType": 5126, "count": count, "type": type]
            if position {
                accessor["min"] = (0..<3).map { c in values.map { Double(Float($0[c])) }.min()! }
                accessor["max"] = (0..<3).map { c in values.map { Double(Float($0[c])) }.max()! }
            }
            accessors.append(accessor)
            return accessors.count - 1
        }
        for mesh in meshes {
            guard mesh.vertexColors.allSatisfy({ $0.a == 1 }) else {
                throw ExportError.unsupportedFeature("glTF vertex transparency requires material alphaMode semantics.")
            }
            // The interchange boundary quantizes to Float32. Refuse quantization
            // that invalidates geometry before publishing any encoded bytes.
            var quantized = mesh
            quantized.positions = mesh.positions.map { Point3D(x: Double(Float($0.x)), y: Double(Float($0.y)), z: Double(Float($0.z))) }
            quantized.normals = try mesh.normals.map { n in
                let value = Vector3D(x: Double(Float(n.x)), y: Double(Float(n.y)), z: Double(Float(n.z)))
                guard value.length.isFinite, value.length > 0 else { throw ExportError.invalidMesh("glTF normal quantization failed.") }
                return value / value.length
            }
            try quantized.validate(tolerance: tolerance)
            var attributes: [String: Any] = [:]
            attributes["POSITION"] = try attribute(mesh.positions.map { [$0.x, $0.y, $0.z] }, type: "VEC3", position: true)
            if !mesh.normals.isEmpty { attributes["NORMAL"] = try attribute(mesh.normals.map { [$0.x, $0.y, $0.z] }, type: "VEC3") }
            if !mesh.textureCoordinates.isEmpty { attributes["TEXCOORD_0"] = try attribute(mesh.textureCoordinates.map { [$0.x, $0.y] }, type: "VEC2") }
            if !mesh.vertexColors.isEmpty { attributes["COLOR_0"] = try attribute(mesh.vertexColors.map { [$0.r, $0.g, $0.b, $0.a] }, type: "VEC4") }
            try resources.recordBytes(mesh.indices.count * 4, label: "binary output")
            let start = binary.count
            for i in mesh.indices { try resources.recordIterations(); meshAppend(i, to: &binary) }
            views.append(["buffer": 0, "byteOffset": start, "byteLength": binary.count - start, "target": 34963])
            accessors.append(["bufferView": views.count - 1, "componentType": 5125, "count": mesh.indices.count, "type": "SCALAR"])
            objects.append(["primitives": [["attributes": attributes, "indices": accessors.count - 1, "mode": 4]]])
        }
        var buffer: [String: Any] = ["byteLength": binary.count]
        if format == .gltf {
            let encodedLength = ((binary.count + 2) / 3) * 4
            try resources.recordBytes(encodedLength, label: "base64 output")
            buffer["uri"] = "data:application/octet-stream;base64," + binary.base64EncodedString()
        }
        let root: [String: Any] = ["asset": ["version": "2.0", "generator": "Swift-CAD"], "buffers": [buffer],
                                  "bufferViews": views, "accessors": accessors, "meshes": objects,
                                  "nodes": meshes.indices.map { ["mesh": $0] },
                                  "scenes": [["nodes": Array(meshes.indices)]], "scene": 0]
        var json = try JSONSerialization.data(withJSONObject: root, options: [.sortedKeys])
        try resources.recordBytes(json.count, label: "JSON output")
        if format == .gltf { return json }
        padToFourBytes(&json, byte: 0x20)
        padToFourBytes(&binary, byte: 0)
        let total = 28 + json.count + binary.count
        guard UInt64(total) <= UInt64(UInt32.max), total <= resources.limits.maximumBytes else {
            throw exchangeResourceLimitError(format: format, detail: "GLB output exceeds its byte bound.")
        }
        var output = Data()
        meshAppend(0x46546c67, to: &output); meshAppend(2, to: &output); meshAppend(UInt32(total), to: &output)
        meshAppend(UInt32(json.count), to: &output); meshAppend(0x4e4f534a, to: &output); output.append(json)
        meshAppend(UInt32(binary.count), to: &output); meshAppend(0x004e4942, to: &output); output.append(binary)
        return output
    }
}

private func meshObjects(_ value: Any?, label: String, optional: Bool = false) throws -> [[String: Any]] {
    if value == nil, optional { return [] }
    guard let result = value as? [[String: Any]] else { throw ImportError.invalidData("Invalid glTF \(label) array.") }
    return result
}

private func admitMeshJSON(_ data: Data, resources: inout ExchangeResourceAccountant) throws {
    var depth = 0, quoted = false, escaped = false
    let initialEntities = resources.entityCount
    for byte in data {
        try resources.recordIterations()
        if quoted {
            if escaped { escaped = false }
            else if byte == 92 { escaped = true }
            else if byte == 34 { quoted = false }
        } else if byte == 34 { quoted = true; try resources.recordEntities() }
        else if byte == 123 || byte == 91 { depth += 1; try resources.validateNestingDepth(depth); try resources.recordEntities() }
        else if byte == 125 || byte == 93 { depth -= 1; guard depth >= 0 else { throw ImportError.invalidData("Unbalanced JSON.") } }
        else if byte == 44 { try resources.recordEntities() }
    }
    try resources.recordBytes(meshResourceProduct(resources.entityCount - initialEntities, 64, format: .gltf), label: "JSON object storage")
    guard depth == 0, !quoted else { throw ImportError.invalidData("Incomplete JSON.") }
}

private func gltfAccessor(_ rawIndex: Any?, semantic: String, accessors: [[String: Any]],
                          views: [[String: Any]], buffers: [Data],
                          resources: inout ExchangeResourceAccountant) throws -> [[Double]] {
    let index = try meshInteger(rawIndex, label: "accessor")
    guard accessors.indices.contains(index) else { throw ImportError.invalidData("glTF accessor index is out of range.") }
    let accessor = accessors[index]
    try meshUnsupportedKeys(accessor, allowed: ["bufferView", "byteOffset", "componentType", "count", "type", "normalized", "min", "max", "name"])
    let component = try meshInteger(accessor["componentType"], label: "componentType")
    let count = try meshInteger(accessor["count"], label: "accessor count")
    let type = accessor["type"] as? String
    let components: Int
    switch (semantic, type) {
    case ("indices", "SCALAR"): components = 1
    case ("POSITION", "VEC3"), ("NORMAL", "VEC3"), ("COLOR_0", "VEC3"): components = 3
    case ("COLOR_0", "VEC4"): components = 4
    case ("TEXCOORD_0", "VEC2"): components = 2
    default: throw ImportError.unsupportedFeature("Unsupported glTF accessor shape for \(semantic).")
    }
    let normalized: Bool
    if let raw = accessor["normalized"] {
        guard let n = raw as? NSNumber, CFGetTypeID(n) == CFBooleanGetTypeID() else { throw ImportError.invalidData("normalized must be boolean.") }
        normalized = n.boolValue
    } else { normalized = false }
    let width: Int
    switch component { case 5121: width = 1; case 5123: width = 2; case 5125, 5126: width = 4
    default: throw ImportError.unsupportedFeature("Unsupported glTF accessor component type.") }
    if semantic == "indices" {
        guard component != 5126, !normalized else { throw ImportError.invalidData("glTF indices must be unsigned integers.") }
    } else if semantic == "POSITION" || semantic == "NORMAL" {
        guard component == 5126, !normalized else { throw ImportError.unsupportedFeature("glTF position/normal requires Float32.") }
    } else {
        guard (component == 5126 && !normalized) || ((component == 5121 || component == 5123) && normalized) else {
            throw ImportError.unsupportedFeature("glTF color/UV requires float or normalized unsigned components.")
        }
    }
    let viewIndex = try meshInteger(accessor["bufferView"], label: "bufferView")
    guard views.indices.contains(viewIndex) else { throw ImportError.invalidData("glTF bufferView is out of range.") }
    let view = views[viewIndex]
    try meshUnsupportedKeys(view, allowed: ["buffer", "byteOffset", "byteLength", "byteStride", "target", "name"])
    let bufferIndex = try meshInteger(view["buffer"], label: "buffer")
    guard buffers.indices.contains(bufferIndex) else { throw ImportError.invalidData("glTF buffer is out of range.") }
    let buffer = buffers[bufferIndex]
    let viewOffset = try meshInteger(view["byteOffset"], label: "view offset", default: 0)
    let viewLength = try meshInteger(view["byteLength"], label: "view length")
    let accessorOffset = try meshInteger(accessor["byteOffset"], label: "accessor offset", default: 0)
    let stride = try meshInteger(view["byteStride"], label: "stride", default: components * width)
    guard count > 0, count <= resources.limits.maximumEntities,
          count <= resources.limits.maximumBytes / (components * 8 + 24),
          viewLength > 0, viewOffset <= buffer.count, viewLength <= buffer.count - viewOffset,
          stride >= components * width, stride <= 252, stride.isMultiple(of: width),
          accessorOffset.isMultiple(of: width), viewOffset.isMultiple(of: width),
          accessorOffset <= viewLength, components * width <= viewLength - accessorOffset,
          count - 1 <= (viewLength - accessorOffset - components * width) / stride else {
        throw ImportError.invalidData("glTF accessor count, stride, alignment or range is invalid.")
    }
    if semantic == "indices", view["byteStride"] != nil { throw ImportError.invalidData("Index accessors cannot be interleaved.") }
    try resources.recordEntities(count)
    try resources.recordBytes(count * (components * 8 + 24), label: "accessor values")
    var result: [[Double]] = []; result.reserveCapacity(count)
    for i in 0..<count {
        try resources.recordIterations()
        var tuple: [Double] = []
        for c in 0..<components {
            let raw = try meshUInt(buffer, offset: viewOffset + accessorOffset + i * stride + c * width, width: width)
            let value: Double
            if component == 5126 { value = Double(Float(bitPattern: UInt32(raw))) }
            else { value = Double(raw) / (normalized ? (component == 5121 ? 255 : 65535) : 1) }
            guard value.isFinite else { throw ImportError.invalidData("Nonfinite glTF accessor component.") }
            tuple.append(value)
        }
        result.append(tuple)
    }
    return result
}

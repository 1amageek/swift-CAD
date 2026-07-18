import Foundation
import CADCore
import CADIR

public struct GLBExporter: Sendable {
    private let tolerance: ModelingTolerance

    public init(tolerance: ModelingTolerance) {
        self.tolerance = tolerance
    }

    public func write(meshes: [BodyID: Mesh], to sink: any ByteSink) throws {
        let layout = try glbLayout(for: meshes)
        let includeNormals = layout.includeNormals
        let json = try glTFJSON(
            binaryLength: layout.binaryLength,
            positionOffset: layout.positionOffset,
            normalOffset: layout.normalOffset,
            indexOffset: layout.indexOffset,
            vertexCount: layout.vertexCount,
            indexCount: layout.indexCount,
            includeNormals: includeNormals,
            bounds: layout.bounds
        )
        var jsonData = Data(json.utf8)
        padToFourBytes(&jsonData, byte: 0x20)

        let totalLength = 12 + 8 + jsonData.count + 8 + layout.binaryLength
        let totalLength32 = try glbUInt32(totalLength, label: "total length")
        let jsonLength32 = try glbUInt32(jsonData.count, label: "JSON chunk length")
        let binaryLength32 = try glbUInt32(layout.binaryLength, label: "binary chunk length")
        try sink.writeLittleEndian(UInt32(0x46546c67))
        try sink.writeLittleEndian(UInt32(2))
        try sink.writeLittleEndian(totalLength32)
        try sink.writeLittleEndian(jsonLength32)
        try sink.writeLittleEndian(UInt32(0x4e4f534a))
        try sink.write(jsonData)
        try sink.writeLittleEndian(binaryLength32)
        try sink.writeLittleEndian(UInt32(0x004e4942))
        try writeGLBBinary(meshes: layout.meshes, includeNormals: includeNormals, to: sink)
    }

    private func glbLayout(for meshes: [BodyID: Mesh]) throws -> GLBLayout {
        guard !meshes.isEmpty else {
            throw ExportError.emptyMesh
        }
        let sortedMeshes = meshes.sorted(by: { $0.key.description < $1.key.description })
        let includeNormals = sortedMeshes.allSatisfy { !$0.value.normals.isEmpty }
        var vertexCount = 0
        var indexCount = 0
        var bounds = GLBPositionBounds()
        for (_, mesh) in sortedMeshes {
            try mesh.validate(tolerance: tolerance)
            guard UInt64(mesh.positions.count) + UInt64(vertexCount) <= UInt64(UInt32.max) else {
                throw ExportError.invalidMesh("GLB vertex count exceeds UInt32 range.")
            }
            let base = UInt32(vertexCount)
            for position in mesh.positions {
                try bounds.include(position)
            }
            for index in mesh.indices {
                guard index <= UInt32.max - base else {
                    throw ExportError.invalidMesh("GLB index exceeds UInt32 range after mesh merge.")
                }
            }
            vertexCount += mesh.positions.count
            indexCount += mesh.indices.count
        }
        let positionOffset = 0
        let positionLength = vertexCount * 12
        let normalOffset = paddedGLBLength(positionLength)
        let normalLength = includeNormals ? vertexCount * 12 : 0
        let indexOffset = paddedGLBLength(normalOffset + normalLength)
        let indexLength = indexCount * 4
        let binaryLength = paddedGLBLength(indexOffset + indexLength)
        return GLBLayout(
            meshes: sortedMeshes,
            includeNormals: includeNormals,
            positionOffset: positionOffset,
            normalOffset: normalOffset,
            indexOffset: indexOffset,
            binaryLength: binaryLength,
            vertexCount: vertexCount,
            indexCount: indexCount,
            bounds: try bounds.values()
        )
    }

    private func glTFJSON(
        binaryLength: Int,
        positionOffset: Int,
        normalOffset: Int,
        indexOffset: Int,
        vertexCount: Int,
        indexCount: Int,
        includeNormals: Bool,
        bounds: (min: [Double], max: [Double])
    ) throws -> String {
        var attributes: [String: Any] = ["POSITION": 0]
        var bufferViews: [[String: Any]] = [
            ["buffer": 0, "byteOffset": positionOffset, "byteLength": vertexCount * 12, "target": 34962]
        ]
        var accessors: [[String: Any]] = [
            [
                "bufferView": 0,
                "componentType": 5126,
                "count": vertexCount,
                "type": "VEC3",
                "min": bounds.min,
                "max": bounds.max
            ]
        ]
        if includeNormals {
            attributes["NORMAL"] = 1
            bufferViews.append(["buffer": 0, "byteOffset": normalOffset, "byteLength": vertexCount * 12, "target": 34962])
            accessors.append(["bufferView": 1, "componentType": 5126, "count": vertexCount, "type": "VEC3"])
        }
        let indexBufferView = bufferViews.count
        let indexAccessor = accessors.count
        bufferViews.append(["buffer": 0, "byteOffset": indexOffset, "byteLength": indexCount * 4, "target": 34963])
        accessors.append(["bufferView": indexBufferView, "componentType": 5125, "count": indexCount, "type": "SCALAR"])

        let root: [String: Any] = [
            "asset": ["version": "2.0", "generator": "Swift-CAD"],
            "buffers": [["byteLength": binaryLength]],
            "bufferViews": bufferViews,
            "accessors": accessors,
            "meshes": [[
                "primitives": [[
                    "attributes": attributes,
                    "indices": indexAccessor,
                    "mode": 4
                ]]
            ]],
            "nodes": [["mesh": 0]],
            "scenes": [["nodes": [0]]],
            "scene": 0
        ]
        let data = try JSONSerialization.data(withJSONObject: root, options: [.sortedKeys])
        guard let json = String(data: data, encoding: .utf8) else {
            throw ExportError.invalidMesh("Unable to encode glTF JSON.")
        }
        return json
    }

}

private struct GLBLayout {
    var meshes: [(key: BodyID, value: Mesh)]
    var includeNormals: Bool
    var positionOffset: Int
    var normalOffset: Int
    var indexOffset: Int
    var binaryLength: Int
    var vertexCount: Int
    var indexCount: Int
    var bounds: (min: [Double], max: [Double])
}

private struct GLBPositionBounds {
    private var minX: Double?
    private var minY: Double?
    private var minZ: Double?
    private var maxX: Double?
    private var maxY: Double?
    private var maxZ: Double?

    mutating func include(_ position: Point3D) throws {
        let x = Double(try checkedGLBFloat32(position.x, label: "position.x"))
        let y = Double(try checkedGLBFloat32(position.y, label: "position.y"))
        let z = Double(try checkedGLBFloat32(position.z, label: "position.z"))
        minX = min(minX ?? x, x)
        minY = min(minY ?? y, y)
        minZ = min(minZ ?? z, z)
        maxX = max(maxX ?? x, x)
        maxY = max(maxY ?? y, y)
        maxZ = max(maxZ ?? z, z)
    }

    func values() throws -> (min: [Double], max: [Double]) {
        guard let minX, let minY, let minZ, let maxX, let maxY, let maxZ else {
            throw ExportError.emptyMesh
        }
        return ([minX, minY, minZ], [maxX, maxY, maxZ])
    }
}

func padToFourBytes(_ data: inout Data, byte: UInt8) {
    while !data.count.isMultiple(of: 4) {
        data.append(byte)
    }
}

private func writeGLBBinary(
    meshes: [(key: BodyID, value: Mesh)],
    includeNormals: Bool,
    to sink: any ByteSink
) throws {
    for (_, mesh) in meshes {
        for point in mesh.positions {
            try writeGLBFloat32(point.x, label: "position.x", to: sink)
            try writeGLBFloat32(point.y, label: "position.y", to: sink)
            try writeGLBFloat32(point.z, label: "position.z", to: sink)
        }
    }
    try padGLBSinkToFourBytes(sink, writtenByteCount: meshes.reduce(0) { $0 + $1.value.positions.count * 12 })
    if includeNormals {
        for (_, mesh) in meshes {
            for normal in mesh.normals {
                try writeGLBFloat32(normal.x, label: "normal.x", to: sink)
                try writeGLBFloat32(normal.y, label: "normal.y", to: sink)
                try writeGLBFloat32(normal.z, label: "normal.z", to: sink)
            }
        }
        try padGLBSinkToFourBytes(sink, writtenByteCount: meshes.reduce(0) { $0 + $1.value.normals.count * 12 })
    }
    var base: UInt32 = 0
    var indexByteCount = 0
    for (_, mesh) in meshes {
        for index in mesh.indices {
            try sink.writeLittleEndian(base + index)
            indexByteCount += 4
        }
        base += UInt32(mesh.positions.count)
    }
    try padGLBSinkToFourBytes(sink, writtenByteCount: indexByteCount)
}

private func writeGLBFloat32(_ value: Double, label: String, to sink: any ByteSink) throws {
    let value32 = try checkedGLBFloat32(value, label: label)
    try sink.writeLittleEndianFloat32(value32)
}

private func paddedGLBLength(_ length: Int) -> Int {
    let remainder = length % 4
    guard remainder != 0 else {
        return length
    }
    return length + 4 - remainder
}

private func padGLBSinkToFourBytes(_ sink: any ByteSink, writtenByteCount: Int) throws {
    let paddingCount = paddedGLBLength(writtenByteCount) - writtenByteCount
    for _ in 0..<paddingCount {
        try sink.writeByte(0)
    }
}

private func checkedGLBFloat32(_ value: Double, label: String) throws -> Float32 {
    let value32 = Float32(value)
    guard value32.isFinite else {
        throw ExportError.invalidMesh("GLB \(label) is outside Float32 range.")
    }
    return value32
}

private func glbUInt32(_ value: Int, label: String) throws -> UInt32 {
    guard value >= 0, UInt64(value) <= UInt64(UInt32.max) else {
        throw ExportError.invalidMesh("GLB \(label) exceeds UInt32 range.")
    }
    return UInt32(value)
}

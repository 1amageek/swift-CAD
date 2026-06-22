import Foundation
import CADCore
import CADIR

public struct OBJExchange: Sendable {
    public init() {}

    public func write(meshes: [BodyID: Mesh], unit: LengthUnit = .meter, to sink: any ByteSink) throws {
        guard !meshes.isEmpty else {
            throw ExportError.emptyMesh
        }
        try sink.writeUTF8("# Swift-CAD OBJ\n# unit \(unit.rawValue)")
        var vertexBase = 1
        var normalBase = 1

        for (bodyID, mesh) in meshes.sorted(by: { $0.key.description < $1.key.description }) {
            try mesh.validate()
            try sink.writeUTF8("\no body_\(bodyID.rawValue.uuidString.replacingOccurrences(of: "-", with: "_"))")
            for point in mesh.positions {
                let x = try checkedExportUnitValue(
                    unit.fromInternal(point.x),
                    formatName: "OBJ",
                    component: "vertex.x"
                )
                let y = try checkedExportUnitValue(
                    unit.fromInternal(point.y),
                    formatName: "OBJ",
                    component: "vertex.y"
                )
                let z = try checkedExportUnitValue(
                    unit.fromInternal(point.z),
                    formatName: "OBJ",
                    component: "vertex.z"
                )
                try sink.writeUTF8("\nv \(x) \(y) \(z)")
            }
            for normal in mesh.normals {
                try sink.writeUTF8("\nvn \(normal.x) \(normal.y) \(normal.z)")
            }
            var index = 0
            while index < mesh.indices.count {
                let a = Int(mesh.indices[index]) + vertexBase
                let b = Int(mesh.indices[index + 1]) + vertexBase
                let c = Int(mesh.indices[index + 2]) + vertexBase
                if mesh.normals.isEmpty {
                    try sink.writeUTF8("\nf \(a) \(b) \(c)")
                } else {
                    let na = Int(mesh.indices[index]) + normalBase
                    let nb = Int(mesh.indices[index + 1]) + normalBase
                    let nc = Int(mesh.indices[index + 2]) + normalBase
                    try sink.writeUTF8("\nf \(a)//\(na) \(b)//\(nb) \(c)//\(nc)")
                }
                index += 3
            }
            vertexBase += mesh.positions.count
            normalBase += mesh.normals.count
        }
    }

    public func `import`(_ source: any ByteSource, unit: LengthUnit = .meter) throws -> ImportedExchangeModel {
        try source.withNoCopyData { data in
            guard let text = String(data: data, encoding: .utf8) else {
                throw ImportError.invalidData("OBJ data is not UTF-8.")
            }
            return try importText(text, unit: unit)
        }
    }

    private func importText(_ text: String, unit: LengthUnit) throws -> ImportedExchangeModel {
        let importUnit = try objLengthUnit(in: text, fallback: unit)
        var sourceVertices: [Point3D] = []
        var textureCoordinateCount = 0
        var sourceNormals: [Vector3D] = []
        var meshBuilders: [OBJMeshBuilder] = [OBJMeshBuilder()]
        var currentMeshIndex = 0

        for rawLine in text.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty, !line.hasPrefix("#") else { continue }
            let parts = line.split(whereSeparator: \.isWhitespace).map(String.init)
            guard let head = parts.first else { continue }
            if head == "v" {
                guard parts.count == 4 else {
                    throw ImportError.invalidData("OBJ vertex record is malformed.")
                }
                guard let x = Double(parts[1]),
                      let y = Double(parts[2]),
                      let z = Double(parts[3]),
                      x.isFinite,
                      y.isFinite,
                      z.isFinite else {
                    throw ImportError.invalidData("Invalid OBJ vertex.")
                }
                let point = Point3D(
                    x: importUnit.toInternal(x),
                    y: importUnit.toInternal(y),
                    z: importUnit.toInternal(z)
                )
                guard point.x.isFinite,
                      point.y.isFinite,
                      point.z.isFinite else {
                    throw ImportError.invalidData("OBJ vertex contains a non-finite coordinate.")
                }
                sourceVertices.append(point)
            } else if head == "vt" {
                guard (2...4).contains(parts.count) else {
                    throw ImportError.invalidData("OBJ texture coordinate record is malformed.")
                }
                for value in parts.dropFirst() {
                    guard let coordinate = Double(value), coordinate.isFinite else {
                        throw ImportError.invalidData("Invalid OBJ texture coordinate.")
                    }
                }
                textureCoordinateCount += 1
            } else if head == "vn" {
                guard parts.count == 4 else {
                    throw ImportError.invalidData("OBJ normal record is malformed.")
                }
                guard let x = Double(parts[1]),
                      let y = Double(parts[2]),
                      let z = Double(parts[3]),
                      x.isFinite,
                      y.isFinite,
                      z.isFinite else {
                    throw ImportError.invalidData("Invalid OBJ normal.")
                }
                let normal = Vector3D(x: x, y: y, z: z)
                let normalLength = normal.length
                guard normalLength.isFinite,
                      normalLength > ModelingTolerance.standard.distance,
                      abs(normalLength - 1.0) <= max(ModelingTolerance.standard.distance, ModelingTolerance.standard.angle) else {
                    throw ImportError.invalidData("OBJ normal must be a finite unit vector.")
                }
                sourceNormals.append(normal)
            } else if head == "o" || head == "g" {
                guard parts.count >= 2 else {
                    throw ImportError.invalidData("OBJ mesh boundary record is malformed.")
                }
                if meshBuilders[currentMeshIndex].isEmpty {
                    continue
                }
                meshBuilders.append(OBJMeshBuilder())
                currentMeshIndex = meshBuilders.count - 1
            } else if head == "f" {
                guard parts.count >= 4 else {
                    throw ImportError.invalidData("OBJ face record must contain at least three vertices.")
                }
                let faceVertices = try parts.dropFirst().map { token in
                    try parseOBJVertexIndex(
                        String(token),
                        vertexCount: sourceVertices.count,
                        textureCoordinateCount: textureCoordinateCount,
                        normalCount: sourceNormals.count
                    )
                }
                guard faceVertices.count == 3 else {
                    throw ImportError.invalidData("Only triangular OBJ faces are supported.")
                }
                try meshBuilders[currentMeshIndex].append(
                    faceVertices: faceVertices,
                    sourceVertices: sourceVertices,
                    sourceNormals: sourceNormals
                )
            } else if unsupportedOBJGeometryRecords.contains(head) {
                throw ImportError.invalidData("Unsupported OBJ geometry record \(head).")
            } else {
                throw ImportError.invalidData("Unsupported OBJ record \(head).")
            }
        }

        var meshes: [BodyID: Mesh] = [:]
        for builder in meshBuilders where !builder.isEmpty {
            let mesh = builder.makeMesh()
            try validateImportedMesh(mesh, formatName: "OBJ")
            meshes[BodyID()] = mesh
        }
        guard !meshes.isEmpty else {
            throw ImportError.invalidData("OBJ mesh contains no faces.")
        }
        return ImportedExchangeModel(format: .obj, meshes: meshes, units: UnitSystem(length: importUnit, angle: .radian))
    }

    private func parseOBJVertexIndex(
        _ token: String,
        vertexCount: Int,
        textureCoordinateCount: Int,
        normalCount: Int
    ) throws -> OBJFaceVertex {
        let components = token.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        guard (1...3).contains(components.count),
              let indexToken = components.first,
              !indexToken.isEmpty else {
            throw ImportError.invalidData("Invalid OBJ face index.")
        }
        let vertexIndex = try resolveOBJIndex(indexToken, count: vertexCount, label: "vertex")
        if components.count >= 2 {
            let textureToken = components[1]
            if textureToken.isEmpty {
                guard components.count == 3 else {
                    throw ImportError.invalidData("Invalid OBJ texture coordinate index.")
                }
            } else {
                _ = try resolveOBJIndex(textureToken, count: textureCoordinateCount, label: "texture coordinate")
            }
        }
        var normalIndex: Int?
        if components.count == 3 {
            let normalToken = components[2]
            guard !normalToken.isEmpty else {
                throw ImportError.invalidData("Invalid OBJ normal index.")
            }
            normalIndex = try resolveOBJIndex(normalToken, count: normalCount, label: "normal")
        }
        return OBJFaceVertex(vertexIndex: vertexIndex, normalIndex: normalIndex)
    }

    private func resolveOBJIndex(_ token: String, count: Int, label: String) throws -> Int {
        guard let rawIndex = Int(token), rawIndex != 0 else {
            throw ImportError.invalidData("Invalid OBJ \(label) index.")
        }
        let resolved = rawIndex > 0 ? rawIndex - 1 : count + rawIndex
        guard resolved >= 0, resolved < count else {
            throw ImportError.invalidData("OBJ \(label) index is out of range.")
        }
        return resolved
    }
}

private func objLengthUnit(in text: String, fallback: LengthUnit) throws -> LengthUnit {
    var resolvedUnit: LengthUnit?
    for rawLine in text.components(separatedBy: .newlines) {
        let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
        if line.isEmpty {
            continue
        }
        guard line.hasPrefix("#") else {
            return resolvedUnit ?? fallback
        }
        guard line.hasPrefix("# unit ") else {
            continue
        }
        guard resolvedUnit == nil else {
            throw ImportError.invalidData("OBJ preamble contains duplicate unit declarations.")
        }
        let value = String(line.dropFirst("# unit ".count)).trimmingCharacters(in: .whitespacesAndNewlines)
        guard let unit = parseLengthUnitName(value) else {
            throw ImportError.invalidData("Unsupported OBJ unit \(value).")
        }
        resolvedUnit = unit
    }
    return resolvedUnit ?? fallback
}

private struct OBJFaceVertex: Sendable {
    var vertexIndex: Int
    var normalIndex: Int?
}

private struct OBJMeshBuilder: Sendable {
    private(set) var positions: [Point3D] = []
    private(set) var normals: [Vector3D] = []
    private(set) var indices: [UInt32] = []

    var isEmpty: Bool {
        indices.isEmpty
    }

    mutating func append(
        faceVertices: [OBJFaceVertex],
        sourceVertices: [Point3D],
        sourceNormals: [Vector3D]
    ) throws {
        let normalIndices = faceVertices.map(\.normalIndex)
        let faceHasNormals = normalIndices.allSatisfy { $0 != nil }
        guard faceHasNormals || normalIndices.allSatisfy({ $0 == nil }) else {
            throw ImportError.invalidData("OBJ face normal indices must be consistently present.")
        }
        if faceHasNormals {
            guard positions.isEmpty || normals.count == positions.count else {
                throw ImportError.invalidData("OBJ faces must consistently include normal indices.")
            }
        } else {
            guard normals.isEmpty else {
                throw ImportError.invalidData("OBJ faces must consistently include normal indices.")
            }
        }

        for faceVertex in faceVertices {
            guard UInt64(positions.count) < UInt64(UInt32.max) else {
                throw ImportError.invalidData("OBJ mesh vertex count exceeds UInt32 range.")
            }
            positions.append(sourceVertices[faceVertex.vertexIndex])
            if let normalIndex = faceVertex.normalIndex {
                normals.append(sourceNormals[normalIndex])
            }
            indices.append(UInt32(positions.count - 1))
        }
    }

    func makeMesh() -> Mesh {
        Mesh(positions: positions, normals: normals, indices: indices)
    }
}

private let unsupportedOBJGeometryRecords: Set<String> = [
    "p",
    "l",
    "vp",
    "cstype",
    "deg",
    "bmat",
    "step",
    "curv",
    "curv2",
    "surf",
    "parm",
    "trim",
    "hole",
    "scrv",
    "sp",
    "con",
    "end",
    "mtllib",
    "usemtl",
    "s"
]

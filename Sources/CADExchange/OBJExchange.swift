import Foundation
import CADCore
import CADIR

public struct OBJExchange: Sendable {
    private let tolerance: ModelingTolerance
    private let resourceLimits: ExchangeResourceLimits
    private let triangulator: ExchangePolygonTriangulator

    public init(
        tolerance: ModelingTolerance,
        resourceLimits: ExchangeResourceLimits = .standard
    ) {
        self.tolerance = tolerance
        self.resourceLimits = resourceLimits
        triangulator = ExchangePolygonTriangulator()
    }

    public func write(meshes: [BodyID: Mesh], unit: LengthUnit = .meter, to sink: any ByteSink) throws {
        guard !meshes.isEmpty else {
            throw ExportError.emptyMesh
        }
        let sortedMeshes = meshes.sorted(by: { $0.key.description < $1.key.description })
        var resources = try ExchangeResourceAccountant(limits: resourceLimits, format: .obj)
        for (_, mesh) in sortedMeshes {
            try mesh.validate(tolerance: tolerance)
            try resources.recordEntities(
                1 + mesh.positions.count + mesh.normals.count + mesh.textureCoordinates.count
            )
            try resources.recordEntities(mesh.indices.count / 3)
            try resources.recordIterations(mesh.positions.count + mesh.normals.count + mesh.indices.count)
        }
        let output = try ExchangeBoundedByteSink(
            downstream: sink,
            limits: resourceLimits,
            format: .obj
        )
        try output.writeUTF8("# Swift-CAD OBJ\n# unit \(unit.rawValue)")
        var vertexBase = 1
        var textureBase = 1
        var normalBase = 1

        for (bodyID, mesh) in sortedMeshes {
            try output.writeUTF8("\no body_\(bodyID.rawValue.uuidString.replacingOccurrences(of: "-", with: "_"))")
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
                try output.writeUTF8("\nv \(x) \(y) \(z)")
            }
            for textureCoordinate in mesh.textureCoordinates {
                try output.writeUTF8("\nvt \(textureCoordinate.x) \(textureCoordinate.y)")
            }
            for normal in mesh.normals {
                try output.writeUTF8("\nvn \(normal.x) \(normal.y) \(normal.z)")
            }
            var index = 0
            while index < mesh.indices.count {
                let a = Int(mesh.indices[index]) + vertexBase
                let b = Int(mesh.indices[index + 1]) + vertexBase
                let c = Int(mesh.indices[index + 2]) + vertexBase
                if mesh.normals.isEmpty, mesh.textureCoordinates.isEmpty {
                    try output.writeUTF8("\nf \(a) \(b) \(c)")
                } else if mesh.textureCoordinates.isEmpty {
                    let na = Int(mesh.indices[index]) + normalBase
                    let nb = Int(mesh.indices[index + 1]) + normalBase
                    let nc = Int(mesh.indices[index + 2]) + normalBase
                    try output.writeUTF8("\nf \(a)//\(na) \(b)//\(nb) \(c)//\(nc)")
                } else if mesh.normals.isEmpty {
                    let ta = Int(mesh.indices[index]) + textureBase
                    let tb = Int(mesh.indices[index + 1]) + textureBase
                    let tc = Int(mesh.indices[index + 2]) + textureBase
                    try output.writeUTF8("\nf \(a)/\(ta) \(b)/\(tb) \(c)/\(tc)")
                } else {
                    let ta = Int(mesh.indices[index]) + textureBase
                    let tb = Int(mesh.indices[index + 1]) + textureBase
                    let tc = Int(mesh.indices[index + 2]) + textureBase
                    let na = Int(mesh.indices[index]) + normalBase
                    let nb = Int(mesh.indices[index + 1]) + normalBase
                    let nc = Int(mesh.indices[index + 2]) + normalBase
                    try output.writeUTF8("\nf \(a)/\(ta)/\(na) \(b)/\(tb)/\(nb) \(c)/\(tc)/\(nc)")
                }
                index += 3
            }
            vertexBase += mesh.positions.count
            textureBase += mesh.textureCoordinates.count
            normalBase += mesh.normals.count
        }
    }

    public func `import`(_ source: any ByteSource, unit: LengthUnit = .meter) throws -> ImportedExchangeModel {
        var resources = try ExchangeResourceAccountant(limits: resourceLimits, format: .obj)
        try resources.validateInputByteCount(source.count)
        try resources.recordIterations(source.count)
        return try source.withNoCopyData { data in
            guard let text = String(data: data, encoding: .utf8) else {
                throw ImportError.invalidData("OBJ data is not UTF-8.")
            }
            return try importText(text, unit: unit, resources: &resources)
        }
    }

    private func importText(
        _ text: String,
        unit: LengthUnit,
        resources: inout ExchangeResourceAccountant
    ) throws -> ImportedExchangeModel {
        let importUnit = try objLengthUnit(in: text, fallback: unit)
        var sourceVertices: [Point3D] = []
        var sourceTextureCoordinates: [Point2D] = []
        var sourceNormals: [Vector3D] = []
        var meshBuilders: [OBJMeshBuilder] = [OBJMeshBuilder()]
        var currentMeshIndex = 0

        for rawLine in text.components(separatedBy: .newlines) {
            let line = rawLine
                .split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false)[0]
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty, !line.hasPrefix("#") else { continue }
            let parts = line.split(whereSeparator: \.isWhitespace).map(String.init)
            guard let head = parts.first else { continue }
            if head == "v" {
                try resources.recordEntities()
                guard parts.count == 4 || parts.count == 5 else {
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
                let weight: Double
                if parts.count == 5 {
                    guard let parsedWeight = Double(parts[4]),
                          parsedWeight.isFinite,
                          abs(parsedWeight) > tolerance.relative else {
                        throw ImportError.invalidData("OBJ homogeneous vertex weight must be finite and nonzero.")
                    }
                    weight = parsedWeight
                } else {
                    weight = 1.0
                }
                let point = Point3D(
                    x: importUnit.toInternal(x / weight),
                    y: importUnit.toInternal(y / weight),
                    z: importUnit.toInternal(z / weight)
                )
                guard point.x.isFinite,
                      point.y.isFinite,
                      point.z.isFinite else {
                    throw ImportError.invalidData("OBJ vertex contains a non-finite coordinate.")
                }
                sourceVertices.append(point)
            } else if head == "vt" {
                try resources.recordEntities()
                guard (2...4).contains(parts.count) else {
                    throw ImportError.invalidData("OBJ texture coordinate record is malformed.")
                }
                let coordinates = try parts.dropFirst().map { value in
                    guard let coordinate = Double(value), coordinate.isFinite else {
                        throw ImportError.invalidData("Invalid OBJ texture coordinate.")
                    }
                    return coordinate
                }
                if coordinates.count == 3, coordinates[2] != 0.0 {
                    throw ImportError.invalidData("OBJ texture coordinate depth is not representable by the mesh contract.")
                }
                sourceTextureCoordinates.append(Point2D(
                    x: coordinates[0],
                    y: coordinates.count > 1 ? coordinates[1] : 0.0
                ))
            } else if head == "vn" {
                try resources.recordEntities()
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
                      normalLength > tolerance.distance else {
                    throw ImportError.invalidData("OBJ normal must be a finite nonzero vector.")
                }
                sourceNormals.append(normal / normalLength)
            } else if head == "o" || head == "g" {
                try resources.recordEntities()
                guard parts.count >= 2 else {
                    throw ImportError.invalidData("OBJ mesh boundary record is malformed.")
                }
                if meshBuilders[currentMeshIndex].isEmpty {
                    continue
                }
                meshBuilders.append(OBJMeshBuilder())
                currentMeshIndex = meshBuilders.count - 1
            } else if head == "f" {
                try resources.recordEntities()
                guard parts.count >= 4 else {
                    throw ImportError.invalidData("OBJ face record must contain at least three vertices.")
                }
                let faceVertices = try parts.dropFirst().map { token in
                    try parseOBJVertexIndex(
                        String(token),
                        vertexCount: sourceVertices.count,
                        textureCoordinateCount: sourceTextureCoordinates.count,
                        normalCount: sourceNormals.count
                    )
                }
                let facePoints = faceVertices.map { sourceVertices[$0.vertexIndex] }
                let triangles = try triangulator.triangles(
                    for: facePoints,
                    tolerance: tolerance
                )
                try resources.recordEntities(triangles.count)
                let attributeLayout = try OBJFaceAttributeLayout(faceVertices: faceVertices)
                if !meshBuilders[currentMeshIndex].canAppend(attributeLayout) {
                    meshBuilders.append(OBJMeshBuilder())
                    currentMeshIndex = meshBuilders.count - 1
                }
                try meshBuilders[currentMeshIndex].append(
                    faceVertices: faceVertices,
                    triangles: triangles,
                    attributeLayout: attributeLayout,
                    sourceVertices: sourceVertices,
                    sourceTextureCoordinates: sourceTextureCoordinates,
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
            try resources.checkTime()
            let mesh = builder.makeMesh()
            try validateImportedMesh(mesh, formatName: "OBJ", tolerance: tolerance)
            meshes[BodyID()] = mesh
        }
        guard !meshes.isEmpty else {
            throw ImportError.invalidData("OBJ mesh contains no faces.")
        }
        try resources.checkTime()
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
        var textureIndex: Int?
        if components.count >= 2 {
            let textureToken = components[1]
            if textureToken.isEmpty {
                guard components.count == 3 else {
                    throw ImportError.invalidData("Invalid OBJ texture coordinate index.")
                }
            } else {
                textureIndex = try resolveOBJIndex(
                    textureToken,
                    count: textureCoordinateCount,
                    label: "texture coordinate"
                )
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
        return OBJFaceVertex(
            vertexIndex: vertexIndex,
            textureIndex: textureIndex,
            normalIndex: normalIndex
        )
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
    var textureIndex: Int?
    var normalIndex: Int?
}

private struct OBJFaceAttributeLayout: Equatable, Sendable {
    var hasTextureCoordinates: Bool
    var hasNormals: Bool

    init(faceVertices: [OBJFaceVertex]) throws {
        let normalIndices = faceVertices.map(\.normalIndex)
        let textureIndices = faceVertices.map(\.textureIndex)
        hasNormals = normalIndices.allSatisfy { $0 != nil }
        hasTextureCoordinates = textureIndices.allSatisfy { $0 != nil }
        guard hasNormals || normalIndices.allSatisfy({ $0 == nil }) else {
            throw ImportError.invalidData("OBJ face normal indices must be consistently present.")
        }
        guard hasTextureCoordinates || textureIndices.allSatisfy({ $0 == nil }) else {
            throw ImportError.invalidData("OBJ face texture coordinate indices must be consistently present.")
        }
    }
}

private struct OBJMeshBuilder: Sendable {
    private(set) var positions: [Point3D] = []
    private(set) var normals: [Vector3D] = []
    private(set) var indices: [UInt32] = []
    private(set) var textureCoordinates: [Point2D] = []
    private var attributeLayout: OBJFaceAttributeLayout?

    var isEmpty: Bool {
        indices.isEmpty
    }

    func canAppend(_ candidate: OBJFaceAttributeLayout) -> Bool {
        attributeLayout == nil || attributeLayout == candidate
    }

    mutating func append(
        faceVertices: [OBJFaceVertex],
        triangles: [(Int, Int, Int)],
        attributeLayout: OBJFaceAttributeLayout,
        sourceVertices: [Point3D],
        sourceTextureCoordinates: [Point2D],
        sourceNormals: [Vector3D]
    ) throws {
        guard canAppend(attributeLayout) else {
            throw ImportError.invalidData("OBJ mesh builder received incompatible face attributes.")
        }
        self.attributeLayout = attributeLayout

        for triangle in triangles {
            for localIndex in [triangle.0, triangle.1, triangle.2] {
                guard faceVertices.indices.contains(localIndex) else {
                    throw ImportError.invalidData("OBJ triangulation produced an invalid face-local index.")
                }
                let faceVertex = faceVertices[localIndex]
                guard UInt64(positions.count) < UInt64(UInt32.max) else {
                    throw ImportError.invalidData("OBJ mesh vertex count exceeds UInt32 range.")
                }
                positions.append(sourceVertices[faceVertex.vertexIndex])
                if let textureIndex = faceVertex.textureIndex {
                    textureCoordinates.append(sourceTextureCoordinates[textureIndex])
                }
                if let normalIndex = faceVertex.normalIndex {
                    normals.append(sourceNormals[normalIndex])
                }
                indices.append(UInt32(positions.count - 1))
            }
        }
    }

    func makeMesh() -> Mesh {
        Mesh(
            positions: positions,
            normals: normals,
            indices: indices,
            textureCoordinates: textureCoordinates
        )
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

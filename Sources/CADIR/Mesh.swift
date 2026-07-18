import CADCore

public struct Mesh: Codable, Sendable, Hashable {
    public var positions: [Point3D]
    public var normals: [Vector3D]
    public var indices: [UInt32]
    public var textureCoordinates: [Point2D]
    public var vertexColors: [ColorRGBA]
    public var material: MaterialID?

    public init(
        positions: [Point3D] = [],
        normals: [Vector3D] = [],
        indices: [UInt32] = [],
        textureCoordinates: [Point2D] = [],
        vertexColors: [ColorRGBA] = [],
        material: MaterialID? = nil
    ) {
        self.positions = positions
        self.normals = normals
        self.indices = indices
        self.textureCoordinates = textureCoordinates
        self.vertexColors = vertexColors
        self.material = material
    }

    private enum CodingKeys: String, CodingKey {
        case positions
        case normals
        case indices
        case textureCoordinates
        case vertexColors
        case material
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        positions = try container.decode([Point3D].self, forKey: .positions)
        normals = try container.decode([Vector3D].self, forKey: .normals)
        indices = try container.decode([UInt32].self, forKey: .indices)
        textureCoordinates = try container.decodeIfPresent([Point2D].self, forKey: .textureCoordinates) ?? []
        vertexColors = try container.decodeIfPresent([ColorRGBA].self, forKey: .vertexColors) ?? []
        material = try container.decodeIfPresent(MaterialID.self, forKey: .material)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(positions, forKey: .positions)
        try container.encode(normals, forKey: .normals)
        try container.encode(indices, forKey: .indices)
        if !textureCoordinates.isEmpty {
            try container.encode(textureCoordinates, forKey: .textureCoordinates)
        }
        if !vertexColors.isEmpty {
            try container.encode(vertexColors, forKey: .vertexColors)
        }
        try container.encodeIfPresent(material, forKey: .material)
    }

    public func validate(tolerance: ModelingTolerance) throws {
        try tolerance.validate()
        guard !positions.isEmpty else {
            throw ExportError.emptyMesh
        }
        guard !indices.isEmpty else {
            throw ExportError.invalidMesh("Mesh must contain at least one triangle.")
        }
        guard indices.count.isMultiple(of: 3) else {
            throw ExportError.invalidMesh("Mesh index count must be divisible by 3.")
        }
        for (positionIndex, position) in positions.enumerated() {
            guard position.x.isFinite,
                  position.y.isFinite,
                  position.z.isFinite else {
                throw ExportError.invalidMesh("Mesh position \(positionIndex) contains a non-finite coordinate.")
            }
        }
        for index in indices where Int(index) >= positions.count {
            throw ExportError.invalidMesh("Mesh index \(index) is out of range.")
        }
        if !normals.isEmpty && normals.count != positions.count {
            throw ExportError.invalidMesh("Mesh normal count must match position count.")
        }
        if !textureCoordinates.isEmpty && textureCoordinates.count != positions.count {
            throw ExportError.invalidMesh("Mesh texture coordinate count must match position count.")
        }
        if !vertexColors.isEmpty && vertexColors.count != positions.count {
            throw ExportError.invalidMesh("Mesh vertex color count must match position count.")
        }
        for (normalIndex, normal) in normals.enumerated() {
            guard normal.x.isFinite,
                  normal.y.isFinite,
                  normal.z.isFinite else {
                throw ExportError.invalidMesh("Mesh normal \(normalIndex) contains a non-finite component.")
            }
            let length = normal.length
            guard length > tolerance.distance,
                  abs(length - 1.0) <= max(tolerance.distance, tolerance.angle) else {
                throw ExportError.invalidMesh("Mesh normal \(normalIndex) is not unit length.")
            }
        }
        for (textureCoordinateIndex, textureCoordinate) in textureCoordinates.enumerated() {
            guard textureCoordinate.x.isFinite,
                  textureCoordinate.y.isFinite else {
                throw ExportError.invalidMesh(
                    "Mesh texture coordinate \(textureCoordinateIndex) contains a non-finite component."
                )
            }
        }
        for (vertexColorIndex, vertexColor) in vertexColors.enumerated() {
            do {
                try vertexColor.validate()
            } catch {
                throw ExportError.invalidMesh("Mesh vertex color \(vertexColorIndex) is invalid.")
            }
        }
        var referencedPositions = Set<Int>()
        var triangleIndex = 0
        while triangleIndex < indices.count {
            let firstIndex = Int(indices[triangleIndex])
            let secondIndex = Int(indices[triangleIndex + 1])
            let thirdIndex = Int(indices[triangleIndex + 2])
            referencedPositions.insert(firstIndex)
            referencedPositions.insert(secondIndex)
            referencedPositions.insert(thirdIndex)
            guard firstIndex != secondIndex,
                  secondIndex != thirdIndex,
                  firstIndex != thirdIndex else {
                throw ExportError.invalidMesh("Mesh triangle \(triangleIndex / 3) uses duplicate vertices.")
            }
            let first = positions[firstIndex]
            let second = positions[secondIndex]
            let third = positions[thirdIndex]
            let areaVector = (second - first).cross(third - first)
            let areaVectorLength = areaVector.length
            guard areaVectorLength.isFinite else {
                throw ExportError.invalidMesh("Mesh triangle \(triangleIndex / 3) area is not finite.")
            }
            guard areaVectorLength > tolerance.distance * tolerance.distance else {
                throw ExportError.invalidMesh("Mesh triangle \(triangleIndex / 3) is degenerate.")
            }
            if !normals.isEmpty {
                let faceNormal = areaVector / areaVectorLength
                for normalIndex in [firstIndex, secondIndex, thirdIndex] {
                    guard normals[normalIndex].dot(faceNormal) > tolerance.angle else {
                        throw ExportError.invalidMesh(
                            "Mesh normal \(normalIndex) does not agree with triangle \(triangleIndex / 3) winding."
                        )
                    }
                }
            }
            triangleIndex += 3
        }
        if let unreferencedPosition = positions.indices.first(where: { !referencedPositions.contains($0) }) {
            throw ExportError.invalidMesh("Mesh position \(unreferencedPosition) is not referenced by any triangle.")
        }
    }
}

public struct TessellationOptions: Codable, Hashable, Sendable {
    public var linearTolerance: Double
    public var angularTolerance: Double
    public var maxEdgeLength: Double?

    public init(linearTolerance: Double, angularTolerance: Double, maxEdgeLength: Double? = nil) {
        self.linearTolerance = linearTolerance
        self.angularTolerance = angularTolerance
        self.maxEdgeLength = maxEdgeLength
    }

    public static let standard = TessellationOptions(
        linearTolerance: 1.0e-4,
        angularTolerance: 1.0e-3
    )

    public func validate() throws {
        guard linearTolerance.isFinite,
              linearTolerance > 0.0,
              angularTolerance.isFinite,
              angularTolerance > 0.0 else {
            throw TessellationError.invalidTolerance
        }
        if let maxEdgeLength {
            guard maxEdgeLength.isFinite, maxEdgeLength > 0.0 else {
                throw TessellationError.invalidTolerance
            }
        }
    }
}

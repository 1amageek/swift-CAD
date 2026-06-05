import CADCore
import CADIR
import OpenUSD

public struct USDSceneImporter: Sendable {
    public init() {}

    public func `import`(_ scene: USDScene, sourceName: String = "USD") throws -> USDImportResult {
        let unit = try lengthUnit(forMetersPerUnit: scene.metersPerUnit)
        var meshes: [BodyID: Mesh] = [:]
        for usdMesh in scene.meshes {
            let mesh = try mesh(from: usdMesh, metersPerUnit: scene.metersPerUnit, upAxis: scene.upAxis)
            try validateImportedMesh(mesh, sourceName: sourceName)
            meshes[BodyID()] = mesh
        }
        guard !meshes.isEmpty else {
            throw ImportError.invalidData("USD scene contains no importable meshes.")
        }
        return USDImportResult(meshes: meshes, units: UnitSystem(length: unit, angle: .radian))
    }

    private func mesh(from usdMesh: USDMesh, metersPerUnit: Double, upAxis: USDUpAxis) throws -> Mesh {
        guard !usdMesh.points.isEmpty else {
            throw ImportError.invalidData("USD Mesh contains no points.")
        }
        let subdivisionScheme = usdMesh.effectiveSubdivisionScheme
        if subdivisionScheme != "none" {
            throw ImportError.invalidData(
                "Unsupported USD feature: subdivisionScheme \(subdivisionScheme) requires subdivision tessellation."
            )
        }
        let expectedIndexCount = try expectedFaceVertexIndexCount(usdMesh.faceVertexCounts)
        guard expectedIndexCount == usdMesh.faceVertexIndices.count else {
            throw ImportError.invalidData("USD Mesh faceVertexIndices count does not match faceVertexCounts.")
        }
        let positions = try usdMesh.points.map { point in
            let convertedPoint = convertToZUp(point, from: upAxis)
            let x = convertedPoint.x * metersPerUnit
            let y = convertedPoint.y * metersPerUnit
            let z = convertedPoint.z * metersPerUnit
            guard x.isFinite, y.isFinite, z.isFinite else {
                throw ImportError.invalidData("USD Mesh point contains a non-finite internal coordinate.")
            }
            return Point3D(x: x, y: y, z: z)
        }
        let normals = try normals(from: usdMesh, positionCount: positions.count, upAxis: upAxis)
        if usdMesh.textureCoordinates != nil || usdMesh.displayColor != nil || usdMesh.displayOpacity != nil {
            return try attributedMesh(
                from: usdMesh,
                positions: positions,
                normals: normals
            )
        }
        let indices = try triangulatedFaceVertexIndices(
            counts: usdMesh.faceVertexCounts,
            indices: usdMesh.faceVertexIndices,
            positionCount: positions.count,
            orientation: usdMesh.orientation ?? .rightHanded
        )
        return Mesh(positions: positions, normals: normals, indices: indices)
    }

    private func normals(from usdMesh: USDMesh, positionCount: Int, upAxis: USDUpAxis) throws -> [Vector3D] {
        guard !usdMesh.normals.isEmpty else {
            return []
        }
        let interpolation = usdMesh.normalsInterpolation ?? "vertex"
        guard interpolation == "vertex" else {
            throw ImportError.invalidData(
                "Unsupported USD feature: Only vertex-interpolated USD Mesh normals are supported."
            )
        }
        guard usdMesh.normals.count == positionCount else {
            throw ImportError.invalidData("USD Mesh vertex normal count does not match point count.")
        }
        return try usdMesh.normals.enumerated().map { index, normal in
            let convertedNormal = convertToZUp(normal, from: upAxis)
            let vector = Vector3D(x: convertedNormal.x, y: convertedNormal.y, z: convertedNormal.z)
            do {
                return try vector.normalized(tolerance: ModelingTolerance.standard.distance)
            } catch {
                throw ImportError.invalidData("USD Mesh normal \(index) is not a finite non-zero vector.")
            }
        }
    }

    private func convertToZUp(_ point: USDPoint3D, from upAxis: USDUpAxis) -> USDPoint3D {
        switch upAxis {
        case .x:
            return USDPoint3D(x: point.y, y: point.z, z: point.x)
        case .y:
            return USDPoint3D(x: point.x, y: -point.z, z: point.y)
        case .z:
            return point
        }
    }

    private func attributedMesh(
        from usdMesh: USDMesh,
        positions: [Point3D],
        normals: [Vector3D]
    ) throws -> Mesh {
        var outputPositions: [Point3D] = []
        var outputNormals: [Vector3D] = []
        var outputTextureCoordinates: [Point2D] = []
        var outputVertexColors: [ColorRGBA] = []
        var outputIndices: [UInt32] = []
        let triangleCount = usdMesh.faceVertexCounts.reduce(0) { $0 + max($1 - 2, 0) }
        outputPositions.reserveCapacity(triangleCount * 3)
        if !normals.isEmpty {
            outputNormals.reserveCapacity(triangleCount * 3)
        }
        if usdMesh.textureCoordinates != nil {
            outputTextureCoordinates.reserveCapacity(triangleCount * 3)
        }
        if usdMesh.displayColor != nil || usdMesh.displayOpacity != nil {
            outputVertexColors.reserveCapacity(triangleCount * 3)
        }
        outputIndices.reserveCapacity(triangleCount * 3)

        let orientation = usdMesh.orientation ?? .rightHanded
        var faceVertexCursor = 0
        for (faceIndex, count) in usdMesh.faceVertexCounts.enumerated() {
            for offset in 1..<(count - 1) {
                let cornerOffsets: [Int]
                switch orientation {
                case .rightHanded:
                    cornerOffsets = [0, offset, offset + 1]
                case .leftHanded:
                    cornerOffsets = [0, offset + 1, offset]
                }
                for cornerOffset in cornerOffsets {
                    let faceVertexIndex = faceVertexCursor + cornerOffset
                    let positionIndex = try meshPositionIndex(
                        usdMesh.faceVertexIndices[faceVertexIndex],
                        positionCount: positions.count
                    )
                    outputPositions.append(positions[positionIndex])
                    if !normals.isEmpty {
                        outputNormals.append(normals[positionIndex])
                    }
                    if let textureCoordinates = usdMesh.textureCoordinates {
                        let textureCoordinate = try self.textureCoordinate(
                            textureCoordinates,
                            faceIndex: faceIndex,
                            faceVertexIndex: faceVertexIndex,
                            positionIndex: positionIndex
                        )
                        outputTextureCoordinates.append(textureCoordinate)
                    }
                    if usdMesh.displayColor != nil || usdMesh.displayOpacity != nil {
                        let vertexColor = try self.vertexColor(
                            displayColor: usdMesh.displayColor,
                            displayOpacity: usdMesh.displayOpacity,
                            faceIndex: faceIndex,
                            faceVertexIndex: faceVertexIndex,
                            positionIndex: positionIndex
                        )
                        outputVertexColors.append(vertexColor)
                    }
                    guard let outputIndex = UInt32(exactly: outputPositions.count - 1) else {
                        throw ImportError.invalidData("USD Mesh expanded vertex count exceeds UInt32 range.")
                    }
                    outputIndices.append(outputIndex)
                }
            }
            faceVertexCursor += count
        }

        return Mesh(
            positions: outputPositions,
            normals: outputNormals,
            indices: outputIndices,
            textureCoordinates: outputTextureCoordinates,
            vertexColors: outputVertexColors
        )
    }

    private func textureCoordinate(
        _ textureCoordinates: USDTextureCoordinatePrimvar,
        faceIndex: Int,
        faceVertexIndex: Int,
        positionIndex: Int
    ) throws -> Point2D {
        let elementIndex = try primvarElementIndex(
            interpolation: textureCoordinates.interpolation,
            faceIndex: faceIndex,
            faceVertexIndex: faceVertexIndex,
            positionIndex: positionIndex,
            name: "primvars:st"
        )
        let valueIndex = try primvarValueIndex(
            indices: textureCoordinates.indices,
            elementIndex: elementIndex,
            valueCount: textureCoordinates.values.count,
            name: "primvars:st"
        )
        let value = textureCoordinates.values[valueIndex]
        guard value.x.isFinite, value.y.isFinite else {
            throw ImportError.invalidData("USD primvars:st contains a non-finite texture coordinate.")
        }
        return Point2D(x: value.x, y: value.y)
    }

    private func vertexColor(
        displayColor: USDDisplayColorPrimvar?,
        displayOpacity: USDDisplayOpacityPrimvar?,
        faceIndex: Int,
        faceVertexIndex: Int,
        positionIndex: Int
    ) throws -> ColorRGBA {
        let color = try displayColor.map {
            try colorValue($0, faceIndex: faceIndex, faceVertexIndex: faceVertexIndex, positionIndex: positionIndex)
        } ?? USDColorRGB(r: 1, g: 1, b: 1)
        let opacity = try displayOpacity.map {
            try opacityValue($0, faceIndex: faceIndex, faceVertexIndex: faceVertexIndex, positionIndex: positionIndex)
        } ?? 1
        let vertexColor = ColorRGBA(r: color.r, g: color.g, b: color.b, a: opacity)
        do {
            try vertexColor.validate()
        } catch {
            throw ImportError.invalidData("USD display color contains a component outside the supported color range.")
        }
        return vertexColor
    }

    private func colorValue(
        _ displayColor: USDDisplayColorPrimvar,
        faceIndex: Int,
        faceVertexIndex: Int,
        positionIndex: Int
    ) throws -> USDColorRGB {
        let elementIndex = try primvarElementIndex(
            interpolation: displayColor.interpolation,
            faceIndex: faceIndex,
            faceVertexIndex: faceVertexIndex,
            positionIndex: positionIndex,
            name: "primvars:displayColor"
        )
        let valueIndex = try primvarValueIndex(
            indices: displayColor.indices,
            elementIndex: elementIndex,
            valueCount: displayColor.values.count,
            name: "primvars:displayColor"
        )
        return displayColor.values[valueIndex]
    }

    private func opacityValue(
        _ displayOpacity: USDDisplayOpacityPrimvar,
        faceIndex: Int,
        faceVertexIndex: Int,
        positionIndex: Int
    ) throws -> Double {
        let elementIndex = try primvarElementIndex(
            interpolation: displayOpacity.interpolation,
            faceIndex: faceIndex,
            faceVertexIndex: faceVertexIndex,
            positionIndex: positionIndex,
            name: "primvars:displayOpacity"
        )
        let valueIndex = try primvarValueIndex(
            indices: displayOpacity.indices,
            elementIndex: elementIndex,
            valueCount: displayOpacity.values.count,
            name: "primvars:displayOpacity"
        )
        return displayOpacity.values[valueIndex]
    }

    private func primvarElementIndex(
        interpolation: String?,
        faceIndex: Int,
        faceVertexIndex: Int,
        positionIndex: Int,
        name: String
    ) throws -> Int {
        switch interpolation ?? "constant" {
        case "constant":
            return 0
        case "uniform":
            return faceIndex
        case "vertex", "varying":
            return positionIndex
        case "faceVarying":
            return faceVertexIndex
        default:
            throw ImportError.invalidData("Unsupported USD feature: \(name) interpolation \(interpolation ?? "").")
        }
    }

    private func primvarValueIndex(indices: [Int]?, elementIndex: Int, valueCount: Int, name: String) throws -> Int {
        let valueIndex: Int
        if let indices {
            guard elementIndex < indices.count else {
                throw ImportError.invalidData("USD \(name) index count does not match its interpolation.")
            }
            valueIndex = indices[elementIndex]
        } else {
            valueIndex = elementIndex
        }
        guard valueIndex >= 0, valueIndex < valueCount else {
            throw ImportError.invalidData("USD \(name) index is outside the value range.")
        }
        return valueIndex
    }

    private func expectedFaceVertexIndexCount(_ counts: [Int]) throws -> Int {
        guard !counts.isEmpty else {
            throw ImportError.invalidData("USD Mesh contains no faces.")
        }
        var total = 0
        for count in counts {
            guard count >= 3 else {
                throw ImportError.invalidData("USD Mesh faces must contain at least three vertices.")
            }
            guard total <= Int.max - count else {
                throw ImportError.invalidData("USD Mesh faceVertexCounts exceed platform range.")
            }
            total += count
        }
        return total
    }

    private func triangulatedFaceVertexIndices(
        counts: [Int],
        indices: [Int],
        positionCount: Int,
        orientation: USDOrientation
    ) throws -> [UInt32] {
        var output: [UInt32] = []
        let triangleCount = counts.reduce(0) { $0 + max($1 - 2, 0) }
        output.reserveCapacity(triangleCount * 3)
        var cursor = 0
        for count in counts {
            let first = try meshIndex(indices[cursor], positionCount: positionCount)
            for offset in 1..<(count - 1) {
                let current = try meshIndex(indices[cursor + offset], positionCount: positionCount)
                let next = try meshIndex(indices[cursor + offset + 1], positionCount: positionCount)
                output.append(first)
                switch orientation {
                case .rightHanded:
                    output.append(current)
                    output.append(next)
                case .leftHanded:
                    output.append(next)
                    output.append(current)
                }
            }
            cursor += count
        }
        return output
    }

    private func meshIndex(_ index: Int, positionCount: Int) throws -> UInt32 {
        let index = try meshPositionIndex(index, positionCount: positionCount)
        guard let value = UInt32(exactly: index) else {
            throw ImportError.invalidData("USD Mesh face index does not fit UInt32.")
        }
        return value
    }

    private func meshPositionIndex(_ index: Int, positionCount: Int) throws -> Int {
        guard index >= 0, index < positionCount else {
            throw ImportError.invalidData("USD Mesh face index is out of range.")
        }
        return index
    }

    private func lengthUnit(forMetersPerUnit metersPerUnit: Double) throws -> LengthUnit {
        guard metersPerUnit.isFinite, metersPerUnit > 0 else {
            throw ImportError.invalidData("USD metersPerUnit must be a positive finite value.")
        }
        let tolerance = max(1.0e-12, metersPerUnit * 1.0e-9)
        guard let unit = LengthUnit.allCases.first(where: { abs($0.metersPerUnit - metersPerUnit) <= tolerance }) else {
            throw ImportError.invalidData("USD metersPerUnit does not map to a supported length unit.")
        }
        return unit
    }

    private func validateImportedMesh(_ mesh: Mesh, sourceName: String) throws {
        do {
            try mesh.validate()
        } catch let error as ExportError {
            throw ImportError.invalidData("\(sourceName) mesh is invalid: \(error).")
        }
    }
}

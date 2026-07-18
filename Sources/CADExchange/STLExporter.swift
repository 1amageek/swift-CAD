import Foundation
import CADCore
import CADIR

public struct STLExportOptions: Sendable, Hashable {
    public var lengthUnit: LengthUnit

    public init(lengthUnit: LengthUnit = .meter) {
        self.lengthUnit = lengthUnit
    }
}

public struct STLExporter: Sendable {
    private let tolerance: ModelingTolerance

    public init(tolerance: ModelingTolerance) {
        self.tolerance = tolerance
    }

    public func writeBinary(meshes: [BodyID: Mesh], options: STLExportOptions = STLExportOptions(), to sink: any ByteSink) throws {
        guard !meshes.isEmpty else {
            throw ExportError.emptyMesh
        }
        let triangleCount = try meshes.values.reduce(0) { partial, mesh in
            try mesh.validate(tolerance: tolerance)
            return partial + mesh.indices.count / 3
        }
        guard UInt64(triangleCount) <= UInt64(UInt32.max) else {
            throw ExportError.triangleCountOverflow
        }

        let headerText = "Swift-CAD binary STL unit=\(options.lengthUnit.rawValue)"
        var data = Data(headerText.utf8.prefix(80))
        if data.count < 80 {
            data.append(Data(repeating: 0, count: 80 - data.count))
        }
        try sink.write(data)
        try sink.writeLittleEndian(UInt32(triangleCount))

        for (_, mesh) in meshes.sorted(by: { $0.key.description < $1.key.description }) {
            var index = 0
            while index < mesh.indices.count {
                let firstIndex = Int(mesh.indices[index])
                let secondIndex = Int(mesh.indices[index + 1])
                let thirdIndex = Int(mesh.indices[index + 2])
                let first = mesh.positions[firstIndex]
                let second = mesh.positions[secondIndex]
                let third = mesh.positions[thirdIndex]
                let normal = try normal(for: mesh, firstIndex: firstIndex, first: first, second: second, third: third)
                try write(vector: normal, to: sink)
                try write(point: first, unit: options.lengthUnit, to: sink)
                try write(point: second, unit: options.lengthUnit, to: sink)
                try write(point: third, unit: options.lengthUnit, to: sink)
                try sink.writeLittleEndian(UInt16(0))
                index += 3
            }
        }
    }

    public func importBinary(_ source: any ByteSource) throws -> ImportedExchangeModel {
        try source.withUnsafeBytes { bytes in
            try importBinary(bytes)
        }
    }

    private func importBinary(_ bytes: UnsafeRawBufferPointer) throws -> ImportedExchangeModel {
        guard bytes.count >= 84 else {
            throw ImportError.invalidData("Binary STL is too short.")
        }
        let triangleCount32 = try bytes.littleEndianUInt32(at: 80)
        guard triangleCount32 <= UInt32.max / 3 else {
            throw ImportError.invalidData("Binary STL triangle count exceeds UInt32 index range.")
        }
        let expectedSize64 = UInt64(84) + UInt64(triangleCount32) * UInt64(50)
        guard expectedSize64 <= UInt64(Int.max) else {
            throw ImportError.invalidData("Binary STL triangle count is too large.")
        }
        guard UInt64(bytes.count) == expectedSize64 else {
            throw ImportError.invalidData("Binary STL triangle payload size does not match the header count.")
        }
        let triangleCount = Int(triangleCount32)

        let unit = try stlLengthUnit(in: bytes, fallback: .meter)
        var positions: [Point3D] = []
        var normals: [Vector3D] = []
        var indices: [UInt32] = []
        positions.reserveCapacity(triangleCount * 3)
        normals.reserveCapacity(triangleCount * 3)
        indices.reserveCapacity(triangleCount * 3)

        var offset = 84
        for triangleIndex in 0..<triangleCount {
            let rawNormal = Vector3D(
                x: Double(try bytes.littleEndianFloat32(at: offset)),
                y: Double(try bytes.littleEndianFloat32(at: offset + 4)),
                z: Double(try bytes.littleEndianFloat32(at: offset + 8))
            )
            guard rawNormal.isFinite else {
                throw ImportError.invalidData("STL normal contains a non-finite component.")
            }
            offset += 12
            let base = UInt32(triangleIndex * 3)
            var trianglePoints: [Point3D] = []
            trianglePoints.reserveCapacity(3)
            for vertexOffset in 0..<3 {
                let start = offset + vertexOffset * 12
                trianglePoints.append(Point3D(
                    x: unit.toInternal(Double(try bytes.littleEndianFloat32(at: start))),
                    y: unit.toInternal(Double(try bytes.littleEndianFloat32(at: start + 4))),
                    z: unit.toInternal(Double(try bytes.littleEndianFloat32(at: start + 8)))
                ))
            }
            let normal = try normalForImportedSTLTriangle(rawNormal: rawNormal, points: trianglePoints)
            for vertexOffset in 0..<3 {
                positions.append(trianglePoints[vertexOffset])
                normals.append(normal)
                indices.append(base + UInt32(vertexOffset))
            }
            let attributeByteCount = try bytes.littleEndianUInt16(at: offset + 36)
            guard attributeByteCount == 0 else {
                throw ImportError.invalidData("STL facet attributes are not supported.")
            }
            offset += 38
        }

        let bodyID = BodyID()
        let mesh = Mesh(positions: positions, normals: normals, indices: indices)
        try validateImportedMesh(mesh, formatName: "STL", tolerance: tolerance)
        return ImportedExchangeModel(format: .stl, meshes: [bodyID: mesh], units: UnitSystem(length: unit, angle: .radian))
    }

    private func normal(
        for mesh: Mesh,
        firstIndex: Int,
        first: Point3D,
        second: Point3D,
        third: Point3D
    ) throws -> Vector3D {
        if !mesh.normals.isEmpty {
            return mesh.normals[firstIndex]
        }
        return try (second - first).cross(third - first).normalized(tolerance: tolerance.distance)
    }

    private func normalForImportedSTLTriangle(rawNormal: Vector3D, points: [Point3D]) throws -> Vector3D {
        if rawNormal.length > tolerance.distance {
            return try rawNormal.normalized(tolerance: tolerance.distance)
        }
        guard points.count == 3 else {
            throw ImportError.invalidData("STL triangle must contain exactly three vertices.")
        }
        do {
            return try (points[1] - points[0])
                .cross(points[2] - points[0])
                .normalized(tolerance: tolerance.distance)
        } catch {
            throw ImportError.invalidData("STL triangle normal cannot be derived from degenerate geometry.")
        }
    }

    private func write(point: Point3D, unit: LengthUnit, to sink: any ByteSink) throws {
        try writeSTLFloat32(unit.fromInternal(point.x), label: "point.x", to: sink)
        try writeSTLFloat32(unit.fromInternal(point.y), label: "point.y", to: sink)
        try writeSTLFloat32(unit.fromInternal(point.z), label: "point.z", to: sink)
    }

    private func write(vector: Vector3D, to sink: any ByteSink) throws {
        try writeSTLFloat32(vector.x, label: "normal.x", to: sink)
        try writeSTLFloat32(vector.y, label: "normal.y", to: sink)
        try writeSTLFloat32(vector.z, label: "normal.z", to: sink)
    }
}

private func writeSTLFloat32(_ value: Double, label: String, to sink: any ByteSink) throws {
    let value32 = Float32(value)
    guard value32.isFinite else {
        throw ExportError.invalidMesh("STL \(label) is outside Float32 range.")
    }
    try sink.writeLittleEndianFloat32(value32)
}

private let swiftCADSTLUnitHeaderPrefix = "Swift-CAD binary STL unit="

private func stlLengthUnit(in bytes: UnsafeRawBufferPointer, fallback: LengthUnit) throws -> LengthUnit {
    let prefix = Array(swiftCADSTLUnitHeaderPrefix.utf8)
    guard bytes.count >= 80,
          bytes.starts(with: prefix) else {
        return fallback
    }

    let valueStart = swiftCADSTLUnitHeaderPrefix.utf8.count
    let suffix = (valueStart..<80).map { bytes[$0] }
    let tokenEnd = suffix.firstIndex(where: isSTLHeaderPadding) ?? suffix.endIndex
    let tokenBytes = suffix[suffix.startIndex..<tokenEnd]
    guard !tokenBytes.isEmpty,
          let value = String(bytes: tokenBytes, encoding: .utf8) else {
        throw ImportError.invalidData("STL unit marker has no value.")
    }
    guard suffix[tokenEnd..<suffix.endIndex].allSatisfy(isSTLHeaderPadding) else {
        throw ImportError.invalidData("STL unit marker contains unsupported trailing data.")
    }
    guard let unit = parseLengthUnitName(value) else {
        throw ImportError.invalidData("Unsupported STL unit \(value).")
    }
    return unit
}

private func isSTLHeaderPadding(_ byte: UInt8) -> Bool {
    byte == 0 || byte == 9 || byte == 10 || byte == 13 || byte == 32
}

private extension UnsafeRawBufferPointer {
    func starts(with prefix: [UInt8]) -> Bool {
        guard count >= prefix.count else {
            return false
        }
        for index in prefix.indices where self[index] != prefix[index] {
            return false
        }
        return true
    }
}

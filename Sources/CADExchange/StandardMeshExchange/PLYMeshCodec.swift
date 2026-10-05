import Foundation
import CADCore
import CADIR

extension StandardMeshExchange {
    func readPLY(_ data: Data, explicitUnit: LengthUnit?,
                 resources: inout ExchangeResourceAccountant) throws -> ImportedExchangeModel {
        var offset = 0
        var lines: [String] = []
        while offset < data.count {
            let start = offset
            while offset < data.count, data[offset] != 10 { offset += 1; try resources.recordIterations() }
            guard offset < data.count, let line = String(data: data[start..<offset], encoding: .utf8) else {
                throw ImportError.invalidData("PLY header is incomplete or not UTF-8.")
            }
            offset += 1
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            try resources.recordEntities()
            lines.append(trimmed)
            if trimmed == "end_header" { break }
        }
        guard lines.first == "ply", lines.last == "end_header", lines.count >= 3 else { throw ImportError.invalidData("Missing PLY header.") }
        let encoding = lines[1].split(whereSeparator: \.isWhitespace).map(String.init)
        guard encoding.count == 3, encoding[0] == "format", encoding[2] == "1.0",
              ["ascii", "binary_little_endian", "binary_big_endian"].contains(encoding[1]) else {
            throw ImportError.unsupportedVersion("Unsupported PLY format declaration.")
        }
        var declaredUnit: LengthUnit?
        var vertexCount = 0, faceCount = 0
        var properties: [(String, PLYScalar)] = []
        var faceTypes: (PLYScalar, PLYScalar)?
        var element = ""
        for line in lines.dropFirst(2).dropLast() {
            let p = line.split(whereSeparator: \.isWhitespace).map(String.init)
            guard let head = p.first else { continue }
            if head == "comment" {
                if p.count >= 2, p[1] == "unit" {
                    guard p.count == 3, declaredUnit == nil, let unit = parseLengthUnitName(p[2]) else { throw ImportError.invalidData("Invalid or duplicate PLY unit marker.") }
                    declaredUnit = unit
                }
                continue
            }
            if head == "element" {
                guard p.count == 3, let count = Int(p[2]), count > 0,
                      count <= resources.limits.maximumEntities else { throw ImportError.invalidData("Invalid PLY element count.") }
                if p[1] == "vertex", element.isEmpty { vertexCount = count; element = "vertex" }
                else if p[1] == "face", element == "vertex" { faceCount = count; element = "face" }
                else { throw ImportError.unsupportedFeature("Only PLY vertex followed by face elements are supported.") }
            } else if head == "property" {
                if element == "vertex" {
                    guard p.count == 3, let type = PLYScalar(p[1]),
                          ["x", "y", "z", "nx", "ny", "nz", "red", "green", "blue", "alpha", "s", "t"].contains(p[2]),
                          !properties.contains(where: { $0.0 == p[2] }) else {
                        throw ImportError.unsupportedFeature("Unsupported or duplicate PLY vertex property.")
                    }
                    properties.append((p[2], type))
                } else if element == "face" {
                    guard p.count == 5, p[1] == "list", ["vertex_indices", "vertex_index"].contains(p[4]),
                          let countType = PLYScalar(p[2]), countType.isInteger,
                          let indexType = PLYScalar(p[3]), indexType.isInteger,
                          faceTypes == nil else { throw ImportError.unsupportedFeature("Unsupported PLY face properties.") }
                    faceTypes = (countType, indexType)
                } else { throw ImportError.invalidData("PLY property precedes an element.") }
            } else { throw ImportError.unsupportedFeature("Unsupported PLY header record \(head).") }
        }
        let names = Set(properties.map(\.0))
        guard names.isSuperset(of: ["x", "y", "z"]), let faceTypes, faceCount > 0 else { throw ImportError.invalidData("PLY lacks geometry properties.") }
        for group: Set<String> in [["nx", "ny", "nz"], ["red", "green", "blue"], ["s", "t"]] {
            guard names.isDisjoint(with: group) || names.isSuperset(of: group) else { throw ImportError.invalidData("PLY attribute property group is incomplete.") }
        }
        if names.contains("alpha"), !names.contains("red") { throw ImportError.invalidData("PLY alpha requires RGB.") }
        guard let unit = declaredUnit ?? explicitUnit else { throw ImportError.invalidData("Unitless PLY requires an explicit caller unit.") }
        let triangleIndexCount = faceCount.multipliedReportingOverflow(by: 3)
        guard !triangleIndexCount.overflow else {
            throw exchangeResourceLimitError(format: .ply, detail: "face index count exceeds the platform integer range.")
        }
        try meshStorageAdmission(vertexCount: vertexCount, indexCount: triangleIndexCount.partialValue, resources: &resources)
        var cursor = try PLYCursor(data: data, offset: offset, encoding: encoding[1], resources: &resources)
        var mesh = Mesh()
        mesh.positions.reserveCapacity(vertexCount)
        for _ in 0..<vertexCount {
            try resources.recordIterations()
            var values: [String: Double] = [:]
            for (name, type) in properties {
                var value = try cursor.scalar(type)
                if ["red", "green", "blue", "alpha"].contains(name), type.isInteger {
                    guard type.width == 1, !type.signed else { throw ImportError.unsupportedFeature("PLY integer colors must be uchar.") }
                    value /= 255
                }
                values[name] = value
            }
            mesh.positions.append(Point3D(x: unit.toInternal(values["x"]!), y: unit.toInternal(values["y"]!), z: unit.toInternal(values["z"]!)))
            if names.contains("nx") {
                let n = Vector3D(x: values["nx"]!, y: values["ny"]!, z: values["nz"]!)
                guard n.length > 0, n.length.isFinite else { throw ImportError.invalidData("Invalid PLY normal.") }
                mesh.normals.append(n / n.length)
            }
            if names.contains("s") { mesh.textureCoordinates.append(Point2D(x: values["s"]!, y: values["t"]!)) }
            if names.contains("red") { mesh.vertexColors.append(ColorRGBA(r: values["red"]!, g: values["green"]!, b: values["blue"]!, a: values["alpha"] ?? 1)) }
        }
        let triangulator = ExchangePolygonTriangulator()
        for _ in 0..<faceCount {
            let rawCount = try cursor.scalar(faceTypes.0)
            guard rawCount >= 3, rawCount <= Double(vertexCount), rawCount <= Double(resources.limits.maximumEntities) else { throw ImportError.invalidData("Invalid PLY face vertex count.") }
            let count = Int(rawCount)
            try resources.recordIterations(meshResourceProduct(count, count, format: .ply))
            try resources.recordEntities(count)
            try resources.recordBytes(meshResourceProduct(count, 32, format: .ply), label: "polygon")
            var indices: [UInt32] = []
            for _ in 0..<count {
                let index = try cursor.scalar(faceTypes.1)
                guard index >= 0, index < Double(vertexCount) else { throw ImportError.invalidData("PLY face index is out of range.") }
                indices.append(UInt32(index))
            }
            let triangles = try triangulator.triangles(for: indices.map { mesh.positions[Int($0)] }, tolerance: tolerance)
            try resources.recordBytes(meshResourceProduct(triangles.count, 12, format: .ply), label: "triangulated indices")
            for t in triangles { mesh.indices.append(contentsOf: [indices[t.0], indices[t.1], indices[t.2]]) }
        }
        try cursor.finish()
        try validateImportedMesh(mesh, formatName: "PLY", tolerance: tolerance)
        return ImportedExchangeModel(format: .ply, meshes: [BodyID(): mesh], units: UnitSystem(length: unit, angle: .radian))
    }

    func writePLY(_ meshes: [Mesh], unit: LengthUnit,
                  resources: inout ExchangeResourceAccountant) throws -> Data {
        let first = meshes[0]
        guard meshes.allSatisfy({ $0.normals.isEmpty == first.normals.isEmpty && $0.textureCoordinates.isEmpty == first.textureCoordinates.isEmpty && $0.vertexColors.isEmpty == first.vertexColors.isEmpty }) else {
            throw ExportError.unsupportedFeature("PLY flattening requires matching mesh attribute layouts.")
        }
        let vertices = meshes.reduce(0) { $0 + $1.positions.count }
        let faces = meshes.reduce(0) { $0 + $1.indices.count / 3 }
        guard UInt64(vertices) <= UInt64(UInt32.max) else { throw ExportError.invalidMesh("PLY flattened index overflow.") }
        var output = Data()
        try meshBoundedAppend("ply\nformat ascii 1.0\ncomment unit \(unit.rawValue)\nelement vertex \(vertices)\nproperty double x\nproperty double y\nproperty double z\n", to: &output, resources: &resources)
        if !first.normals.isEmpty { try meshBoundedAppend("property double nx\nproperty double ny\nproperty double nz\n", to: &output, resources: &resources) }
        if !first.textureCoordinates.isEmpty { try meshBoundedAppend("property double s\nproperty double t\n", to: &output, resources: &resources) }
        if !first.vertexColors.isEmpty { try meshBoundedAppend("property double red\nproperty double green\nproperty double blue\nproperty double alpha\n", to: &output, resources: &resources) }
        try meshBoundedAppend("element face \(faces)\nproperty list uchar uint vertex_indices\nend_header\n", to: &output, resources: &resources)
        for mesh in meshes {
            for i in mesh.positions.indices {
                let p = mesh.positions[i]
                let xyz = [unit.fromInternal(p.x), unit.fromInternal(p.y), unit.fromInternal(p.z)]
                guard xyz.allSatisfy(\.isFinite) else { throw ExportError.invalidMesh("PLY coordinate unit conversion overflow.") }
                var values = xyz
                if !mesh.normals.isEmpty { let n = mesh.normals[i]; values += [n.x, n.y, n.z] }
                if !mesh.textureCoordinates.isEmpty { let t = mesh.textureCoordinates[i]; values += [t.x, t.y] }
                if !mesh.vertexColors.isEmpty { let c = mesh.vertexColors[i]; values += [c.r, c.g, c.b, c.a] }
                try meshBoundedAppend(values.map(String.init(describing:)).joined(separator: " ") + "\n", to: &output, resources: &resources)
            }
        }
        var base: UInt32 = 0
        for mesh in meshes {
            for i in stride(from: 0, to: mesh.indices.count, by: 3) {
                try meshBoundedAppend("3 \(base + mesh.indices[i]) \(base + mesh.indices[i+1]) \(base + mesh.indices[i+2])\n", to: &output, resources: &resources)
            }
            base += UInt32(mesh.positions.count)
        }
        return output
    }
}

private struct PLYScalar {
    let width: Int
    let signed: Bool
    let isInteger: Bool
    init?(_ name: String) {
        switch name {
        case "char", "int8": width = 1; signed = true; isInteger = true
        case "uchar", "uint8": width = 1; signed = false; isInteger = true
        case "short", "int16": width = 2; signed = true; isInteger = true
        case "ushort", "uint16": width = 2; signed = false; isInteger = true
        case "int", "int32": width = 4; signed = true; isInteger = true
        case "uint", "uint32": width = 4; signed = false; isInteger = true
        case "float", "float32": width = 4; signed = true; isInteger = false
        case "double", "float64": width = 8; signed = true; isInteger = false
        default: return nil
        }
    }
}

private struct PLYCursor {
    let data: Data
    var offset: Int
    let ascii: Bool
    let little: Bool
    init(data: Data, offset: Int, encoding: String, resources: inout ExchangeResourceAccountant) throws {
        self.data = data; self.offset = offset; ascii = encoding == "ascii"; little = encoding != "binary_big_endian"
        try resources.recordIterations(data.count - offset)
    }
    mutating func skipWhitespace() {
        while offset < data.count, [UInt8(9), 10, 13, 32].contains(data[offset]) { offset += 1 }
    }
    mutating func scalar(_ type: PLYScalar) throws -> Double {
        let value: Double
        if ascii {
            skipWhitespace()
            let start = offset
            while offset < data.count, ![UInt8(9), 10, 13, 32].contains(data[offset]) { offset += 1 }
            guard offset > start, offset - start <= 128,
                  let text = String(data: data[start..<offset], encoding: .utf8),
                  let parsed = Double(text) else { throw ImportError.invalidData("Incomplete or invalid PLY scalar.") }
            value = parsed
        } else {
            let raw = try meshUInt(data, offset: offset, width: type.width, littleEndian: little)
            offset += type.width
            if type.isInteger {
                if type.signed {
                    let shift = 64 - type.width * 8
                    value = Double(Int64(bitPattern: raw << shift) >> shift)
                } else { value = Double(raw) }
            } else if type.width == 4 { value = Double(Float(bitPattern: UInt32(raw))) }
            else { value = Double(bitPattern: raw) }
        }
        guard value.isFinite else { throw ImportError.invalidData("Nonfinite PLY scalar.") }
        if type.isInteger {
            let maximum = pow(2, Double(type.width * 8 - (type.signed ? 1 : 0))) - 1
            let minimum = type.signed ? -maximum - 1 : 0
            guard value.rounded(.towardZero) == value, value >= minimum, value <= maximum else { throw ImportError.invalidData("PLY scalar exceeds its declared integer type.") }
        }
        return value
    }
    mutating func finish() throws {
        if ascii { skipWhitespace() }
        guard offset == data.count else { throw ImportError.invalidData("Trailing PLY body records.") }
    }
}

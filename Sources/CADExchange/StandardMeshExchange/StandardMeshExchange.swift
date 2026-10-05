import Foundation
import CoreFoundation
import CADCore
import CADIR

public struct StandardMeshExchange: StandardMeshExchanging {
    let tolerance: ModelingTolerance
    let resourceLimits: ExchangeResourceLimits

    public init(tolerance: ModelingTolerance, resourceLimits: ExchangeResourceLimits = .standard) {
        self.tolerance = tolerance
        self.resourceLimits = resourceLimits
    }

    // FIXME(INCOMPLETE_IMPLEMENTATION): Standard mesh readers currently admit a static
    // triangle-scene subset through OfficialFormatExchange's memory and URL routes.
    // Materials, animation, skinning, custom semantic fields, and other declared
    // unsupported domains must preserve their semantics before full format parity
    // is claimed; these domains currently return an explicit typed refusal.
    public func read(_ source: any ByteSource, as format: ExchangeFileFormat,
                     explicitUnit: LengthUnit? = nil,
                     resolver: (any StandardMeshBufferResolving)? = nil) throws -> ImportedExchangeModel {
        var resources = try ExchangeResourceAccountant(limits: resourceLimits, format: format)
        try resources.validateInputByteCount(source.count)
        try resources.recordBytes(source.count, label: "source")
        return try source.withNoCopyData { data in
            let result: ImportedExchangeModel
            switch format {
            case .gltf, .glb:
                result = try readGLTF(data, format: format, resolver: resolver, resources: &resources)
            case .ply:
                result = try readPLY(data, explicitUnit: explicitUnit, resources: &resources)
            case .vrml:
                result = try readVRML(data, resources: &resources)
            default:
                throw ImportError.unsupportedFormat(format.displayName)
            }
            try resources.checkTime()
            return result
        }
    }

    // FIXME(INCOMPLETE_IMPLEMENTATION): Standard mesh export currently projects native
    // provenance to geometry and refuses unrepresented material/transparency domains.
    // OfficialFormatExchange calls this path; complete semantic attribute exchange
    // and independent interoperability evidence are required before full parity.
    public func write(meshes: [BodyID: Mesh], as format: ExchangeFileFormat,
                      unit: LengthUnit = .meter, to sink: any ByteSink) throws {
        var resources = try ExchangeResourceAccountant(limits: resourceLimits, format: format)
        guard !meshes.isEmpty else { throw ExportError.emptyMesh }
        let ordered = meshes.sorted { $0.key.description < $1.key.description }.map(\.value)
        for mesh in ordered {
            try resources.checkTime()
            try meshStorageAdmission(vertexCount: mesh.positions.count, indexCount: mesh.indices.count, resources: &resources)
            try resources.recordIterations(mesh.positions.count + mesh.indices.count)
            try mesh.validate(tolerance: tolerance)
            guard mesh.material == nil else {
                throw ExportError.unsupportedFeature("Standard mesh exchange cannot preserve a material reference.")
            }
            // Face provenance belongs to native topology; standard mesh formats
            // carry geometric triangles and never claim exact B-rep provenance.
        }
        let data: Data
        switch format {
        case .gltf, .glb: data = try writeGLTF(ordered, format: format, resources: &resources)
        case .ply: data = try writePLY(ordered, unit: unit, resources: &resources)
        case .vrml: data = try writeVRML(ordered, resources: &resources)
        default: throw ExportError.unsupportedFeature(format.displayName)
        }
        try resources.checkTime()
        try sink.write(data)
    }
}

func meshResourceProduct(_ left: Int, _ right: Int, format: ExchangeFileFormat) throws -> Int {
    let result = left.multipliedReportingOverflow(by: right)
    guard left >= 0, right >= 0, !result.overflow else {
        throw exchangeResourceLimitError(format: format, detail: "derived work exceeds the platform integer range.")
    }
    return result.partialValue
}

func meshStorageAdmission(vertexCount: Int, indexCount: Int,
                          resources: inout ExchangeResourceAccountant) throws {
    guard vertexCount >= 0, indexCount >= 0,
          UInt64(vertexCount) <= UInt64(UInt32.max),
          vertexCount <= resources.limits.maximumBytes / 112,
          indexCount <= resources.limits.maximumBytes / 4 else {
        throw exchangeResourceLimitError(format: resources.format, detail: "derived mesh size is not admissible.")
    }
    let entities = vertexCount.addingReportingOverflow(indexCount)
    let bytes = (vertexCount * 112).addingReportingOverflow(indexCount * 4)
    guard !entities.overflow, !bytes.overflow else {
        throw exchangeResourceLimitError(format: resources.format, detail: "derived mesh accounting exceeds the platform integer range.")
    }
    try resources.recordEntities(entities.partialValue)
    try resources.recordBytes(bytes.partialValue, label: "derived mesh")
}

func meshNumber(_ value: Any?, label: String) throws -> Double {
    guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID(),
          number.doubleValue.isFinite else {
        throw ImportError.invalidData("Invalid numeric \(label).")
    }
    return number.doubleValue
}

func meshInteger(_ value: Any?, label: String, default defaultValue: Int? = nil) throws -> Int {
    if value == nil, let defaultValue { return defaultValue }
    let number = try meshNumber(value, label: label)
    guard number >= 0, number < Double(Int.max), number.rounded(.towardZero) == number else {
        throw ImportError.invalidData("Invalid nonnegative integer \(label).")
    }
    return Int(number)
}

func meshDoubles(_ value: Any?, count: Int, fallback: [Double]? = nil) throws -> [Double] {
    if value == nil, let fallback { return fallback }
    guard let array = value as? [Any], array.count == count else {
        throw ImportError.invalidData("Invalid vector dimension.")
    }
    return try array.map { try meshNumber($0, label: "vector") }
}

func meshUnsupportedKeys(_ object: [String: Any], allowed: Set<String>) throws {
    if let key = object.keys.sorted().first(where: { !allowed.contains($0) }) {
        throw ImportError.unsupportedFeature("Unrepresented mesh property \(key).")
    }
}

func meshUInt(_ data: Data, offset: Int, width: Int, littleEndian: Bool = true) throws -> UInt64 {
    guard offset >= 0, width > 0, width <= 8, offset <= data.count - width else {
        throw ImportError.invalidData("Binary mesh record exceeds its buffer.")
    }
    var value: UInt64 = 0
    for i in 0..<width {
        let shift = (littleEndian ? i : width - i - 1) * 8
        value |= UInt64(data[data.startIndex + offset + i]) << shift
    }
    return value
}

func meshAppend(_ value: UInt32, to data: inout Data) {
    var value = value.littleEndian
    Swift.withUnsafeBytes(of: &value) { data.append(contentsOf: $0) }
}

func meshAppendFloat(_ value: Double, to data: inout Data) throws {
    let float = Float(value)
    guard float.isFinite else { throw ExportError.invalidMesh("Coordinate exceeds glTF Float32 range.") }
    meshAppend(float.bitPattern, to: &data)
}

func meshBoundedAppend(_ text: String, to data: inout Data,
                       resources: inout ExchangeResourceAccountant) throws {
    try resources.recordIterations()
    try resources.recordBytes(text.utf8.count, label: "output")
    data.append(contentsOf: text.utf8)
}

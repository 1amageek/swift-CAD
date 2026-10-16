#if !hasFeature(Embedded)
import CADCore
import CADGeometry
import CADTopology

/// Canonical wire maps preserve existing tagged-key Codable representation without duplicate-key overwrite.
package enum IndependentShapeMapCoding {
    private enum GeometryKeys: String, CodingKey { case curves, surfaces }
    static func decodeGeometry(from decoder: Decoder) throws -> GeometryStore {
        let c = try decoder.container(keyedBy: GeometryKeys.self)
        try c.validateOnlyExpectedKeys([.curves, .surfaces], in: decoder)
        let curves: [CurveID: Curve3D] = try decode(from: c.superDecoder(forKey: .curves))
        let surfaces: [SurfaceID: Surface3D] = try decode(from: c.superDecoder(forKey: .surfaces))
        return GeometryStore(curves: curves, surfaces: surfaces)
    }
    static func encodeGeometry(_ geometry: GeometryStore, to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: GeometryKeys.self)
        var curves = c.nestedUnkeyedContainer(forKey: .curves)
        for id in geometry.curves.keys.sorted() {
            try CurrentTaskCancellationChecker().checkCancellation()
            try curves.encode(id); try curves.encode(geometry.curves[id]!)
        }
        var surfaces = c.nestedUnkeyedContainer(forKey: .surfaces)
        for id in geometry.surfaces.keys.sorted() {
            try CurrentTaskCancellationChecker().checkCancellation()
            try surfaces.encode(id); try surfaces.encode(geometry.surfaces[id]!)
        }
    }
    static func decode<Key: Decodable & Hashable, Value: Decodable>(from decoder: Decoder) throws -> [Key: Value] {
        guard #available(macOS 15.0, iOS 18.0, visionOS 2.0, watchOS 11.0, tvOS 18.0, *) else {
            throw NativeRationalSourceDecodingError.synchronizationCapabilityUnavailable
        }
        try OriginalAffineWordDecodingContext.validateSourceNesting(from: decoder)
        var allowance = try NativeRationalSourceDecodingContext.execution(from: decoder)
        try allowance.visitCell(axis: .value, depth: 0)
        var c = try decoder.unkeyedContainer()
        guard let count = c.count, count.isMultiple(of: 2) else {
            throw DecodingError.dataCorrupted(.init(codingPath: c.codingPath, debugDescription: "Expected complete original key/value pairs."))
        }
        try allowance.consumeWork(count)
        let bytes = (count / 2).multipliedReportingOverflow(by: MemoryLayout<(Key, Value)>.stride)
        guard !bytes.overflow else { throw IndependentShapeSourceError.resourceLimitExceeded("Original source pair storage overflow.") }
        let stride = MemoryLayout<UInt32>.stride
        try RationalAlgebraStorage.retain(bytes.partialValue / stride + (bytes.partialValue % stride == 0 ? 0 : 1), of: UInt32.self, usage: &allowance)
        var result: [Key: Value] = [:]
        result.reserveCapacity(count / 2)
        while !c.isAtEnd {
            try CurrentTaskCancellationChecker().checkCancellation()
            try allowance.visitCell(axis: .value, depth: 0)
            let id = try c.decode(Key.self)
            guard result[id] == nil else {
                throw DecodingError.dataCorrupted(.init(codingPath: c.codingPath, debugDescription: "Duplicate original source map key."))
            }
            result[id] = try c.decode(Value.self)
        }
        return result
    }
    static func encode<Key: Encodable & Comparable & Hashable, Value: Encodable>(_ labels: [Key: Value], to encoder: Encoder) throws {
        var c = encoder.unkeyedContainer()
        for id in labels.keys.sorted() {
            try CurrentTaskCancellationChecker().checkCancellation()
            try c.encode(id); try c.encode(labels[id]!)
        }
    }
}

#endif

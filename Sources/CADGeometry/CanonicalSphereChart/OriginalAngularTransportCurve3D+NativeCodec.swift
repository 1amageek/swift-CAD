#if !hasFeature(Embedded)
import CADCore
extension OriginalAngularTransportCurve3D: Codable {
    private enum Keys: String, CodingKey { case source, transport }
    public init(from decoder: Decoder) throws {
        if #available(macOS 15, iOS 18, visionOS 2, watchOS 11, tvOS 18, *) {
            var usage = try NativeRationalSourceDecodingContext.execution(from: decoder)
            try OriginalAffineWordDecodingContext.validateSourceNesting(from: decoder)
            try usage.visitCell(axis: .value, depth: 0)
            let c = try decoder.container(keyedBy: Keys.self)
            try usage.consumeWork(c.allKeys.count)
            try c.validateOnlyExpectedKeys([.source, .transport], in: decoder)
            let source = try c.decode(Curve3D.self, forKey: .source)
            try self.init(source: source, transport: try c.decode(OriginalAngularParameterTransport.self, forKey: .transport),
                tolerance: OriginalAffineWordDecodingContext.tolerance(from: decoder), usage: &usage)
        } else { throw NativeRationalSourceDecodingError.synchronizationCapabilityUnavailable }
    }
    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: Keys.self)
        try c.encode(source, forKey: .source)
        try c.encode(transport, forKey: .transport)
    }
}
#endif

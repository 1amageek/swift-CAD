#if !hasFeature(Embedded)
import CADCore
extension OriginalAngularTransportSurface3D: Codable {
    private enum Keys: String, CodingKey { case source, uTransport, vTransport }
    public init(from decoder: Decoder) throws {
        if #available(macOS 15, iOS 18, visionOS 2, watchOS 11, tvOS 18, *) {
            var usage = try NativeRationalSourceDecodingContext.allowance(from: decoder)
            try OriginalAffineWordDecodingContext.validateSourceNesting(from: decoder)
            try usage.visitExactCell(depth: 0)
            let c = try decoder.container(keyedBy: Keys.self)
            try usage.consumeExactWork(c.allKeys.count)
            try c.validateOnlyExpectedKeys([.source, .uTransport, .vTransport], in: decoder)
            let source = try c.decode(Surface3D.self, forKey: .source)
            try self.init(source: source, uTransport: try c.decode(OriginalAngularParameterTransport.self, forKey: .uTransport), vTransport: try c.decode(OriginalAngularParameterTransport.self, forKey: .vTransport),
                tolerance: OriginalAffineWordDecodingContext.tolerance(from: decoder), usage: &usage)
        } else { throw NativeRationalSourceDecodingError.synchronizationCapabilityUnavailable }
    }
    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: Keys.self)
        try c.encode(source, forKey: .source)
        try c.encode(uTransport, forKey: .uTransport)
        try c.encode(vTransport, forKey: .vTransport)
    }
}
#endif

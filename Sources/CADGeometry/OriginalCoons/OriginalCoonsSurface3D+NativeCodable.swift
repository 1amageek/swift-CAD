#if !hasFeature(Embedded)
import CADCore

extension OriginalCoonsSurface3D: Codable {
    private enum CodingKeys: String, CodingKey {
        case vMinimumBoundary, vMaximumBoundary, uMinimumBoundary, uMaximumBoundary
    }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        try c.validateOnlyExpectedKeys([.vMinimumBoundary, .vMaximumBoundary,
            .uMinimumBoundary, .uMaximumBoundary], in: decoder)
        if #available(macOS 15, iOS 18, visionOS 2, watchOS 11, tvOS 18, *) {
            var usage = try NativeRationalSourceDecodingContext.allowance(from: decoder)
            let bottom = try c.decode(OriginalCurveRootSpan3D.self, forKey: .vMinimumBoundary)
            try self.init(vMinimumBoundary: bottom,
                vMaximumBoundary: c.decode(OriginalCurveRootSpan3D.self, forKey: .vMaximumBoundary),
                uMinimumBoundary: c.decode(OriginalCurveRootSpan3D.self, forKey: .uMinimumBoundary),
                uMaximumBoundary: c.decode(OriginalCurveRootSpan3D.self, forKey: .uMaximumBoundary),
                tolerance: bottom.certificationTolerance, usage: &usage)
        } else { throw NativeRationalSourceDecodingError.synchronizationCapabilityUnavailable }
    }
    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(vMinimumBoundary, forKey: .vMinimumBoundary)
        try c.encode(vMaximumBoundary, forKey: .vMaximumBoundary)
        try c.encode(uMinimumBoundary, forKey: .uMinimumBoundary)
        try c.encode(uMaximumBoundary, forKey: .uMaximumBoundary)
    }
}
#endif

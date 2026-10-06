#if !hasFeature(Embedded)
import CADCore

extension OriginalBoundaryCorrectedSurface3D: Codable {
    private enum CodingKeys: String, CodingKey { case construction, boundaries }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        try c.validateOnlyExpectedKeys([.construction, .boundaries], in: decoder)
        if #available(macOS 15, iOS 18, visionOS 2, watchOS 11, tvOS 18, *) {
            var usage = try NativeRationalSourceDecodingContext.allowance(from: decoder)
            let boundaries = try c.decode(OriginalCoonsSurface3D.self, forKey: .boundaries)
            let spans = min(boundaries.vMinimumBoundary.maximumSpanCount, boundaries.vMaximumBoundary.maximumSpanCount,
                boundaries.uMinimumBoundary.maximumSpanCount, boundaries.uMaximumBoundary.maximumSpanCount)
            let depth = min(boundaries.vMinimumBoundary.maximumSubdivisionDepth, boundaries.vMaximumBoundary.maximumSubdivisionDepth,
                boundaries.uMinimumBoundary.maximumSubdivisionDepth, boundaries.uMaximumBoundary.maximumSubdivisionDepth)
            try self.init(construction: c.decode(BSplineSurface3D.self, forKey: .construction),
                boundaries: boundaries, maximumSpanCount: spans, maximumSubdivisionDepth: depth,
                tolerance: boundaries.certificationTolerance, usage: &usage)
        } else { throw NativeRationalSourceDecodingError.synchronizationCapabilityUnavailable }
    }
    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(construction, forKey: .construction)
        try c.encode(boundaries, forKey: .boundaries)
    }
}
#endif

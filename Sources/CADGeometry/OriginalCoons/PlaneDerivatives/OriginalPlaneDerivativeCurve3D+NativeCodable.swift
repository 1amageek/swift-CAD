#if !hasFeature(Embedded)
import CADCore

extension OriginalPlaneDerivativeCurve3D: Codable {
    private enum CodingKeys: String, CodingKey { case source, startConstraints, endConstraints }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy:CodingKeys.self)
        try c.validateOnlyExpectedKeys([.source,.startConstraints,.endConstraints],in:decoder)
        if #available(macOS 15, iOS 18, visionOS 2, watchOS 11, tvOS 18, *) {
            try OriginalAffineWordDecodingContext.validateSourceNesting(from:decoder)
            var usage = try NativeRationalSourceDecodingContext.allowance(from:decoder)
            let source = try c.decode(OriginalCurveRootSpan3D.self,forKey:.source)
            let start = try OriginalPlaneDerivativeNativeDecoding.constraints(from:c.superDecoder(forKey:.startConstraints),usage:&usage)
            let end = try OriginalPlaneDerivativeNativeDecoding.constraints(from:c.superDecoder(forKey:.endConstraints),usage:&usage)
            let depth = try OriginalAffineWordDecodingContext.maximumSourceDepth(from:decoder)-decoder.codingPath.count
            try self.init(source:source,startConstraints:start,endConstraints:end,
                tolerance:source.certificationTolerance,usage:&usage,remainingSourceDepth:depth)
        } else { throw NativeRationalSourceDecodingError.synchronizationCapabilityUnavailable }
    }
    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy:CodingKeys.self)
        try c.encode(source,forKey:.source); try c.encode(startConstraints,forKey:.startConstraints)
        try c.encode(endConstraints,forKey:.endConstraints)
    }
}
#endif

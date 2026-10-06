#if !hasFeature(Embedded)
import CADCore

extension OriginalPlaneDerivativeSurface3D: Codable {
    private enum CodingKeys: String, CodingKey { case construction, boundaries, startConstraints, endConstraints }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy:CodingKeys.self)
        try c.validateOnlyExpectedKeys([.construction,.boundaries,.startConstraints,.endConstraints],in:decoder)
        if #available(macOS 15, iOS 18, visionOS 2, watchOS 11, tvOS 18, *) {
            try OriginalAffineWordDecodingContext.validateSourceNesting(from:decoder)
            var usage = try NativeRationalSourceDecodingContext.allowance(from:decoder)
            let original = try c.decode(OriginalBoundaryCorrectedSurface3D.self,forKey:.construction)
            let boundaries = try c.decode(OriginalCoonsSurface3D.self,forKey:.boundaries)
            let start = try OriginalPlaneDerivativeNativeDecoding.constraints(from:c.superDecoder(forKey:.startConstraints),usage:&usage)
            let end = try OriginalPlaneDerivativeNativeDecoding.constraints(from:c.superDecoder(forKey:.endConstraints),usage:&usage)
            let depth = try OriginalAffineWordDecodingContext.maximumSourceDepth(from:decoder)-decoder.codingPath.count
            try self.init(construction:original,boundaries:boundaries,startConstraints:start,endConstraints:end,
                remainingSourceDepth:depth,tolerance:original.certificationTolerance,usage:&usage)
        } else { throw NativeRationalSourceDecodingError.synchronizationCapabilityUnavailable }
    }
    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy:CodingKeys.self)
        try c.encode(construction,forKey:.construction); try c.encode(boundaries,forKey:.boundaries)
        try c.encode(startConstraints,forKey:.startConstraints); try c.encode(endConstraints,forKey:.endConstraints)
    }
}
#endif

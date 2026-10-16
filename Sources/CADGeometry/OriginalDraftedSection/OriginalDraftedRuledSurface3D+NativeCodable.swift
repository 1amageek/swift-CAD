#if !hasFeature(Embedded)
import CADCore

extension OriginalDraftedRuledSurface3D: Codable {
    private enum CodingKeys:String,CodingKey { case start,endHeight }
    public init(from decoder:Decoder) throws {
        let c = try decoder.container(keyedBy:CodingKeys.self)
        try c.validateOnlyExpectedKeys([.start,.endHeight],in:decoder)
            try OriginalAffineWordDecodingContext.validateSourceNesting(from:decoder)
            var usage = try NativeRationalSourceDecodingContext.execution(from:decoder)
            let start = try c.decode(OriginalDraftedCurve3D.self,forKey:.start)
            let depth = try OriginalAffineWordDecodingContext.maximumSourceDepth(from:decoder)-decoder.codingPath.count
            try self.init(start:start,endHeight:c.decode(Double.self,forKey:.endHeight),
                remainingSourceDepth:depth,tolerance:start.certificationTolerance,usage:&usage)
    }
    public func encode(to encoder:Encoder) throws {
        var c = encoder.container(keyedBy:CodingKeys.self)
        try c.encode(start,forKey:.start); try c.encode(endHeight,forKey:.endHeight)
    }
}
#endif

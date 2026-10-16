#if !hasFeature(Embedded)
import CADCore

extension OriginalDraftedCurve3D: Codable {
    private enum CodingKeys:String,CodingKey { case generator,normal,axis,pull,height,angle }
    public init(from decoder:Decoder) throws {
        let c = try decoder.container(keyedBy:CodingKeys.self)
        try c.validateOnlyExpectedKeys([.generator,.normal,.axis,.pull,.height,.angle],in:decoder)
        if #available(macOS 15,iOS 18,visionOS 2,watchOS 11,tvOS 18,*) {
            try OriginalAffineWordDecodingContext.validateSourceNesting(from:decoder)
            var usage = try NativeRationalSourceDecodingContext.execution(from:decoder)
            let generator = try c.decode(OriginalCurveRootSpan3D.self,forKey:.generator)
            let depth = try OriginalAffineWordDecodingContext.maximumSourceDepth(from:decoder)-decoder.codingPath.count
            try self.init(generator:generator,normal:c.decode(Vector3D.self,forKey:.normal),
                axis:c.decode(Vector3D.self,forKey:.axis),pull:c.decode(Vector3D.self,forKey:.pull),
                height:c.decode(Double.self,forKey:.height),angle:c.decode(Double.self,forKey:.angle),
                remainingSourceDepth:depth,tolerance:generator.certificationTolerance,usage:&usage)
        } else { throw NativeRationalSourceDecodingError.synchronizationCapabilityUnavailable }
    }
    public func encode(to encoder:Encoder) throws {
        var c = encoder.container(keyedBy:CodingKeys.self)
        try c.encode(generator,forKey:.generator); try c.encode(normal,forKey:.normal)
        try c.encode(axis,forKey:.axis); try c.encode(pull,forKey:.pull)
        try c.encode(height,forKey:.height); try c.encode(angle,forKey:.angle)
    }
}
#endif

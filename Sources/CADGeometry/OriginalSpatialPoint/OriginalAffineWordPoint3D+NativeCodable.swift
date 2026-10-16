#if !hasFeature(Embedded)
import CADCore

extension OriginalAffineWordPoint3D: Codable {
    private enum CodingKeys: String, CodingKey { case point, word }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        try c.validateOnlyExpectedKeys([.point, .word], in: decoder)
            try OriginalAffineWordDecodingContext.validateSourceNesting(from: decoder)
            var usage = try NativeRationalSourceDecodingContext.execution(from: decoder)
            let remaining = try OriginalAffineWordDecodingContext.maximumSourceDepth(from: decoder) - decoder.codingPath.count
            try self.init(point: c.decode(Point3D.self, forKey: .point),
                word: c.decode(OriginalAffineOperationWord.self, forKey: .word),
                tolerance: OriginalAffineWordDecodingContext.tolerance(from: decoder),
                remainingSourceDepth: remaining, maximumSubdivisionDepth: 0,
                maximumAlgebraicDepth: usage.limits.maximumValueDepth, usage: &usage)
    }
    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(point, forKey: .point); try c.encode(word, forKey: .word)
    }
}
#endif

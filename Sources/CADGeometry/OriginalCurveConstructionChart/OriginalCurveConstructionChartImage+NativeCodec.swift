#if !hasFeature(Embedded)
import CADCore

extension OriginalCurveConstructionChartImage: Codable {
    private enum Keys: String, CodingKey { case chart, certificationTolerance }
    public init(from decoder: Decoder) throws {
        if #available(macOS 15, iOS 18, visionOS 2, watchOS 11, tvOS 18, *) {
            var usage = try NativeRationalSourceDecodingContext.allowance(from: decoder)
            try OriginalAffineWordDecodingContext.validateSourceNesting(from: decoder)
            let c = try decoder.container(keyedBy: Keys.self)
            try usage.consumeExactWork(c.allKeys.count); try usage.visitExactCell(depth: 0)
            try c.validateOnlyExpectedKeys([.chart, .certificationTolerance], in: decoder)
            let tolerance = try c.decode(ModelingTolerance.self, forKey: .certificationTolerance)
            guard tolerance == (try OriginalAffineWordDecodingContext.tolerance(from: decoder)) else {
                throw GeometryConversionError.invalidInput("Original construction chart Native tolerance differs from its caller.")
            }
            switch try c.decode(OriginalCurveConstructionChart.self, forKey: .chart) {
            case .traversal(let value):
                guard value.certificationTolerance == tolerance else {
                    throw GeometryConversionError.invalidInput("Original root traversal has another preparation tolerance.")
                }
                try self.init(traversal: value, maximumSpanCount: Int.max, usage: &usage)
            case .parameterLaw(let value):
                let sourceDepth = try OriginalAffineWordDecodingContext.maximumSourceDepth(from: decoder)
                try self.init(parameterSource: value, tolerance: tolerance, maximumSpanCount: Int.max,
                    maximumSubdivisionDepth: OriginalAffineWordDecodingContext.maximumCurveSubdivisionDepth(from: decoder),
                    remainingSourceDepth: sourceDepth - decoder.codingPath.count,
                    storageByteStride: MemoryLayout<UInt32>.stride, usage: &usage)
            }
        } else { throw NativeRationalSourceDecodingError.synchronizationCapabilityUnavailable }
    }
    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: Keys.self)
        try c.encode(chart, forKey: .chart); try c.encode(certificationTolerance, forKey: .certificationTolerance)
    }
}
#endif

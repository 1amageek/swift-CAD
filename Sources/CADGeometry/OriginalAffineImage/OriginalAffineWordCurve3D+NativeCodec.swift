#if !hasFeature(Embedded)
import CADCore

extension OriginalAffineWordCurve3D: Codable {
  private enum Keys: String, CodingKey { case source, operationWord }
  public init(from decoder: Decoder) throws {
    if #available(macOS 15, iOS 18, visionOS 2, watchOS 11, tvOS 18, *) {
      var usage = try NativeRationalSourceDecodingContext.allowance(from: decoder)
      let c = try decoder.container(keyedBy: Keys.self)
      try usage.consumeExactWork(c.allKeys.count)
      try c.validateOnlyExpectedKeys([.source, .operationWord], in: decoder)
      try OriginalAffineWordDecodingContext.validateSourceNesting(from: decoder)
      let depth = decoder.codingPath.count
      let sourceDepth = try OriginalAffineWordDecodingContext.maximumSourceDepth(from: decoder)
      try usage.visitExactCell(depth: 0)
      guard depth < sourceDepth else { throw GeometryConversionError.resourceLimitExceeded("Original word image exceeds the caller source depth.") }
      let source = try c.decode(Curve3D.self, forKey: .source)
      let operationWord = try c.decode(OriginalAffineOperationWord.self, forKey: .operationWord)
      try self.init(source: source, operationWord: operationWord,
        tolerance: OriginalAffineWordDecodingContext.tolerance(from: decoder),
        remainingSourceDepth: sourceDepth - depth,
        maximumSubdivisionDepth: OriginalAffineWordDecodingContext.maximumCurveSubdivisionDepth(from: decoder),
        maximumAlgebraicDepth: OriginalAffineWordDecodingContext.maximumAlgebraicDepth(from: decoder), usage: &usage)
    } else { throw NativeRationalSourceDecodingError.synchronizationCapabilityUnavailable }
  }
  public func encode(to encoder: Encoder) throws {
    var c = encoder.container(keyedBy: Keys.self)
    try c.encode(source, forKey: .source)
    try c.encode(operationWord, forKey: .operationWord)
  }
}
#endif

#if !hasFeature(Embedded)
import CADCore

extension OriginalAffineWordSurfaceParameterCurve: Codable {
  private enum Keys: String, CodingKey { case source, target, startFraction, endFraction }
  public init(from decoder: Decoder) throws {
    if #available(macOS 15, iOS 18, visionOS 2, watchOS 11, tvOS 18, *) {
      var usage = try NativeRationalSourceDecodingContext.execution(from: decoder)
      let c = try decoder.container(keyedBy: Keys.self)
      try usage.consumeWork(c.allKeys.count)
      try c.validateOnlyExpectedKeys([.source, .target, .startFraction, .endFraction], in: decoder)
      try OriginalAffineWordDecodingContext.validateSourceNesting(from: decoder)
      let depth = decoder.codingPath.count
      let sourceDepth = try OriginalAffineWordDecodingContext.maximumSourceDepth(from: decoder)
      try usage.visitCell(axis: .value, depth: 0)
      guard depth < sourceDepth else { throw GeometryConversionError.resourceLimitExceeded("Original word image exceeds the caller source depth.") }
      let source = try c.decode(SurfaceLiftCurve3D.self, forKey: .source)
      let target = try c.decode(OriginalAffineWordSurface3D.self, forKey: .target)
      let startFraction = try c.decode(Double.self, forKey: .startFraction)
      let endFraction = try c.decode(Double.self, forKey: .endFraction)
      try self.init(source: source, target: target, startFraction: startFraction, endFraction: endFraction,
        tolerance: OriginalAffineWordDecodingContext.tolerance(from: decoder),
        remainingSourceDepth: sourceDepth - depth,
        maximumSubdivisionDepth: OriginalAffineWordDecodingContext.maximumCurveSubdivisionDepth(from: decoder), usage: &usage)
    } else { throw NativeRationalSourceDecodingError.synchronizationCapabilityUnavailable }
  }
  public func encode(to encoder: Encoder) throws {
    var c = encoder.container(keyedBy: Keys.self)
    try c.encode(source, forKey: .source)
    try c.encode(target, forKey: .target)
    try c.encode(startFraction, forKey: .startFraction)
    try c.encode(endFraction, forKey: .endFraction)
  }
}
#endif

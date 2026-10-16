#if !hasFeature(Embedded)
  import CADCore

  extension OriginalCurveConstructionParameterSource: Codable {
    private enum Keys: String, CodingKey {
      case source, startParameter, endParameter, law, firstFraction, lastFraction
    }
    public init(from decoder: Decoder) throws {
      try OriginalAffineWordDecodingContext.validateSourceNesting(from: decoder)
      let c = try decoder.container(keyedBy: Keys.self)
      try c.validateOnlyExpectedKeys(
        [.source, .startParameter, .endParameter, .law, .firstFraction, .lastFraction], in: decoder)
      self.init(
        source: try c.decode(Curve3D.self, forKey: .source),
        startParameter: try c.decode(Double.self, forKey: .startParameter),
        endParameter: try c.decode(Double.self, forKey: .endParameter),
        law: try c.decode(OriginalCurveConstructionParameterLaw.self, forKey: .law),
        firstFraction: try c.decode(ExactRationalCoefficient.self, forKey: .firstFraction),
        lastFraction: try c.decode(ExactRationalCoefficient.self, forKey: .lastFraction))
    }
    public func encode(to encoder: Encoder) throws {
      var c = encoder.container(keyedBy: Keys.self)
      try c.encode(source, forKey: .source)
      try c.encode(startParameter, forKey: .startParameter)
      try c.encode(endParameter, forKey: .endParameter)
      try c.encode(law, forKey: .law)
      try c.encode(firstFraction, forKey: .firstFraction)
      try c.encode(lastFraction, forKey: .lastFraction)
    }
  }
#endif

#if !hasFeature(Embedded)
  import CADCore

  extension OriginalCurveConstructionChartImage: Codable {
    private enum Keys: String, CodingKey { case chart, certificationTolerance }
    public init(from decoder: Decoder) throws {
        var usage = try NativeRationalSourceDecodingContext.execution(from: decoder)
        try OriginalAffineWordDecodingContext.validateSourceNesting(from: decoder)
        let c = try decoder.container(keyedBy: Keys.self)
        try usage.consumeWork(c.allKeys.count)
        try usage.visitCell(axis: .value, depth: 0)
        try c.validateOnlyExpectedKeys([.chart, .certificationTolerance], in: decoder)
        let tolerance = try c.decode(ModelingTolerance.self, forKey: .certificationTolerance)
        guard tolerance == (try OriginalAffineWordDecodingContext.tolerance(from: decoder)) else {
          throw GeometryConversionError.invalidInput(
            "Original construction chart Native tolerance differs from its caller.")
        }
        switch try c.decode(OriginalCurveConstructionChart.self, forKey: .chart) {
        case .traversal(let value):
          guard value.certificationTolerance == tolerance else {
            throw GeometryConversionError.invalidInput(
              "Original root traversal has another preparation tolerance.")
          }
          try self.init(traversal: value, maximumSpanCount: Int.max, using: &usage)
        case .parameterLaw(let value):
          let sourceDepth = try OriginalAffineWordDecodingContext.maximumSourceDepth(from: decoder)
          try self.init(
            parameterSource: value, tolerance: tolerance, maximumSpanCount: Int.max,
            maximumSubdivisionDepth: OriginalAffineWordDecodingContext.maximumCurveSubdivisionDepth(
              from: decoder),
            remainingSourceDepth: sourceDepth - decoder.codingPath.count,
            using: &usage)
        }
    }
    public func encode(to encoder: Encoder) throws {
      var c = encoder.container(keyedBy: Keys.self)
      try c.encode(chart, forKey: .chart)
      try c.encode(certificationTolerance, forKey: .certificationTolerance)
    }
  }
#endif

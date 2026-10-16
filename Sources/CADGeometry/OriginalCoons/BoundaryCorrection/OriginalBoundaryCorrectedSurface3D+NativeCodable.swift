#if !hasFeature(Embedded)
  import CADCore

  extension OriginalBoundaryCorrectedSurface3D: Codable {
    private enum CodingKeys: String, CodingKey { case construction, boundaries }

    public init(from decoder: Decoder) throws {
      let c = try decoder.container(keyedBy: CodingKeys.self)
      try c.validateOnlyExpectedKeys([.construction, .boundaries], in: decoder)
        var usage = try NativeRationalSourceDecodingContext.execution(from: decoder)
        let boundaries = try c.decode(OriginalCoonsSurface3D.self, forKey: .boundaries)
        let spans = min(
          PreparedBSplineSurfaceDifferentialEncloser.maximumOriginalNativeSpanCount,
          boundaries.vMinimumBoundary.maximumSpanCount,
          boundaries.vMaximumBoundary.maximumSpanCount,
          boundaries.uMinimumBoundary.maximumSpanCount, boundaries.uMaximumBoundary.maximumSpanCount
        )
        let depth = min(
          boundaries.vMinimumBoundary.maximumSubdivisionDepth,
          boundaries.vMaximumBoundary.maximumSubdivisionDepth,
          boundaries.uMinimumBoundary.maximumSubdivisionDepth,
          boundaries.uMaximumBoundary.maximumSubdivisionDepth)
        try self.init(
          construction: c.decode(BSplineSurface3D.self, forKey: .construction),
          boundaries: boundaries, maximumSpanCount: spans, maximumSubdivisionDepth: depth,
          tolerance: boundaries.certificationTolerance, using: &usage)
    }
    public func encode(to encoder: Encoder) throws {
      var c = encoder.container(keyedBy: CodingKeys.self)
      try c.encode(construction, forKey: .construction)
      try c.encode(boundaries, forKey: .boundaries)
    }
  }
#endif

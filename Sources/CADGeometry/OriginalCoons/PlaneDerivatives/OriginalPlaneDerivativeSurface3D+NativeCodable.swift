#if !hasFeature(Embedded)
  import CADCore

  extension OriginalPlaneDerivativeSurface3D: Codable {
    private enum CodingKeys: String, CodingKey {
      case construction, boundaries, startConstraints, endConstraints
    }
    public init(from decoder: Decoder) throws {
      let c = try decoder.container(keyedBy: CodingKeys.self)
      try c.validateOnlyExpectedKeys(
        [.construction, .boundaries, .startConstraints, .endConstraints], in: decoder)
        try OriginalAffineWordDecodingContext.validateSourceNesting(from: decoder)
        var usage = try NativeRationalSourceDecodingContext.execution(from: decoder)
        let original = try c.decode(OriginalBoundaryCorrectedSurface3D.self, forKey: .construction)
        let boundaries = try c.decode(OriginalCoonsSurface3D.self, forKey: .boundaries)
        let start = try OriginalPlaneDerivativeNativeDecoding.constraints(
          from: c.superDecoder(forKey: .startConstraints), using: &usage)
        let end = try OriginalPlaneDerivativeNativeDecoding.constraints(
          from: c.superDecoder(forKey: .endConstraints), using: &usage)
        let depth =
          try OriginalAffineWordDecodingContext.maximumSourceDepth(from: decoder)
          - decoder.codingPath.count
        try RationalAlgebraStorage.retain(1, of: Self.self, usage: &usage)
        try self.init(
          construction: original, boundaries: boundaries, startConstraints: start,
          endConstraints: end,
          remainingSourceDepth: depth, tolerance: original.certificationTolerance, using: &usage)
    }
    public func encode(to encoder: Encoder) throws {
      var c = encoder.container(keyedBy: CodingKeys.self)
      try c.encode(construction, forKey: .construction)
      try c.encode(boundaries, forKey: .boundaries)
      try c.encode(startConstraints, forKey: .startConstraints)
      try c.encode(endConstraints, forKey: .endConstraints)
    }
  }
#endif

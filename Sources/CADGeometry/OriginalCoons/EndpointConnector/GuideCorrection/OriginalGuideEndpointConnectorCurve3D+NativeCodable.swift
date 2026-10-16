#if !hasFeature(Embedded)
  import CADCore

  extension OriginalGuideEndpointConnectorCurve3D: Codable {
    private enum CodingKeys: String, CodingKey {
      case source, startBoundary, startAtEnd, endBoundary, endAtEnd, correctionBasis
    }
    public init(from decoder: Decoder) throws {
      let c = try decoder.container(keyedBy: CodingKeys.self)
      try c.validateOnlyExpectedKeys(
        [.source, .startBoundary, .startAtEnd, .endBoundary, .endAtEnd, .correctionBasis],
        in: decoder)
      if #available(macOS 15, iOS 18, visionOS 2, watchOS 11, tvOS 18, *) {
        try OriginalAffineWordDecodingContext.validateSourceNesting(from: decoder)
        var usage = try NativeRationalSourceDecodingContext.execution(from: decoder)
        let source = try c.decode(OriginalCurveRootSpan3D.self, forKey: .source)
        let start = try c.decode(OriginalCurveRootSpan3D.self, forKey: .startBoundary)
        let end = try c.decode(OriginalCurveRootSpan3D.self, forKey: .endBoundary)
        let depth =
          try OriginalAffineWordDecodingContext.maximumSourceDepth(from: decoder)
          - decoder.codingPath.count
        try self.init(
          source: source, startBoundary: start,
          startAtEnd: c.decode(Bool.self, forKey: .startAtEnd),
          endBoundary: end, endAtEnd: c.decode(Bool.self, forKey: .endAtEnd),
          correctionBasis: c.decode(OriginalEndpointCorrectionBasis.self, forKey: .correctionBasis),
          remainingSourceDepth: depth, tolerance: source.certificationTolerance, using: &usage)
      } else {
        throw NativeRationalSourceDecodingError.synchronizationCapabilityUnavailable
      }
    }
    public func encode(to encoder: Encoder) throws {
      var c = encoder.container(keyedBy: CodingKeys.self)
      try c.encode(source, forKey: .source)
      try c.encode(startBoundary, forKey: .startBoundary)
      try c.encode(startAtEnd, forKey: .startAtEnd)
      try c.encode(endBoundary, forKey: .endBoundary)
      try c.encode(endAtEnd, forKey: .endAtEnd)
      try c.encode(correctionBasis, forKey: .correctionBasis)
    }
  }
#endif

#if !hasFeature(Embedded)
  import CADCore

  extension OriginalEndpointConnectorCurve3D: Codable {
    private enum CodingKeys: String, CodingKey {
      case construction, startBoundary, startAtEnd, endBoundary, endAtEnd, correctionBasis
    }

    public init(from decoder: Decoder) throws {
      let c = try decoder.container(keyedBy: CodingKeys.self)
      try c.validateOnlyExpectedKeys(
        [
          .construction, .startBoundary, .startAtEnd,
          .endBoundary, .endAtEnd, .correctionBasis,
        ], in: decoder)
      if #available(macOS 15, iOS 18, visionOS 2, watchOS 11, tvOS 18, *) {
        var usage = try NativeRationalSourceDecodingContext.execution(from: decoder)
        let start = try c.decode(OriginalCurveRootSpan3D.self, forKey: .startBoundary)
        let end = try c.decode(OriginalCurveRootSpan3D.self, forKey: .endBoundary)
        try self.init(
          construction: c.decode(BSplineCurve3D.self, forKey: .construction),
          startBoundary: start, startAtEnd: c.decode(Bool.self, forKey: .startAtEnd),
          endBoundary: end, endAtEnd: c.decode(Bool.self, forKey: .endAtEnd),
          correctionBasis: c.decode(OriginalEndpointCorrectionBasis.self, forKey: .correctionBasis),
          maximumSpanCount: usage.effectiveLimits.maximumCells,
          maximumSubdivisionDepth: min(start.maximumSubdivisionDepth, end.maximumSubdivisionDepth),
          tolerance: start.certificationTolerance, using: &usage)
      } else {
        throw NativeRationalSourceDecodingError.synchronizationCapabilityUnavailable
      }
    }

    public func encode(to encoder: Encoder) throws {
      var c = encoder.container(keyedBy: CodingKeys.self)
      try c.encode(construction, forKey: .construction)
      try c.encode(startBoundary, forKey: .startBoundary)
      try c.encode(startAtEnd, forKey: .startAtEnd)
      try c.encode(endBoundary, forKey: .endBoundary)
      try c.encode(endAtEnd, forKey: .endAtEnd)
      try c.encode(correctionBasis, forKey: .correctionBasis)
    }
  }

  extension OriginalEndpointCorrectionBasis: Codable {}
#endif

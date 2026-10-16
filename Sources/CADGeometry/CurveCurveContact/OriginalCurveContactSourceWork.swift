import CADCore

/// Visits retained original source metadata; mathematical preparation charges its actual operations.
enum OriginalCurveContactSourceWork {
  static func charge(_ source: Curve3D, using execution: inout OriginalQueryExecution) throws {
    func visit(_ curve: Curve3D, depth: Int) throws {
      try execution.consumeWork(1)
      guard depth <= min(32, execution.effectiveLimits.remainingSourceDepth) else {
        throw GeometryConversionError.resourceLimitExceeded(
          "Original contact exceeded its source descent ceiling.")
      }
      try execution.admitSourceDepth(depth)
      switch curve {
      case .rigidImage(let image): try visit(image.source, depth: depth + 1)
      case .affineImage(let image): try visit(image.source, depth: depth + 1)
      case .parameterImage(let image): try visit(image.source, depth: depth + 1)
      case .originalAffineWord(let image):
        try execution.consumeWork(image.operationWord.factors.count)
        try visit(image.source, depth: depth + 1)
      case .originalAngularTransport(let image): try visit(image.source, depth: depth + 1)
      case .originalConstructionChart(let image): try visit(image.source, depth: depth + 1)
      case .originalGuideEndpointConnector(let connector):
        try visit(connector.source.source, depth: depth + 1)
        try visit(connector.startBoundary.source, depth: depth + 1)
        try visit(connector.endBoundary.source, depth: depth + 1)
      case .originalGuideTraversalChain(let chain):
        for traversal in chain.traversals { try visit(traversal.source, depth: depth + 1) }
        for station in chain.stations {
          try execution.consumeWork(station.canonicalNumeratorWords.count)
          try execution.consumeWork(station.canonicalDenominatorWords.count)
        }
        try execution.consumeWork(chain.sourceSegmentOrdinals.count)
      case .originalEndpointConnector(let connector):
        try visit(.bSpline(connector.construction), depth: depth + 1)
        try visit(connector.startBoundary.source, depth: depth + 1)
        try visit(connector.endBoundary.source, depth: depth + 1)
      case .originalDrafted(let image): try visit(image.generator.source, depth: depth + 1)
      case .originalPlaneDerivative(let image):
        try visit(image.source.source, depth: depth + 1)
        for constraint in image.startConstraints {
          try execution.consumeWork(1)
          try GeometryStructuralComparisonWork.charge(
            surface: constraint.surface, using: &execution)
        }
        for constraint in image.endConstraints {
          try execution.consumeWork(1)
          try GeometryStructuralComparisonWork.charge(
            surface: constraint.surface, using: &execution)
        }
      case .line, .circle, .analytic, .bSpline, .originalPolyline, .implicit, .surfaceLift,
        .certifiedIntersection:
        try GeometryStructuralComparisonWork.charge(curve: curve, using: &execution)
      }
    }
    try visit(source, depth: 0)
  }
}

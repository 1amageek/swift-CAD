import CADCore

extension OriginalCoonsSurface3D {
  /// Complete structural law equality, without any rounded coefficient product.
  package func exactBilinearImage<B: ExactScalarAdmission & ~Copyable>(usage: inout B) throws
    -> BSplineSurface3D?
  {
    try admitScalarPreparation(using: &usage)
    try usage.consumeWork(64)
    func points(_ span: OriginalCurveRootSpan3D) -> [Point3D]? {
      guard case .bSpline(let curve) = span.source, curve.degree == 1,
        curve.controlPoints.count == 2, curve.knots == [0, 0, 1, 1], curve.weights == [1, 1],
        case .authored(0) = span.start, case .authored(1) = span.end
      else { return nil }
      return curve.controlPoints
    }
    guard let bottom = points(vMinimumBoundary), let top = points(vMaximumBoundary),
      let left = points(uMinimumBoundary), let right = points(uMaximumBoundary),
      bottom[0] == left[0], bottom[1] == right[0], top[0] == left[1], top[1] == right[1]
    else { return nil }
    try OriginalCoefficientAllocation.reserve(count: 12, of: Double.self, using: &usage)
    try OriginalCoefficientAllocation.reserve(count: 2, of: [Point3D].self, using: &usage)
    try OriginalCoefficientAllocation.reserve(count: 2, of: [Double].self, using: &usage)
    return .init(
      uDegree: 1, vDegree: 1, uKnots: [0, 0, 1, 1], vKnots: [0, 0, 1, 1],
      controlPoints: [bottom, top], weights: [[1, 1], [1, 1]])
  }
}

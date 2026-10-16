/// Retains only the original fields consumed by an embedding proof.
package struct OriginalSurfaceFirstOrderEnclosure: Sendable {
  package struct Axis: Sendable {
    package let value: OutwardScalarInterval
    package let derivativeU: OutwardScalarInterval
    package let derivativeV: OutwardScalarInterval
  }
  package let x: Axis, y: Axis, z: Axis

  init(x: Axis, y: Axis, z: Axis) {
    self.x = x
    self.y = y
    self.z = z
  }

  init(_ original: SurfaceIntervalVectorJet) {
    func axis(_ q: SurfaceIntervalJet) -> Axis {
      .init(value: q.value, derivativeU: q.derivativeU, derivativeV: q.derivativeV)
    }
    x = axis(original.x)
    y = axis(original.y)
    z = axis(original.z)
  }

  init(_ original: SurfaceAreaIntervalTaylorVectorJet) throws {
    func axis(_ q: SurfaceAreaIntervalTaylorScalarJet) throws -> Axis {
      try .init(
        value: q.coefficient(0, 0), derivativeU: q.coefficient(1, 0),
        derivativeV: q.coefficient(0, 1))
    }
    x = try axis(original.x)
    y = try axis(original.y)
    z = try axis(original.z)
  }
}

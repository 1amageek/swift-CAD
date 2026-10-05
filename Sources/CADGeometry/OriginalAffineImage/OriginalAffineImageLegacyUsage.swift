import CADCore

/// Cancellation-only policy for unbounded common numerical conveniences.
struct OriginalAffineImageLegacyUsage: RationalAlgebraAdmitting {
  mutating func visitExactCell(depth: Int) throws { try Task.checkCancellation() }
  mutating func consumeExactWork(_ count: Int) throws {
    guard count >= 0 else { throw GeometryConversionError.invalidInput("Original legacy work count must be nonnegative.") }
    try Task.checkCancellation()
  }
  mutating func retainExactStorage(_ count: Int) throws {
    guard count >= 0 else { throw GeometryConversionError.invalidInput("Original legacy storage count must be nonnegative.") }
    try Task.checkCancellation()
  }
}

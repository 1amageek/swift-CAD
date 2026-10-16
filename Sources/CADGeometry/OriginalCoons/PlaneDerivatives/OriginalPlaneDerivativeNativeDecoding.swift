#if !hasFeature(Embedded)
  import CADCore

  package struct OriginalPlaneDerivativeNativeDecoding {
    @available(macOS 15, iOS 18, visionOS 2, watchOS 11, tvOS 18, *)
    package static func constraints(
      from decoder: Decoder, using execution: inout OriginalQueryExecution
    )
      throws -> [OriginalPlaneDerivativeConstraint]
    {
      var input = try decoder.unkeyedContainer()
      var result: [OriginalPlaneDerivativeConstraint] = []
      while !input.isAtEnd {
        try execution.consumeWork(1)
        if result.count == result.capacity {
          let doubled = result.capacity.multipliedReportingOverflow(by: 2)
          guard !doubled.overflow else {
            throw GeometryConversionError.resourceLimitExceeded(
              "Original plane constraint array capacity overflows.")
          }
          let capacity = result.capacity == 0 ? 1 : doubled.partialValue
          guard capacity > result.capacity else {
            throw GeometryConversionError.resourceLimitExceeded(
              "Original plane constraint array capacity overflows.")
          }
          try RationalAlgebraStorage.retain(
            capacity, of: OriginalPlaneDerivativeConstraint.self, usage: &execution)
          try execution.consumeWork(result.count)
          result.reserveCapacity(capacity)
        }
        result.append(try input.decode(OriginalPlaneDerivativeConstraint.self))
      }
      return result
    }
  }
#endif

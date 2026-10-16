import CADCore
import CADGeometry

/// The mathematical coefficient-operation bound remains independent of the
/// query's total work and allocation policies. The count belongs to the caller.
enum OriginalPolynomialCoefficientOperations {
  static func record(
    _ amount: Int, count: inout Int, maximum: Int,
    using execution: inout OriginalQueryExecution
  ) throws {
    let next = count.addingReportingOverflow(amount)
    guard amount >= 0, maximum >= 0, !next.overflow, next.partialValue <= maximum else {
      throw KernelError(
        phase: .topology, code: .resourceLimitExceeded, tolerance: nil,
        message: "Original polynomial coefficient-operation limit was exceeded.")
    }
    try execution.consumeWork(1)
    count = next.partialValue
  }
}

protocol STEPSourceIdentityReading: Sendable {
    func read(fields: any STEPFieldReading, names: [Int: String], processingBudget: ExchangeProcessingBudget, limits: ExchangeResourceLimits,
              remainingWork: Int, remainingTextBytes: Int) throws -> STEPSourceIdentityResult
}

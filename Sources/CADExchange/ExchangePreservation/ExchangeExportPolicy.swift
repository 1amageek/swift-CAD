public enum ExchangeExportPolicy: Equatable, Sendable {
    case preserveAll
    case allowLoss(accepting: Set<ExchangeInformationDomain>)
}

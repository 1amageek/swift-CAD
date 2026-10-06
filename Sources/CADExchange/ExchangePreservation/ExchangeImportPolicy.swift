public enum ExchangeImportPolicy: Equatable, Sendable {
    case strict
    case allowPartial(accepting: Set<ExchangeInformationDomain>)
}

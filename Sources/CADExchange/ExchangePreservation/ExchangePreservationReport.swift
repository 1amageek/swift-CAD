public struct ExchangePreservationReport: Codable, Equatable, Sendable {
    public let losses: [ExchangeInformationLoss]
    public init(losses: [ExchangeInformationLoss] = []) { self.losses = losses }
    public var isComplete: Bool { losses.isEmpty }
    public var lostDomains: Set<ExchangeInformationDomain> { Set(losses.map(\.domain)) }
}

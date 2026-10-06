import Foundation

public struct ExchangeInformationLoss: Codable, Equatable, Sendable {
    public enum Reason: String, Codable, Sendable { case unsupportedEntity, dependentOnDiscardedEntity, unrepresentableSource, certifiedConversion }
    public let domain: ExchangeInformationDomain
    public let reason: Reason
    public let entityID: Int?
    public let entityName: String?
    public let originalRecord: String?
    public let description: String
    public init(domain: ExchangeInformationDomain, reason: Reason, entityID: Int? = nil, entityName: String? = nil,
                originalRecord: String? = nil, description: String) {
        self.domain = domain; self.reason = reason; self.entityID = entityID; self.entityName = entityName
        self.originalRecord = originalRecord; self.description = description
    }
}

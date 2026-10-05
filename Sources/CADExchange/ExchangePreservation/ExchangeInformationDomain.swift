import Foundation

public enum ExchangeInformationDomain: String, Codable, Hashable, Sendable {
    case geometry, topology, units, orientation, placement, appearance, physicalProperties,
         manufacturingInformation, savedViews, validationProperties, sourceHistory, independentShapes,
         unknownSemantics
}

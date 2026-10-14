import CADCore

/// One connected figure-eight image; dimensions belong to its three strata.
public struct OriginalApexSphereConeSurfaceComponent: Hashable, Sendable {
    public enum Stratum: Int, CaseIterable, Sendable {
        case apex, positiveArc, negativeArc
        public var imageDimension: Int { self == .apex ? 0 : 1 }
        public var fiberDimension: Int { self == .apex ? 1 : 0 }
        public var isClosed: Bool { self == .apex }
    }
    public struct ApexIncident: Hashable, Sendable {
        public let chart: Int
        public let parameterSide: Int
        public var stratum: Stratum { (chart == 0 ? parameterSide : -parameterSide) > 0 ? .positiveArc : .negativeArc }
        private init(chart: Int, parameterSide: Int) { self.chart = chart; self.parameterSide = parameterSide }
        static let firstNegative = Self(chart: 0, parameterSide: -1)
        static let firstPositive = Self(chart: 0, parameterSide: 1)
        static let secondNegative = Self(chart: 1, parameterSide: -1)
        static let secondPositive = Self(chart: 1, parameterSide: 1)
    }
    public let relation: OriginalApexSphereConeSurfaceRelation
    public var imageDimension: Int { 1 }
    public var strata: (Stratum, Stratum, Stratum) { (.apex, .positiveArc, .negativeArc) }
    public var apexIncidents: (ApexIncident, ApexIncident, ApexIncident, ApexIncident) { (.firstNegative, .firstPositive, .secondNegative, .secondPositive) }
    public var firstSurface: Surface3D { relation.source.original.original.first }
    public var secondSurface: Surface3D { relation.source.original.original.second }
    init(relation: OriginalApexSphereConeSurfaceRelation) { self.relation = relation }
    public static func == (lhs: Self, rhs: Self) -> Bool { lhs.relation === rhs.relation }
    public func hash(into hasher: inout Hasher) { hasher.combine(ObjectIdentifier(relation)) }
}

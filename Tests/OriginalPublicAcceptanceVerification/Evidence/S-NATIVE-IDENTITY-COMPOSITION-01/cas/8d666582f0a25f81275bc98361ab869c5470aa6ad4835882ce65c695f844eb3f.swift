import CADCore
import CADGeometry

public struct BRepDistanceQueryResult: Sendable {
    public let lowerBound: Double
    public let upperBound: Double
    public let witnesses: [BRepDistanceWitness]
    public let minimumRegions: [BRepDistanceMinimumRegion]
    public let requestedOptions: BRepDistanceOptions?
    public let consumedWork: Int
    public init(lowerBound: Double, upperBound: Double, witnesses: [BRepDistanceWitness],
        minimumRegions: [BRepDistanceMinimumRegion] = [], requestedOptions: BRepDistanceOptions? = nil,
        consumedWork: Int = 0) {
        self.requestedOptions = requestedOptions
        self.consumedWork = consumedWork
        self.lowerBound=lowerBound;self.upperBound=upperBound;self.witnesses=witnesses;self.minimumRegions=minimumRegions
    }
}

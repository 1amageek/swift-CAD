import CADCore
import CADTopology

public struct SelectionDistanceOverview: Sendable {
    public let modelLengthUnit: LengthUnit
    public let minimum: BRepDistanceQueryResult
    public let boundarySeparation: BRepDistanceQueryResult
    public let relationship: SelectionDistanceRelationship
}

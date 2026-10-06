import CADCore
import CADTopology

public enum SelectionDistanceRelationship: Sendable {
    /// A finite accuracy enclosure does not yet certify a topological relation.
    case indeterminate
    case separated
    case firstContainedInSecond
    case secondContainedInFirst
    case intersecting
    case boundaryContact
    case mixedComponents
}

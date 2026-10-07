public enum ExactRealCellKind: Sendable, Equatable {
 case origin
 case section(rootOrdinal: Int)
 case sector(lowerRootOrdinal: Int?, upperRootOrdinal: Int?)
}

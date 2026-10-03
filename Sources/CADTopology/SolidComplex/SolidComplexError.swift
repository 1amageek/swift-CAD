import CADCore

public enum SolidComplexError: Error, Equatable, Sendable {
    case invalidSelection
    case invalidCell(BodyID)
    case foreignFaceUse(SolidFaceUse)
    case repeatedFaceUse(SolidFaceUse)
    case sameOrientation(SolidInterface)
    case unprovenInterface(SolidInterface)
    case disconnectedCells
    case invalidWorkLimit
    case comparisonLimitExceeded(limit: Int)
}

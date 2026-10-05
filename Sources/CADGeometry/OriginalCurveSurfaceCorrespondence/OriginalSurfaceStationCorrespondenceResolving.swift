import CADCore

/// Resolves retained native edge stations on an authored original surface use.
package protocol OriginalSurfaceStationCorrespondenceResolving: Sendable {
    func resolve(stationParameter: Double, maximumDeviation: Double,
        maximumSubdivisionDepth: Int, consumeWork: () throws -> Void) throws
        -> OriginalSurfaceStationCorrespondenceReceipt
    func resolve(liftFraction: Double, maximumDeviation: Double,
        maximumSubdivisionDepth: Int, consumeWork: () throws -> Void) throws
        -> OriginalSurfaceStationInverseReceipt
}

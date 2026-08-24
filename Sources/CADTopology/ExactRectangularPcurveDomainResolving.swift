import CADCore

package protocol ExactRectangularPcurveDomainResolving: Sendable {
    func resolve(
        face: Face,
        model: BRepModel,
        tolerance: ModelingTolerance
    ) throws -> ExactRectangularPcurveDomain?
}

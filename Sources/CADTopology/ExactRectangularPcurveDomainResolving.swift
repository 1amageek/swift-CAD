import CADCore

package protocol ExactRectangularPcurveDomainResolving: Sendable {
    func resolve(face: Face, model: BRepModel,
        tolerance: ModelingTolerance) throws -> ExactRectangularPcurveDomain?

    func resolve(face: Face, model: BRepModel, tolerance: ModelingTolerance,
        maximumSubdivisionDepth: Int, remainingSourceDepth: Int,
        consumeWork: (@Sendable (Int) throws -> Void)?,
        consumeStorage: (@Sendable (Int) throws -> Void)?) throws -> ExactRectangularPcurveDomain?
}

extension ExactRectangularPcurveDomainResolving {
    package func resolve(face: Face, model: BRepModel, tolerance: ModelingTolerance,
        maximumSubdivisionDepth: Int, remainingSourceDepth: Int,
        consumeWork: (@Sendable (Int) throws -> Void)?,
        consumeStorage: (@Sendable (Int) throws -> Void)?) throws -> ExactRectangularPcurveDomain? {
        // FIXME(INCOMPLETE_IMPLEMENTATION): Legacy injected rectangle providers
        // have no original bounded traversal. Face bounds and query callers
        // must not publish complete accounting through their opaque resolver.
        guard consumeWork == nil, consumeStorage == nil else {
            throw KernelError(phase: .topology, code: .unsupportedGeometry,
                tolerance: tolerance, message: "The injected rectangle provider has no bounded original traversal.")
        }
        return try resolve(face: face, model: model, tolerance: tolerance)
    }
}

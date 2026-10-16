import CADCore
import CADGeometry

package protocol ExactRectangularPcurveDomainResolving: Sendable {
    func resolve(face: Face, model: BRepModel,
        tolerance: ModelingTolerance) throws -> ExactRectangularPcurveDomain?

    func resolve(face: Face, model: BRepModel, tolerance: ModelingTolerance,
        maximumSubdivisionDepth: Int, remainingSourceDepth: Int,
        using execution: inout OriginalQueryExecution) throws -> ExactRectangularPcurveDomain?
}

extension ExactRectangularPcurveDomainResolving {
    package func resolve(face: Face, model: BRepModel, tolerance: ModelingTolerance,
        maximumSubdivisionDepth: Int, remainingSourceDepth: Int,
        using execution: inout OriginalQueryExecution) throws -> ExactRectangularPcurveDomain? {
        // FIXME(INCOMPLETE_IMPLEMENTATION): Legacy injected rectangle providers
        // have no original bounded traversal. Face bounds and query callers
        // must not publish complete accounting through their opaque resolver.
        throw KernelError(phase: .topology, code: .unsupportedCapability,
            tolerance: tolerance, message: "The injected rectangle provider has no bounded original traversal.")
    }
}

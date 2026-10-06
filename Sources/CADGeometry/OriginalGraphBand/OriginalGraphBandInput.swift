import CADCore

/// Numeric geometry supplied after the consumer verifies original ordered coedge-use identity.
package struct OriginalGraphBandInput: Sendable, Hashable {
    package struct Use: Sendable, Hashable {
        package let boundaryIndex: Int
        package let reversed: Bool

        package init(boundaryIndex: Int, reversed: Bool = false) {
            self.boundaryIndex = boundaryIndex
            self.reversed = reversed
        }
    }

    package struct Fidelity: Sendable, Hashable {
        package let linearTolerance: Double
        package let angularTolerance: Double
        package let maximumEdgeLength: Double

        package init(linearTolerance: Double, angularTolerance: Double, maximumEdgeLength: Double) {
            self.linearTolerance = linearTolerance
            self.angularTolerance = angularTolerance
            self.maximumEdgeLength = maximumEdgeLength
        }

        func validate(tolerance: ModelingTolerance) throws {
            guard linearTolerance.isFinite, linearTolerance > 0,
                  angularTolerance.isFinite, angularTolerance > 0, angularTolerance <= .pi,
                  maximumEdgeLength.isFinite, maximumEdgeLength > 0 else {
                throw KernelError(phase: .geometry, code: .invalidInput, tolerance: tolerance,
                                  message: "Original graph-band fidelity requires finite positive caller allowances.")
            }
        }
    }

    package let surface: BSplineSurface3D
    package let boundaries: [SurfaceParameterCurve]
    /// The actual source-space vertex at each original boundary use's fraction zero.
    package let sharedVertices: [Point3D]
    /// Both graph chains follow increasing U; a reversal remains an original-law view.
    package let lowerChain: [Use]
    package let upperChain: [Use]

    package init(surface: BSplineSurface3D, boundaries: [SurfaceParameterCurve],
                 sharedVertices: [Point3D], lowerChain: [Use], upperChain: [Use]) {
        self.surface = surface
        self.boundaries = boundaries
        self.sharedVertices = sharedVertices
        self.lowerChain = lowerChain
        self.upperChain = upperChain
    }
}

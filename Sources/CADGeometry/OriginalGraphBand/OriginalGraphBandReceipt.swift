import CADCore
import Foundation

/// Immutable whole-reference geometry; spatial-edge correspondence is a consumer assumption.
package struct OriginalGraphBandReceipt: Sendable {
    fileprivate final class Identity: Sendable {}

    package struct Station: Sendable {
        package let parameter: SurfaceParameter
        package let point: Point3D
        package let normal: Vector3D
        package let positionErrorUpperBound: Double
        package let normalErrorUpperBound: Double
        fileprivate let owner: Identity
        fileprivate let cellIndex: Int
        fileprivate let w: Double
    }

    package struct ReferenceCell: Sendable {
        package let u: ScalarInterval
        package let parameters: SurfaceParameterBox
        package let nativePanel: SurfaceTessellationDifferentialBounds.OriginalNativePanel
        package let bounds: SurfaceTessellationDifferentialBounds
        package let boundaryUncertaintyUpperBound: Double
        package let boundaryNormalUncertaintyUpperBound: Double
        let lowerPiece: OriginalGraphBandReference
        let upperPiece: OriginalGraphBandReference
    }

    package struct OriginalBoundaryInterval: Sendable {
        package let boundaryIndex: Int
        package let nativeParameters: ScalarInterval
        package let normalizedParameters: ScalarInterval
        package let joinIndex: Int?
    }

    package struct JoinCell: Sendable {
        package let parameters: SurfaceParameterBox
        package let sourceVertex: Point3D
        package let originalPositionErrorUpperBound: Double
        package let panels: [SurfaceTessellationDifferentialBounds.OriginalNativePanel]
        package let entry: SurfaceParameterBox
        package let exit: SurfaceParameterBox
    }

    package let input: OriginalGraphBandInput
    package let fidelity: OriginalGraphBandInput.Fidelity
    package let tolerance: ModelingTolerance
    package let winding: Int
    package let referenceCells: [ReferenceCell]
    package let joinCells: [JoinCell]
    package let originalBoundaryIntervals: [OriginalBoundaryInterval]
    private let identity = Identity()

    init(input: OriginalGraphBandInput, fidelity: OriginalGraphBandInput.Fidelity,
         tolerance: ModelingTolerance, winding: Int, referenceCells: [ReferenceCell], joinCells: [JoinCell],
         originalBoundaryIntervals: [OriginalBoundaryInterval]) {
        self.input = input
        self.fidelity = fidelity
        self.tolerance = tolerance
        self.winding = winding
        self.referenceCells = referenceCells
        self.joinCells = joinCells
        self.originalBoundaryIntervals = originalBoundaryIntervals
    }

    /// The station is a mesh approximation, paired with its original inverse uncertainty.
    package func station(cellIndex: Int, u: Double, w: Double,
                         pointCandidate: Point3D? = nil,
                         proofUsage: inout OriginalTessellationProofUsage)
      throws -> Station {
        guard referenceCells.indices.contains(cellIndex), u.isFinite, w.isFinite,
              referenceCells[cellIndex].u.contains(u), (0...1).contains(w) else {
            throw KernelError(phase: .geometry, code: .invalidInput, tolerance: tolerance,
                              message: "A graph-band station requires its original retained reference cell.")
        }
        // Materialization is its own proof operation even when every original
        // graph inverse is an exact native endpoint shortcut.
        try proofUsage.consume(depth: 0, tolerance: tolerance)
        let cell = referenceCells[cellIndex]
        let pointU = try ScalarInterval(lower: u, upper: u)
        let lower = try cell.lowerPiece.graphJet(over: pointU, tolerance: tolerance, proofUsage: &proofUsage)
        let upper = try cell.upperPiece.graphJet(over: pointU, tolerance: tolerance, proofUsage: &proofUsage)
        let value = (OutwardScalarInterval.exact(1) - .exact(w)) * lower.v + .exact(w) * upper.v
        guard value.isFinite else {
            throw KernelError(phase: .geometry, code: .resourceLimitExceeded, tolerance: tolerance,
                              message: "An original graph-band station exceeded finite materialization arithmetic.")
        }
        let v = value.midpoint
        let parameter = SurfaceParameter(u: u, v: v)
        let point = try pointCandidate ?? input.surface.point(u: u, v: v, tolerance: tolerance)
        guard point.x.isFinite, point.y.isFinite, point.z.isFinite else {
            throw KernelError(phase: .geometry, code: .invalidInput, tolerance: tolerance,
                              message: "A retained mesh station candidate must have finite coordinates.")
        }
        let normal = try input.surface.normal(u: u, v: v, owning: cell.nativePanel.span, tolerance: tolerance)
        let query = try SurfaceParameterBox(u: pointU,
            v: ScalarInterval(lower: value.lower, upper: value.upper))
        let original = try cell.nativePanel.span.intervalJet(overClosedBox: query,
                                                            on: input.surface, tolerance: tolerance)
        let positionError = IntervalVector3DBounds(
            x: original.x.value - .exact(point.x), y: original.y.value - .exact(point.y),
            z: original.z.value - .exact(point.z)).lengthUpperBound
        let normalError = try Self.normalAngleUpper(jet: original, candidate: normal, tolerance: tolerance)
        guard positionError.isFinite, positionError <= fidelity.linearTolerance else {
            throw KernelError(phase: .geometry, code: .resourceLimitExceeded,
                              residual: positionError, tolerance: tolerance,
                              message: "Original graph inversion could not materialize a station within the caller allowance.")
        }
        try Task.checkCancellation()
        return Station(parameter: parameter, point: point, normal: normal,
                       positionErrorUpperBound: positionError, normalErrorUpperBound: normalError,
                       owner: identity, cellIndex: cellIndex, w: w)
    }

    /// Whole Taylor interpolation includes the trim Hessian and actual station errors.
    package func admitReferenceFacet(cellIndex: Int, stations: [Station],
                                    positions: [Point3D], normals: [Vector3D],
                                    proofUsage: inout OriginalTessellationProofUsage) throws {
        guard referenceCells.indices.contains(cellIndex), stations.count == 3,
              positions.count == 3, normals.count == 3,
              stations.indices.allSatisfy({ stations[$0].owner === identity
                  && stations[$0].cellIndex == cellIndex
                  && stations[$0].point == positions[$0] && stations[$0].normal == normals[$0] }) else {
            throw KernelError(phase: .geometry, code: .invalidInput, tolerance: tolerance,
                              message: "Original reference-facet admission requires its complete retained station evidence.")
        }
        try proofUsage.consume(depth: 0, tolerance: tolerance)
        let bounds = referenceCells[cellIndex].bounds
        let uValues = stations.map { $0.parameter.u }
        let wValues = stations.map(\.w)
        let du = OutwardScalarInterval.exact(uValues.max()!) - .exact(uValues.min()!)
        let dw = OutwardScalarInterval.exact(wValues.max()!) - .exact(wValues.min()!)
        let error = (OutwardScalarInterval.exact(bounds.secondDerivativeUUMagnitudeUpperBound) * du * du
            + .exact(2) * .exact(bounds.secondDerivativeUVMagnitudeUpperBound) * du * dw
            + .exact(bounds.secondDerivativeVVMagnitudeUpperBound) * dw * dw) * .exact(0.5)
            + .exact(stations.map(\.positionErrorUpperBound).max()!)
            + .exact(referenceCells[cellIndex].boundaryUncertaintyUpperBound)
        guard error.isFinite, error.upper <= fidelity.linearTolerance else {
            throw KernelError(phase: .geometry, code: .unsupportedCapability,
                              residual: error.upper, tolerance: tolerance,
                              message: "The actual reference facet exceeds whole original trim-cell fidelity.")
        }
        let angularError = OutwardScalarInterval.exact(bounds.unitNormalDerivativeUMagnitudeUpperBound) * du
            + .exact(bounds.unitNormalDerivativeVMagnitudeUpperBound) * dw
            + .exact(2) * .exact(stations.map(\.normalErrorUpperBound).max()!)
            + .exact(referenceCells[cellIndex].boundaryNormalUncertaintyUpperBound)
        guard angularError.isFinite, angularError.upper <= fidelity.angularTolerance else {
            throw KernelError(phase: .geometry, code: .unsupportedCapability,
                              residual: angularError.upper, tolerance: tolerance,
                              message: "The actual reference facet exceeds original selected-normal fidelity.")
        }
        try admitEdges(positions)
        try Task.checkCancellation()
    }

    /// E + D holds for every retained source tail and every admissible completion in the join box.
    package func admitJoinFacet(joinIndex: Int, panelIndex: Int,
                               positions: [Point3D], normals: [Vector3D],
                               proofUsage: inout OriginalTessellationProofUsage) throws {
        guard joinCells.indices.contains(joinIndex), positions.count == 3, normals.count == 3,
              joinCells[joinIndex].panels.indices.contains(panelIndex) else {
            throw KernelError(phase: .geometry, code: .invalidInput, tolerance: tolerance,
                              message: "A join facet requires its retained original uncertainty cell.")
        }
        try proofUsage.consume(depth: 0, tolerance: tolerance)
        let join = joinCells[joinIndex]
        let distances = positions.map { point in
            IntervalVector3DBounds(x: .exact(point.x) - .exact(join.sourceVertex.x),
                                  y: .exact(point.y) - .exact(join.sourceVertex.y),
                                  z: .exact(point.z) - .exact(join.sourceVertex.z)).lengthUpperBound
        }
        let bound = (OutwardScalarInterval.exact(join.originalPositionErrorUpperBound)
            + OutwardScalarInterval.exact(distances.max() ?? .infinity)).upper
        guard bound.isFinite, bound <= fidelity.linearTolerance else {
            throw KernelError(phase: .geometry, code: .unsupportedCapability,
                              residual: bound, tolerance: tolerance,
                              message: "The actual join facet exceeds retained original uncertainty fidelity.")
        }
        let panel = join.panels[panelIndex]
        let jet = try panel.span.intervalJet(overClosedBox: panel.parameters,
                                            on: input.surface, tolerance: tolerance)
        for normal in normals {
            let angle = try Self.normalAngleUpper(jet: jet, candidate: normal, tolerance: tolerance)
            guard angle <= fidelity.angularTolerance else {
                throw KernelError(phase: .geometry, code: .unsupportedCapability,
                                  residual: angle, tolerance: tolerance,
                                  message: "The actual join facet exceeds original one-sided normal fidelity.")
            }
        }
        try admitEdges(positions)
        try Task.checkCancellation()
    }

    private static func normalAngleUpper(jet: SurfaceIntervalVectorJet,
                                         candidate: Vector3D, tolerance: ModelingTolerance) throws -> Double {
        guard candidate.x.isFinite, candidate.y.isFinite, candidate.z.isFinite,
              let original = jet.differentiatedUThroughSecondOrder()
                .cross(jet.differentiatedVThroughSecondOrder()).normalized() else {
            throw KernelError(phase: .geometry, code: .singularGeometry, tolerance: tolerance,
                              message: "Original graph-band normals require a proved regular selected support.")
        }
        let raw = IntervalVector3DBounds(x: .exact(candidate.x), y: .exact(candidate.y), z: .exact(candidate.z))
        let magnitude = OutwardScalarInterval(lower: raw.lengthLowerBound, upper: raw.lengthUpperBound)
        guard magnitude.lower > 0, let x = raw.x.divided(by: magnitude),
              let y = raw.y.divided(by: magnitude), let z = raw.z.divided(by: magnitude) else {
            throw KernelError(phase: .geometry, code: .invalidInput, tolerance: tolerance,
                              message: "Actual mesh normals must have a finite nonzero direction.")
        }
        let chord = IntervalVector3DBounds(x: original.x.value - x, y: original.y.value - y,
                                          z: original.z.value - z).lengthUpperBound
        guard chord.isFinite else {
            throw KernelError(phase: .geometry, code: .resourceLimitExceeded, tolerance: tolerance,
                              message: "Original graph-band normal comparison exceeded finite arithmetic.")
        }
        return (2 * asin(min(1, (chord * 0.5).nextUp))).nextUp
    }

    private func admitEdges(_ positions: [Point3D]) throws {
        guard positions.count == 3,
              positions.allSatisfy({ $0.x.isFinite && $0.y.isFinite && $0.z.isFinite }) else {
            throw KernelError(phase: .geometry, code: .invalidInput, tolerance: tolerance,
                              message: "Original graph-band facet positions must be finite triangles.")
        }
        for index in 0..<3 {
            let a = positions[index]
            let b = positions[(index + 1) % 3]
            let edge = IntervalVector3DBounds(x: .exact(a.x) - .exact(b.x),
                                            y: .exact(a.y) - .exact(b.y),
                                            z: .exact(a.z) - .exact(b.z)).lengthUpperBound
            guard edge <= fidelity.maximumEdgeLength else {
                throw KernelError(phase: .geometry, code: .unsupportedCapability,
                                  residual: edge, tolerance: tolerance,
                                  message: "An actual original graph-band triangle edge exceeds the caller length allowance.")
            }
        }
    }
}

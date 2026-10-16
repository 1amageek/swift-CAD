import CADCore
#if !hasFeature(Embedded)
import Foundation
#elseif canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#elseif canImport(WASILibc)
import WASILibc
#else
#error("CADGeometry numeric algorithms require the target C math module.")
#endif

/// Immutable whole-reference geometry; spatial-edge correspondence is a consumer assumption.
package struct OriginalGraphBandReceipt: Sendable {
    fileprivate final class Identity: Sendable {}

    package struct Row: Sendable {
        fileprivate let owner: Identity
        fileprivate let cellIndex: Int
        fileprivate let u: Double
        fileprivate let lower: OriginalGraphBandRationalPiece.GraphJet
        fileprivate let upper: OriginalGraphBandRationalPiece.GraphJet
        fileprivate let surfaceRow: PreparedBSplineSurfaceDifferentialEncloser.OriginalNativeSpan.RowEvaluator
    }

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
        let originalPanelJets: [SurfaceIntervalVectorJet]
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
    private let preparation: OriginalGeometryPreparationReceipt
    package let contribution: OriginalQueryContributionHandle

    init(input: OriginalGraphBandInput, fidelity: OriginalGraphBandInput.Fidelity,
         tolerance: ModelingTolerance, winding: Int, referenceCells: [ReferenceCell], joinCells: [JoinCell],
         originalBoundaryIntervals: [OriginalBoundaryInterval], preparation: OriginalGeometryPreparationReceipt,
         contribution: OriginalQueryContributionHandle) {
        self.input = input
        self.fidelity = fidelity
        self.tolerance = tolerance
        self.winding = winding
        self.referenceCells = referenceCells
        self.joinCells = joinCells
        self.originalBoundaryIntervals = originalBoundaryIntervals
        self.preparation = preparation
        self.contribution = contribution
    }

    /// Retains one original lower/upper inverse proof for a closed U station.
    package func stationRow(cellIndex: Int, u: Double,
                            using execution: inout OriginalQueryExecution) throws -> Row {
        return try preparation.withContributionScopes(using: &execution) { execution in
            try preparation.admit(tolerance: tolerance, using: &execution)
        guard referenceCells.indices.contains(cellIndex), u.isFinite,
              referenceCells[cellIndex].u.contains(u) else {
            throw KernelError(phase: .geometry, code: .invalidInput, tolerance: tolerance,
                              message: "A graph-band row requires its original retained reference cell.")
        }
        try execution.visitGeometricCell(depth: 0)
        let cell = referenceCells[cellIndex]
        let pointU = try ScalarInterval(lower: u, upper: u)
        let lower = try cell.lowerPiece.graphJet(over: pointU, tolerance: tolerance, using: &execution)
        let upper = try cell.upperPiece.graphJet(over: pointU, tolerance: tolerance, using: &execution)
        let surfaceRow = try cell.nativePanel.span.prepareStationRow(u: u, on: input.surface,
            tolerance: tolerance, using: &execution)
        try CurrentTaskCancellationChecker().checkCancellation()
        return Row(owner: identity, cellIndex: cellIndex, u: u, lower: lower, upper: upper, surfaceRow: surfaceRow)
    
        }
    }

    /// The station is a mesh approximation, paired with its original inverse uncertainty.
    package func station(cellIndex: Int, u: Double, w: Double,
                         pointCandidate: Point3D? = nil,
                         using execution: inout OriginalQueryExecution) throws -> Station {
        return try preparation.withContributionScopes(using: &execution) { execution in
            try preparation.admit(tolerance: tolerance, using: &execution)
        guard w.isFinite, (0...1).contains(w) else {
            throw KernelError(phase: .geometry, code: .invalidInput, tolerance: tolerance,
                              message: "A graph-band station requires a finite normalized W value.")
        }
        let row = try stationRow(cellIndex: cellIndex, u: u, using: &execution)
        return try station(row: row, w: w, pointCandidate: pointCandidate, using: &execution)
    
        }
    }

    /// Reuses original U preparation; each actual V station retains its independent proof.
    package func station(row: Row, w: Double, pointCandidate: Point3D? = nil,
                         using execution: inout OriginalQueryExecution) throws -> Station {
        return try preparation.withContributionScopes(using: &execution) { execution in
            try preparation.admit(tolerance: tolerance, using: &execution)
        guard row.owner === identity, referenceCells.indices.contains(row.cellIndex),
              row.u.isFinite, referenceCells[row.cellIndex].u.contains(row.u),
              w.isFinite, (0...1).contains(w) else {
            throw KernelError(phase: .geometry, code: .invalidInput, tolerance: tolerance,
                              message: "A graph-band station requires this receipt's retained original row.")
        }
        // Original surface materialization remains paid even when row inverse
        // evidence was already retained or used at another W station.
        try execution.visitGeometricCell(depth: 0)
        let cellIndex = row.cellIndex
        let u = row.u
        let value = (OutwardScalarInterval.exact(1) - .exact(w)) * row.lower.v + .exact(w) * row.upper.v
        guard value.isFinite else {
            throw KernelError(phase: .geometry, code: .resourceLimitExceeded, tolerance: tolerance,
                              message: "An original graph-band station exceeded finite materialization arithmetic.")
        }
        let v = value.midpoint
        let parameter = SurfaceParameter(u: u, v: v)
        let intervalV = try ScalarInterval(lower: value.lower, upper: value.upper)
        let materialized = try row.surfaceRow.materialize(v: v, overClosedV: intervalV, pointCandidate: pointCandidate, using: &execution)
        let point = materialized.point
        guard point.x.isFinite, point.y.isFinite, point.z.isFinite else {
            throw KernelError(phase: .geometry, code: .invalidInput, tolerance: tolerance,
                              message: "A retained mesh station candidate must have finite coordinates.")
        }
        let normal = materialized.normal
        let original = materialized.enclosure
        let positionError = IntervalVector3DBounds(
            x: original.value.x - .exact(point.x), y: original.value.y - .exact(point.y),
            z: original.value.z - .exact(point.z)).lengthUpperBound
        let normalError = try Self.normalAngleUpper(tangents: original.derivativeU.cross(original.derivativeV),
                                                   candidate: normal, tolerance: tolerance)
        guard positionError.isFinite, positionError <= fidelity.linearTolerance else {
            throw KernelError(phase: .geometry, code: .resourceLimitExceeded,
                              residual: positionError, tolerance: tolerance,
                              message: "Original graph inversion could not materialize a station within the caller allowance.")
        }
        try CurrentTaskCancellationChecker().checkCancellation()
        return Station(parameter: parameter, point: point, normal: normal,
                       positionErrorUpperBound: positionError, normalErrorUpperBound: normalError,
                       owner: identity, cellIndex: cellIndex, w: w)
    
        }
    }

    /// Whole Taylor interpolation includes the trim Hessian and actual station errors.
    package func admitReferenceFacet(cellIndex: Int, stations: [Station],
                                    positions: [Point3D], normals: [Vector3D],
                                    using execution: inout OriginalQueryExecution) throws {
        return try preparation.withContributionScopes(using: &execution) { execution in
            try preparation.admit(tolerance: tolerance, using: &execution)
        guard referenceCells.indices.contains(cellIndex), stations.count == 3,
              positions.count == 3, normals.count == 3,
              stations.indices.allSatisfy({ stations[$0].owner === identity
                  && stations[$0].cellIndex == cellIndex
                  && stations[$0].point == positions[$0] && stations[$0].normal == normals[$0] }) else {
            throw KernelError(phase: .geometry, code: .invalidInput, tolerance: tolerance,
                              message: "Original reference-facet admission requires its complete retained station evidence.")
        }
        try execution.visitGeometricCell(depth: 0)
        let bounds = referenceCells[cellIndex].bounds
        let uValues = try OriginalGraphBandStorage.map(stations, using: &execution) { station, execution in station.parameter.u }
        let wValues = try OriginalGraphBandStorage.map(stations, using: &execution) { station, execution in station.w }
        let du = OutwardScalarInterval.exact(uValues.max()!) - .exact(uValues.min()!)
        let dw = OutwardScalarInterval.exact(wValues.max()!) - .exact(wValues.min()!)
        let error = (OutwardScalarInterval.exact(bounds.secondDerivativeUUMagnitudeUpperBound) * du * du
            + .exact(2) * .exact(bounds.secondDerivativeUVMagnitudeUpperBound) * du * dw
            + .exact(bounds.secondDerivativeVVMagnitudeUpperBound) * dw * dw) * .exact(0.5)
            + .exact(try OriginalGraphBandStorage.map(stations, using: &execution) { station, execution in station.positionErrorUpperBound }.max()!)
            + .exact(referenceCells[cellIndex].boundaryUncertaintyUpperBound)
        guard error.isFinite, error.upper <= fidelity.linearTolerance else {
            throw KernelError(phase: .geometry, code: .unsupportedCapability,
                              residual: error.upper, tolerance: tolerance,
                              message: "The actual reference facet exceeds whole original trim-cell fidelity.")
        }
        let angularError = OutwardScalarInterval.exact(bounds.unitNormalDerivativeUMagnitudeUpperBound) * du
            + .exact(bounds.unitNormalDerivativeVMagnitudeUpperBound) * dw
            + .exact(2) * .exact(try OriginalGraphBandStorage.map(stations, using: &execution) { station, execution in station.normalErrorUpperBound }.max()!)
            + .exact(referenceCells[cellIndex].boundaryNormalUncertaintyUpperBound)
        guard angularError.isFinite, angularError.upper <= fidelity.angularTolerance else {
            throw KernelError(phase: .geometry, code: .unsupportedCapability,
                              residual: angularError.upper, tolerance: tolerance,
                              message: "The actual reference facet exceeds original selected-normal fidelity.")
        }
        try admitEdges(positions)
        try CurrentTaskCancellationChecker().checkCancellation()
    
        }
    }

    /// E + D holds for every retained source tail and every admissible completion in the join box.
    package func admitJoinFacet(joinIndex: Int, panelIndex: Int,
                               positions: [Point3D], normals: [Vector3D],
                               using execution: inout OriginalQueryExecution) throws {
        return try preparation.withContributionScopes(using: &execution) { execution in
            try preparation.admit(tolerance: tolerance, using: &execution)
        guard joinCells.indices.contains(joinIndex), positions.count == 3, normals.count == 3,
              joinCells[joinIndex].panels.indices.contains(panelIndex),
              joinCells[joinIndex].originalPanelJets.count == joinCells[joinIndex].panels.count else {
            throw KernelError(phase: .geometry, code: .invalidInput, tolerance: tolerance,
                              message: "A join facet requires its retained original uncertainty cell.")
        }
        try execution.visitGeometricCell(depth: 0)
        let join = joinCells[joinIndex]
        let distances = try OriginalGraphBandStorage.map(positions, using: &execution) { point, execution in
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
        // Construction paid and retained the full original closed selected panel.
        // Actual facet admission still pays its existing operation and verifies
        // every position, normal and edge against that same immutable authority.
        let jet = join.originalPanelJets[panelIndex]
        for normal in normals {
            let angle = try Self.normalAngleUpper(jet: jet, candidate: normal, tolerance: tolerance)
            guard angle <= fidelity.angularTolerance else {
                throw KernelError(phase: .geometry, code: .unsupportedCapability,
                                  residual: angle, tolerance: tolerance,
                                  message: "The actual join facet exceeds original one-sided normal fidelity.")
            }
        }
        try admitEdges(positions)
        try CurrentTaskCancellationChecker().checkCancellation()
    
        }
    }

    private static func normalAngleUpper(jet: SurfaceIntervalVectorJet,
                                         candidate: Vector3D, tolerance: ModelingTolerance) throws -> Double {
        let u = IntervalVector3DBounds(x: jet.x.derivativeU, y: jet.y.derivativeU, z: jet.z.derivativeU)
        let v = IntervalVector3DBounds(x: jet.x.derivativeV, y: jet.y.derivativeV, z: jet.z.derivativeV)
        return try normalAngleUpper(tangents: u.cross(v), candidate: candidate, tolerance: tolerance)
    }

    private static func normalAngleUpper(tangents: IntervalVector3DBounds,
                                         candidate: Vector3D, tolerance: ModelingTolerance) throws -> Double {
        let originalMagnitude = OutwardScalarInterval(lower: tangents.lengthLowerBound,
                                                      upper: tangents.lengthUpperBound)
        guard candidate.x.isFinite, candidate.y.isFinite, candidate.z.isFinite,
              originalMagnitude.lower > 0,
              let originalX = tangents.x.divided(by: originalMagnitude),
              let originalY = tangents.y.divided(by: originalMagnitude),
              let originalZ = tangents.z.divided(by: originalMagnitude) else {
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
        let chord = IntervalVector3DBounds(x: originalX - x, y: originalY - y,
                                          z: originalZ - z).lengthUpperBound
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

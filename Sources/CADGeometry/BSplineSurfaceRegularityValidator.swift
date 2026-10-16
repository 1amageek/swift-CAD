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

public struct BSplineSurfaceRegularityValidator: Sendable {
    public var maximumSubdivisionDepth: Int
    public var maximumCellCount: Int

    public init(
        maximumSubdivisionDepth: Int = 18,
        maximumCellCount: Int = 262_144
    ) {
        self.maximumSubdivisionDepth = maximumSubdivisionDepth
        self.maximumCellCount = maximumCellCount
    }

    public func validate(_ surface: BSplineSurface3D, uDomain: ParameterDomain,
        vDomain: ParameterDomain, tolerance: ModelingTolerance,
        allowStationaryBoundaryParameterization: Bool = false) throws {
        var execution = try OriginalQueryExecution.independentGeometry()
        try validate(surface, uDomain: uDomain, vDomain: vDomain, tolerance: tolerance,
            allowStationaryBoundaryParameterization: allowStationaryBoundaryParameterization, using: &execution)
    }

    public func validate(
        _ surface: BSplineSurface3D,
        uDomain: ParameterDomain,
        vDomain: ParameterDomain,
        tolerance: ModelingTolerance,
        allowStationaryBoundaryParameterization: Bool = false,
        using execution: inout OriginalQueryExecution
    ) throws {
        try tolerance.validate()
        try surface.validate(tolerance: tolerance, using: &execution)
        guard maximumSubdivisionDepth >= 0, maximumCellCount > 0 else {
            throw KernelError(
                phase: .geometry,
                code: .invalidInput,
                tolerance: tolerance,
                message: "B-spline surface regularity limits must be positive."
            )
        }
        guard surface.uDegree > 0, surface.vDegree > 0,
              case let .closed(uLower, uUpper) = uDomain,
              case let .closed(vLower, vUpper) = vDomain,
              try surface.uDomain.containsSpan(from: uLower, to: uUpper, tolerance: tolerance),
              try surface.vDomain.containsSpan(from: vLower, to: vUpper, tolerance: tolerance) else {
            throw KernelError(
                phase: .geometry,
                code: .singularGeometry,
                tolerance: tolerance,
                message: "A regular B-spline surface requires positive degrees and contained finite parameter domains."
            )
        }

        let parameterTolerance = max(
            tolerance.relative * max(abs(uLower), abs(uUpper), abs(vLower), abs(vUpper), 1.0),
            Double.ulpOfOne * 256.0
        )
        let sourcePatches = try BSplineSurfaceBezierDecomposer()
            .surfacePatches(surface: surface, tolerance: tolerance, using: &execution)

        try OriginalCoefficientAllocation.reserve(count: sourcePatches.count, of: RationalBezierSurfacePatch3D.self, using: &execution)
        var patches: [RationalBezierSurfacePatch3D] = []; patches.reserveCapacity(sourcePatches.count)
        for patch in sourcePatches {
                try execution.consumeWork(1)
                let clippedULower = max(patch.uLower, uLower)
                let clippedUUpper = min(patch.uUpper, uUpper)
                let clippedVLower = max(patch.vLower, vLower)
                let clippedVUpper = min(patch.vUpper, vUpper)
                guard clippedUUpper - clippedULower > parameterTolerance,
                      clippedVUpper - clippedVLower > parameterTolerance else {
                    continue
                }
                patches.append(try patch.trimmed(
                    uFrom: clippedULower,
                    uTo: clippedUUpper,
                    vFrom: clippedVLower,
                    vTo: clippedVUpper,
                    tolerance: tolerance, using: &execution
                ))
            }
        guard patches.isEmpty == false else {
            throw KernelError(
                phase: .geometry,
                code: .invalidInput,
                tolerance: tolerance,
                message: "The requested B-spline surface domain contains no non-degenerate knot span."
            )
        }

        var pending = try OriginalCoefficientAllocation.map(elements: patches, using: &execution) { patch, _ in Cell(patch: patch, depth: 0) }
        var pendingCapacity = pending.count
        var visitedCellCount = 0
        while let cell = pending.popLast() {
            try execution.visitGeometricCell(depth: cell.depth)
            visitedCellCount += 1
            guard visitedCellCount <= maximumCellCount else {
                throw resourceLimit(
                    residual: Double(visitedCellCount),
                    tolerance: tolerance,
                    message: "B-spline surface regularity exhausted its certified cell budget."
                )
            }
            if allowStationaryBoundaryParameterization {
                try OriginalCoefficientAllocation.reserve(count: 4, of: SurfaceParameterBoundary.self, using: &execution)
            }
            let stationaryBoundaries = allowStationaryBoundaryParameterization
                ? RationalBezierSurfaceDifferentialBounds.outerBoundaries(of: cell.patch,
                    uDomain: uDomain, vDomain: vDomain) : []
            if try certificate(for: cell.patch, tolerance: tolerance,
                stationaryBoundaries: stationaryBoundaries, using: &execution).isRegular {
                continue
            }
            try rejectSampledSingularity(
                in: cell.patch,
                surface: surface,
                tolerance: tolerance,
                stationaryBoundaries: stationaryBoundaries, using: &execution
            )
            guard cell.depth < maximumSubdivisionDepth else {
                throw resourceLimit(
                    residual: Double(cell.depth),
                    tolerance: tolerance,
                    message: "B-spline surface regularity could not certify a cell within the subdivision limit."
                )
            }
            let children = try cell.patch.subdivided(using: &execution)
            for patch in children {
                try OriginalCoefficientAllocation.reserveAppend(to: &pending, capacity: &pendingCapacity, using: &execution)
                pending.append(Cell(patch: patch, depth: cell.depth + 1))
            }
        }
    }

    private struct Cell: Sendable {
        let patch: RationalBezierSurfacePatch3D
        let depth: Int
    }

    private struct Certificate: Sendable {
        let isRegular: Bool
    }

    private func certificate(
        for patch: RationalBezierSurfacePatch3D,
        tolerance: ModelingTolerance,
        stationaryBoundaries: Set<SurfaceParameterBoundary>, using execution: inout OriginalQueryExecution
    ) throws -> Certificate {
        let weights = try OriginalCoefficientAllocation.flatten(rows: patch.weights, using: &execution)
        guard let minimumWeight = weights.min(),
              let maximumWeightValue = weights.max(),
              minimumWeight.isFinite,
              minimumWeight > 0.0,
              maximumWeightValue.isFinite else {
            return Certificate(isRegular: false)
        }
        let differentialBounds = try RationalBezierSurfaceDifferentialBounds.prepared(patch: patch,
            stationaryBoundaries: stationaryBoundaries, using: &execution)
        let maximumWeight = maximumWeightValue.nextUp
        let maximumWeightSquared = (maximumWeight * maximumWeight).nextUp
        let tangentULower = max(
            0.0,
            (differentialBounds.tangentUNumerator.lengthLowerBound
                / maximumWeightSquared).nextDown
        )
        let tangentVLower = max(
            0.0,
            (differentialBounds.tangentVNumerator.lengthLowerBound
                / maximumWeightSquared).nextDown
        )
        let denominator = (
            differentialBounds.tangentUNumerator.lengthUpperBound
                * differentialBounds.tangentVNumerator.lengthUpperBound
        ).nextUp
        let angularLower = denominator > 0.0
            ? max(
                0.0,
                (differentialBounds.normalNumerator.lengthLowerBound
                    / denominator).nextDown
            )
            : 0.0
        let angularTolerance = max(
            sin(min(tolerance.angle, Double.pi * 0.5)),
            tolerance.relative,
            Double.ulpOfOne * 256.0
        )
        return Certificate(
            isRegular: tangentULower > tolerance.distance
                && tangentVLower > tolerance.distance
                && angularLower > angularTolerance
        )
    }

    private func rejectSampledSingularity(
        in patch: RationalBezierSurfacePatch3D,
        surface: BSplineSurface3D,
        tolerance: ModelingTolerance,
        stationaryBoundaries: Set<SurfaceParameterBoundary>, using execution: inout OriginalQueryExecution
    ) throws {
        for uFraction in [0.0, 0.5, 1.0] {
            let u = patch.uLower + (patch.uUpper - patch.uLower) * uFraction
            for vFraction in [0.0, 0.5, 1.0] {
                if (uFraction == 0 && stationaryBoundaries.contains(.uLower))
                    || (uFraction == 1 && stationaryBoundaries.contains(.uUpper))
                    || (vFraction == 0 && stationaryBoundaries.contains(.vLower))
                    || (vFraction == 1 && stationaryBoundaries.contains(.vUpper)) { continue }
                let v = patch.vLower + (patch.vUpper - patch.vLower) * vFraction
                do {
                    _ = try surface.normal(u: u, v: v, tolerance: tolerance, using: &execution)
                } catch let error as KernelError where error.code == .singularSystem {
                    throw KernelError(
                        phase: .geometry,
                        code: .singularGeometry,
                        residual: error.residual,
                        tolerance: tolerance,
                        message: "The B-spline surface contains a singular parameter in the retained domain."
                    )
                }
            }
        }
    }

    private func resourceLimit(
        residual: Double,
        tolerance: ModelingTolerance,
        message: String
    ) -> KernelError {
        KernelError(
            phase: .geometry,
            code: .resourceLimitExceeded,
            residual: residual,
            tolerance: tolerance,
            message: message
        )
    }

}

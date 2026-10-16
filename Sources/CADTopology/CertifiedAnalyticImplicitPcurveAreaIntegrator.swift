import CADCore
import CADGeometry
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#elseif canImport(WASILibc)
import WASILibc
#else
#error("A C math implementation is required.")
#endif

struct CertifiedAnalyticImplicitPcurveAreaIntegrator {
    func bounds(for curve: CertifiedAnalyticImplicitSurfaceParameterCurve,
        uShift: Double, tolerance: ModelingTolerance) throws -> SurfaceParameterAreaBounds {
        var execution = try OriginalQueryExecution.independentGeometry()
        return try bounds(for: curve, uShift: uShift, tolerance: tolerance, using: &execution)
    }

    func bounds(for curve: CertifiedAnalyticImplicitSurfaceParameterCurve,
        uShift: Double, tolerance: ModelingTolerance,
        using execution: inout OriginalQueryExecution) throws -> SurfaceParameterAreaBounds {
        try execution.checkpoint()
        let intersection = curve.intersection
        try intersection.validate(tolerance: tolerance, using: &execution)
        let implicit = intersection.implicitCurve
        guard implicit.cells.isEmpty == false else {
            throw KernelError(
                phase: .topology,
                code: .invalidInput,
                tolerance: tolerance,
                message: "Certified analytic pcurve area requires at least one graph cell."
            )
        }
        let ascendingStart = min(curve.startFraction, curve.endFraction)
        let ascendingEnd = max(curve.startFraction, curve.endFraction)
        let cellCount = implicit.cells.count
        var result = SurfaceParameterAreaBounds.zero
        for (index, cell) in implicit.cells.enumerated() {
            try execution.visitGeometricCell(depth: 0)
            let cellStart = Double(index) / Double(cellCount)
            let cellEnd = Double(index + 1) / Double(cellCount)
            let overlapStart = max(ascendingStart, cellStart)
            let overlapEnd = min(ascendingEnd, cellEnd)
            guard overlapEnd - overlapStart > tolerance.relative else {
                continue
            }
            let localLower = (overlapStart - cellStart) * Double(cellCount)
            let localUpper = (overlapEnd - cellStart) * Double(cellCount)
            let subcell = try cell.restrictedBounds(
                fromNormalizedFraction: localLower,
                toNormalizedFraction: localUpper,
                firstSurface: implicit.firstSurface,
                secondSurface: implicit.secondSurface,
                tolerance: tolerance, using: &execution
            )
            let enclosure = try curve.parameterEnclosure(
                for: subcell,
                tolerance: tolerance, using: &execution
            )
            result = result.adding(intervalProductBounds(
                lower: (enclosure.u.lower + uShift).nextDown,
                upper: (enclosure.u.upper + uShift).nextUp,
                scalarLower: enclosure.vDerivative.lower,
                scalarUpper: enclosure.vDerivative.upper
            ))
        }
        try execution.checkpoint()
        guard curve.startFraction <= curve.endFraction else {
            return SurfaceParameterAreaBounds(
                lower: (-result.upper).nextDown,
                upper: (-result.lower).nextUp
            )
        }
        return result
    }

    private func intervalProductBounds(
        lower: Double,
        upper: Double,
        scalarLower: Double,
        scalarUpper: Double
    ) -> SurfaceParameterAreaBounds {
        let a = lower * scalarLower, b = lower * scalarUpper
        let c = upper * scalarLower, d = upper * scalarUpper
        return SurfaceParameterAreaBounds(
            lower: min(min(a, b), min(c, d)).nextDown,
            upper: max(max(a, b), max(c, d)).nextUp
        )
    }
}

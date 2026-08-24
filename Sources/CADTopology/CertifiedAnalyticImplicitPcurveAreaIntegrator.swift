import CADCore
import CADGeometry
import Foundation

struct CertifiedAnalyticImplicitPcurveAreaIntegrator {
    func bounds(
        for curve: CertifiedAnalyticImplicitSurfaceParameterCurve,
        uShift: Double,
        tolerance: ModelingTolerance
    ) throws -> SurfaceParameterAreaBounds {
        let intersection = curve.intersection
        try intersection.validate(tolerance: tolerance)
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
                tolerance: tolerance
            )
            let enclosure = try curve.parameterEnclosure(
                for: subcell,
                tolerance: tolerance
            )
            result = result.adding(intervalProductBounds(
                lower: (enclosure.u.lower + uShift).nextDown,
                upper: (enclosure.u.upper + uShift).nextUp,
                scalarLower: enclosure.vDerivative.lower,
                scalarUpper: enclosure.vDerivative.upper
            ))
        }
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
        let products = [
            lower * scalarLower,
            lower * scalarUpper,
            upper * scalarLower,
            upper * scalarUpper,
        ]
        return SurfaceParameterAreaBounds(
            lower: (products.min() ?? -.infinity).nextDown,
            upper: (products.max() ?? .infinity).nextUp
        )
    }
}

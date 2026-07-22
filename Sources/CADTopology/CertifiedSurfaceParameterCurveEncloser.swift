import Foundation
import CADCore
import CADGeometry

package struct CertifiedSurfaceParameterCurveEncloser {
    private struct ImplicitWorkItem {
        let cell: CertifiedImplicitIntersectionGraphCell
        let cellIndex: Int
        let curveLowerFraction: Double
        let curveUpperFraction: Double
        let depth: Int
    }

    private let maximumDepth = 48
    private let maximumCellCount = 131_072

    package init() {}

    package func enclosures(
        for curve: SurfaceParameterCurve,
        maximumWidth: Double,
        tolerance: ModelingTolerance
    ) throws -> [SurfaceParameterCurveEnclosure] {
        try tolerance.validate()
        guard maximumWidth.isFinite, maximumWidth > 0.0 else {
            throw failure(
                .invalidInput,
                residual: maximumWidth,
                tolerance: tolerance,
                "Surface-parameter enclosure requires a finite positive width."
            )
        }
        switch curve {
        case let .certifiedImplicit(certified):
            return try implicitEnclosures(
                for: certified,
                maximumWidth: maximumWidth,
                tolerance: tolerance
            )
        case let .certifiedAnalyticImplicit(certified):
            return try analyticImplicitEnclosures(
                for: certified,
                maximumWidth: maximumWidth,
                tolerance: tolerance
            )
        case .sphericalGreatCircle, .projectedAnalytic:
            return try CertifiedAnalyticPcurveFluxIntegrator()
                .parameterEnclosures(
                    for: curve,
                    maximumWidth: maximumWidth,
                    tolerance: tolerance
                )
        case let .certifiedAnalyticPair(certified):
            return try CertifiedAnalyticPairPcurveAreaIntegrator()
                .parameterEnclosures(
                    for: certified,
                    maximumWidth: maximumWidth,
                    tolerance: tolerance
                )
        case .affine, .constantU, .constantV, .harmonic, .polyline, .bSpline:
            throw failure(
                .invalidInput,
                tolerance: tolerance,
                "Rationally representable pcurves must use their Bézier hull enclosure path."
            )
        }
    }

    private func implicitEnclosures(
        for curve: CertifiedImplicitSurfaceParameterCurve,
        maximumWidth: Double,
        tolerance: ModelingTolerance
    ) throws -> [SurfaceParameterCurveEnclosure] {
        try curve.validate(
            on: curve.role == .first
                ? .bSpline(curve.intersection.firstSurface)
                : .bSpline(curve.intersection.secondSurface),
            tolerance: tolerance
        )
        let uCoordinate: SurfaceIntersectionParameterCoordinate = curve.role == .first
            ? .firstU
            : .secondU
        let vCoordinate: SurfaceIntersectionParameterCoordinate = curve.role == .first
            ? .firstV
            : .secondV
        return try graphEnclosures(
            cells: curve.intersection.cells,
            firstSurface: curve.intersection.firstSurface,
            secondSurface: curve.intersection.secondSurface,
            startFraction: curve.startFraction,
            endFraction: curve.endFraction,
            maximumWidth: maximumWidth,
            tolerance: tolerance
        ) { subcell, lowerFraction, upperFraction in
            SurfaceParameterCurveEnclosure(
                lowerFraction: lowerFraction,
                upperFraction: upperFraction,
                u: subcell.parameterBox.interval(for: uCoordinate),
                v: subcell.parameterBox.interval(for: vCoordinate)
            )
        }
    }

    private func analyticImplicitEnclosures(
        for curve: CertifiedAnalyticImplicitSurfaceParameterCurve,
        maximumWidth: Double,
        tolerance: ModelingTolerance
    ) throws -> [SurfaceParameterCurveEnclosure] {
        try curve.validate(
            on: curve.intersection.analyticSurface,
            tolerance: tolerance
        )
        let intersection = curve.intersection
        let implicit = intersection.implicitCurve
        let uCoordinate: SurfaceIntersectionParameterCoordinate = intersection.analyticIsFirst
            ? .firstU
            : .secondU
        let vCoordinate: SurfaceIntersectionParameterCoordinate = intersection.analyticIsFirst
            ? .firstV
            : .secondV
        return try graphEnclosures(
            cells: implicit.cells,
            firstSurface: implicit.firstSurface,
            secondSurface: implicit.secondSurface,
            startFraction: curve.startFraction,
            endFraction: curve.endFraction,
            maximumWidth: maximumWidth,
            tolerance: tolerance
        ) { subcell, lowerFraction, upperFraction in
            let u = try circleAngleBounds(
                subcell.parameterBox.interval(for: uCoordinate),
                offset: intersection.periodicSeamOffset,
                parameterUpperBound: 4.0,
                tolerance: tolerance
            )
            let vSource = subcell.parameterBox.interval(for: vCoordinate)
            let v: ScalarInterval
            switch intersection.analyticSurface {
            case .cylinder, .analytic(.cylinder), .analytic(.cone):
                v = vSource
            case .analytic(.sphere):
                v = try circleAngleBounds(
                    vSource,
                    offset: -Double.pi * 0.5,
                    parameterUpperBound: 2.0,
                    tolerance: tolerance
                )
            case .analytic(.torus):
                v = try circleAngleBounds(
                    vSource,
                    offset: intersection.periodicSeamOffset,
                    parameterUpperBound: 4.0,
                    tolerance: tolerance
                )
            case .plane, .analytic(.plane), .bSpline:
                throw failure(
                    .invalidInput,
                    tolerance: tolerance,
                    "A certified analytic-implicit pcurve has an invalid support surface."
                )
            }
            return SurfaceParameterCurveEnclosure(
                lowerFraction: lowerFraction,
                upperFraction: upperFraction,
                u: u,
                v: v
            )
        }
    }

    private func graphEnclosures(
        cells: [CertifiedImplicitIntersectionGraphCell],
        firstSurface: BSplineSurface3D,
        secondSurface: BSplineSurface3D,
        startFraction: Double,
        endFraction: Double,
        maximumWidth: Double,
        tolerance: ModelingTolerance,
        transform: (
            CertifiedImplicitIntersectionGraphSubcell,
            Double,
            Double
        ) throws -> SurfaceParameterCurveEnclosure
    ) throws -> [SurfaceParameterCurveEnclosure] {
        guard cells.isEmpty == false else {
            throw failure(
                .invalidInput,
                tolerance: tolerance,
                "A certified implicit pcurve requires graph cells."
            )
        }
        let ascendingStart = min(startFraction, endFraction)
        let ascendingEnd = max(startFraction, endFraction)
        let cellCount = cells.count
        var pending: [ImplicitWorkItem] = []
        for (index, cell) in cells.enumerated() {
            let cellStart = Double(index) / Double(cellCount)
            let cellEnd = Double(index + 1) / Double(cellCount)
            let overlapStart = max(ascendingStart, cellStart)
            let overlapEnd = min(ascendingEnd, cellEnd)
            guard overlapEnd - overlapStart > tolerance.relative else { continue }
            let firstLocal = (overlapStart - startFraction)
                / (endFraction - startFraction)
            let secondLocal = (overlapEnd - startFraction)
                / (endFraction - startFraction)
            pending.append(ImplicitWorkItem(
                cell: cell,
                cellIndex: index,
                curveLowerFraction: min(firstLocal, secondLocal),
                curveUpperFraction: max(firstLocal, secondLocal),
                depth: 0
            ))
        }
        var result: [SurfaceParameterCurveEnclosure] = []
        var processedCount = 0
        while let item = pending.popLast() {
            processedCount += 1
            guard processedCount <= maximumCellCount else {
                throw failure(
                    .resourceLimitExceeded,
                    residual: Double(processedCount),
                    tolerance: tolerance,
                    "Certified pcurve enclosure exceeded its graph-cell budget."
                )
            }
            let subcell = try restrictedBounds(
                item,
                cellCount: cellCount,
                firstSurface: firstSurface,
                secondSurface: secondSurface,
                startFraction: startFraction,
                endFraction: endFraction,
                tolerance: tolerance
            )
            let enclosure = try transform(
                subcell,
                item.curveLowerFraction,
                item.curveUpperFraction
            )
            if enclosure.maximumWidth <= maximumWidth {
                result.append(enclosure)
                continue
            }
            guard item.depth < maximumDepth else {
                throw failure(
                    .resourceLimitExceeded,
                    residual: enclosure.maximumWidth,
                    tolerance: tolerance,
                    "Certified pcurve enclosure exceeded its subdivision depth."
                )
            }
            let middle = item.curveLowerFraction
                + (item.curveUpperFraction - item.curveLowerFraction) * 0.5
            guard middle > item.curveLowerFraction,
                  middle < item.curveUpperFraction else {
                throw failure(
                    .resourceLimitExceeded,
                    tolerance: tolerance,
                    "Certified pcurve enclosure reached floating-point subdivision resolution."
                )
            }
            pending.append(ImplicitWorkItem(
                cell: item.cell,
                cellIndex: item.cellIndex,
                curveLowerFraction: middle,
                curveUpperFraction: item.curveUpperFraction,
                depth: item.depth + 1
            ))
            pending.append(ImplicitWorkItem(
                cell: item.cell,
                cellIndex: item.cellIndex,
                curveLowerFraction: item.curveLowerFraction,
                curveUpperFraction: middle,
                depth: item.depth + 1
            ))
        }
        guard result.isEmpty == false else {
            throw failure(
                .topologyFailure,
                tolerance: tolerance,
                "Certified pcurve enclosure produced no covered cells."
            )
        }
        return result.sorted { $0.lowerFraction < $1.lowerFraction }
    }

    private func restrictedBounds(
        _ item: ImplicitWorkItem,
        cellCount: Int,
        firstSurface: BSplineSurface3D,
        secondSurface: BSplineSurface3D,
        startFraction: Double,
        endFraction: Double,
        tolerance: ModelingTolerance
    ) throws -> CertifiedImplicitIntersectionGraphSubcell {
        let firstGlobal = startFraction
            + (endFraction - startFraction) * item.curveLowerFraction
        let secondGlobal = startFraction
            + (endFraction - startFraction) * item.curveUpperFraction
        let cellStart = Double(item.cellIndex) / Double(cellCount)
        let localLower = (min(firstGlobal, secondGlobal) - cellStart)
            * Double(cellCount)
        let localUpper = (max(firstGlobal, secondGlobal) - cellStart)
            * Double(cellCount)
        return try item.cell.restrictedBounds(
            fromNormalizedFraction: min(max(localLower, 0.0), 1.0),
            toNormalizedFraction: min(max(localUpper, 0.0), 1.0),
            firstSurface: firstSurface,
            secondSurface: secondSurface,
            tolerance: tolerance
        )
    }

    private func circleAngleBounds(
        _ parameter: ScalarInterval,
        offset: Double,
        parameterUpperBound: Double,
        tolerance: ModelingTolerance
    ) throws -> ScalarInterval {
        guard parameter.lower >= -tolerance.relative,
              parameter.upper <= parameterUpperBound + tolerance.relative else {
            throw failure(
                .intersectionFailure,
                tolerance: tolerance,
                "An analytic circle parameter left its certified conversion domain."
            )
        }
        let lower = circleAngle(
            at: min(max(parameter.lower, 0.0), parameterUpperBound)
        ) + offset
        let upper = circleAngle(
            at: min(max(parameter.upper, 0.0), parameterUpperBound)
        ) + offset
        guard lower.isFinite, upper.isFinite, lower <= upper else {
            throw failure(
                .topologyFailure,
                tolerance: tolerance,
                "An analytic circle parameter lost monotone angle order."
            )
        }
        return try ScalarInterval(lower: lower.nextDown, upper: upper.nextUp)
    }

    private func circleAngle(at parameter: Double) -> Double {
        if parameter >= 4.0 { return 2.0 * Double.pi }
        let segment = min(max(Int(floor(parameter)), 0), 3)
        let local = parameter - Double(segment)
        let complement = 1.0 - local
        let diagonalWeight = sqrt(0.5)
        let x = complement * complement
            + 2.0 * diagonalWeight * local * complement
        let y = 2.0 * diagonalWeight * local * complement
            + local * local
        return Double(segment) * Double.pi * 0.5 + atan2(y, x)
    }

    private func failure(
        _ code: KernelErrorCode,
        residual: Double? = nil,
        tolerance: ModelingTolerance,
        _ message: String
    ) -> KernelError {
        KernelError(
            phase: .topology,
            code: code,
            residual: residual,
            tolerance: tolerance,
            message: message
        )
    }
}

import Foundation
import CADCore

struct DefaultParametricCurveSurfaceRootCertifier:
    ParametricCurveSurfaceRootCertifying
{
    private let curveDerivativeRangeResolver:
        any CurveSpatialDerivativeRangeResolving
    private let surfaceDerivativeRangeResolver:
        any BSplineSurfaceDerivativeRangeResolving

    init(
        curveDerivativeRangeResolver:
            any CurveSpatialDerivativeRangeResolving =
                DefaultCurveSpatialDerivativeRangeResolver(),
        surfaceDerivativeRangeResolver:
            any BSplineSurfaceDerivativeRangeResolving =
                DefaultBSplineSurfaceDerivativeRangeResolver()
    ) {
        self.curveDerivativeRangeResolver = curveDerivativeRangeResolver
        self.surfaceDerivativeRangeResolver = surfaceDerivativeRangeResolver
    }

    private struct IntervalVector {
        let x: ScalarInterval
        let y: ScalarInterval
        let z: ScalarInterval
    }

    func certificate(
        curve: Curve3D,
        surface: BSplineSurface3D,
        cell: ParametricCurveSurfaceRootCell,
        tolerance: ModelingTolerance
    ) throws -> ParametricCurveSurfaceRootCertificate {
        guard let curveDerivative = try curveDerivativeRangeResolver
            .derivativeRange(
                curve: curve,
                interval: cell.curve,
                tolerance: tolerance
            ) else {
            return .unresolved
        }
        let surfaceDerivative = try surfaceDerivativeRanges(
            patches: cell.surfacePatches,
            uInterval: cell.surfaceU,
            vInterval: cell.surfaceV,
            tolerance: tolerance
        )
        let curveGeometry = try curve.differentialGeometry(
            at: cell.curve.midpoint,
            tolerance: tolerance
        )
        let surfaceGeometry = try Surface3D.bSpline(surface).parameterDerivatives(
            atU: cell.surfaceU.midpoint,
            v: cell.surfaceV.midpoint,
            tolerance: tolerance
        )
        let midpointColumns = [
            curveGeometry.firstDerivative * cell.curve.width,
            surfaceGeometry.tangentU * -cell.surfaceU.width,
            surfaceGeometry.tangentV * -cell.surfaceV.width,
        ]
        guard let inverse = inverseRows(columns: midpointColumns) else {
            return .unresolved
        }
        let jacobian = [
            [
                try scaled(curveDerivative.x, by: cell.curve.width),
                try scaled(surfaceDerivative.u.x, by: -cell.surfaceU.width),
                try scaled(surfaceDerivative.v.x, by: -cell.surfaceV.width),
            ],
            [
                try scaled(curveDerivative.y, by: cell.curve.width),
                try scaled(surfaceDerivative.u.y, by: -cell.surfaceU.width),
                try scaled(surfaceDerivative.v.y, by: -cell.surfaceV.width),
            ],
            [
                try scaled(curveDerivative.z, by: cell.curve.width),
                try scaled(surfaceDerivative.u.z, by: -cell.surfaceU.width),
                try scaled(surfaceDerivative.v.z, by: -cell.surfaceV.width),
            ],
        ]
        let residual = curveGeometry.position - surfaceGeometry.position
        let functionValue = [
            try constantInterval(residual.x),
            try constantInterval(residual.y),
            try constantInterval(residual.z),
        ]
        let radius = try ScalarInterval(lower: -0.5, upper: 0.5)
        var krawczyk: [ScalarInterval] = []
        krawczyk.reserveCapacity(3)
        for row in 0..<3 {
            var component = try constantInterval(0.5)
            for inner in 0..<3 {
                component = try added(
                    component,
                    scaled(
                        functionValue[inner],
                        by: -inverse[row][inner]
                    )
                )
            }
            for column in 0..<3 {
                var preconditioned = try constantInterval(0.0)
                for inner in 0..<3 {
                    preconditioned = try added(
                        preconditioned,
                        scaled(
                            jacobian[inner][column],
                            by: inverse[row][inner]
                        )
                    )
                }
                let identity = try constantInterval(
                    row == column ? 1.0 : 0.0
                )
                component = try added(
                    component,
                    multiplied(
                        added(
                            identity,
                            scaled(preconditioned, by: -1.0)
                        ),
                        radius
                    )
                )
            }
            krawczyk.append(component)
        }
        if krawczyk.contains(where: {
            $0.upper < 0.0 || $0.lower > 1.0
        }) {
            return .excluded
        }
        if krawczyk.allSatisfy({
            $0.lower > 0.0 && $0.upper < 1.0
        }) {
            return .unique
        }
        return .unresolved
    }

    func boundaryCertificate(
        curve: Curve3D,
        surface: BSplineSurface3D,
        cell: ParametricCurveSurfaceRootCell,
        witness: CurveSurfaceIntersection,
        tolerance: ModelingTolerance
    ) throws -> ParametricCurveSurfaceRootCertificate {
        let parameters = [
            (witness.curveParameter - cell.curve.lower) / cell.curve.width,
            (witness.surfaceU - cell.surfaceU.lower) / cell.surfaceU.width,
            (witness.surfaceV - cell.surfaceV.lower) / cell.surfaceV.width,
        ]
        let parameterSlack = Double.ulpOfOne * 8_192.0
        guard parameters.allSatisfy({
            $0.isFinite && $0 >= -parameterSlack && $0 <= 1.0 + parameterSlack
        }) else {
            return .unresolved
        }
        let curveDerivative = try curveDerivativeRangeResolver.derivativeRange(
            curve: curve,
            interval: cell.curve,
            tolerance: tolerance
        )
        guard let curveDerivative else { return .unresolved }
        let surfaceDerivative = try surfaceDerivativeRanges(
            patches: cell.surfacePatches,
            uInterval: cell.surfaceU,
            vInterval: cell.surfaceV,
            tolerance: tolerance
        )
        let curveGeometry = try curve.differentialGeometry(
            at: witness.curveParameter,
            tolerance: tolerance
        )
        let surfaceGeometry = try Surface3D.bSpline(surface).parameterDerivatives(
            atU: witness.surfaceU,
            v: witness.surfaceV,
            tolerance: tolerance
        )
        let midpointColumns = [
            curveGeometry.firstDerivative * cell.curve.width,
            surfaceGeometry.tangentU * -cell.surfaceU.width,
            surfaceGeometry.tangentV * -cell.surfaceV.width,
        ]
        guard let inverse = inverseRows(columns: midpointColumns) else {
            return .unresolved
        }
        let jacobian = [
            [
                try scaled(curveDerivative.x, by: cell.curve.width),
                try scaled(surfaceDerivative.u.x, by: -cell.surfaceU.width),
                try scaled(surfaceDerivative.v.x, by: -cell.surfaceV.width),
            ],
            [
                try scaled(curveDerivative.y, by: cell.curve.width),
                try scaled(surfaceDerivative.u.y, by: -cell.surfaceU.width),
                try scaled(surfaceDerivative.v.y, by: -cell.surfaceV.width),
            ],
            [
                try scaled(curveDerivative.z, by: cell.curve.width),
                try scaled(surfaceDerivative.u.z, by: -cell.surfaceU.width),
                try scaled(surfaceDerivative.v.z, by: -cell.surfaceV.width),
            ],
        ]
        let curvePoint = curveGeometry.position
        let surfacePoint = surfaceGeometry.position
        let residual = curvePoint - surfacePoint
        guard residual.length <= tolerance.distance,
              witness.residual <= tolerance.distance else {
            return .unresolved
        }
        var contractionBound = 0.0
        for row in 0..<3 {
            var rowBound = 0.0
            for column in 0..<3 {
                var preconditioned = try constantInterval(0.0)
                for inner in 0..<3 {
                    preconditioned = try added(
                        preconditioned,
                        scaled(
                            jacobian[inner][column],
                            by: inverse[row][inner]
                        )
                    )
                }
                let identity = try constantInterval(
                    row == column ? 1.0 : 0.0
                )
                let value = try added(
                    identity,
                    scaled(preconditioned, by: -1.0)
                )
                rowBound += max(abs(value.lower), abs(value.upper))
            }
            contractionBound = max(contractionBound, rowBound)
        }
        return contractionBound < 1.0 ? .unique : .unresolved
    }

    private func surfaceDerivativeRanges(
        patches: [RationalBezierSurfacePatch3D],
        uInterval: ScalarInterval,
        vInterval: ScalarInterval,
        tolerance: ModelingTolerance
    ) throws -> (u: IntervalVector, v: IntervalVector) {
        let ranges = try surfaceDerivativeRangeResolver.derivativeRanges(
            patches: patches,
            uInterval: uInterval,
            vInterval: vInterval,
            tolerance: tolerance
        )
        return (
            u: IntervalVector(
                x: ranges.u.x,
                y: ranges.u.y,
                z: ranges.u.z
            ),
            v: IntervalVector(
                x: ranges.v.x,
                y: ranges.v.y,
                z: ranges.v.z
            )
        )
    }

    private func inverseRows(
        columns: [Vector3D]
    ) -> [[Double]]? {
        guard columns.count == 3 else { return nil }
        let firstCross = columns[1].cross(columns[2])
        let determinant = columns[0].dot(firstCross)
        let scale = max(
            columns[0].length,
            max(columns[1].length, columns[2].length)
        )
        let determinantFloor = max(
            pow(scale, 3.0) * Double.ulpOfOne * 1_024.0,
            Double.leastNonzeroMagnitude
        )
        guard determinant.isFinite,
              scale.isFinite,
              abs(determinant) > determinantFloor else {
            return nil
        }
        let rows = [
            firstCross * (1.0 / determinant),
            columns[2].cross(columns[0]) * (1.0 / determinant),
            columns[0].cross(columns[1]) * (1.0 / determinant),
        ]
        return rows.map { [$0.x, $0.y, $0.z] }
    }

    private func constantInterval(_ value: Double) throws -> ScalarInterval {
        try ScalarInterval(lower: value, upper: value)
    }

    private func added(
        _ first: ScalarInterval,
        _ second: ScalarInterval
    ) throws -> ScalarInterval {
        try outwardInterval([
            first.lower + second.lower,
            first.upper + second.upper,
        ])
    }

    private func multiplied(
        _ first: ScalarInterval,
        _ second: ScalarInterval
    ) throws -> ScalarInterval {
        try outwardInterval([
            first.lower * second.lower,
            first.lower * second.upper,
            first.upper * second.lower,
            first.upper * second.upper,
        ])
    }

    private func scaled(
        _ interval: ScalarInterval,
        by scale: Double
    ) throws -> ScalarInterval {
        try outwardInterval([
            interval.lower * scale,
            interval.upper * scale,
        ])
    }

    private func outwardInterval(
        _ values: [Double]
    ) throws -> ScalarInterval {
        guard let lower = values.min(),
              let upper = values.max(),
              lower.isFinite,
              upper.isFinite else {
            throw arithmeticFailure()
        }
        return try ScalarInterval(
            lower: lower.nextDown,
            upper: upper.nextUp
        )
    }

    private func arithmeticFailure() -> KernelError {
        KernelError(
            phase: .geometry,
            code: .resourceLimitExceeded,
            tolerance: nil,
            message: "Parametric root interval arithmetic exceeded finite representation."
        )
    }
}

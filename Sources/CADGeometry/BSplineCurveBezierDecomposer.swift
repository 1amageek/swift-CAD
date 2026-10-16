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

struct BSplineCurveBezierDecomposer {
    func curvePatches<A: ExactScalarAdmission & ~Copyable>(
        curve: BSplineCurve3D,
        tolerance: ModelingTolerance, using execution: inout A
    ) throws -> [RationalBezierCurvePatch3D] {
        try execution.consumeWork(1)
        return try resolvedCurvePatches(
            curve: curve,
            intersecting: nil,
            tolerance: tolerance, using: &execution
        )
    }

    func curvePatches<A: ExactScalarAdmission & ~Copyable>(
        curve: BSplineCurve3D,
        intersecting interval: ScalarInterval,
        tolerance: ModelingTolerance, using execution: inout A
    ) throws -> [RationalBezierCurvePatch3D] {
        try execution.consumeWork(1)
        return try resolvedCurvePatches(
            curve: curve,
            intersecting: interval,
            tolerance: tolerance, using: &execution
        )
    }

    private func resolvedCurvePatches<A: ExactScalarAdmission & ~Copyable>(
        curve: BSplineCurve3D,
        intersecting interval: ScalarInterval?,
        tolerance: ModelingTolerance, using execution: inout A
    ) throws -> [RationalBezierCurvePatch3D] {
        try execution.consumeWork(1)
        try curve.validate(tolerance: tolerance, using: &execution)
        if curve.isPeriodic {
            guard case let .closed(lower, upper) = curve.fundamentalDomain else {
                throw GeometryError.invalidDistance(0)
            }
            let restriction = try curve.trimmed(from: interval?.lower ?? lower,
                to: interval?.upper ?? upper, tolerance: tolerance, using: &execution)
            return try resolvedCurvePatches(curve: restriction, intersecting: interval, tolerance: tolerance, using: &execution)
        }
        let breaks = try parameterBreaks(
            knots: curve.knots,
            domain: curve.domain,
            tolerance: tolerance, using: &execution
        )
        var result: [RationalBezierCurvePatch3D] = []
        try execution.retainStorage(bytes: exactScalarPayloadBytes(count: breaks.count - 1, of: RationalBezierCurvePatch3D.self))
        result.reserveCapacity(breaks.count - 1)
        for index in 0..<(breaks.count - 1) {
            try execution.consumeWork(1)
            if let interval,
               breaks[index + 1] <= interval.lower
                || breaks[index] >= interval.upper {
                continue
            }
            let patch = try curvePatch(
                curve: curve,
                lower: breaks[index],
                upper: breaks[index + 1],
                tolerance: tolerance, using: &execution
            )
            result.append(patch)
        }
        return result
    }

    private func curvePatch<A: ExactScalarAdmission & ~Copyable>(
        curve: BSplineCurve3D,
        lower: Double,
        upper: Double,
        tolerance: ModelingTolerance, using execution: inout A
    ) throws -> RationalBezierCurvePatch3D {
        try execution.consumeWork(1)
        let width = curve.degree.addingReportingOverflow(1)
        guard !width.overflow else { throw ExactScalarFailure.countOverflow }
        let span = upper - lower
        guard span.isFinite, span > 0.0 else {
            throw KernelError(
                phase: .geometry,
                code: .invalidInput,
                tolerance: tolerance,
                message: "B-spline Bezier extraction requires a positive finite knot span."
            )
        }
        // Degree-fold boundary knots already isolate a Bezier control polygon.
        if let upperIndex = try curve.knots.firstIndex(where: {
            try execution.consumeWork(1)
            return $0 == upper
        }),
           upperIndex > curve.degree, upperIndex <= curve.controlPointCount,
           try curve.knots[(upperIndex - curve.degree)..<upperIndex].allSatisfy({
               try execution.consumeWork(1); return $0 == lower
           }),
           try curve.knots[upperIndex..<(upperIndex + curve.degree)].allSatisfy({
               try execution.consumeWork(1); return $0 == upper
           }) {
            let controls = (upperIndex - curve.degree - 1)..<upperIndex
            try execution.retainStorage(bytes: exactScalarPayloadBytes(count: controls.count, of: Point3D.self))
            try execution.retainStorage(bytes: exactScalarPayloadBytes(count: controls.count, of: Double.self))
            for _ in controls { try execution.consumeWork(1) }
            return RationalBezierCurvePatch3D(
                controlPoints: Array(curve.controlPoints[controls]),
                weights: Array(curve.weights[controls]),
                lower: lower,
                upper: upper
            )
        }
        var derivatives: [HomogeneousVector] = []
        try execution.retainStorage(bytes: exactScalarPayloadBytes(count: width.partialValue, of: HomogeneousVector.self))
        derivatives.reserveCapacity(width.partialValue)
        for derivativeOrder in 0...curve.degree {
            let basis = try BSplineBasis.derivativeValues(
                parameter: lower,
                degree: curve.degree,
                derivativeOrder: derivativeOrder,
                knots: curve.knots,
                count: curve.controlPointCount, using: &execution
            )
            derivatives.append(try homogeneousDerivative(curve: curve, basis: basis, using: &execution))
        }
        var controls: [HomogeneousVector] = []
        try execution.retainStorage(bytes: exactScalarPayloadBytes(count: width.partialValue, of: HomogeneousVector.self))
        controls.reserveCapacity(width.partialValue)
        for controlIndex in 0...curve.degree {
            var control = HomogeneousVector.zero
            for derivativeOrder in 0...controlIndex {
                let scale = try derivativeToBernsteinScale(
                    degree: curve.degree,
                    controlIndex: controlIndex,
                    derivativeOrder: derivativeOrder,
                    span: span,
                    tolerance: tolerance, using: &execution
                )
                control = control + derivatives[derivativeOrder] * scale
            }
            controls.append(control)
        }
        var points: [Point3D] = []
        var weights: [Double] = []
        try execution.retainStorage(bytes: exactScalarPayloadBytes(count: controls.count, of: Point3D.self))
        points.reserveCapacity(controls.count)
        try execution.retainStorage(bytes: exactScalarPayloadBytes(count: controls.count, of: Double.self))
        weights.reserveCapacity(controls.count)
        // A polynomial curve (one weight throughout) keeps that weight exactly on every span; its
        // weight's derivatives, zero, would otherwise leave rounding in the extracted weights.
        let uniform = try curve.weights.allSatisfy {
            try execution.consumeWork(1)
            return $0 == curve.weights[0]
        } ? curve.weights[0] : nil
        for control in controls {
            try execution.consumeWork(1)
            guard control.isFinite,
                  control.weight > Double.ulpOfOne else {
                throw KernelError(
                    phase: .geometry,
                    code: .singularSystem,
                    residual: control.weight,
                    tolerance: tolerance,
                    message: "B-spline Bezier extraction produced a non-positive homogeneous weight."
                )
            }
            let weight = uniform ?? control.weight
            points.append(Point3D(
                x: control.x / weight,
                y: control.y / weight,
                z: control.z / weight
            ))
            weights.append(weight)
        }
        return RationalBezierCurvePatch3D(
            controlPoints: points,
            weights: weights,
            lower: lower,
            upper: upper
        )
    }

    private func homogeneousDerivative<A: ExactScalarAdmission & ~Copyable>(
        curve: BSplineCurve3D,
        basis: [Double], using execution: inout A
    ) throws -> HomogeneousVector {
        try execution.consumeWork(1)
        var result = HomogeneousVector.zero
        for index in 0..<curve.controlPointCount {
            try execution.consumeWork(1)
            let weight = curve.weights[index]
            let coefficient = basis[index] * weight
            guard coefficient != 0.0 else { continue }
            let point = curve.controlPoints[index]
            result = result + HomogeneousVector(
                x: point.x * coefficient,
                y: point.y * coefficient,
                z: point.z * coefficient,
                weight: coefficient
            )
        }
        return result
    }

    private func derivativeToBernsteinScale<A: ExactScalarAdmission & ~Copyable>(
        degree: Int,
        controlIndex: Int,
        derivativeOrder: Int,
        span: Double,
        tolerance: ModelingTolerance, using execution: inout A
    ) throws -> Double {
        try execution.consumeWork(1)
        var binomial = 1.0
        if derivativeOrder > 0 {
            for index in 1...derivativeOrder {
                try execution.consumeWork(1)
                binomial *= Double(controlIndex - derivativeOrder + index) / Double(index)
            }
        }
        var fallingFactorial = 1.0
        var spanPower = 1.0
        if derivativeOrder > 0 {
            for index in 0..<derivativeOrder {
                try execution.consumeWork(1)
                fallingFactorial *= Double(degree - index)
                spanPower *= span
            }
        }
        let scale = binomial * spanPower / fallingFactorial
        guard scale.isFinite else {
            throw KernelError(
                phase: .geometry,
                code: .resourceLimitExceeded,
                tolerance: tolerance,
                message: "B-spline Bezier extraction exceeded finite derivative scaling."
            )
        }
        return scale
    }

    private func parameterBreaks<A: ExactScalarAdmission & ~Copyable>(
        knots: [Double],
        domain: ParameterDomain,
        tolerance: ModelingTolerance, using execution: inout A
    ) throws -> [Double] {
        try execution.consumeWork(1)
        guard case let .closed(lower, upper) = domain else {
            throw KernelError(
                phase: .geometry,
                code: .invalidInput,
                tolerance: tolerance,
                message: "B-spline Bezier decomposition requires a bounded parameter domain."
            )
        }
        try execution.retainStorage(bytes: exactScalarPayloadBytes(count: 1, of: Double.self))
        var result = [lower]
        for knot in knots {
            try execution.consumeWork(1)
            guard knot > lower && knot < upper else { continue }
            if result.last != knot {
                try execution.retainStorage(bytes: exactScalarPayloadBytes(count: 1, of: Double.self))
                result.append(knot)
            }
        }
        try execution.retainStorage(bytes: exactScalarPayloadBytes(count: 1, of: Double.self))
        result.append(upper)
        return result
    }

    private struct HomogeneousVector: Sendable {
        let x: Double
        let y: Double
        let z: Double
        let weight: Double

        static let zero = HomogeneousVector(x: 0.0, y: 0.0, z: 0.0, weight: 0.0)

        static func + (lhs: HomogeneousVector, rhs: HomogeneousVector) -> HomogeneousVector {
            HomogeneousVector(
                x: lhs.x + rhs.x,
                y: lhs.y + rhs.y,
                z: lhs.z + rhs.z,
                weight: lhs.weight + rhs.weight
            )
        }

        static func * (lhs: HomogeneousVector, rhs: Double) -> HomogeneousVector {
            HomogeneousVector(
                x: lhs.x * rhs,
                y: lhs.y * rhs,
                z: lhs.z * rhs,
                weight: lhs.weight * rhs
            )
        }

        var isFinite: Bool {
            x.isFinite && y.isFinite && z.isFinite && weight.isFinite
        }
    }
}

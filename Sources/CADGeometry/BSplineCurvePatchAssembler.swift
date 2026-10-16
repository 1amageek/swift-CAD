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

struct BSplineCurvePatchAssembler {
    func trimmedCurve<A: ExactScalarAdmission & ~Copyable>(
        source: BSplineCurve3D,
        lower: Double,
        upper: Double,
        tolerance: ModelingTolerance, using execution: inout A
    ) throws -> BSplineCurve3D {
        try execution.consumeWork(1)
        try source.validate(tolerance: tolerance, using: &execution)
        guard try source.domain.containsSpan(
            from: lower,
            to: upper,
            tolerance: tolerance
        ) else {
            throw KernelError(
                phase: .geometry,
                code: .invalidInput,
                tolerance: tolerance,
                message: "Rational B-spline curve trimming exceeds the source parameter domain."
            )
        }
        let requestedInterval = try ScalarInterval(
            lower: lower,
            upper: upper
        )
        let sourcePatches = try BSplineCurveBezierDecomposer().curvePatches(
            curve: source,
            intersecting: requestedInterval,
            tolerance: tolerance, using: &execution
        )
        try execution.retainStorage(bytes: exactScalarPayloadBytes(count: 2, of: Double.self))
        let parameterResolution = try resolution(
            values: [lower, upper],
            tolerance: tolerance, using: &execution
        )
        let endpointsCount = sourcePatches.count.multipliedReportingOverflow(by: 2)
        guard !endpointsCount.overflow else { throw ExactScalarFailure.countOverflow }
        try execution.retainStorage(bytes: exactScalarPayloadBytes(count: endpointsCount.partialValue, of: Double.self))
        var sourceValues: [Double] = []
        sourceValues.reserveCapacity(endpointsCount.partialValue)
        for patch in sourcePatches {
            try execution.consumeWork(1)
            sourceValues.append(patch.lower)
            sourceValues.append(patch.upper)
        }
        let breaks = try parameterBreaks(
            lower: lower,
            upper: upper,
            sourceValues: sourceValues,
            resolution: parameterResolution, using: &execution
        )
        let spanCount = breaks.count - 1
        guard spanCount > 0 else {
            throw KernelError(
                phase: .geometry,
                code: .invalidInput,
                tolerance: tolerance,
                message: "Rational B-spline curve trimming produced no positive parameter span."
            )
        }
        var patches: [RationalBezierCurvePatch3D] = []
        try execution.retainStorage(bytes: exactScalarPayloadBytes(count: spanCount, of: RationalBezierCurvePatch3D.self))
        patches.reserveCapacity(spanCount)
        for index in 0..<spanCount {
            try execution.consumeWork(1)
            let requested = (breaks[index], breaks[index + 1])
            guard let sourcePatch = try sourcePatches.first(where: { patch in
                try execution.consumeWork(1)
                return patch.lower <= requested.0 + parameterResolution
                    && patch.upper >= requested.1 - parameterResolution
            }) else {
                throw KernelError(
                    phase: .geometry,
                    code: .intersectionFailure,
                    tolerance: tolerance,
                    message: "Rational B-spline curve trimming could not cover a requested parameter span."
                )
            }
            patches.append(try sourcePatch.trimmed(
                from: requested.0,
                to: requested.1,
                tolerance: tolerance, using: &execution
            ))
        }

        let product = spanCount.multipliedReportingOverflow(by: source.degree)
        let count = product.partialValue.addingReportingOverflow(1)
        guard !product.overflow, !count.overflow else { throw ExactScalarFailure.countOverflow }
        let controlCount = count.partialValue
        try execution.retainStorage(bytes: exactScalarPayloadBytes(count: controlCount, of: Point3D?.self))
        try execution.retainStorage(bytes: exactScalarPayloadBytes(count: controlCount, of: Double?.self))
        var points = Array<Point3D?>(repeating: nil, count: controlCount)
        var weights = Array<Double?>(repeating: nil, count: controlCount)
        for span in 0..<spanCount {
            try execution.consumeWork(1)
            let patch = patches[span]
            for localIndex in 0...source.degree {
                try execution.consumeWork(1)
                let targetIndex = span * source.degree + localIndex
                let point = patch.controlPoints[localIndex]
                let weight = patch.weights[localIndex]
                if let existingPoint = points[targetIndex],
                   let existingWeight = weights[targetIndex] {
                    try validateSharedControl(
                        firstPoint: existingPoint,
                        firstWeight: existingWeight,
                        secondPoint: point,
                        secondWeight: weight,
                        tolerance: tolerance, using: &execution
                    )
                } else {
                    points[targetIndex] = point
                    weights[targetIndex] = weight
                }
            }
        }
        try execution.retainStorage(bytes: exactScalarPayloadBytes(count: controlCount, of: Point3D.self))
        let resolvedPoints = try points.map { value -> Point3D in
            try execution.consumeWork(1)
            guard let value else {
                throw KernelError(
                    phase: .geometry,
                    code: .intersectionFailure,
                    tolerance: tolerance,
                    message: "Rational B-spline curve trimming left a control point uninitialized."
                )
            }
            return value
        }
        try execution.retainStorage(bytes: exactScalarPayloadBytes(count: controlCount, of: Double.self))
        let resolvedWeights = try weights.map { value -> Double in
            try execution.consumeWork(1)
            guard let value else {
                throw KernelError(
                    phase: .geometry,
                    code: .intersectionFailure,
                    tolerance: tolerance,
                    message: "Rational B-spline curve trimming left a control weight uninitialized."
                )
            }
            return value
        }
        let result = BSplineCurve3D(
            degree: source.degree,
            knots: try knotVector(breaks: breaks, degree: source.degree, using: &execution),
            controlPoints: resolvedPoints,
            weights: resolvedWeights
        )
        try result.validate(tolerance: tolerance, using: &execution)
        try verify(
            result: result,
            source: source,
            breaks: breaks,
            tolerance: tolerance, using: &execution
        )
        return result
    }

    private func validateSharedControl<A: ExactScalarAdmission & ~Copyable>(
        firstPoint: Point3D,
        firstWeight: Double,
        secondPoint: Point3D,
        secondWeight: Double,
        tolerance: ModelingTolerance, using execution: inout A
    ) throws {
        try execution.consumeWork(1)
        let pointResidual = (firstPoint - secondPoint).length.nextUp
        let weightScale = max(1.0, abs(firstWeight), abs(secondWeight))
        let weightResidual = abs(firstWeight - secondWeight).nextUp
        guard pointResidual <= tolerance.distance,
              weightResidual <= max(tolerance.relative * weightScale, Double.ulpOfOne * weightScale * 512.0) else {
            throw KernelError(
                phase: .geometry,
                code: .intersectionFailure,
                residual: max(pointResidual, weightResidual),
                tolerance: tolerance,
                message: "Adjacent rational Bezier curve spans disagree at a shared homogeneous control point."
            )
        }
    }

    private func verify<A: ExactScalarAdmission & ~Copyable>(
        result: BSplineCurve3D,
        source: BSplineCurve3D,
        breaks: [Double],
        tolerance: ModelingTolerance, using execution: inout A
    ) throws {
        try execution.consumeWork(1)
        var maximumResidual = 0.0
        for parameter in try samples(from: breaks, using: &execution) {
            try execution.consumeWork(1)
            let expected = try source.point(at: parameter, tolerance: tolerance, using: &execution)
            let actual = try result.point(at: parameter, tolerance: tolerance, using: &execution)
            maximumResidual = max(maximumResidual, (actual - expected).length.nextUp)
        }
        guard maximumResidual <= tolerance.distance else {
            throw KernelError(
                phase: .geometry,
                code: .intersectionFailure,
                residual: maximumResidual,
                tolerance: tolerance,
                message: "Rational B-spline trimmed curve failed exact-locus verification."
            )
        }
    }

    private func samples<A: ExactScalarAdmission & ~Copyable>(from breaks: [Double], using execution: inout A) throws -> [Double] {
        try execution.consumeWork(1)
        var result: [Double] = []
        for index in 0..<(breaks.count - 1) {
            try execution.consumeWork(1)
            if result.last != breaks[index] {
                try execution.retainStorage(bytes: exactScalarPayloadBytes(count: 1, of: Double.self))
                result.append(breaks[index])
            }
            try execution.retainStorage(bytes: exactScalarPayloadBytes(count: 1, of: Double.self))
                result.append(breaks[index] + (breaks[index + 1] - breaks[index]) * 0.5)
        }
        if let last = breaks.last {
            try execution.retainStorage(bytes: exactScalarPayloadBytes(count: 1, of: Double.self))
                result.append(last)
        }
        return result
    }

    private func parameterBreaks<A: ExactScalarAdmission & ~Copyable>(
        lower: Double,
        upper: Double,
        sourceValues: [Double],
        resolution: Double, using execution: inout A
    ) throws -> [Double] {
        try execution.consumeWork(1)
        var interior: [Double] = []
        for value in sourceValues {
            try execution.consumeWork(1)
            if value > lower + resolution && value < upper - resolution {
                try execution.retainStorage(bytes: exactScalarPayloadBytes(count: 1, of: Double.self))
                interior.append(value)
            }
        }
        try interior.sort { lhs, rhs in try execution.consumeWork(1); return lhs < rhs }
        try execution.retainStorage(bytes: exactScalarPayloadBytes(count: 1, of: Double.self))
        var result = [lower]
        for value in interior where abs(value - (result.last ?? lower)) > resolution {
            try execution.consumeWork(1)
            try execution.retainStorage(bytes: exactScalarPayloadBytes(count: 1, of: Double.self))
                result.append(value)
        }
        try execution.retainStorage(bytes: exactScalarPayloadBytes(count: 1, of: Double.self))
                result.append(upper)
        return result
    }

    private func knotVector<A: ExactScalarAdmission & ~Copyable>(breaks: [Double], degree: Int, using execution: inout A) throws -> [Double] {
        try execution.consumeWork(1)
        let product = breaks.count.multipliedReportingOverflow(by: degree)
        let total = product.partialValue.addingReportingOverflow(2)
        let endpointCount = degree.addingReportingOverflow(1)
        guard degree >= 0, !product.overflow, !total.overflow, !endpointCount.overflow else { throw ExactScalarFailure.countOverflow }
        try execution.retainStorage(bytes: exactScalarPayloadBytes(count: total.partialValue, of: Double.self))
        var result: [Double] = []
        result.reserveCapacity(total.partialValue)
        for _ in 0..<endpointCount.partialValue { try execution.consumeWork(1); result.append(breaks[0]) }
        for value in breaks.dropFirst().dropLast() {
            try execution.consumeWork(1)
            for _ in 0..<degree { try execution.consumeWork(1); result.append(value) }
        }
        for _ in 0..<endpointCount.partialValue { try execution.consumeWork(1); result.append(breaks[breaks.count - 1]) }
        return result
    }

    private func resolution<A: ExactScalarAdmission & ~Copyable>(
        values: [Double],
        tolerance: ModelingTolerance, using execution: inout A
    ) throws -> Double {
        try execution.consumeWork(1)
        try execution.retainStorage(bytes: exactScalarPayloadBytes(count: values.count, of: Double.self))
        let magnitudes = try values.map { try execution.consumeWork(1); return abs($0) }
        for _ in magnitudes { try execution.consumeWork(1) }
        let scale = max(1.0, magnitudes.max() ?? 1.0)
        return max(
            tolerance.relative * scale,
            Double.ulpOfOne * scale * 512.0
        )
    }
}

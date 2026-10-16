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

struct BSplineSurfacePatchAssembler {
    func trimmedSurface<A: ExactScalarAdmission & ~Copyable>(
        source: BSplineSurface3D,
        uBounds: (lower: Double, upper: Double),
        vBounds: (lower: Double, upper: Double),
        tolerance: ModelingTolerance, using execution: inout A
    ) throws -> BSplineSurface3D {
        try execution.consumeWork(1)
        try source.validate(tolerance: tolerance, using: &execution)
        guard try source.uDomain.containsSpan(
            from: uBounds.lower,
            to: uBounds.upper,
            tolerance: tolerance
        ), try source.vDomain.containsSpan(
            from: vBounds.lower,
            to: vBounds.upper,
            tolerance: tolerance
        ) else {
            throw KernelError(
                phase: .geometry,
                code: .invalidInput,
                tolerance: tolerance,
                message: "Rational B-spline surface trimming exceeds the source parameter domain."
            )
        }
        let sourcePatches = try BSplineSurfaceBezierDecomposer().surfacePatches(
            surface: source,
            tolerance: tolerance, using: &execution
        )
        try execution.retainStorage(bytes: exactScalarPayloadBytes(count: 4, of: Double.self))
        let parameterTolerance = try resolution(
            values: [uBounds.lower, uBounds.upper, vBounds.lower, vBounds.upper],
            tolerance: tolerance, using: &execution
        )
        let endpoints = sourcePatches.count.multipliedReportingOverflow(by: 2)
        guard !endpoints.overflow else { throw ExactScalarFailure.countOverflow }
        try execution.retainStorage(bytes: exactScalarPayloadBytes(count: endpoints.partialValue, of: Double.self))
        try execution.retainStorage(bytes: exactScalarPayloadBytes(count: endpoints.partialValue, of: Double.self))
        var sourceU: [Double] = [], sourceV: [Double] = []
        sourceU.reserveCapacity(endpoints.partialValue); sourceV.reserveCapacity(endpoints.partialValue)
        for patch in sourcePatches {
            try execution.consumeWork(1)
            sourceU.append(patch.uLower); sourceU.append(patch.uUpper)
            sourceV.append(patch.vLower); sourceV.append(patch.vUpper)
        }
        let uBreaks = try breaks(
            lower: uBounds.lower,
            upper: uBounds.upper,
            sourceValues: sourceU,
            resolution: parameterTolerance, using: &execution
        )
        let vBreaks = try breaks(
            lower: vBounds.lower,
            upper: vBounds.upper,
            sourceValues: sourceV,
            resolution: parameterTolerance, using: &execution
        )
        let uSpanCount = uBreaks.count - 1
        let vSpanCount = vBreaks.count - 1
        guard uSpanCount > 0, vSpanCount > 0 else {
            throw KernelError(
                phase: .geometry,
                code: .invalidInput,
                tolerance: tolerance,
                message: "Rational B-spline surface trimming produced no positive parameter span."
            )
        }
        var patches: [RationalBezierSurfacePatch3D] = []
        let patchCount = uSpanCount.multipliedReportingOverflow(by: vSpanCount)
        guard !patchCount.overflow else { throw ExactScalarFailure.countOverflow }
        try execution.retainStorage(bytes: exactScalarPayloadBytes(count: patchCount.partialValue, of: RationalBezierSurfacePatch3D.self))
        patches.reserveCapacity(patchCount.partialValue)
        for vIndex in 0..<vSpanCount {
            try execution.consumeWork(1)
            for uIndex in 0..<uSpanCount {
                try execution.consumeWork(1)
                let requestedU = (uBreaks[uIndex], uBreaks[uIndex + 1])
                let requestedV = (vBreaks[vIndex], vBreaks[vIndex + 1])
                guard let sourcePatch = try sourcePatches.first(where: { patch in
                    try execution.consumeWork(1)
                    return patch.uLower <= requestedU.0 + parameterTolerance
                        && patch.uUpper >= requestedU.1 - parameterTolerance
                        && patch.vLower <= requestedV.0 + parameterTolerance
                        && patch.vUpper >= requestedV.1 - parameterTolerance
                }) else {
                    throw KernelError(
                        phase: .geometry,
                        code: .intersectionFailure,
                        tolerance: tolerance,
                        message: "Rational B-spline trimming could not cover the requested parameter cell."
                    )
                }
                patches.append(try sourcePatch.trimmed(
                    uFrom: requestedU.0,
                    uTo: requestedU.1,
                    vFrom: requestedV.0,
                    vTo: requestedV.1,
                    tolerance: tolerance, using: &execution
                ))
            }
        }

        let uControlCount = try checkedControlCount(uSpanCount, degree: source.uDegree)
        let vControlCount = try checkedControlCount(vSpanCount, degree: source.vDegree)
        try retainMatrix(rows: vControlCount, columns: uControlCount, of: Point3D?.self, using: &execution)
        try retainMatrix(rows: vControlCount, columns: uControlCount, of: Double?.self, using: &execution)
        var points = Array(
            repeating: Array<Point3D?>(repeating: nil, count: uControlCount),
            count: vControlCount
        )
        var weights = Array(
            repeating: Array<Double?>(repeating: nil, count: uControlCount),
            count: vControlCount
        )
        for vSpan in 0..<vSpanCount {
            try execution.consumeWork(1)
            for uSpan in 0..<uSpanCount {
                try execution.consumeWork(1)
                let patch = patches[vSpan * uSpanCount + uSpan]
                for localV in 0...source.vDegree {
                    try execution.consumeWork(1)
                    for localU in 0...source.uDegree {
                        try execution.consumeWork(1)
                        let targetV = vSpan * source.vDegree + localV
                        let targetU = uSpan * source.uDegree + localU
                        let point = patch.controlPoints[localV][localU]
                        let weight = patch.weights[localV][localU]
                        if let existingPoint = points[targetV][targetU],
                           let existingWeight = weights[targetV][targetU] {
                            try validateSharedControl(
                                firstPoint: existingPoint,
                                firstWeight: existingWeight,
                                secondPoint: point,
                                secondWeight: weight,
                                tolerance: tolerance, using: &execution
                            )
                        } else {
                            points[targetV][targetU] = point
                            weights[targetV][targetU] = weight
                        }
                    }
                }
            }
        }
        try retainMatrix(rows: vControlCount, columns: uControlCount, of: Point3D.self, using: &execution)
        let resolvedPoints = try points.map { row in
            try row.map { value in
                try execution.consumeWork(1)
                guard let value else {
                    throw KernelError(
                        phase: .geometry,
                        code: .intersectionFailure,
                        tolerance: tolerance,
                        message: "Rational B-spline trimming left a control point uninitialized."
                    )
                }
                return value
            }
        }
        try retainMatrix(rows: vControlCount, columns: uControlCount, of: Double.self, using: &execution)
        let resolvedWeights = try weights.map { row in
            try row.map { value in
                try execution.consumeWork(1)
                guard let value else {
                    throw KernelError(
                        phase: .geometry,
                        code: .intersectionFailure,
                        tolerance: tolerance,
                        message: "Rational B-spline trimming left a control weight uninitialized."
                    )
                }
                return value
            }
        }
        let result = BSplineSurface3D(
            uDegree: source.uDegree,
            vDegree: source.vDegree,
            uKnots: try knotVector(breaks: uBreaks, degree: source.uDegree, using: &execution),
            vKnots: try knotVector(breaks: vBreaks, degree: source.vDegree, using: &execution),
            controlPoints: resolvedPoints,
            weights: resolvedWeights
        )
        try result.validate(tolerance: tolerance, using: &execution)
        try verify(
            result: result,
            source: source,
            uBreaks: uBreaks,
            vBreaks: vBreaks,
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
                message: "Adjacent rational Bezier patches disagree at a shared homogeneous control point."
            )
        }
    }

    private func verify<A: ExactScalarAdmission & ~Copyable>(
        result: BSplineSurface3D,
        source: BSplineSurface3D,
        uBreaks: [Double],
        vBreaks: [Double],
        tolerance: ModelingTolerance, using execution: inout A
    ) throws {
        try execution.consumeWork(1)
        let uSamples = try samples(from: uBreaks, using: &execution)
        let vSamples = try samples(from: vBreaks, using: &execution)
        var maximumResidual = 0.0
        for v in vSamples {
            try execution.consumeWork(1)
            for u in uSamples {
                try execution.consumeWork(1)
                let expected = try source.point(u: u, v: v, tolerance: tolerance, using: &execution)
                let actual = try result.point(u: u, v: v, tolerance: tolerance, using: &execution)
                maximumResidual = max(maximumResidual, (actual - expected).length.nextUp)
            }
        }
        guard maximumResidual <= tolerance.distance else {
            throw KernelError(
                phase: .geometry,
                code: .intersectionFailure,
                residual: maximumResidual,
                tolerance: tolerance,
                message: "Rational B-spline trimmed surface failed exact-locus verification."
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

    private func breaks<A: ExactScalarAdmission & ~Copyable>(
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

    private func checkedControlCount(_ spans: Int, degree: Int) throws -> Int {
        let product = spans.multipliedReportingOverflow(by: degree)
        let count = product.partialValue.addingReportingOverflow(1)
        guard !product.overflow, !count.overflow else { throw ExactScalarFailure.countOverflow }
        return count.partialValue
    }
    private func retainMatrix<T, A: ExactScalarAdmission & ~Copyable>(rows: Int, columns: Int, of: T.Type, using execution: inout A) throws {
        try execution.retainStorage(bytes: exactScalarPayloadBytes(count: rows, of: [T].self))
        for _ in 0..<rows { try execution.retainStorage(bytes: exactScalarPayloadBytes(count: columns, of: T.self)) }
    }
}

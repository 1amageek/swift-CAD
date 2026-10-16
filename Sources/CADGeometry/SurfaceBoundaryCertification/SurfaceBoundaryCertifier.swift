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

package enum SurfaceBoundaryCertifier {
    package struct Side: Sendable {
        package let lift: SurfaceLiftCurve3D
        package let reversedParameter: Bool
        package let reversedNormal: Bool

        package init(lift: SurfaceLiftCurve3D, reversedParameter: Bool = false, reversedNormal: Bool = false) {
            self.lift = lift
            self.reversedParameter = reversedParameter
            self.reversedNormal = reversedNormal
        }
    }

    package struct Certificate: Sendable {
        package let position: Double
        package let normalChord: Double?
        package let shapeOperator: Double?
        package let inspectedCells: Int
    }

    package static func certify(
        first: Side, second: Side, positionTolerance: Double,
        normalChordTolerance: Double? = nil, shapeOperatorTolerance: Double? = nil,
        maximumCells: Int, maximumDepth: Int, tolerance: ModelingTolerance
    ) throws -> Certificate {
        var execution = OriginalQueryExecution(budget: try OriginalQueryBudget(),
            limits: try .init(maximumValueDepth: 32, maximumCoefficientDepth: 32,
                remainingSourceDepth: 16, maximumSubdivisionDepth: max(0, maximumDepth),
                maximumSpans: 262_144))
        return try certify(first: first, second: second, positionTolerance: positionTolerance,
            normalChordTolerance: normalChordTolerance, shapeOperatorTolerance: shapeOperatorTolerance,
            maximumCells: maximumCells, maximumDepth: maximumDepth, tolerance: tolerance, using: &execution)
    }

    /// Compares final original sources under the complete caller invocation.
    package static func certify(
        first: Side, second: Side, positionTolerance: Double,
        normalChordTolerance: Double? = nil, shapeOperatorTolerance: Double? = nil,
        maximumCells: Int, maximumDepth: Int, tolerance: ModelingTolerance,
        using execution: inout OriginalQueryExecution
    ) throws -> Certificate {
        guard positionTolerance.isFinite, positionTolerance > 0,
            normalChordTolerance.map({ $0.isFinite && $0 > 0 && $0 <= 2 }) ?? true,
            shapeOperatorTolerance.map({ $0.isFinite && $0 > 0 }) ?? true,
            shapeOperatorTolerance == nil || normalChordTolerance != nil,
            maximumCells > 0, maximumDepth >= 0 else {
            throw failure(.invalidInput, "Original boundary certification requires positive finite limits and caller ceilings.")
        }
        let scope = try execution.makeContributionHandle(
            allocationPolicy: execution.effectiveAllocationPolicy,
            executionLimits: .init(maximumValueDepth: Int.max, maximumCoefficientDepth: Int.max,
                maximumSubdivisionDepth: maximumDepth))
        return try execution.withContributionScope(scope) { execution in
            let order = shapeOperatorTolerance != nil ? 2 : normalChordTolerance != nil ? 1 : 0
            let depthLimit = min(maximumDepth, execution.effectiveLimits.maximumSubdivisionDepth)
            let a = try PreparedSide(side: first, tolerance: tolerance, using: &execution)
            let b = try PreparedSide(side: second, tolerance: tolerance, using: &execution)
            let capacity = depthLimit.addingReportingOverflow(1)
            let bytes = capacity.partialValue.multipliedReportingOverflow(by: MemoryLayout<BoundaryCell>.stride)
            guard !capacity.overflow, !bytes.overflow else {
                throw failure(.resourceLimitExceeded, "Original boundary frontier storage overflowed.")
            }
            try execution.retainStorage(bytes: bytes.partialValue)
            var pending: [BoundaryCell] = []
            pending.reserveCapacity(capacity.partialValue)
            pending.append(.init(lower: 0, upper: 1, depth: 0))
            var visited = 0
            var positionMaximum = 0.0, normalMaximum = 0.0, shapeMaximum = 0.0
            while let cell = pending.popLast() {
                try execution.visitGeometricCell(depth: cell.depth)
                guard visited < maximumCells else {
                    throw failure(.resourceLimitExceeded, "Original boundary certification exhausted its cell ceiling.")
                }
                visited += 1
                let interval = try ScalarInterval(lower: cell.lower, upper: cell.upper)
                let middle = cell.lower + (cell.upper - cell.lower) * 0.5
                let center = try ScalarInterval(lower: middle, upper: middle)
                let wholeA = try a.quantities(over: interval, order: order, depth: cell.depth, using: &execution)
                let wholeB = try b.quantities(over: interval, order: order, depth: cell.depth, using: &execution)
                let centerA = try a.quantities(over: center, order: order, depth: cell.depth, using: &execution)
                let centerB = try b.quantities(over: center, order: order, depth: cell.depth, using: &execution)
                if let wholeA, let wholeB, let centerA, let centerB {
                    let radius = OutwardScalarInterval(lower: (cell.lower - middle).nextDown,
                        upper: (cell.upper - middle).nextUp)
                    var admitted = true
                    var cellPosition = 0.0, cellNormal = 0.0, cellShape = 0.0
                    for group in 0...order {
                        try execution.consumeWork(1)
                        let lowerIndex = group == 0 ? 0 : group == 1 ? 3 : 6
                        let upperIndex = group == 0 ? 3 : group == 1 ? 6 : 15
                        let limit = group == 0 ? positionTolerance
                            : group == 1 ? normalChordTolerance! : shapeOperatorTolerance!
                        var upperSquared = OutwardScalarInterval.exact(0)
                        var lowerSquared = OutwardScalarInterval.exact(0)
                        var witnessSquared = OutwardScalarInterval.exact(0)
                        for index in lowerIndex..<upperIndex {
                            try execution.consumeWork(1)
                            var difference = wholeA.values[index].value - wholeB.values[index].value
                            if wholeA.continuousOrder >= group && wholeB.continuousOrder >= group {
                                let tightened = centerA.values[index].value - centerB.values[index].value
                                    + radius * (wholeA.values[index].derivativeU - wholeB.values[index].derivativeU)
                                difference = OutwardScalarInterval(lower: max(difference.lower, tightened.lower),
                                    upper: min(difference.upper, tightened.upper))
                            }
                            guard difference.isFinite, difference.lower <= difference.upper else {
                                throw failure(.resourceLimitExceeded, "Original boundary difference has no finite coherent enclosure.")
                            }
                            let high = OutwardScalarInterval.exact(difference.absoluteUpperBound)
                            let low = OutwardScalarInterval.exact(difference.absoluteLowerBound)
                            let witness = OutwardScalarInterval.exact(
                                (centerA.values[index].value - centerB.values[index].value).absoluteLowerBound)
                            upperSquared = upperSquared + high * high
                            lowerSquared = lowerSquared + low * low
                            witnessSquared = witnessSquared + witness * witness
                        }
                        let magnitude = sqrt(max(0, upperSquared.upper)).nextUp
                        let upper = group == 1 ? min(2, magnitude) : magnitude
                        guard upper.isFinite else {
                            throw failure(.resourceLimitExceeded, "Original boundary magnitude overflowed.")
                        }
                        let lower = max(0, sqrt(max(0, lowerSquared.lower)).nextDown)
                        let witness = max(0, sqrt(max(0, witnessSquared.lower)).nextDown)
                        guard max(lower, witness) <= limit else {
                            throw failure(.classificationFailure, "An original boundary interval violates its continuity request.")
                        }
                        if upper > limit { admitted = false }
                        if group == 0 { cellPosition = upper }
                        else if group == 1 { cellNormal = upper }
                        else { cellShape = upper }
                    }
                    if admitted {
                        positionMaximum = max(positionMaximum, cellPosition)
                        normalMaximum = max(normalMaximum, cellNormal)
                        shapeMaximum = max(shapeMaximum, cellShape)
                        continue
                    }
                }
                guard cell.depth < depthLimit, middle > cell.lower, middle < cell.upper else {
                    throw failure(.resourceLimitExceeded, "Original boundary regularity or continuity remains unresolved at the caller depth.")
                }
                pending.append(.init(lower: middle, upper: cell.upper, depth: cell.depth + 1))
                pending.append(.init(lower: cell.lower, upper: middle, depth: cell.depth + 1))
            }
            try execution.checkpoint()
            return Certificate(position: positionMaximum, normalChord: order >= 1 ? normalMaximum : nil,
                shapeOperator: order >= 2 ? shapeMaximum : nil, inspectedCells: visited)
        }
    }

    private struct BoundaryCell { let lower: Double; let upper: Double; let depth: Int }

    private struct PreparedSide {
        let side: Side
        let surface: PreparedSurfaceDifferentialEncloser
        let chart: SurfaceAreaParameterChartEncloser
        let tolerance: ModelingTolerance
        let sourceDepth: Int
        struct Quantities { let values: [SurfaceIntervalJet]; let continuousOrder: Int }

        init(side: Side, tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution) throws {
            self.side = side; self.tolerance = tolerance
            sourceDepth = min(16, execution.effectiveLimits.remainingSourceDepth)
            surface = try PreparedSurfaceDifferentialEncloser(surface: side.lift.surface, tolerance: tolerance,
                remainingSourceDepth: sourceDepth,
                maximumSubdivisionDepth: execution.effectiveLimits.maximumSubdivisionDepth,
                maximumAlgebraicDepth: 32, using: &execution)
            chart = try SurfaceAreaParameterChartEncloser(curve: side.lift.parameterCurve, on: side.lift.surface,
                tolerance: tolerance, maximumSubdivisionDepth: execution.effectiveLimits.maximumSubdivisionDepth,
                remainingSourceDepth: sourceDepth, maximumAlgebraicDepth: 32, using: &execution)
        }

        func quantities(over interval: ScalarInterval, order: Int, depth: Int,
            using execution: inout OriginalQueryExecution) throws -> Quantities? {
            return try execution.withGeometricDepthOffset(depth) { execution -> Quantities? in
                try execution.visitGeometricCell(depth: 0)
                let remainingDepth = execution.effectiveLimits.maximumSubdivisionDepth - depth
                guard remainingDepth >= 0 else {
                    throw failure(.resourceLimitExceeded, "Original boundary exhausted its causal geometric depth.")
                }
                let mapped: ScalarInterval
                if side.reversedParameter {
                    let image = OutwardScalarInterval.exact(1)
                        - OutwardScalarInterval(lower: interval.lower, upper: interval.upper)
                    mapped = try ScalarInterval(lower: max(0, image.lower), upper: min(1, image.upper))
                } else { mapped = interval }
                let proof = try chart.intervalProof(over: mapped, tolerance: tolerance, using: &execution)
                let uv = proof.values
                let box = try SurfaceParameterBox(
                    u: ScalarInterval(lower: uv.u.lower, upper: uv.u.upper),
                    v: ScalarInterval(lower: uv.v.lower, upper: uv.v.upper))
                let p = try surface.intervalJet(overClosedBox: box, tolerance: tolerance,
                    maximumSpanCount: execution.effectiveLimits.maximumSpans,
                    maximumSubdivisionDepth: remainingDepth, remainingSourceDepth: sourceDepth, using: &execution)
                var continuousOrder = -1
                if case .smooth = proof {
                    if try surface.admittingContinuousFirstOrder(over: box, tolerance: tolerance,
                        remainingSourceDepth: sourceDepth, maximumSpanCount: execution.effectiveLimits.maximumSpans,
                        maximumSubdivisionDepth: remainingDepth, using: &execution) != nil {
                        continuousOrder = 0
                        if order > 0 {
                            for requested in stride(from: order, through: 1, by: -1) {
                                try execution.consumeWork(1)
                                if try surface.admittingContinuousPartials(over: box, throughOrder: requested,
                                    tolerance: tolerance, remainingSourceDepth: sourceDepth,
                                    maximumSpanCount: execution.effectiveLimits.maximumSpans,
                                    maximumSubdivisionDepth: remainingDepth, using: &execution) != nil {
                                    continuousOrder = requested
                                    break
                                }
                            }
                        }
                    }
                }
                let count = order == 0 ? 3 : order == 1 ? 6 : 15
                try execution.retainStorage(bytes: exactScalarPayloadBytes(count: count, of: SurfaceIntervalJet.self))
                var values: [SurfaceIntervalJet] = []
                values.reserveCapacity(count)
                values.append(p.x); values.append(p.y); values.append(p.z)
                if order > 0 {
                    let rawU = p.differentiatedUThroughSecondOrder(), rawV = p.differentiatedVThroughSecondOrder()
                    let uScale = max(rawU.x.value.absoluteUpperBound,
                        max(rawU.y.value.absoluteUpperBound, rawU.z.value.absoluteUpperBound))
                    let vScale = max(rawV.x.value.absoluteUpperBound,
                        max(rawV.y.value.absoluteUpperBound, rawV.z.value.absoluteUpperBound))
                    try execution.consumeWork(2)
                    guard uScale.isFinite, vScale.isFinite, uScale > 0, vScale > 0,
                        let inverseU = SurfaceIntervalJet.constant(uScale).reciprocal(),
                        let inverseV = SurfaceIntervalJet.constant(vScale).reciprocal() else { return nil }
                    let u = rawU * inverseU, v = rawV * inverseV
                    let cross = u.cross(v)
                    guard let unit = cross.normalized() else { return nil }
                    let normal = side.reversedNormal ? -unit : unit
                    values.append(normal.x); values.append(normal.y); values.append(normal.z)
                    if order > 1 {
                        guard let inverse = cross.dot(cross).reciprocal() else { return nil }
                        let e = u.dot(u), f = u.dot(v), g = v.dot(v)
                        let dualU = (u * g + -(v * f)) * inverse
                        let dualV = (v * e + -(u * f)) * inverse
                        let l = normal.dot(u.differentiatedUThroughSecondOrder()) * inverseU
                        let m = normal.dot(u.differentiatedVThroughSecondOrder()) * inverseV
                        let n = normal.dot(v.differentiatedVThroughSecondOrder()) * inverseV
                        func component(_ value: SurfaceIntervalVectorJet, _ index: Int) -> SurfaceIntervalJet {
                            index == 0 ? value.x : index == 1 ? value.y : value.z
                        }
                        for row in 0..<3 { for column in 0..<3 {
                            try execution.consumeWork(1)
                            let ur = component(dualU, row), uc = component(dualU, column)
                            let vr = component(dualV, row), vc = component(dualV, column)
                            values.append(l * ur * uc + m * (ur * vc + vr * uc) + n * vr * vc)
                        } }
                    }
                }
                let sign = OutwardScalarInterval.exact(side.reversedParameter ? -1 : 1)
                let zero = OutwardScalarInterval.exact(0)
                for index in values.indices {
                    try execution.consumeWork(1)
                    let value = values[index]
                    values[index] = SurfaceIntervalJet(value: value.value,
                        derivativeU: (value.derivativeU * uv.tangentU + value.derivativeV * uv.tangentV) * sign,
                        derivativeV: zero, secondDerivativeUU: zero, secondDerivativeUV: zero, secondDerivativeVV: zero,
                        thirdDerivativeUUU: zero, thirdDerivativeUUV: zero, thirdDerivativeUVV: zero, thirdDerivativeVVV: zero)
                }
                return Quantities(values: values, continuousOrder: continuousOrder)
            }
        }
    }

    private static func failure(_ code: KernelErrorCode, _ message: String) -> KernelError {
        KernelError(phase: .geometry, code: code, tolerance: nil, message: message)
    }
}

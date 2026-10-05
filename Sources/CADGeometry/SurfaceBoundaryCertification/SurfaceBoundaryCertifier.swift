import CADCore
import Foundation

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
        let limits = [positionTolerance] + (normalChordTolerance.map { [$0] } ?? [])
            + (shapeOperatorTolerance.map { [$0] } ?? [])
        guard limits.allSatisfy({ $0.isFinite && $0 > 0 }),
              shapeOperatorTolerance == nil || normalChordTolerance != nil,
              normalChordTolerance == nil || normalChordTolerance! <= 2,
              maximumCells > 0, maximumDepth >= 0 else {
            throw failure(.invalidInput, "Boundary certification requires finite positive limits and subdivision budgets.")
        }
        let order = shapeOperatorTolerance != nil ? 2 : normalChordTolerance != nil ? 1 : 0
        let a = try Prepared(side: first, order: order, tolerance: tolerance)
        let b = try Prepared(side: second, order: order, tolerance: tolerance)
        var pending = [(lower: 0.0, upper: 1.0, depth: 0)]
        var visited = 0
        var maxima = Array(repeating: 0.0, count: order + 1)
        while let cell = pending.popLast() {
            try Task.checkCancellation()
            guard visited < maximumCells else {
                throw failure(.resourceLimitExceeded, "Boundary certification exhausted its cell budget.")
            }
            visited += 1
            let interval = try ScalarInterval(lower: cell.lower, upper: cell.upper)
            let mid = cell.lower + (cell.upper - cell.lower) * 0.5
            let center = try ScalarInterval(lower: mid.nextDown, upper: mid.nextUp)
            let firstBounds = try a.quantities(over: interval, order: order, tolerance: tolerance)
            let secondBounds = try b.quantities(over: interval, order: order, tolerance: tolerance)
            let firstCenter = try a.quantities(over: center, order: order, tolerance: tolerance)
            let secondCenter = try b.quantities(over: center, order: order, tolerance: tolerance)
            if let firstBounds, let secondBounds, let firstCenter, let secondCenter {
                let radius = OutwardScalarInterval(lower: (cell.lower - mid).nextDown,
                    upper: (cell.upper - mid).nextUp)
                var differences: [OutwardScalarInterval] = []
                for index in firstBounds.indices {
                    differences.append((firstCenter[index].value - secondCenter[index].value)
                        + radius * (firstBounds[index].derivativeU - secondBounds[index].derivativeU))
                }
                let ranges = [0..<3, 3..<6, 6..<15]
                var upperBounds: [Double] = []
                for group in 0...order {
                    var upperSquared = OutwardScalarInterval.exact(0)
                    var lowerSquared = OutwardScalarInterval.exact(0)
                    var centerLowerSquared = OutwardScalarInterval.exact(0)
                    for index in ranges[group] {
                        let bound = differences[index]
                        guard bound.isFinite else {
                            throw failure(.resourceLimitExceeded, "Boundary error enclosure exceeded finite arithmetic range.")
                        }
                        let high = OutwardScalarInterval.exact(bound.absoluteUpperBound)
                        let low = OutwardScalarInterval.exact(bound.absoluteLowerBound)
                        upperSquared = upperSquared + high * high
                        lowerSquared = lowerSquared + low * low
                        let centerDifference = firstCenter[index].value - secondCenter[index].value
                        let witness = OutwardScalarInterval.exact(centerDifference.absoluteLowerBound)
                        centerLowerSquared = centerLowerSquared + witness * witness
                    }
                    let magnitude = sqrt(max(0, upperSquared.upper)).nextUp
                    let upper = group == 1 ? min(2, magnitude) : magnitude
                    let lower = max(0, sqrt(max(0, lowerSquared.lower)).nextDown)
                    guard upper.isFinite else {
                        throw failure(.resourceLimitExceeded, "Boundary error magnitude exceeded finite arithmetic range.")
                    }
                    let centerLower = max(0, sqrt(max(0, centerLowerSquared.lower)).nextDown)
                    guard max(lower, centerLower) <= limits[group] else {
                        throw failure(.classificationFailure, "A boundary interval violates the requested continuity bound.")
                    }
                    upperBounds.append(upper)
                }
                if zip(upperBounds, limits).allSatisfy({ $0 <= $1 }) {
                    for index in maxima.indices { maxima[index] = max(maxima[index], upperBounds[index]) }
                    continue
                }
            }
            guard cell.depth < maximumDepth, mid > cell.lower, mid < cell.upper else {
                throw failure(.resourceLimitExceeded, "Boundary continuity or regularity remains uncertified at the subdivision limit.")
            }
            pending.append((mid, cell.upper, cell.depth + 1))
            pending.append((cell.lower, mid, cell.depth + 1))
        }
        return Certificate(position: maxima[0], normalChord: order >= 1 ? maxima[1] : nil,
            shapeOperator: order >= 2 ? maxima[2] : nil, inspectedCells: visited)
    }

    /// Compares final original sources under the complete caller invocation.
    package static func certify(
        first: Side, second: Side, positionTolerance: Double,
        normalChordTolerance: Double? = nil, shapeOperatorTolerance: Double? = nil,
        maximumCells: Int, maximumDepth: Int, tolerance: ModelingTolerance,
        admission: GeometryConversionAdmission
    ) throws -> Certificate {
        guard positionTolerance.isFinite, positionTolerance > 0,
            normalChordTolerance.map({ $0.isFinite && $0 > 0 && $0 <= 2 }) ?? true,
            shapeOperatorTolerance.map({ $0.isFinite && $0 > 0 }) ?? true,
            shapeOperatorTolerance == nil || normalChordTolerance != nil,
            maximumCells > 0, maximumDepth >= 0 else {
            throw failure(.invalidInput, "Original boundary certification requires positive finite limits and caller ceilings.")
        }
        let order = shapeOperatorTolerance != nil ? 2 : normalChordTolerance != nil ? 1 : 0
        let depthLimit = min(maximumDepth, admission.maximumSubdivisionDepth)
        let a = try AdmittedSide(side: first, tolerance: tolerance, admission: admission)
        let b = try AdmittedSide(side: second, tolerance: tolerance, admission: admission)
        let capacity = depthLimit.addingReportingOverflow(1)
        let bytes = capacity.partialValue.multipliedReportingOverflow(by: MemoryLayout<BoundaryCell>.stride)
        guard !capacity.overflow, !bytes.overflow else {
            throw failure(.resourceLimitExceeded, "Original boundary frontier storage overflowed.")
        }
        try admission.chargeStorage(bytes: bytes.partialValue)
        var pending: [BoundaryCell] = []
        pending.reserveCapacity(capacity.partialValue)
        pending.append(.init(lower: 0, upper: 1, depth: 0))
        var visited = 0
        var positionMaximum = 0.0, normalMaximum = 0.0, shapeMaximum = 0.0
        while let cell = pending.popLast() {
            try admission.visit(depth: cell.depth)
            guard visited < maximumCells else {
                throw failure(.resourceLimitExceeded, "Original boundary certification exhausted its cell ceiling.")
            }
            visited += 1
            let interval = try ScalarInterval(lower: cell.lower, upper: cell.upper)
            let middle = cell.lower + (cell.upper - cell.lower) * 0.5
            let center = try ScalarInterval(lower: middle, upper: middle)
            let wholeA = try a.quantities(over: interval, order: order, depth: cell.depth)
            let wholeB = try b.quantities(over: interval, order: order, depth: cell.depth)
            let centerA = try a.quantities(over: center, order: order, depth: cell.depth)
            let centerB = try b.quantities(over: center, order: order, depth: cell.depth)
            if let wholeA, let wholeB, let centerA, let centerB {
                let radius = OutwardScalarInterval(lower: (cell.lower - middle).nextDown,
                    upper: (cell.upper - middle).nextUp)
                var admitted = true
                var cellPosition = 0.0, cellNormal = 0.0, cellShape = 0.0
                for group in 0...order {
                    let lowerIndex = group == 0 ? 0 : group == 1 ? 3 : 6
                    let upperIndex = group == 0 ? 3 : group == 1 ? 6 : 15
                    let limit = group == 0 ? positionTolerance
                        : group == 1 ? normalChordTolerance! : shapeOperatorTolerance!
                    var upperSquared = OutwardScalarInterval.exact(0)
                    var lowerSquared = OutwardScalarInterval.exact(0)
                    var witnessSquared = OutwardScalarInterval.exact(0)
                    for index in lowerIndex..<upperIndex {
                        try admission.chargeWork()
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
        return Certificate(position: positionMaximum, normalChord: order >= 1 ? normalMaximum : nil,
            shapeOperator: order >= 2 ? shapeMaximum : nil, inspectedCells: visited)
    }

    private struct BoundaryCell { let lower: Double; let upper: Double; let depth: Int }

    private struct ExactAdmission: RationalAlgebraAdmitting {
        let admission: GeometryConversionAdmission
        mutating func visitExactCell(depth: Int) throws {
            guard depth >= 0, depth <= (admission.maximumAlgebraicDepth ?? 32) else {
                throw failure(.resourceLimitExceeded, "Original boundary algebra exhausted its independent depth.")
            }
            try admission.chargeWork()
        }
        mutating func consumeExactWork(_ count: Int) throws { try admission.chargeWork(count) }
        mutating func retainExactStorage(_ count: Int) throws {
            let bytes = count.multipliedReportingOverflow(by: MemoryLayout<UInt32>.stride)
            guard count >= 0, !bytes.overflow else {
                throw failure(.resourceLimitExceeded, "Original boundary exact storage overflowed.")
            }
            try admission.chargeStorage(bytes: bytes.partialValue)
        }
    }

    private struct AdmittedSide {
        let side: Side
        let surface: PreparedSurfaceDifferentialEncloser
        let chart: SurfaceAreaParameterChartEncloser
        let tolerance: ModelingTolerance
        let admission: GeometryConversionAdmission
        let sourceDepth: Int
        struct Quantities { let values: [SurfaceIntervalJet]; let continuousOrder: Int }

        init(side: Side, tolerance: ModelingTolerance, admission: GeometryConversionAdmission) throws {
            self.side = side; self.tolerance = tolerance; self.admission = admission
            sourceDepth = min(16, admission.remainingSourceDepth)
            surface = try PreparedSurfaceDifferentialEncloser(surface: side.lift.surface, tolerance: tolerance,
                remainingSourceDepth: sourceDepth, maximumSubdivisionDepth: admission.maximumSubdivisionDepth,
                consumeWork: { try admission.chargeWork() }, consumeStorage: { try admission.chargeStorage(bytes: $0) },
                maximumAlgebraicDepth: admission.maximumAlgebraicDepth)
            chart = try SurfaceAreaParameterChartEncloser(curve: side.lift.parameterCurve, on: side.lift.surface,
                tolerance: tolerance, maximumSubdivisionDepth: admission.maximumSubdivisionDepth,
                remainingSourceDepth: sourceDepth, maximumAlgebraicDepth: admission.maximumAlgebraicDepth ?? 32,
                consumeWork: { _ in try admission.chargeWork() },
                consumeStorage: { try admission.chargeStorage(bytes: $0) })
        }

        func quantities(over interval: ScalarInterval, order: Int, depth: Int) throws -> Quantities? {
            try admission.visit(depth: depth)
            let mapped: ScalarInterval
            if side.reversedParameter {
                let image = OutwardScalarInterval.exact(1)
                    - OutwardScalarInterval(lower: interval.lower, upper: interval.upper)
                mapped = try ScalarInterval(lower: max(0, image.lower), upper: min(1, image.upper))
            } else { mapped = interval }
            let proof = try chart.intervalProof(over: mapped, tolerance: tolerance,
                consumeWork: { try admission.chargeWork() }, consumeStorage: { try admission.chargeStorage(bytes: $0) })
            let uv = proof.values
            let box = try SurfaceParameterBox(
                u: ScalarInterval(lower: uv.u.lower, upper: uv.u.upper),
                v: ScalarInterval(lower: uv.v.lower, upper: uv.v.upper))
            let p = try surface.intervalJet(overClosedBox: box, tolerance: tolerance,
                maximumSpanCount: admission.maximumSpanCount,
                maximumSubdivisionDepth: admission.maximumSubdivisionDepth, remainingSourceDepth: sourceDepth,
                consumeWork: { try admission.chargeWork() }, consumeStorage: { try admission.chargeStorage(bytes: $0) })
            var continuousOrder = -1
            if case .smooth = proof {
                var usage = ExactAdmission(admission: admission)
                if try surface.admittingContinuousFirstOrder(over: box, tolerance: tolerance,
                    remainingSourceDepth: sourceDepth, maximumSpanCount: admission.maximumSpanCount,
                    maximumSubdivisionDepth: admission.maximumSubdivisionDepth, usage: &usage) != nil {
                    continuousOrder = 0
                    if order > 0 {
                        for requested in stride(from: order, through: 1, by: -1) {
                            if try surface.admittingContinuousPartials(over: box, throughOrder: requested,
                                tolerance: tolerance, remainingSourceDepth: sourceDepth,
                                maximumSpanCount: admission.maximumSpanCount,
                                maximumSubdivisionDepth: admission.maximumSubdivisionDepth, usage: &usage) != nil {
                                continuousOrder = requested
                                break
                            }
                        }
                    }
                }
            }
            let count = order == 0 ? 3 : order == 1 ? 6 : 15
            try admission.chargeStorage(bytes: count * MemoryLayout<SurfaceIntervalJet>.stride)
            var values: [SurfaceIntervalJet] = []
            values.reserveCapacity(count)
            values.append(p.x); values.append(p.y); values.append(p.z)
            if order > 0 {
                let rawU = p.differentiatedUThroughSecondOrder(), rawV = p.differentiatedVThroughSecondOrder()
                let uScale = max(rawU.x.value.absoluteUpperBound,
                    max(rawU.y.value.absoluteUpperBound, rawU.z.value.absoluteUpperBound))
                let vScale = max(rawV.x.value.absoluteUpperBound,
                    max(rawV.y.value.absoluteUpperBound, rawV.z.value.absoluteUpperBound))
                try admission.chargeWork(2)
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
                        try admission.chargeWork()
                        let ur = component(dualU, row), uc = component(dualU, column)
                        let vr = component(dualV, row), vc = component(dualV, column)
                        values.append(l * ur * uc + m * (ur * vc + vr * uc) + n * vr * vc)
                    } }
                }
            }
            let sign = OutwardScalarInterval.exact(side.reversedParameter ? -1 : 1)
            let zero = OutwardScalarInterval.exact(0)
            for index in values.indices {
                try admission.chargeWork()
                let value = values[index]
                values[index] = SurfaceIntervalJet(value: value.value,
                    derivativeU: (value.derivativeU * uv.tangentU + value.derivativeV * uv.tangentV) * sign,
                    derivativeV: zero, secondDerivativeUU: zero, secondDerivativeUV: zero, secondDerivativeVV: zero,
                    thirdDerivativeUUU: zero, thirdDerivativeUUV: zero, thirdDerivativeUVV: zero, thirdDerivativeVVV: zero)
            }
            return Quantities(values: values, continuousOrder: continuousOrder)
        }
    }

    private struct Prepared {
        let side: Side
        let surface: PreparedSurfaceDifferentialEncloser

        init(side: Side, order: Int, tolerance: ModelingTolerance) throws {
            try side.lift.validate(tolerance: tolerance)
            if case let .bSpline(value) = side.lift.surface {
                for (knots, degree, domain) in [(value.uKnots, value.uDegree, value.uDomain),
                                               (value.vKnots, value.vDegree, value.vDomain)] {
                    guard case let .closed(lower, upper) = domain else {
                        throw failure(.invalidInput, "Boundary certification requires a valid spline domain.")
                    }
                    var index = 0
                    while index < knots.count {
                        var end = index + 1
                        while end < knots.count, knots[end] == knots[index] { end += 1 }
                        if knots[index] > lower, knots[index] < upper, end - index > degree - order {
                            throw failure(.unsupportedCapability, "Boundary certification requires the requested spline smoothness at interior knots.")
                        }
                        index = end
                    }
                }
            }
            self.side = side
            surface = try PreparedSurfaceDifferentialEncloser(surface: side.lift.surface, tolerance: tolerance)
        }

        /// Only value and first boundary derivative of the returned jets are consumed.
        func quantities(over interval: ScalarInterval, order: Int,
                        tolerance: ModelingTolerance) throws -> [SurfaceIntervalJet]? {
            let mapped: ScalarInterval
            if side.reversedParameter {
                let value = OutwardScalarInterval.exact(1)
                    - OutwardScalarInterval(lower: interval.lower, upper: interval.upper)
                mapped = try ScalarInterval(lower: max(0, value.lower), upper: min(1, value.upper))
            } else { mapped = interval }
            guard let uv = try SurfaceParameterIntervalJet.enclose(
                side.lift.parameterCurve, over: mapped, tolerance: tolerance) else {
                throw failure(.unsupportedCapability, "The boundary parameter curve has no certified interval jet.")
            }
            let bounder = SurfaceLiftDifferentialBounder()
            let box = try SurfaceParameterBox(
                u: bounder.nondegenerateRange(ScalarInterval(lower: uv.u.value.lower, upper: uv.u.value.upper),
                    domain: side.lift.surface.uDomain, tolerance: tolerance),
                v: bounder.nondegenerateRange(ScalarInterval(lower: uv.v.value.lower, upper: uv.v.value.upper),
                    domain: side.lift.surface.vDomain, tolerance: tolerance))
            let p = try surface.intervalJet(over: box, tolerance: tolerance)
            var values = [p.x, p.y, p.z]
            if order > 0 {
                let u = p.differentiatedUThroughSecondOrder()
                let v = p.differentiatedVThroughSecondOrder()
                let cross = u.cross(v)
                guard let unit = cross.normalized() else { return nil }
                let normal = side.reversedNormal ? -unit : unit
                values += [normal.x, normal.y, normal.z]
                if order > 1 {
                    guard let inverseDeterminant = cross.dot(cross).reciprocal() else { return nil }
                    let e = u.dot(u), f = u.dot(v), g = v.dot(v)
                    let dualU = (u * g + -(v * f)) * inverseDeterminant
                    let dualV = (v * e + -(u * f)) * inverseDeterminant
                    let l = normal.dot(u.differentiatedUThroughSecondOrder())
                    let m = normal.dot(u.differentiatedVThroughSecondOrder())
                    let n = normal.dot(v.differentiatedVThroughSecondOrder())
                    let first = [dualU.x, dualU.y, dualU.z]
                    let second = [dualV.x, dualV.y, dualV.z]
                    for row in 0..<3 {
                        for column in 0..<3 {
                            values.append(l * first[row] * first[column]
                                + m * (first[row] * second[column] + second[row] * first[column])
                                + n * second[row] * second[column])
                        }
                    }
                }
            }
            let direction = OutwardScalarInterval.exact(side.reversedParameter ? -1 : 1)
            let zero = OutwardScalarInterval.exact(0)
            return values.map { value in
                SurfaceIntervalJet(value: value.value,
                    derivativeU: (value.derivativeU * uv.u.derivativeU + value.derivativeV * uv.v.derivativeU) * direction,
                    derivativeV: zero, secondDerivativeUU: zero, secondDerivativeUV: zero, secondDerivativeVV: zero,
                    thirdDerivativeUUU: zero, thirdDerivativeUUV: zero, thirdDerivativeUVV: zero, thirdDerivativeVVV: zero)
            }
        }
    }

    private static func failure(_ code: KernelErrorCode, _ message: String) -> KernelError {
        KernelError(phase: .geometry, code: code, tolerance: nil, message: message)
    }
}

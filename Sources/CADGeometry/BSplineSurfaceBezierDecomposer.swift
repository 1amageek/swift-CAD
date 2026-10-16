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

struct BSplineSurfaceBezierDecomposer {
    struct OriginalHomogeneousPatch {
        let controls: [[IntervalHomogeneousSurfaceControl]]
        let origin: Point3D
        let commonWeight: Double?
        let uSpanIndex: Int
        let vSpanIndex: Int
        let uBounds: ScalarInterval
        let vBounds: ScalarInterval
    }

    /// Proof preparation retains intervals of original homogeneous coefficients.
    /// The separate Cartesian Double geometry producer is not used here.
    func originalHomogeneousPatches<A: ExactScalarAdmission & ~Copyable>(surface: BSplineSurface3D,
                                    tolerance: ModelingTolerance, using execution: inout A) throws -> [OriginalHomogeneousPatch] {
        try surface.validate(tolerance: tolerance, using: &execution)
        try execution.checkpoint()
        // Cyclic surfaces already retain their original repeated tails. The stored
        // count and native basis are identical to canonical evaluation; no trimmed
        // Cartesian net or newly materialized cycle supplies coefficient authority.
        var us: [Int] = [], vs: [Int] = []
        try OriginalCoefficientAllocation.reserve(count: surface.uControlPointCount - surface.uDegree, of: Int.self, using: &execution)
        try OriginalCoefficientAllocation.reserve(count: surface.vControlPointCount - surface.vDegree, of: Int.self, using: &execution)
        us.reserveCapacity(surface.uControlPointCount - surface.uDegree)
        vs.reserveCapacity(surface.vControlPointCount - surface.vDegree)
        for index in surface.uDegree..<surface.uControlPointCount {
            try execution.consumeWork(1)
            if surface.uKnots[index] < surface.uKnots[index + 1] {
                us.append(index)
            }
        }
        for index in surface.vDegree..<surface.vControlPointCount {
            try execution.consumeWork(1)
            if surface.vKnots[index] < surface.vKnots[index + 1] {
                vs.append(index)
            }
        }
        let count = us.count.multipliedReportingOverflow(by: vs.count)
        let net = (surface.uDegree + 1).multipliedReportingOverflow(by: surface.vDegree + 1)
        let storage = count.partialValue.multipliedReportingOverflow(by: net.partialValue)
        guard !count.overflow, !net.overflow, !storage.overflow else {
            throw KernelError(phase: .geometry, code: .resourceLimitExceeded, tolerance: tolerance,
                message: "Original homogeneous coefficient storage count overflowed.")
        }
        let origin = surface.controlPoints[0][0], weight = surface.weights[0][0]
        var identicalWeight = true
        for row in surface.weights { for value in row {
            try execution.consumeWork(1)
            if value != weight { identicalWeight = false }
        } }
        let commonWeight = identicalWeight ? weight : nil
        var result: [OriginalHomogeneousPatch] = []
        try OriginalCoefficientAllocation.reserve(count: count.partialValue, of: OriginalHomogeneousPatch.self, using: &execution)
        result.reserveCapacity(count.partialValue)
        for v in vs {
            for u in us {
                try execution.checkpoint(); try execution.consumeWork(1)
                let ub = try ScalarInterval(lower: surface.uKnots[u], upper: surface.uKnots[u + 1])
                let vb = try ScalarInterval(lower: surface.vKnots[v], upper: surface.vKnots[v + 1])
                let uBasis = try BSplineBasis.nonzeroIntervalDerivativeValues(parameter: ub.lower, degree: surface.uDegree,
                    throughDerivativeOrder: surface.uDegree, knots: surface.uKnots, count: surface.uControlPointCount,
                    owningSpan: u, tolerance: tolerance, using: &execution)
                let vBasis = try BSplineBasis.nonzeroIntervalDerivativeValues(parameter: vb.lower, degree: surface.vDegree,
                    throughDerivativeOrder: surface.vDegree, knots: surface.vKnots, count: surface.vControlPointCount,
                    owningSpan: v, tolerance: tolerance, using: &execution)
                typealias Interval = OutwardScalarInterval
                func add(_ a: IntervalHomogeneousSurfaceControl, _ b: IntervalHomogeneousSurfaceControl) -> IntervalHomogeneousSurfaceControl {
                    IntervalHomogeneousSurfaceControl(x: a.x + b.x, y: a.y + b.y, z: a.z + b.z, weight: a.weight + b.weight)
                }
                try OriginalCoefficientAllocation.reserve(count: surface.vDegree + 1, of: [IntervalHomogeneousSurfaceControl].self, using: &execution)
                for _ in 0...surface.vDegree {
                    try OriginalCoefficientAllocation.reserve(count: surface.uDegree + 1, of: IntervalHomogeneousSurfaceControl.self, using: &execution)
                }
                var derivatives = Array(repeating: Array(repeating: IntervalHomogeneousSurfaceControl.zero,
                    count: surface.uDegree + 1), count: surface.vDegree + 1)
                for vOrder in 0...surface.vDegree {
                    try execution.checkpoint(); try execution.consumeWork(1)
                    for uOrder in 0...surface.uDegree {
                        try execution.consumeWork(1)
                        var value = IntervalHomogeneousSurfaceControl.zero
                        for j in vBasis[vOrder].values.indices {
                            let row = vBasis[vOrder].startIndex + j
                            for i in uBasis[uOrder].values.indices {
                                try execution.consumeWork(1)
                                let column = uBasis[uOrder].startIndex + i
                                let point = surface.controlPoints[row][column]
                                let coefficient = uBasis[uOrder].values[i] * vBasis[vOrder].values[j]
                                    * .exact(surface.weights[row][column])
                                value = add(value, IntervalHomogeneousSurfaceControl(
                                    x: (.exact(point.x) - .exact(origin.x)) * coefficient,
                                    y: (.exact(point.y) - .exact(origin.y)) * coefficient,
                                    z: (.exact(point.z) - .exact(origin.z)) * coefficient, weight: coefficient))
                            }
                        }
                        // Partition of unity applies to original common weights, not
                        // approximately equal extracted coefficients.
                        let denominator = commonWeight.map { Interval.exact(uOrder == 0 && vOrder == 0 ? $0 : 0) } ?? value.weight
                        derivatives[vOrder][uOrder] = IntervalHomogeneousSurfaceControl(
                            x: value.x, y: value.y, z: value.z, weight: denominator)
                    }
                }
                let uSpan = Interval.exact(ub.upper) - .exact(ub.lower)
                let vSpan = Interval.exact(vb.upper) - .exact(vb.lower)
                try OriginalCoefficientAllocation.reserve(count: surface.vDegree + 1, of: [IntervalHomogeneousSurfaceControl].self, using: &execution)
                for _ in 0...surface.vDegree {
                    try OriginalCoefficientAllocation.reserve(count: surface.uDegree + 1, of: IntervalHomogeneousSurfaceControl.self, using: &execution)
                }
                var controls = derivatives
                for j in 0...surface.vDegree {
                    try execution.checkpoint(); try execution.consumeWork(1)
                    for i in 0...surface.uDegree {
                        try execution.consumeWork(1)
                        var value = IntervalHomogeneousSurfaceControl.zero
                        for q in 0...j {
                            let vScale = try originalBernsteinScale(degree: surface.vDegree, index: j, order: q, span: vSpan, tolerance: tolerance, using: &execution)
                            for p in 0...i {
                                let uScale = try originalBernsteinScale(degree: surface.uDegree, index: i, order: p, span: uSpan, tolerance: tolerance, using: &execution)
                                try execution.consumeWork(1)
                                value = add(value, derivatives[q][p].scaled(by: uScale * vScale))
                            }
                        }
                        controls[j][i] = IntervalHomogeneousSurfaceControl(x: value.x, y: value.y, z: value.z,
                            weight: commonWeight.map { .exact($0) } ?? value.weight)
                        guard [value.x, value.y, value.z, value.weight].allSatisfy({ $0.isFinite }) else {
                            throw KernelError(phase: .geometry, code: .resourceLimitExceeded, tolerance: tolerance,
                                message: "Original homogeneous extraction exceeds finite coefficient arithmetic.")
                        }
                    }
                }
                result.append(OriginalHomogeneousPatch(controls: controls, origin: origin, commonWeight: commonWeight,
                    uSpanIndex: u, vSpanIndex: v, uBounds: ub, vBounds: vb))
            }
        }
        return result
    }

    private func originalBernsteinScale<A: ExactScalarAdmission & ~Copyable>(degree: Int, index: Int, order: Int,
        span: OutwardScalarInterval, tolerance: ModelingTolerance, using execution: inout A) throws -> OutwardScalarInterval {
        var scale = OutwardScalarInterval.exact(1)
        if order > 0 {
            for p in 0..<order {
                try execution.consumeWork(1)
                guard let next = (scale * .exact(Double(index - p)) * span)
                    .divided(by: .exact(Double(p + 1)) * .exact(Double(degree - p))), next.isFinite else {
                    throw KernelError(phase: .geometry, code: .resourceLimitExceeded, tolerance: tolerance,
                        message: "Original Taylor-to-Bernstein scaling has no finite enclosure.")
                }
                scale = next
            }
        }
        return scale
    }
    func surfacePatches<A: ExactScalarAdmission & ~Copyable>(
        surface: BSplineSurface3D,
        tolerance: ModelingTolerance,
        using execution: inout A
    ) throws -> [RationalBezierSurfacePatch3D] {
        try resolvedSurfacePatches(
            surface: surface,
            uInterval: nil,
            vInterval: nil,
            tolerance: tolerance, using: &execution
        )
    }

    func surfacePatches<A: ExactScalarAdmission & ~Copyable>(
        surface: BSplineSurface3D,
        intersectingU uInterval: ScalarInterval,
        v vInterval: ScalarInterval,
        tolerance: ModelingTolerance,
        using execution: inout A
    ) throws -> [RationalBezierSurfacePatch3D] {
        try resolvedSurfacePatches(
            surface: surface,
            uInterval: uInterval,
            vInterval: vInterval,
            tolerance: tolerance, using: &execution
        )
    }

    private func resolvedSurfacePatches<A: ExactScalarAdmission & ~Copyable>(
        surface: BSplineSurface3D,
        uInterval: ScalarInterval?,
        vInterval: ScalarInterval?,
        tolerance: ModelingTolerance,
        using execution: inout A
    ) throws -> [RationalBezierSurfacePatch3D] {
        try surface.validate(tolerance: tolerance, using: &execution)
        if surface.isUPeriodic || surface.isVPeriodic {
            let u = try uInterval ?? ScalarInterval(
                lower: surface.uKnots[surface.uDegree], upper: surface.uKnots[surface.uControlPointCount])
            let v = try vInterval ?? ScalarInterval(
                lower: surface.vKnots[surface.vDegree], upper: surface.vKnots[surface.vControlPointCount])
            // FIXME(INCOMPLETE_IMPLEMENTATION): Legacy periodic Cartesian
            // restriction still owns unbounded internal preparation. Native
            // embedding must use original periodic receipts before this branch
            // can close its caller-paid source contract.
            let restriction = try surface.trimmed(uFrom: u.lower, uTo: u.upper,
                vFrom: v.lower, vTo: v.upper, tolerance: tolerance, using: &execution)
            return try resolvedSurfacePatches(surface: restriction, uInterval: nil,
                vInterval: nil, tolerance: tolerance, using: &execution)
        }
        let uBreaks = try parameterBreaks(
            knots: surface.uKnots,
            domain: surface.uDomain,
            tolerance: tolerance, using: &execution
        )
        let vBreaks = try parameterBreaks(
            knots: surface.vKnots,
            domain: surface.vDomain,
            tolerance: tolerance, using: &execution
        )
        var result: [RationalBezierSurfacePatch3D] = []
        let capacity = try NativeSurfaceEmbeddingPreparationReservation.product([uBreaks.count - 1, vBreaks.count - 1])
        try OriginalCoefficientAllocation.reserve(count: capacity, of: RationalBezierSurfacePatch3D.self, using: &execution)
        result.reserveCapacity(capacity)
        for vIndex in 0..<(vBreaks.count - 1) {
            try execution.consumeWork(1)
            if let vInterval,
               vBreaks[vIndex + 1] <= vInterval.lower
                || vBreaks[vIndex] >= vInterval.upper {
                continue
            }
            for uIndex in 0..<(uBreaks.count - 1) {
                // Enumerating original knot pairs is not geometric subdivision.
                // Count the native cell without increasing algebraic depth.
                try execution.visitCell(axis: .value, depth: 0)
                if let uInterval,
                   uBreaks[uIndex + 1] <= uInterval.lower
                    || uBreaks[uIndex] >= uInterval.upper {
                    continue
                }
                let patch = try surfacePatch(
                    surface: surface,
                    uBounds: (uBreaks[uIndex], uBreaks[uIndex + 1]),
                    vBounds: (vBreaks[vIndex], vBreaks[vIndex + 1]),
                    tolerance: tolerance, using: &execution
                )
                try verify(
                    patch: patch,
                    against: surface,
                    tolerance: tolerance, using: &execution
                )
                result.append(patch)
            }
        }
        return result
    }

    func scalarDistancePatches<A: ExactScalarAdmission & ~Copyable>(
        surface: BSplineSurface3D,
        plane: CanonicalAnalyticSurface.Plane,
        tolerance: ModelingTolerance, using execution: inout A
    ) throws -> [RationalScalarBezierPatch] {
        let patches = try surfacePatches(surface: surface, tolerance: tolerance, using: &execution)
        try OriginalCoefficientAllocation.reserve(count: patches.count, of: RationalScalarBezierPatch.self, using: &execution)
        return try patches.map { patch in
            try OriginalCoefficientAllocation.reserve(count: patch.controlPoints.count, of: [Double].self, using: &execution)
            for row in patch.controlPoints { try OriginalCoefficientAllocation.reserve(count: row.count, of: Double.self, using: &execution) }
            return RationalScalarBezierPatch(
                numerator: try patch.controlPoints.indices.map { vIndex in
                    try patch.controlPoints[vIndex].indices.map { uIndex in
                        try execution.consumeWork(1)
                        return patch.weights[vIndex][uIndex]
                            * signedDistance(patch.controlPoints[vIndex][uIndex], plane: plane)
                    }
                },
                weights: patch.weights,
                uLower: patch.uLower,
                uUpper: patch.uUpper,
                vLower: patch.vLower,
                vUpper: patch.vUpper
            )
        }
    }

    private func surfacePatch<A: ExactScalarAdmission & ~Copyable>(
        surface: BSplineSurface3D,
        uBounds: (lower: Double, upper: Double),
        vBounds: (lower: Double, upper: Double),
        tolerance: ModelingTolerance,
        using execution: inout A
    ) throws -> RationalBezierSurfacePatch3D {
        let uSpan = uBounds.upper - uBounds.lower
        let vSpan = vBounds.upper - vBounds.lower
        guard uSpan.isFinite, uSpan > 0.0,
              vSpan.isFinite, vSpan > 0.0 else {
            throw KernelError(
                phase: .geometry,
                code: .invalidInput,
                tolerance: tolerance,
                message: "B-spline Bezier extraction requires positive finite knot spans."
            )
        }
        try execution.consumeWork(NativeSurfaceEmbeddingPreparationReservation.sum([surface.uKnots.count, surface.vKnots.count]))
        if surface.uControlPointCount == surface.uDegree + 1,
           surface.vControlPointCount == surface.vDegree + 1,
           surface.uKnots.prefix(surface.uDegree + 1).allSatisfy({ $0 == uBounds.lower }),
           surface.uKnots.suffix(surface.uDegree + 1).allSatisfy({ $0 == uBounds.upper }),
           surface.vKnots.prefix(surface.vDegree + 1).allSatisfy({ $0 == vBounds.lower }),
           surface.vKnots.suffix(surface.vDegree + 1).allSatisfy({ $0 == vBounds.upper }) {
            return RationalBezierSurfacePatch3D(
                controlPoints: surface.controlPoints, weights: surface.weights,
                uLower: uBounds.lower, uUpper: uBounds.upper,
                vLower: vBounds.lower, vUpper: vBounds.upper)
        }
        try OriginalCoefficientAllocation.reserve(count: surface.vDegree + 1, of: [HomogeneousVector].self, using: &execution)
        for _ in 0...surface.vDegree {
            try OriginalCoefficientAllocation.reserve(count: surface.uDegree + 1, of: HomogeneousVector.self, using: &execution)
        }
        var derivatives = Array(
            repeating: Array(
                repeating: HomogeneousVector.zero,
                count: surface.uDegree + 1
            ),
            count: surface.vDegree + 1
        )
        for vOrder in 0...surface.vDegree {

            let vBasis = try BSplineBasis.derivativeValues(
                parameter: vBounds.lower,
                degree: surface.vDegree,
                derivativeOrder: vOrder,
                knots: surface.vKnots,
                count: surface.vControlPointCount, using: &execution
            )
            for uOrder in 0...surface.uDegree {

                let uBasis = try BSplineBasis.derivativeValues(
                    parameter: uBounds.lower,
                    degree: surface.uDegree,
                    derivativeOrder: uOrder,
                    knots: surface.uKnots,
                    count: surface.uControlPointCount, using: &execution
                )
                try execution.consumeWork(NativeSurfaceEmbeddingPreparationReservation.product([surface.uControlPointCount, surface.vControlPointCount]))
                derivatives[vOrder][uOrder] = homogeneousDerivative(
                    surface: surface,
                    uBasis: uBasis,
                    vBasis: vBasis
                )
            }
        }

        try OriginalCoefficientAllocation.reserve(count: surface.vDegree + 1, of: [HomogeneousVector].self, using: &execution)
        for _ in 0...surface.vDegree {
            try OriginalCoefficientAllocation.reserve(count: surface.uDegree + 1, of: HomogeneousVector.self, using: &execution)
        }
        var homogeneousControlNet = Array(
            repeating: Array(
                repeating: HomogeneousVector.zero,
                count: surface.uDegree + 1
            ),
            count: surface.vDegree + 1
        )
        for vControl in 0...surface.vDegree {
            for uControl in 0...surface.uDegree {
                var value = HomogeneousVector.zero
                for vOrder in 0...vControl {
                    try execution.consumeWork(2 * vOrder + 1)
                    let vScale = try derivativeToBernsteinScale(
                        degree: surface.vDegree,
                        controlIndex: vControl,
                        derivativeOrder: vOrder,
                        span: vSpan,
                        tolerance: tolerance
                    )
                    for uOrder in 0...uControl {
                        try execution.consumeWork(2 * uOrder + 2)
                        let uScale = try derivativeToBernsteinScale(
                            degree: surface.uDegree,
                            controlIndex: uControl,
                            derivativeOrder: uOrder,
                            span: uSpan,
                            tolerance: tolerance
                        )
                        value = value + derivatives[vOrder][uOrder] * (uScale * vScale)
                    }
                }
                homogeneousControlNet[vControl][uControl] = value
            }
        }

        try OriginalCoefficientAllocation.reserve(count: surface.vDegree + 1, of: [Point3D].self, using: &execution)
        try OriginalCoefficientAllocation.reserve(count: surface.vDegree + 1, of: [Double].self, using: &execution)
        for _ in 0...surface.vDegree {
            try OriginalCoefficientAllocation.reserve(count: surface.uDegree + 1, of: Point3D.self, using: &execution)
            try OriginalCoefficientAllocation.reserve(count: surface.uDegree + 1, of: Double.self, using: &execution)
        }
        var points: [[Point3D]] = []
        var weights: [[Double]] = []
        points.reserveCapacity(surface.vDegree + 1)
        weights.reserveCapacity(surface.vDegree + 1)
        for row in homogeneousControlNet {
            var pointRow: [Point3D] = []
            var weightRow: [Double] = []
            pointRow.reserveCapacity(surface.uDegree + 1)
            weightRow.reserveCapacity(surface.uDegree + 1)
            for value in row {
                try execution.consumeWork(1)
                guard value.isFinite,
                      value.weight > Double.ulpOfOne else {
                    throw KernelError(
                        phase: .geometry,
                        code: .singularSystem,
                        residual: value.weight,
                        tolerance: tolerance,
                        message: "B-spline Bezier extraction produced a non-positive homogeneous weight."
                    )
                }
                pointRow.append(Point3D(
                    x: value.x / value.weight,
                    y: value.y / value.weight,
                    z: value.z / value.weight
                ))
                weightRow.append(value.weight)
            }
            points.append(pointRow)
            weights.append(weightRow)
        }
        return RationalBezierSurfacePatch3D(
            controlPoints: points,
            weights: weights,
            uLower: uBounds.lower,
            uUpper: uBounds.upper,
            vLower: vBounds.lower,
            vUpper: vBounds.upper
        )
    }

    private func homogeneousDerivative(
        surface: BSplineSurface3D,
        uBasis: [Double],
        vBasis: [Double]
    ) -> HomogeneousVector {
        var result = HomogeneousVector.zero
        for vIndex in 0..<surface.vControlPointCount {
            for uIndex in 0..<surface.uControlPointCount {
                let weight = surface.weights[vIndex][uIndex]
                let coefficient = uBasis[uIndex] * vBasis[vIndex] * weight
                guard coefficient != 0.0 else { continue }
                let point = surface.controlPoints[vIndex][uIndex]
                result = result + HomogeneousVector(
                    x: point.x * coefficient,
                    y: point.y * coefficient,
                    z: point.z * coefficient,
                    weight: coefficient
                )
            }
        }
        return result
    }

    private func derivativeToBernsteinScale(
        degree: Int,
        controlIndex: Int,
        derivativeOrder: Int,
        span: Double,
        tolerance: ModelingTolerance
    ) throws -> Double {
        guard derivativeOrder <= controlIndex,
              derivativeOrder <= degree else {
            return 0.0
        }
        var binomial = 1.0
        if derivativeOrder > 0 {
            for index in 1...derivativeOrder {
                binomial *= Double(controlIndex - derivativeOrder + index) / Double(index)
            }
        }
        var fallingFactorial = 1.0
        var spanPower = 1.0
        if derivativeOrder > 0 {
            for index in 0..<derivativeOrder {
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

    private func verify<A: ExactScalarAdmission & ~Copyable>(
        patch: RationalBezierSurfacePatch3D,
        against surface: BSplineSurface3D,
        tolerance: ModelingTolerance,
        using execution: inout A
    ) throws {
        let knotCount = try NativeSurfaceEmbeddingPreparationReservation.product([4, try NativeSurfaceEmbeddingPreparationReservation.sum([surface.uDegree, surface.vDegree, 2])])
        try OriginalCoefficientAllocation.reserve(count: knotCount, of: Double.self, using: &execution)
        let extracted = BSplineSurface3D(
            uDegree: surface.uDegree,
            vDegree: surface.vDegree,
            uKnots: Array(repeating: patch.uLower, count: surface.uDegree + 1)
                + Array(repeating: patch.uUpper, count: surface.uDegree + 1),
            vKnots: Array(repeating: patch.vLower, count: surface.vDegree + 1)
                + Array(repeating: patch.vUpper, count: surface.vDegree + 1),
            controlPoints: patch.controlPoints,
            weights: patch.weights
        )
        try extracted.validate(tolerance: tolerance, using: &execution)
        var maximumResidual = 0.0
        let uSampleCount = max(3, surface.uDegree * 2 + 1)
        let vSampleCount = max(3, surface.vDegree * 2 + 1)
        for vIndex in 0..<vSampleCount {
            let vFraction = Double(vIndex) / Double(vSampleCount - 1)
            let v = patch.vLower + (patch.vUpper - patch.vLower) * vFraction
            for uIndex in 0..<uSampleCount {
                let uFraction = Double(uIndex) / Double(uSampleCount - 1)
                let u = patch.uLower + (patch.uUpper - patch.uLower) * uFraction

                let expected = try surface.point(u: u, v: v, tolerance: tolerance, using: &execution)

                let actual = try extracted.point(u: u, v: v, tolerance: tolerance, using: &execution)
                maximumResidual = max(maximumResidual, (actual - expected).length.nextUp)
            }
        }
        try execution.consumeWork(patch.controlPoints.count)
        var count = 0
        for row in patch.controlPoints { count = try NativeSurfaceEmbeddingPreparationReservation.sum([count, row.count]) }
        try execution.consumeWork(count)
        let modelScale = max(
            1.0,
            patch.controlPoints.reduce(0.0) { scale, row in
                row.reduce(scale) { scale, point in max(scale, abs(point.x), abs(point.y), abs(point.z)) }
            }
        )
        let allowedResidual = max(
            tolerance.distance,
            tolerance.relative * modelScale
        )
        guard maximumResidual <= allowedResidual else {
            throw KernelError(
                phase: .geometry,
                code: .intersectionFailure,
                residual: maximumResidual,
                tolerance: tolerance,
                message: "B-spline Bezier extraction failed its exact-locus verification."
            )
        }
    }

    private func parameterBreaks<A: ExactScalarAdmission & ~Copyable>(
        knots: [Double],
        domain: ParameterDomain,
        tolerance: ModelingTolerance,
        using execution: inout A
    ) throws -> [Double] {
        guard case let .closed(lower, upper) = domain else {
            throw KernelError(
                phase: .geometry,
                code: .invalidInput,
                tolerance: tolerance,
                message: "B-spline Bezier decomposition requires a bounded parameter domain."
            )
        }
        let capacity = try NativeSurfaceEmbeddingPreparationReservation.sum([knots.count, 2])
        try OriginalCoefficientAllocation.reserve(count: capacity, of: Double.self, using: &execution)
        var result: [Double] = []
        result.reserveCapacity(capacity)
        result.append(lower)
        for knot in knots {
            try execution.consumeWork(1)
            guard knot > lower && knot < upper else { continue }
            if result.last != knot {
                result.append(knot)
            }
        }
        result.append(upper)
        guard result.count >= 2 else {
            throw KernelError(
                phase: .geometry,
                code: .invalidInput,
                tolerance: tolerance,
                message: "B-spline Bezier decomposition found no nonzero knot span."
            )
        }
        return result
    }

    private func midpoint(_ lower: Double, _ upper: Double) -> Double {
        lower + (upper - lower) * 0.5
    }

    private func signedDistance(
        _ point: Point3D,
        plane: CanonicalAnalyticSurface.Plane
    ) -> Double {
        (point - plane.origin).dot(plane.normal)
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

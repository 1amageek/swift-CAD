import CADCore
import CADGeometry

// FIXME(INCOMPLETE_IMPLEMENTATION): This original chart admission is a dependency
// consumed by the native public Revolve sheet path and retained original support.
// Original analytic-conic and cyclic chart admission remains required before
// general S7 publication may be reported. Original higher-order pole normals
// remain a separate lower requirement from exact open-chart orbit signs.
package struct OriginalRevolutionOrbitAdmitter: Sendable {
    package struct Admission: Sendable {
        package let spans: [OriginalRevolveGeneratorResolver.Span]
        package let angle: Double
        package let isClosed: Bool
        package let tolerance: ModelingTolerance

        fileprivate init(spans: [OriginalRevolveGeneratorResolver.Span], angle: Double,
            isClosed: Bool, tolerance: ModelingTolerance) {
            self.spans = spans
            self.angle = angle
            self.isClosed = isClosed
            self.tolerance = tolerance
        }
    }

    private struct Cell: Sendable {
        let chartIndex: Int
        let parameters: ScalarInterval
        let depth: Int
        let axial: OutwardScalarInterval
        let radial: OutwardScalarInterval
        let crossX: OutwardScalarInterval
        let crossY: OutwardScalarInterval
        let crossZ: OutwardScalarInterval
        let axialDerivative: OutwardScalarInterval
        let radialDerivative: OutwardScalarInterval
    }

    package init() {}

    /// Proves whole original generator orbit injectivity without fitted image authority.
    package func validate<B: RationalAlgebraAdmitting>(
        _ spans: [OriginalRevolveGeneratorResolver.Span], angle: Double,
        isClosed: Bool, maximumSpanCount: Int,
        maximumSubdivisionDepth: Int, maximumPairVisits: Int,
        tolerance: ModelingTolerance, usage: inout B
    ) throws -> Admission {
        guard let first = spans.first, angle.isFinite, angle != 0,
              abs(angle) <= 2 * Double.pi, maximumSpanCount > 0, maximumSpanCount <= 65_536,
              spans.count <= maximumSpanCount, maximumPairVisits > 0, maximumPairVisits <= 65_536,
              maximumSubdivisionDepth >= 0, maximumSubdivisionDepth <= 32 else {
            throw GeometryConversionError.invalidInput("Original revolution orbit admission requires bounded charts, angle and caller limits.")
        }
        let origin = first.originalAxisOrigin
        let direction = first.originalAxisDirection
        guard spans.allSatisfy({ $0.originalAxisOrigin == origin
            && $0.originalAxisDirection == direction
            && $0.chart.certificationTolerance == tolerance }) else {
            throw GeometryConversionError.invalidInput("Original revolution orbit charts must retain one source axis and preparation tolerance.")
        }
        let full = try ScalarInterval(lower: 0, upper: 1)
        try usage.consumeExactWork(1)
        let cosineLower = abs(angle) < Double.pi
            ? CanonicalSphereAngularPhase.harmonic(of: .constant(abs(angle)), cosine: true).value.lower
            : nil
        try usage.retainExactStorage(spans.count)
        var originalSigns = [OriginalRevolutionMonotonicityProof?](repeating: nil, count: spans.count)
        func exactSigns(_ index: Int, usage: inout B) throws -> OriginalRevolutionMonotonicityProof {
            if let retained = originalSigns[index] { return retained }
            let prepared = try OriginalRevolutionMonotonicityProof.prepare(for: spans[index],
                maximumSubdivisionDepth: maximumSubdivisionDepth, tolerance: tolerance, usage: &usage)
            originalSigns[index] = prepared
            return prepared
        }
        func cell(chartIndex: Int, parameters: ScalarInterval, depth: Int,
            usage: inout B) throws -> Cell {
            try usage.visitExactCell(depth: depth)
            let original = try spans[chartIndex].chart.preparedDerivatives(over: parameters,
                tolerance: tolerance, consumeWork: { try usage.consumeExactWork(1) })
            // Fixed scalar fields avoid temporary vector-jet arrays for every
            // retained pair cell. Only the lower original jet owns its buffers.
            let x = original.x.value - .exact(origin.x)
            let y = original.y.value - .exact(origin.y)
            let z = original.z.value - .exact(origin.z)
            let dx = original.x.derivatives[1]
            let dy = original.y.derivatives[1]
            let dz = original.z.derivatives[1]
            let axisX = OutwardScalarInterval.exact(direction.x)
            let axisY = OutwardScalarInterval.exact(direction.y)
            let axisZ = OutwardScalarInterval.exact(direction.z)
            let crossX = y * axisZ - z * axisY
            let crossY = z * axisX - x * axisZ
            let crossZ = x * axisY - y * axisX
            let crossDX = dy * axisZ - dz * axisY
            let crossDY = dz * axisX - dx * axisZ
            let crossDZ = dx * axisY - dy * axisX
            let height = x * axisX + y * axisY + z * axisZ
            let heightDerivative = dx * axisX + dy * axisY + dz * axisZ
            let radius = crossX * crossX + crossY * crossY + crossZ * crossZ
            let radiusDerivative = (crossX * crossDX + crossY * crossDY + crossZ * crossDZ) * .exact(2)
            try usage.consumeExactWork(7)
            guard height.isFinite, radius.isFinite, crossX.isFinite,
                  crossY.isFinite, crossZ.isFinite, heightDerivative.isFinite,
                  radiusDerivative.isFinite else {
                throw GeometryConversionError.resourceLimitExceeded("Original revolution orbit bounds are nonfinite.")
            }
            try usage.retainExactStorage(1)
            return Cell(chartIndex: chartIndex, parameters: parameters, depth: depth,
                axial: height, radial: radius, crossX: crossX,
                crossY: crossY, crossZ: crossZ,
                axialDerivative: heightDerivative, radialDerivative: radiusDerivative)
        }
        func monotone(_ a: Cell, _ b: Cell, usage: inout B) throws -> Bool {
            try usage.consumeExactWork(1)
            let axial = a.axialDerivative.union(b.axialDerivative)
            let radial = a.radialDerivative.union(b.radialDerivative)
            if axial.excludesZero || radial.excludesZero { return true }
            // Midpoint coefficients propose one fixed linear functional only.
            // Both whole derivative intervals must prove its strict positive sign.
            let h = axial.midpoint
            let r = radial.midpoint
            guard h.isFinite, r.isFinite else { return false }
            if (a.axialDerivative * .exact(h) + a.radialDerivative * .exact(r)).lower > 0
                && (b.axialDerivative * .exact(h) + b.radialDerivative * .exact(r)).lower > 0 {
                return true
            }
            let first = try exactSigns(a.chartIndex, usage: &usage)
            if a.chartIndex == b.chartIndex { return first.axialSign != 0 || first.radialSign != 0 }
            let second = try exactSigns(b.chartIndex, usage: &usage)
            return first.axialSign != 0 && first.axialSign == second.axialSign
                || first.radialSign != 0 && first.radialSign == second.radialSign
        }
        func adjacent(_ a: Cell, _ b: Cell) -> Bool {
            if a.chartIndex == b.chartIndex, a.parameters.upper == b.parameters.lower { return true }
            if a.chartIndex + 1 == b.chartIndex,
               a.parameters.upper == 1, b.parameters.lower == 0 { return true }
            return isClosed && a.chartIndex == 0 && b.chartIndex == spans.count - 1
                && a.parameters.lower == 0 && b.parameters.upper == 1
        }
        func angularlySeparated(_ a: Cell, _ b: Cell, usage: inout B) throws -> Bool {
            try usage.consumeExactWork(1)
            guard let cosineLower, a.radial.lower > 0, b.radial.lower > 0 else { return false }
            let radiusA = OutwardScalarInterval(lower: a.radial.lower.squareRoot().nextDown,
                upper: a.radial.upper.squareRoot().nextUp)
            let radiusB = OutwardScalarInterval(lower: b.radial.lower.squareRoot().nextDown,
                upper: b.radial.upper.squareRoot().nextUp)
            let dot = a.crossX * b.crossX + a.crossY * b.crossY + a.crossZ * b.crossZ
            guard let cosine = dot.divided(by: radiusA * radiusB), cosine.isFinite else { return false }
            return cosine.upper < cosineLower
        }
        func split(_ source: Cell, usage: inout B) throws -> (Cell, Cell) {
            let middle = source.parameters.midpoint
            guard source.depth < maximumSubdivisionDepth,
                  middle > source.parameters.lower, middle < source.parameters.upper else {
                throw GeometryConversionError.resourceLimitExceeded("Original revolution orbit separation exhausted its source subdivision allowance.")
            }
            return try (cell(chartIndex: source.chartIndex,
                parameters: ScalarInterval(lower: source.parameters.lower, upper: middle),
                depth: source.depth + 1, usage: &usage),
                cell(chartIndex: source.chartIndex,
                    parameters: ScalarInterval(lower: middle, upper: source.parameters.upper),
                    depth: source.depth + 1, usage: &usage))
        }
        var initial: [Cell] = []
        for index in spans.indices where !spans[index].isWholeAxis {
            initial.append(try cell(chartIndex: index, parameters: full, depth: 0, usage: &usage))
        }
        guard !initial.isEmpty else {
            throw GeometryConversionError.invalidInput("An original generator wholly on the axis does not produce a revolution sheet.")
        }
        var remainingPairs = maximumPairVisits
        for firstIndex in initial.indices {
            for secondIndex in firstIndex..<initial.count {
                try usage.retainExactStorage(1)
                var pending = [(initial[firstIndex], initial[secondIndex])]
                while let (a, b) = pending.popLast() {
                    guard remainingPairs > 0 else {
                        throw GeometryConversionError.resourceLimitExceeded("Original revolution exhausted its cumulative orbit-pair visits.")
                    }
                    remainingPairs -= 1
                    try usage.consumeExactWork(1)
                    let diagonal = a.chartIndex == b.chartIndex && a.parameters == b.parameters
                    if diagonal {
                        if try monotone(a, a, usage: &usage) { continue }
                        let (left, right) = try split(a, usage: &usage)
                        try usage.retainExactStorage(3)
                        pending.append((left, left))
                        pending.append((left, right))
                        pending.append((right, right))
                    } else {
                        if !a.axial.intersects(b.axial) || !a.radial.intersects(b.radial) { continue }
                        if adjacent(a, b), try monotone(a, b, usage: &usage) { continue }
                        if try angularlySeparated(a, b, usage: &usage) { continue }
                        try usage.retainExactStorage(2)
                        if a.parameters.width >= b.parameters.width {
                            let (left, right) = try split(a, usage: &usage)
                            pending.append((left, b))
                            pending.append((right, b))
                        } else {
                            let (left, right) = try split(b, usage: &usage)
                            pending.append((a, left))
                            pending.append((a, right))
                        }
                    }
                }
            }
        }
        return Admission(spans: spans, angle: angle, isClosed: isClosed, tolerance: tolerance)
    }
}

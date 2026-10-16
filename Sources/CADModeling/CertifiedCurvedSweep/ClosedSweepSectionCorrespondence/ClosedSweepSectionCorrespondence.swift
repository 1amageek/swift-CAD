import CADCore
import CADGeometry

/// A unique original cyclic seam correspondence, independent of holonomy correction.
package struct ClosedSweepSectionCorrespondence: Sendable {
    package struct RowTransport: Sendable {
        package let row: [Point3D]
        package let maximumControlDisplacement: Double
        package let guarantees: [GeometryConversionGuarantee]
    }
    private let loopShifts: [Int]
    private let authoredGuarantees: [GeometryConversionGuarantee]

    package init(loops: [[ExactBSplineCurveSpan]], authoredAction: ClosedSweepIntervalFrameAction,
        tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution) throws {
        guard !loops.isEmpty, loops.allSatisfy({ !$0.isEmpty }) else {
            throw GeometryConversionError.invalidInput("Closed section correspondence requires retained nonempty original loops.")
        }
        try execution.retainStorage(bytes: loops.count * MemoryLayout<Int>.stride)
        let totalSpans = loops.reduce(0) { $0 + $1.count }
        try execution.retainStorage(bytes: 2 * totalSpans * MemoryLayout<GeometryConversionGuarantee>.stride)
        var shifts: [Int] = [], retained: [GeometryConversionGuarantee] = []
        shifts.reserveCapacity(loops.count); retained.reserveCapacity(2 * totalSpans)
        for loop in loops {
            var selected: Int?
            var selectedGuarantees: [GeometryConversionGuarantee] = []
            var incompatibleBasis = false
            for shift in loop.indices {
                try execution.consumeWork(1)
                var accepted = true
                try execution.retainStorage(bytes: 2 * loop.count * MemoryLayout<GeometryConversionGuarantee>.stride)
                var proposed: [GeometryConversionGuarantee] = []
                proposed.reserveCapacity(2 * loop.count)
                for index in loop.indices {
                    try execution.consumeWork(1)
                    let source = loop[index], target = loop[(index + shift) % loop.count]
                    guard source.curve.degree == target.curve.degree,
                          source.curve.controlPointCount == target.curve.controlPointCount else {
                        incompatibleBasis = true; accepted = false; break
                    }
                    let candidate = try Self.candidate(on: source.curve, points: target.curve.controlPoints,
                        tolerance: tolerance, using: &execution)
                    do {
                        let domain = try Self.domain(source.curve)
                        let originalTarget = try OriginalCurveConstructionSource(chart: target.originalChart,
                            domain: domain, tolerance: tolerance, using: &execution)
                        let end = try ClosedSweepSectionSource(chart: source.originalChart, domain: domain,
                            action: authoredAction, tolerance: tolerance, using: &execution)
                        let pair = try Self.certificates(first: originalTarget, second: end,
                            candidate: candidate, domain: domain, tolerance: tolerance, using: &execution)
                        proposed.append(contentsOf: pair)
                    } catch GeometryConversionError.toleranceRejected {
                        accepted = false; break
                    }
                }
                if accepted {
                    guard selected == nil else {
                        throw KernelError(phase: .evaluation, code: .ambiguousSelection,
                            tolerance: tolerance, message: "The original closed section admits more than one cyclic seam correspondence.")
                    }
                    selected = shift; selectedGuarantees = proposed
                }
            }
            guard let selected else {
                if incompatibleBasis {
                    // FIXME(INCOMPLETE_IMPLEMENTATION): Closed Sweep/Pipe's original
                    // cyclic search now proves complete compatible-basis spans. A
                    // common rational tensor basis and cross-loop transport producer
                    // are still required for differing authored representations;
                    // coefficient-only remapping cannot complete this domain.
                    throw KernelError(phase: .evaluation, code: .unsupportedCapability,
                        tolerance: tolerance, message: "Original closed section correspondence needs a retained common rational basis.")
                }
                throw KernelError(phase: .evaluation, code: .sweepTwistUnavailable,
                    tolerance: tolerance, message: "The authored end twist does not preserve the complete original section.")
            }
            shifts.append(selected)
            retained.append(contentsOf: selectedGuarantees)
        }
        loopShifts = shifts; authoredGuarantees = retained
    }

    /// Certifies the original actual endpoint action against the selected initial rows.
    package func transport(loops: [[ExactBSplineCurveSpan]], firstRow: [Point3D], lastRow: [Point3D],
        startAction: ClosedSweepIntervalFrameAction, endAction: ClosedSweepIntervalFrameAction,
        tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution) throws -> RowTransport? {
        guard loops.count == loopShifts.count, firstRow.count == lastRow.count else {
            throw GeometryConversionError.invalidInput("Closed row transport must retain its original loop and coefficient layout.")
        }
        let count = loops.reduce(0) { $0 + $1.reduce(0) { $0 + $1.curve.controlPointCount } }
        guard firstRow.count == count else {
            throw GeometryConversionError.invalidInput("Closed row transport requires every original section coefficient.")
        }
        try execution.retainStorage(bytes: count * MemoryLayout<Point3D>.stride)
        let totalSpans = loops.reduce(0) { $0 + $1.count }
        try execution.retainStorage(bytes: 2 * totalSpans * MemoryLayout<GeometryConversionGuarantee>.stride)
        var replacement: [Point3D] = [], guarantees: [GeometryConversionGuarantee] = []
        replacement.reserveCapacity(count); guarantees.reserveCapacity(2 * totalSpans)
        var loopOffset = 0
        var gap = 0.0
        for (loopIndex, loop) in loops.enumerated() {
            try execution.retainStorage(bytes: loop.count * MemoryLayout<Int>.stride)
            var offsets: [Int] = []; offsets.reserveCapacity(loop.count)
            var next = loopOffset
            for span in loop { try execution.consumeWork(1); offsets.append(next); next += span.curve.controlPointCount }
            for index in loop.indices {
                let targetIndex = (index + loopShifts[loopIndex]) % loop.count
                let source = loop[index], target = loop[targetIndex]
                let size = source.curve.controlPointCount
                guard size == target.curve.controlPointCount, source.curve.degree == target.curve.degree else {
                    throw GeometryConversionError.invalidInput("The certified cyclic seam's rational basis changed during construction.")
                }
                try execution.retainStorage(bytes: size * MemoryLayout<Point3D>.stride)
                let points = Array(firstRow[offsets[targetIndex]..<(offsets[targetIndex] + size)])
                let candidate = try Self.candidate(on: source.curve, points: points,
                    tolerance: tolerance, using: &execution)
                let domain = try Self.domain(source.curve)
                let beginning = try ClosedSweepSectionSource(chart: target.originalChart, domain: domain,
                    action: startAction, tolerance: tolerance, using: &execution)
                let ending = try ClosedSweepSectionSource(chart: source.originalChart, domain: domain,
                    action: endAction, tolerance: tolerance, using: &execution)
                let pair: [GeometryConversionGuarantee]
                do {
                    pair = try Self.certificates(first: beginning, second: ending,
                        candidate: candidate, domain: domain, tolerance: tolerance, using: &execution)
                } catch GeometryConversionError.toleranceRejected { return nil }
                guarantees.append(contentsOf: pair)
                for local in points.indices {
                    try execution.consumeWork(1)
                    let a = points[local], b = lastRow[offsets[index] + local]
                    let x = OutwardScalarInterval.exact(a.x) - .exact(b.x)
                    let y = OutwardScalarInterval.exact(a.y) - .exact(b.y)
                    let z = OutwardScalarInterval.exact(a.z) - .exact(b.z)
                    let squared = x * x + y * y + z * z
                    gap = max(gap, max(0, squared.upper).squareRoot().nextUp)
                    replacement.append(a)
                }
            }
            loopOffset = next
        }
        return RowTransport(row: replacement, maximumControlDisplacement: gap, guarantees: guarantees)
    }

    private static func candidate(on basis: BSplineCurve3D, points: [Point3D],
        tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution) throws -> BSplineCurve3D {
        try execution.consumeWork(points.count)
        let result = BSplineCurve3D(degree: basis.degree, knots: basis.knots,
            controlPoints: points, weights: basis.weights)
        try result.validate(tolerance: tolerance)
        return result
    }
    private static func domain(_ curve: BSplineCurve3D) throws -> ScalarInterval {
        guard case let .closed(a, b) = curve.domain else {
            throw GeometryConversionError.invalidInput("A cyclic seam candidate requires its closed native domain.")
        }
        return try ScalarInterval(lower: a, upper: b)
    }
    private static func certificates(first: any GeometryCurveConversionSource,
        second: any GeometryCurveConversionSource, candidate: BSplineCurve3D, domain: ScalarInterval,
        tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution) throws -> [GeometryConversionGuarantee] {
        let requirements = GeometryConversionRequirements(maximumPositionError: tolerance.distance * 0.25,
            maximumTangentAngle: tolerance.angle, maximumCurvatureError: tolerance.distance,
            maximumDegree: max(3, candidate.degree))
        try execution.retainStorage(bytes: 2 * MemoryLayout<GeometryConversionGuarantee>.stride)
        let converter = CertifiedGeometryConverter()
        return [try converter.certifyCurve(source: first, candidate: candidate, over: domain,
                    requirements: requirements, tolerance: tolerance, using: &execution),
                try converter.certifyCurve(source: second, candidate: candidate, over: domain,
                    requirements: requirements, tolerance: tolerance, using: &execution)]
    }
}

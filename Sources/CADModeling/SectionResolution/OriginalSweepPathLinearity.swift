import CADCore
import CADGeometry

/// Whole original source incidence used to select straight Sweep/Pipe routes.
package struct OriginalSweepPathLinearity {
    private enum Frame: Equatable {
        case rigid(RigidTransform3D)
        case affine(AffineTransform3D)
        case word(PreparedOriginalAffineOperationWord)
    }
    private struct Axis {
        var origin: [ExactRationalCoefficient]
        var direction: [ExactRationalCoefficient]
        var frames: [Frame] = []
    }
    private struct Usage: RationalAlgebraAdmitting {
        let admission: GeometryConversionAdmission
        func consumeExactWork(_ count: Int) throws { try admission.chargeWork(count) }
        func retainExactStorage(_ count: Int) throws {
            let bytes = count.multipliedReportingOverflow(by: MemoryLayout<UInt32>.stride)
            guard count >= 0, !bytes.overflow else { throw GeometryConversionError.resourceLimitExceeded("Original straight-path exact storage overflowed.") }
            try admission.chargeStorage(bytes: bytes.partialValue)
        }
        func visitExactCell(depth: Int) throws {
            guard depth >= 0, depth <= (admission.maximumAlgebraicDepth ?? 32) else { throw GeometryConversionError.resourceLimitExceeded("Original straight-path algebra depth exhausted.") }
            try admission.chargeWork()
        }
    }
    private let tolerance: ModelingTolerance
    private let admission: GeometryConversionAdmission

    package init(tolerance: ModelingTolerance, admission: GeometryConversionAdmission? = nil) throws {
        self.tolerance = tolerance
        if let admission { self.admission = admission }
        else { self.admission = try CurvedSweepSourceBudget(tolerance: tolerance).conversionAdmission() }
    }

    package func containsOnlyLinearArms(_ spans: [ExactBSplineCurveSpan]) throws -> Bool {
        guard !spans.isEmpty else { return false }
        var usage = Usage(admission: admission)
        for span in spans {
            if try axis(for: span, usage: &usage) == nil { return false }
        }
        return true
    }

    package func isStraight(_ spans: [ExactBSplineCurveSpan]) throws -> Bool {
        guard let first = spans.first else { return false }
        var usage = Usage(admission: admission)
        guard let initial = try axis(for: first, usage: &usage) else { return false }
        for span in spans.dropFirst() {
            guard let next = try axis(for: span, usage: &usage) else { return false }
            let a: Axis, b: Axis
            try admission.chargeWork(initial.frames.count + next.frames.count + 1)
            if initial.frames == next.frames { a = initial; b = next }
            else {
                guard let firstWorld = try worldAxis(initial, usage: &usage),
                      let nextWorld = try worldAxis(next, usage: &usage) else { return false }
                a = firstWorld; b = nextWorld
            }
            var directedDot = ExactRationalCoefficient.zero
            for component in 0..<3 {
                directedDot = try directedDot.adding(a.direction[component].multiplied(by: b.direction[component], usage: &usage), usage: &usage)
                let j = (component + 1) % 3, k = (component + 2) % 3
                let parallel = try a.direction[j].multiplied(by: b.direction[k], usage: &usage)
                    .subtracting(a.direction[k].multiplied(by: b.direction[j], usage: &usage), usage: &usage)
                let displacementJ = try b.origin[j].subtracting(a.origin[j], usage: &usage)
                let displacementK = try b.origin[k].subtracting(a.origin[k], usage: &usage)
                let incident = try displacementJ.multiplied(by: a.direction[k], usage: &usage)
                    .subtracting(displacementK.multiplied(by: a.direction[j], usage: &usage), usage: &usage)
                if !parallel.isZero || !incident.isZero { return false }
            }
            if !directedDot.isPositive { return false }
        }
        return true
    }

    private func axis(for span: ExactBSplineCurveSpan, usage: inout Usage) throws -> Axis? {
        let chart = span.originalChart
        guard var result = try axis(curve: chart.curve,
            parameters: ScalarInterval(lower: min(chart.startParameter, chart.endParameter),
                upper: max(chart.startParameter, chart.endParameter)), depth: 0, usage: &usage) else { return nil }
        let fractionGain = try chart.exactLastFraction.subtracting(chart.exactFirstFraction, usage: &usage)
        guard !fractionGain.isZero else {
            throw GeometryConversionError.invalidInput("Original straight-path traversal has equal directed fractions.")
        }
        if (chart.endParameter < chart.startParameter) != fractionGain.isNegative {
            try admission.chargeStorage(bytes: 3 * MemoryLayout<ExactRationalCoefficient>.stride)
            result.direction = result.direction.map(\.negated)
        }
        return result
    }

    private func axis(curve: Curve3D, parameters: ScalarInterval, depth: Int,
        usage: inout Usage) throws -> Axis? {
        guard depth <= admission.remainingSourceDepth else {
            throw GeometryConversionError.resourceLimitExceeded("Original straight-path source nesting exhausted.")
        }
        try admission.chargeWork()
        switch curve {
        case .line(let line):
            return try axis(origin: line.origin, direction: line.direction, usage: &usage)
        case .analytic(.line(let origin, let direction)):
            return try axis(origin: origin, direction: direction, usage: &usage)
        case .bSpline(let source):
            return try nativeAxis(source, parameters: parameters, usage: &usage)
        case .originalPolyline(let source):
            return try polylineAxis(source, parameters: parameters, usage: &usage)
        case .rigidImage(let image):
            guard var result = try axis(curve: image.source, parameters: parameters, depth: depth + 1, usage: &usage) else { return nil }
            try admission.chargeStorage(bytes: MemoryLayout<Frame>.stride)
            result.frames.append(.rigid(image.transform)); return result
        case .affineImage(let image):
            guard var result = try axis(curve: image.source, parameters: parameters, depth: depth + 1, usage: &usage) else { return nil }
            try admission.chargeStorage(bytes: MemoryLayout<Frame>.stride)
            result.frames.append(.affine(image.transform)); return result
        case .originalAffineWord(let image):
            guard var result = try axis(curve: image.source, parameters: parameters, depth: depth + 1, usage: &usage) else { return nil }
            try admission.chargeStorage(bytes: MemoryLayout<Frame>.stride)
            result.frames.append(.word(image.preparedWord)); return result
        case .parameterImage(let image):
            let native = try image.originalInterval(parameters, consumeWork: { try admission.chargeWork() })
            guard var result = try axis(curve: image.source, parameters: native, depth: depth + 1, usage: &usage) else { return nil }
            let gain = try image.parameterGain.exactCoefficient(usage: &usage)
            if gain.isNegative {
                try admission.chargeStorage(bytes: 3 * MemoryLayout<ExactRationalCoefficient>.stride)
                result.direction = result.direction.map(\.negated)
            }
            return result
        case .originalConstructionChart(let image):
            switch image.chart {
            case .parameterLaw(let chart):
                guard chart.law == .affine else { return nil }
                let start = try ExactRationalCoefficient.originalDouble(chart.startParameter, usage: &usage)
                let gain = try ExactRationalCoefficient.originalDouble(chart.endParameter, usage: &usage)
                    .subtracting(start, usage: &usage)
                let first = try start.adding(gain.multiplied(by: chart.firstFraction, usage: &usage), usage: &usage)
                let last = try start.adding(gain.multiplied(by: chart.lastFraction, usage: &usage), usage: &usage)
                let firstBox = try first.outwardInterval(usage: &usage)
                let lastBox = try last.outwardInterval(usage: &usage)
                guard var result = try axis(curve: chart.source,
                    parameters: ScalarInterval(lower: min(firstBox.lower, lastBox.lower),
                        upper: max(firstBox.upper, lastBox.upper)), depth: depth + 1, usage: &usage) else { return nil }
                let directed = try last.subtracting(first, usage: &usage)
                if directed.isNegative {
                    try admission.chargeStorage(bytes: 3 * MemoryLayout<ExactRationalCoefficient>.stride)
                    result.direction = result.direction.map(\.negated)
                }
                return result
            case .traversal(let traversal):
                if case .authored(let first) = traversal.start,
                   case .authored(let last) = traversal.end {
                    guard var result = try axis(curve: traversal.source,
                        parameters: ScalarInterval(lower: min(first, last), upper: max(first, last)),
                        depth: depth + 1, usage: &usage) else { return nil }
                    if last < first {
                        try admission.chargeStorage(bytes: 3 * MemoryLayout<ExactRationalCoefficient>.stride)
                        result.direction = result.direction.map(\.negated)
                    }
                    return result
                }
                // FIXME(INCOMPLETE_IMPLEMENTATION): Algebraic-root normalized
                // line traversal needs retained exact endpoint ordering/axis
                // transport. Original closed boxes cannot become an exact
                // station; the original curved route remains selected.
                return nil
            }
        case .circle, .analytic, .originalAngularTransport:
            return nil
        case .implicit, .surfaceLift, .certifiedIntersection, .originalEndpointConnector, .originalPlaneDerivative, .originalDrafted,
             .originalGuideTraversalChain, .originalGuideEndpointConnector:
            // FIXME(INCOMPLETE_IMPLEMENTATION): Sweep/Pipe source dispatch must
            // consume an original complete incidence producer for these charts.
            // Candidate line-like coefficients cannot authorize straight arms;
            // the certified original curved route remains selected meanwhile.
            return nil
        }
    }

    private func axis(origin: Point3D, direction: Vector3D, usage: inout Usage) throws -> Axis {
        try admission.chargeStorage(bytes: 6 * MemoryLayout<ExactRationalCoefficient>.stride)
        return Axis(origin: [try .originalDouble(origin.x, usage: &usage),
            try .originalDouble(origin.y, usage: &usage), try .originalDouble(origin.z, usage: &usage)],
            direction: [try .originalDouble(direction.x, usage: &usage),
                try .originalDouble(direction.y, usage: &usage), try .originalDouble(direction.z, usage: &usage)])
    }

    private func polylineAxis(_ source: OriginalPolylineCurve3D, parameters: ScalarInterval,
        usage: inout Usage) throws -> Axis? {
        guard !source.isClosed, parameters.lower >= 0, parameters.upper <= 1,
            parameters.lower < parameters.upper, let first = source.points.first,
            let last = source.points.last, source.points.count > 1 else { return nil }
        func point(_ value: Point3D, usage: inout Usage) throws -> [ExactRationalCoefficient] {
            try admission.chargeStorage(bytes: 3 * MemoryLayout<ExactRationalCoefficient>.stride)
            return [try .originalDouble(value.x, usage: &usage),
                try .originalDouble(value.y, usage: &usage), try .originalDouble(value.z, usage: &usage)]
        }
        let start = try point(first, usage: &usage), end = try point(last, usage: &usage)
        try admission.chargeStorage(bytes: 3 * MemoryLayout<ExactRationalCoefficient>.stride)
        var direction: [ExactRationalCoefficient] = []; direction.reserveCapacity(3)
        for index in 0..<3 {
            direction.append(try end[index].subtracting(start[index], usage: &usage))
        }
        guard direction.contains(where: { !$0.isZero }) else { return nil }
        var previous = start
        for raw in source.points.dropFirst() {
            try admission.chargeWork()
            let next = try point(raw, usage: &usage)
            try admission.chargeStorage(bytes: 3 * MemoryLayout<ExactRationalCoefficient>.stride)
            var displacement: [ExactRationalCoefficient] = []; displacement.reserveCapacity(3)
            for index in 0..<3 {
                displacement.append(try next[index].subtracting(previous[index], usage: &usage))
            }
            var dot = ExactRationalCoefficient.zero
            for index in 0..<3 {
                dot = try dot.adding(displacement[index].multiplied(by: direction[index], usage: &usage), usage: &usage)
                let j = (index + 1) % 3, k = (index + 2) % 3
                let cross = try displacement[j].multiplied(by: direction[k], usage: &usage)
                    .subtracting(displacement[k].multiplied(by: direction[j], usage: &usage), usage: &usage)
                if !cross.isZero { return nil }
            }
            if displacement.contains(where: { !$0.isZero }), !dot.isPositive { return nil }
            previous = next
        }
        return Axis(origin: start, direction: direction)
    }

    private func nativeAxis(_ source: BSplineCurve3D, parameters: ScalarInterval,
        usage: inout Usage) throws -> Axis? {
        guard case let .closed(lower, upper) = source.domain,
              parameters.lower >= lower, parameters.upper <= upper else {
            // FIXME(INCOMPLETE_IMPLEMENTATION): Periodic translated native
            // incidence needs its retained lifted source chart; base-cover
            // coefficients cannot authorize a foreign periodic trim.
            return nil
        }
        var ownerCount = 0
        for index in source.degree..<source.controlPoints.count {
            try admission.chargeWork()
            if source.knots[index] < source.knots[index + 1],
               source.knots[index + 1] > parameters.lower, source.knots[index] < parameters.upper {
                ownerCount += 1
                guard ownerCount <= admission.maximumSpanCount else {
                    throw GeometryConversionError.resourceLimitExceeded("Original straight-path owning span count exhausted.")
                }
            }
        }
        try admission.chargeStorage(bytes: ownerCount * MemoryLayout<OriginalRationalCurvePolynomial>.stride)
        var owners: [OriginalRationalCurvePolynomial] = []
        owners.reserveCapacity(ownerCount)
        for index in source.degree..<source.controlPoints.count {
            try admission.chargeWork()
            if source.knots[index] < source.knots[index + 1],
               source.knots[index + 1] > parameters.lower, source.knots[index] < parameters.upper {
                guard owners.count < admission.maximumSpanCount else {
                    throw GeometryConversionError.resourceLimitExceeded("Original straight-path owning span count exhausted.")
                }
                try usage.visitExactCell(depth: 0)
                owners.append(try OriginalRationalCurvePolynomial(source: source,
                    spanIndex: index, tolerance: tolerance, usage: &usage))
            }
        }
        guard let first = owners.first, let last = owners.last else { return nil }
        func point(_ law: OriginalRationalCurvePolynomial, at parameter: Double,
            usage: inout Usage) throws -> [ExactRationalCoefficient] {
            let station = try ExactRationalCoefficient.originalDouble(parameter, usage: &usage)
            let weight = try law.homogeneous[3].evaluated(atU: station, v: .zero, usage: &usage)
            guard weight.isPositive else { throw GeometryConversionError.invalidInput("Original line incidence requires positive homogeneous endpoint weight.") }
            try admission.chargeStorage(bytes: 3 * MemoryLayout<ExactRationalCoefficient>.stride)
            return try (0..<3).map { index in
                try law.homogeneous[index].evaluated(atU: station, v: .zero, usage: &usage)
                    .divided(by: weight, usage: &usage)
            }
        }
        let start = try point(first, at: parameters.lower, usage: &usage)
        let end = try point(last, at: parameters.upper, usage: &usage)
        try admission.chargeStorage(bytes: 3 * MemoryLayout<ExactRationalCoefficient>.stride)
        var direction: [ExactRationalCoefficient] = []; direction.reserveCapacity(3)
        for index in 0..<3 { direction.append(try end[index].subtracting(start[index], usage: &usage)) }
        guard direction.contains(where: { !$0.isZero }) else { return nil }
        for (ownerIndex, owner) in owners.enumerated() {
            if ownerIndex > 0 {
                let prior = owners[ownerIndex - 1]
                let parameter = source.knots[owner.spanIndex]
                let left = try point(prior, at: parameter, usage: &usage)
                let right = try point(owner, at: parameter, usage: &usage)
                for component in 0..<3 {
                    try admission.chargeWork()
                    if left[component] != right[component] { return nil }
                }
            }
            for component in 0..<3 {
                let j = (component + 1) % 3, k = (component + 2) % 3
                let a = try owner.homogeneous[j].subtracting(owner.homogeneous[3].scaled(by: start[j], usage: &usage), usage: &usage)
                let b = try owner.homogeneous[k].subtracting(owner.homogeneous[3].scaled(by: start[k], usage: &usage), usage: &usage)
                let cross = try a.scaled(by: direction[k], usage: &usage)
                    .subtracting(b.scaled(by: direction[j], usage: &usage), usage: &usage)
                if !cross.isZero { return nil }
            }
            let derivatives = try OriginalRationalCurveDerivativeLaw(original: owner,
                throughOrder: 1, usage: &usage)
            var speed = ExactBivariatePolynomial.zero
            for component in 0..<3 {
                speed = try speed.adding(derivatives.numerators[1][component]
                    .scaled(by: direction[component], usage: &usage), usage: &usage)
            }
            guard !speed.isZero else { return nil }
            let lower = try ExactRationalCoefficient.originalDouble(
                max(parameters.lower, source.knots[owner.spanIndex]), usage: &usage)
            let upper = try ExactRationalCoefficient.originalDouble(
                min(parameters.upper, source.knots[owner.spanIndex + 1]), usage: &usage)
            if try speed.evaluated(atU: lower, v: .zero, usage: &usage).isNegative
                || speed.evaluated(atU: upper, v: .zero, usage: &usage).isNegative { return nil }
            let critical = try speed.differentiated(alongU: true, usage: &usage)
            if !critical.isZero {
                let roots = try ExactUnivariateRootIsolator().isolate(critical,
                    lower: lower, upper: upper, maximumDepth: admission.maximumAlgebraicDepth ?? 32, usage: &usage)
                for isolation in roots {
                    let root = try ExactAlgebraicRealRoot(polynomial: critical,
                        isolation: isolation, usage: &usage)
                    if try root.sign(of: speed, maximumDepth: admission.maximumAlgebraicDepth ?? 32, usage: &usage) == .negative { return nil }
                }
            }
        }
        return Axis(origin: start, direction: direction)
    }

    private func worldAxis(_ axis: Axis, usage: inout Usage) throws -> Axis? {
        var result = axis
        for frame in axis.frames {
            if case .word(let word) = frame {
                for factor in word.source.factors {
                    try admission.chargeWork()
                    switch factor {
                    case .normalizedForward, .normalizedInverse:
                        // FIXME(INCOMPLETE_IMPLEMENTATION): Distinct algebraic
                        // image words need an exact ordered-field line relation;
                        // interval coefficient coincidence is not that proof.
                        return nil
                    case .forward, .inverse, .rationalForward, .rationalInverse: break
                    }
                }
            }
            func coordinate(_ vector: Vector3D, _ component: Int) -> Double {
                switch component { case 0: vector.x; case 1: vector.y; default: vector.z }
            }
            func translation(row: Int, usage: inout Usage) throws -> ExactRationalCoefficient {
                switch frame {
                case .word(let word): return try word.translationCoefficient(row: row)
                case .rigid(let transform): return try .originalDouble(coordinate(transform.translation, row), usage: &usage)
                case .affine(let transform): return try .originalDouble(coordinate(transform.translation, row), usage: &usage)
                }
            }
            func coefficient(row: Int, column: Int, usage: inout Usage) throws -> ExactRationalCoefficient {
                let vector: Vector3D
                switch frame {
                case .word(let word): return try word.linearCoefficient(row: row, column: column)
                case .rigid(let transform):
                    vector = column == 0 ? transform.basisX : column == 1 ? transform.basisY : transform.basisZ
                case .affine(let transform):
                    vector = column == 0 ? transform.basisX : column == 1 ? transform.basisY : transform.basisZ
                }
                return try .originalDouble(coordinate(vector, row), usage: &usage)
            }
            try admission.chargeStorage(bytes: 6 * MemoryLayout<ExactRationalCoefficient>.stride)
            var origin: [ExactRationalCoefficient] = [], direction: [ExactRationalCoefficient] = []
            origin.reserveCapacity(3); direction.reserveCapacity(3)
            for row in 0..<3 {
                var p = try translation(row: row, usage: &usage)
                var d = ExactRationalCoefficient.zero
                for column in 0..<3 {
                    let entry = try coefficient(row: row, column: column, usage: &usage)
                    p = try p.adding(entry.multiplied(by: result.origin[column], usage: &usage), usage: &usage)
                    d = try d.adding(entry.multiplied(by: result.direction[column], usage: &usage), usage: &usage)
                }
                origin.append(p); direction.append(d)
            }
            result.origin = origin; result.direction = direction
        }
        result.frames = []
        return result
    }
}

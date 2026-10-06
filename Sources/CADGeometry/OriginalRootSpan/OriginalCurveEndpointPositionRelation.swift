import CADCore

/// Exact original endpoint equality without numerical point coincidence.
package struct OriginalCurveEndpointPositionRelation: Sendable {
    package let first: Curve3D
    package let firstParameter: Double
    package let firstNativeSpanIndex: Int?
    package let second: Curve3D
    package let secondParameter: Double
    package let secondNativeSpanIndex: Int?
    package let tolerance: ModelingTolerance
    private init(first: Curve3D, firstParameter: Double, second: Curve3D,
        secondParameter: Double, firstNativeSpanIndex: Int?, secondNativeSpanIndex: Int?, tolerance: ModelingTolerance) {
        self.first = first; self.firstParameter = firstParameter
        self.second = second; self.secondParameter = secondParameter
        self.firstNativeSpanIndex = firstNativeSpanIndex; self.secondNativeSpanIndex = secondNativeSpanIndex
        self.tolerance = tolerance
    }

    /// Nil means a proved unequal original position; missing authority throws.
    package static func prove<B: RationalAlgebraAdmitting>(first: Curve3D, at firstParameter: Double,
        second: Curve3D, at secondParameter: Double,
        firstNativeSpanIndex: Int? = nil, secondNativeSpanIndex: Int? = nil, remainingSourceDepth: Int,
        maximumSubdivisionDepth: Int, tolerance: ModelingTolerance,
        storageByteStride: Int = MemoryLayout<UInt32>.stride, usage: inout B,
        maximumAlgebraicDepth: Int? = nil) throws -> Self? {
        guard storageByteStride > 0, maximumAlgebraicDepth.map({ (0...32).contains($0) }) ?? true else {
            throw GeometryConversionError.invalidInput("Original endpoint storage stride must be positive.")
        }
        func bytes(_ count: Int) throws {
            try retainBytes(count, stride: storageByteStride, usage: &usage)
        }
        try withoutActuallyEscaping(bytes) { storage in
            try first.validateOriginalSource(tolerance: tolerance, remainingSourceDepth: remainingSourceDepth,
                maximumSubdivisionDepth: maximumSubdivisionDepth, consumeWork: { _ in try usage.consumeExactWork(1) }, consumeStorage: storage,
                maximumAlgebraicDepth: maximumAlgebraicDepth)
            try second.validateOriginalSource(tolerance: tolerance, remainingSourceDepth: remainingSourceDepth,
                maximumSubdivisionDepth: maximumSubdivisionDepth, consumeWork: { _ in try usage.consumeExactWork(1) }, consumeStorage: storage,
                maximumAlgebraicDepth: maximumAlgebraicDepth)
        }
        guard firstParameter.isFinite, secondParameter.isFinite else {
            throw GeometryConversionError.invalidInput("Original endpoint stations must be finite.")
        }
        if firstParameter == secondParameter, firstNativeSpanIndex == secondNativeSpanIndex {
            try GeometryStructuralComparisonWork.charge(curve: first, using: { try usage.consumeExactWork($0) })
            try GeometryStructuralComparisonWork.charge(curve: second, using: { try usage.consumeExactWork($0) })
            if first == second {
                var admitted = true
                switch first.parameterDomain {
                case .closed(let lower, let upper): admitted = firstParameter >= lower && firstParameter <= upper
                case .periodic, .unbounded: break
                }
                if let index = firstNativeSpanIndex {
                    if case .bSpline(let spline) = first {
                        admitted = admitted && index >= spline.degree && index < spline.controlPoints.count
                        if admitted {
                            admitted = spline.knots[index] < spline.knots[index + 1]
                                && firstParameter >= spline.knots[index] && firstParameter <= spline.knots[index + 1]
                        }
                    } else { admitted = false }
                }
                if admitted {
                    return .init(first: first, firstParameter: firstParameter, second: second,
                        secondParameter: secondParameter, firstNativeSpanIndex: firstNativeSpanIndex,
                        secondNativeSpanIndex: secondNativeSpanIndex, tolerance: tolerance)
                }
            }
        }
        if try OriginalConstructionChartEndpointRelation.matches(first: first, at: firstParameter,
            second: second, at: secondParameter, remainingSourceDepth: remainingSourceDepth,
            tolerance: tolerance, usage: &usage) {
            return .init(first: first, firstParameter: firstParameter, second: second,
                secondParameter: secondParameter, firstNativeSpanIndex: firstNativeSpanIndex,
                secondNativeSpanIndex: secondNativeSpanIndex, tolerance: tolerance)
        }
        if let a = try retainedEndpoint(of: first, at: firstParameter,
                remainingSourceDepth: remainingSourceDepth, usage: &usage),
            let b = try retainedEndpoint(of: second, at: secondParameter,
                remainingSourceDepth: remainingSourceDepth, usage: &usage) {
            guard try OriginalCurveTraversalEndpointRelation().proves(first: a.boundary,
                firstAtEnd: a.atEnd, second: b.boundary, secondAtEnd: b.atEnd,
                remainingSourceDepth: remainingSourceDepth - 1,
                maximumSubdivisionDepth: maximumSubdivisionDepth, storageByteStride: storageByteStride, usage: &usage,
                maximumAlgebraicDepth: maximumAlgebraicDepth) else { return nil }
            return .init(first: first, firstParameter: firstParameter, second: second,
                secondParameter: secondParameter, firstNativeSpanIndex: firstNativeSpanIndex,
                secondNativeSpanIndex: secondNativeSpanIndex, tolerance: tolerance)
        }
        if firstNativeSpanIndex == nil, secondNativeSpanIndex == nil,
            try hasSamePhysicalAngularStation(first: first, at: .originalDouble(firstParameter, usage: &usage),
                second: second, at: .originalDouble(secondParameter, usage: &usage),
                remainingSourceDepth: remainingSourceDepth, usage: &usage) {
            return .init(first: first, firstParameter: firstParameter, second: second,
                secondParameter: secondParameter, firstNativeSpanIndex: nil, secondNativeSpanIndex: nil, tolerance: tolerance)
        }
        if try hasSameIdealPeriodicStation(first: first, at: .originalDouble(firstParameter, usage: &usage),
            second: second, at: .originalDouble(secondParameter, usage: &usage),
            remainingSourceDepth: remainingSourceDepth, usage: &usage) {
            return .init(first: first, firstParameter: firstParameter, second: second,
                secondParameter: secondParameter, firstNativeSpanIndex: firstNativeSpanIndex,
                secondNativeSpanIndex: secondNativeSpanIndex, tolerance: tolerance)
        }
        let a = try coordinates(first, at: .originalDouble(firstParameter, usage: &usage),
            owningSpanIndex: firstNativeSpanIndex, remainingSourceDepth: remainingSourceDepth, tolerance: tolerance, storageByteStride: storageByteStride, usage: &usage)
        let b = try coordinates(second, at: .originalDouble(secondParameter, usage: &usage),
            owningSpanIndex: secondNativeSpanIndex, remainingSourceDepth: remainingSourceDepth, tolerance: tolerance, storageByteStride: storageByteStride, usage: &usage)
        for axis in 0..<3 {
            try usage.consumeExactWork(1)
            if a[axis] != b[axis] { return nil }
        }
        return .init(first: first, firstParameter: firstParameter, second: second,
            secondParameter: secondParameter, firstNativeSpanIndex: firstNativeSpanIndex,
            secondNativeSpanIndex: secondNativeSpanIndex, tolerance: tolerance)
    }

    private static func retainBytes<B: RationalAlgebraAdmitting>(_ bytes: Int, stride: Int,
        usage: inout B) throws {
        let rounded = bytes.addingReportingOverflow(stride - 1)
        guard bytes >= 0, stride > 0, !rounded.overflow else {
            throw GeometryConversionError.resourceLimitExceeded("Original endpoint storage conversion overflows.")
        }
        try usage.retainExactStorage(rounded.partialValue / stride)
    }

    private static func hasSamePhysicalAngularStation<B: RationalAlgebraAdmitting>(first: Curve3D,
        at a: ExactRationalCoefficient, second: Curve3D, at b: ExactRationalCoefficient,
        remainingSourceDepth: Int, usage: inout B) throws -> Bool {
        try GeometryStructuralComparisonWork.charge(curve: first, using: { try usage.consumeExactWork($0) })
        try GeometryStructuralComparisonWork.charge(curve: second, using: { try usage.consumeExactWork($0) })
        guard first == second else { return false }
        func angle(_ curve: Curve3D, _ station: ExactRationalCoefficient, _ depth: Int, usage: inout B) throws -> ExactRationalCoefficient? {
            try usage.consumeExactWork(1)
            guard depth >= 0 else { throw GeometryConversionError.resourceLimitExceeded("Original physical endpoint exhausted source depth.") }
            switch curve {
            case .originalAngularTransport(let image):
                switch image.transport {
                case .intrinsic: return nil
                case .physicalRadians(let gain, let offset): return try gain.multiplied(by: station, usage: &usage).adding(offset, usage: &usage)
                case .physicalRadianArc(let start, let end, _):
                    if station.isZero { return start }; if station == .one { return end }; return nil
                }
            case .originalAffineWord(let image): return try angle(image.source, station, depth - 1, usage: &usage)
            case .affineImage(let image): return try angle(image.source, station, depth - 1, usage: &usage)
            case .rigidImage(let image): return try angle(image.source, station, depth - 1, usage: &usage)
            case .parameterImage(let image):
                let mapped = try image.parameterGain.exactCoefficient(usage: &usage).multiplied(by: station, usage: &usage)
                    .adding(.originalDouble(image.offset, usage: &usage), usage: &usage)
                return try angle(image.source, mapped, depth - 1, usage: &usage)
            case .originalConstructionChart(let image):
                guard case .parameterLaw(let chart) = image.chart, chart.law == .affine else { return nil }
                let fraction = try chart.firstFraction.adding(chart.lastFraction.subtracting(chart.firstFraction, usage: &usage)
                    .multiplied(by: station, usage: &usage), usage: &usage)
                let start = try ExactRationalCoefficient.originalDouble(chart.startParameter, usage: &usage)
                let mapped = try start.adding(ExactRationalCoefficient.originalDouble(chart.endParameter, usage: &usage)
                    .subtracting(start, usage: &usage).multiplied(by: fraction, usage: &usage), usage: &usage)
                return try angle(chart.source, mapped, depth - 1, usage: &usage)
            default: return nil
            }
        }
        guard let x = try angle(first, a, remainingSourceDepth, usage: &usage),
            let y = try angle(second, b, remainingSourceDepth, usage: &usage) else { return false }
        return x == y
    }

    private static func hasSameIdealPeriodicStation<B: RationalAlgebraAdmitting>(first: Curve3D,
        at a: ExactRationalCoefficient, second: Curve3D, at b: ExactRationalCoefficient,
        remainingSourceDepth: Int, usage: inout B) throws -> Bool {
        func native(_ curve: Curve3D, _ station: ExactRationalCoefficient, _ depth: Int,
            usage: inout B) throws -> (Curve3D, ExactRationalCoefficient)? {
            try usage.consumeExactWork(1)
            switch curve {
            case .circle, .analytic(.circle), .analytic(.ellipse): return (curve, station)
            case .originalConstructionChart(let image):
                guard depth > 0 else {
                    throw GeometryConversionError.resourceLimitExceeded("Original phase endpoint exhausted source depth.")
                }
                guard case .parameterLaw(let chart) = image.chart else { return nil }
                let fraction = try chart.firstFraction.adding(chart.lastFraction.subtracting(chart.firstFraction, usage: &usage)
                    .multiplied(by: station, usage: &usage), usage: &usage)
                let label: ExactRationalCoefficient
                if fraction.isZero { label = try .originalDouble(chart.startParameter, usage: &usage) }
                else if fraction == .one { label = try .originalDouble(chart.endParameter, usage: &usage) }
                else if chart.law == .affine {
                    let start = try ExactRationalCoefficient.originalDouble(chart.startParameter, usage: &usage)
                    label = try start.adding(ExactRationalCoefficient.originalDouble(chart.endParameter, usage: &usage)
                        .subtracting(start, usage: &usage).multiplied(by: fraction, usage: &usage), usage: &usage)
                } else { return nil }
                return try native(chart.source, label, depth - 1, usage: &usage)
            default: return nil
            }
        }
        guard let x = try native(first, a, remainingSourceDepth, usage: &usage),
            let y = try native(second, b, remainingSourceDepth, usage: &usage) else { return false }
        try GeometryStructuralComparisonWork.charge(curve: x.0, using: { try usage.consumeExactWork($0) })
        try GeometryStructuralComparisonWork.charge(curve: y.0, using: { try usage.consumeExactWork($0) })
        guard x.0 == y.0 else { return false }
        let turns = try x.1.subtracting(y.1, usage: &usage)
            .divided(by: .originalDouble(2 * Double.pi, usage: &usage), usage: &usage)
        return turns.canonicalDenominatorWords == [1]
    }

    /// Borrows symbolic endpoint incidence without evaluating a point candidate.
    package static func retainedEndpoint<B: RationalAlgebraAdmitting>(of source: Curve3D,
        at parameter: Double, remainingSourceDepth: Int, usage: inout B)
        throws -> (boundary: OriginalCurveRootSpan3D, atEnd: Bool)? {
        try usage.consumeExactWork(1)
        guard remainingSourceDepth >= 0, parameter.isFinite else {
            throw GeometryConversionError.invalidInput("Original symbolic endpoint requires finite station and source capability.")
        }
        let endpoint: (boundary: OriginalCurveRootSpan3D, atEnd: Bool)?
        switch source {
        case .originalGuideTraversalChain(let chain): endpoint = chain.originalEndpoint(at: parameter)
        case .originalGuideEndpointConnector(let connector): endpoint = connector.originalEndpoint(at: parameter)
        case .originalEndpointConnector(let connector): endpoint = connector.originalEndpoint(at: parameter)
        case .originalPlaneDerivative(let curve):
            endpoint = parameter == 0 || parameter == 1 ? (curve.source, parameter == 1) : nil
        case .originalConstructionChart(let image):
            if case .traversal(let traversal) = image.chart, parameter == 0 || parameter == 1 {
                endpoint = (traversal, parameter == 1)
            } else { endpoint = nil }
        default: endpoint = nil
        }
        guard let endpoint else { return nil }
        guard remainingSourceDepth > 0 else {
            throw GeometryConversionError.resourceLimitExceeded("Original symbolic endpoint exhausted source depth.")
        }
        return endpoint
    }

    package static func coordinates<B: RationalAlgebraAdmitting>(_ source: Curve3D,
        at station: ExactRationalCoefficient, owningSpanIndex: Int? = nil, remainingSourceDepth: Int,
        tolerance: ModelingTolerance, storageByteStride: Int = MemoryLayout<UInt32>.stride,
        usage: inout B) throws -> [ExactRationalCoefficient] {
        try CurrentTaskCancellationChecker().checkCancellation(); try usage.consumeExactWork(1)
        guard remainingSourceDepth >= 0 else {
            throw GeometryConversionError.resourceLimitExceeded("Original endpoint relation exhausted source depth.")
        }
        func child(_ curve: Curve3D, _ station: ExactRationalCoefficient) throws -> [ExactRationalCoefficient] {
            guard remainingSourceDepth > 0 else {
                throw GeometryConversionError.resourceLimitExceeded("Original endpoint image exhausted source depth.")
            }
            return try coordinates(curve, at: station, owningSpanIndex: owningSpanIndex, remainingSourceDepth: remainingSourceDepth - 1,
                tolerance: tolerance, storageByteStride: storageByteStride, usage: &usage)
        }
        func linear(_ origin: Point3D, _ direction: Vector3D) throws -> [ExactRationalCoefficient] {
            try retainBytes(3 * MemoryLayout<ExactRationalCoefficient>.stride, stride: storageByteStride, usage: &usage)
            var result: [ExactRationalCoefficient] = []
            result.reserveCapacity(3)
            for axis in 0..<3 {
                let o = axis == 0 ? origin.x : axis == 1 ? origin.y : origin.z
                let d = axis == 0 ? direction.x : axis == 1 ? direction.y : direction.z
                result.append(try ExactRationalCoefficient.originalDouble(o, usage: &usage)
                    .adding(ExactRationalCoefficient.originalDouble(d, usage: &usage)
                        .multiplied(by: station, usage: &usage), usage: &usage))
            }
            return result
        }
        func transformed(_ q: [ExactRationalCoefficient], _ x: Vector3D, _ y: Vector3D,
            _ z: Vector3D, _ t: Vector3D) throws -> [ExactRationalCoefficient] {
            try retainBytes(3 * MemoryLayout<ExactRationalCoefficient>.stride, stride: storageByteStride, usage: &usage)
            var result: [ExactRationalCoefficient] = []
            result.reserveCapacity(3)
            for axis in 0..<3 {
                let shift = axis == 0 ? t.x : axis == 1 ? t.y : t.z
                var value = try ExactRationalCoefficient.originalDouble(shift, usage: &usage)
                for column in 0..<3 {
                    let vector = column == 0 ? x : column == 1 ? y : z
                    let component = axis == 0 ? vector.x : axis == 1 ? vector.y : vector.z
                    value = try value.adding(q[column].multiplied(by:
                        .originalDouble(component, usage: &usage), usage: &usage), usage: &usage)
                }
                result.append(value)
            }
            return result
        }
        switch source {
        case .originalConstructionChart(let image):
            guard remainingSourceDepth > 0 else {
                throw GeometryConversionError.resourceLimitExceeded("Original chart endpoint exhausted source depth.")
            }
            switch image.chart {
            case .parameterLaw(let chart):
                let fraction = try chart.firstFraction.adding(
                    chart.lastFraction.subtracting(chart.firstFraction, usage: &usage)
                        .multiplied(by: station, usage: &usage), usage: &usage)
                let native: ExactRationalCoefficient
                if fraction.isZero { native = try .originalDouble(chart.startParameter, usage: &usage) }
                else if fraction == .one { native = try .originalDouble(chart.endParameter, usage: &usage) }
                else if chart.law == .affine {
                    let start = try ExactRationalCoefficient.originalDouble(chart.startParameter, usage: &usage)
                    native = try start.adding(ExactRationalCoefficient.originalDouble(chart.endParameter, usage: &usage)
                        .subtracting(start, usage: &usage).multiplied(by: fraction, usage: &usage), usage: &usage)
                } else {
                    // FIXME(INCOMPLETE_IMPLEMENTATION): Interior nonlinear chart
                    // endpoint consumers need exact symbolic coordinate equality;
                    // the closed station enclosure cannot provide that authority.
                    throw KernelError(phase: .geometry, code: .unsupportedCapability, tolerance: tolerance,
                        message: "Original nonlinear chart coordinate requires a symbolic endpoint relation.")
                }
                return try child(chart.source, native)
            case .traversal(let traversal):
                guard station.isZero || station == .one else {
                    // FIXME(INCOMPLETE_IMPLEMENTATION): Algebraic affine root
                    // traversal interior coordinate expressions require retained
                    // ordered-field transport before rational XYZ may succeed.
                    throw KernelError(phase: .geometry, code: .unsupportedCapability, tolerance: tolerance,
                        message: "Original traversal rational coordinate is available only at authored endpoints.")
                }
                let endpoint = station.isZero ? traversal.start : traversal.end
                guard case .authored(let native) = endpoint else {
                    throw KernelError(phase: .geometry, code: .unsupportedCapability, tolerance: tolerance,
                        message: "Original algebraic traversal endpoint requires retained root coordinate transport.")
                }
                return try coordinates(traversal.source, at: .originalDouble(native, usage: &usage),
                    owningSpanIndex: traversal.nativeSpanIndex,
                    remainingSourceDepth: min(remainingSourceDepth - 1, traversal.remainingSourceDepth),
                    tolerance: traversal.certificationTolerance, storageByteStride: storageByteStride, usage: &usage)
            }
        case .originalPolyline(let original):
            let point: Point3D
            if station.isZero { point = original.points[0] }
            else if station == .one { point = original.points[original.points.count-1] }
            else {
                // FIXME(INCOMPLETE_IMPLEMENTATION): Exact interior polyline
                // endpoint comparison needs the retained Euclidean field clock;
                // rational XYZ alone cannot substitute a numerical station.
                throw KernelError(phase: .geometry, code: .unsupportedCapability, tolerance: tolerance,
                    message: "Original polyline interior endpoint requires its field clock receipt.")
            }
            try retainBytes(3 * MemoryLayout<ExactRationalCoefficient>.stride, stride: storageByteStride, usage: &usage)
            return try [.originalDouble(point.x, usage: &usage), .originalDouble(point.y, usage: &usage),
                .originalDouble(point.z, usage: &usage)]
        case .originalDrafted:
            // FIXME(INCOMPLETE_IMPLEMENTATION): Drafted endpoint coordinates
            // retain a tangent-dependent quadratic ruling. Exact source endpoint
            // position relation must consume that law before this path can prove
            // equality; neither generator points nor numerical draft samples suffice.
            throw KernelError(phase: .geometry, code: .unsupportedCapability, tolerance: tolerance,
                message: "Original drafted endpoint relation has no exact ruling coefficient issuer.")
        case .originalEndpointConnector, .originalPlaneDerivative, .originalGuideTraversalChain, .originalGuideEndpointConnector:
            let parameter: Double
            if station.isZero { parameter = 0 }
            else if station == .one { parameter = 1 }
            else {
                // FIXME(INCOMPLETE_IMPLEMENTATION): General endpoint consumers
                // need exact corrected polynomial coordinates at interior
                // connector stations before rational equality may succeed.
                throw KernelError(phase: .geometry, code: .unsupportedCapability, tolerance: tolerance,
                    message: "Original connector interior has no rational endpoint-coordinate receipt.")
            }
            guard let retained = try retainedEndpoint(of: source, at: parameter,
                remainingSourceDepth: remainingSourceDepth, usage: &usage) else {
                throw GeometryConversionError.invalidInput("Original connector station is not a retained endpoint.")
            }
            let endpoint = retained.atEnd ? retained.boundary.end : retained.boundary.start
            guard case .authored(let original) = endpoint else {
                // FIXME(INCOMPLETE_IMPLEMENTATION): Algebraic connector
                // endpoints retain their original root; rational XYZ alone
                // cannot replace that coordinate-image authority.
                throw KernelError(phase: .geometry, code: .unsupportedCapability, tolerance: tolerance,
                    message: "Original algebraic connector endpoint requires root-coordinate transport.")
            }
            return try coordinates(retained.boundary.source,
                at: .originalDouble(original, usage: &usage), owningSpanIndex: retained.boundary.nativeSpanIndex,
                remainingSourceDepth: min(remainingSourceDepth - 1, retained.boundary.remainingSourceDepth),
                tolerance: retained.boundary.certificationTolerance, storageByteStride: storageByteStride, usage: &usage)
        case .line(let line): return try linear(line.origin, line.direction)
        case .analytic(.line(let origin, let direction)): return try linear(origin, direction)
        case .parameterImage(let image):
            let native = try station.multiplied(by: image.parameterGain.exactCoefficient(usage: &usage), usage: &usage)
                .adding(.originalDouble(image.offset, usage: &usage), usage: &usage)
            return try child(image.source, native)
        case .rigidImage(let image):
            let q = try child(image.source, station), t = image.transform
            return try transformed(q, t.basisX, t.basisY, t.basisZ, t.translation)
        case .affineImage(let image):
            let q = try child(image.source, station), t = image.transform
            return try transformed(q, t.basisX, t.basisY, t.basisZ, t.translation)
        case .originalAffineWord(let image):
            let q = try child(image.source, station)
            try retainBytes(3 * MemoryLayout<ExactRationalCoefficient>.stride, stride: storageByteStride, usage: &usage)
            var result: [ExactRationalCoefficient] = []
            result.reserveCapacity(3)
            for axis in 0..<3 {
                try usage.consumeExactWork(1)
                // FIXME(INCOMPLETE_IMPLEMENTATION): Exact endpoint/corner
                // consumers currently transport rational word coefficients.
                // Normalized algebraic words need retained ordered-field
                // coordinate equality before this rational issuer may succeed.
                var value = try image.preparedWord.translationCoefficient(row: axis)
                for column in 0..<3 {
                    value = try value.adding(q[column].multiplied(by:
                        image.preparedWord.linearCoefficient(row: axis, column: column),
                        usage: &usage), usage: &usage)
                }
                result.append(value)
            }
            return result
        case .bSpline(let spline):
            var selected: Int?
            let candidates: Range<Int>
            if let index = owningSpanIndex {
                guard index >= spline.degree, index < spline.controlPoints.count,
                      spline.knots[index] < spline.knots[index + 1] else {
                    throw GeometryConversionError.invalidInput("Original endpoint selected side is not a positive native owner.")
                }
                candidates = index..<(index + 1)
            } else { candidates = spline.degree..<spline.controlPoints.count }
            for index in candidates {
                try usage.consumeExactWork(1)
                if spline.knots[index] >= spline.knots[index + 1] { continue }
                let lower = try ExactRationalCoefficient.originalDouble(spline.knots[index], usage: &usage)
                let upper = try ExactRationalCoefficient.originalDouble(spline.knots[index + 1], usage: &usage)
                if try station.subtracting(lower, usage: &usage).isNegative { continue }
                if try upper.subtracting(station, usage: &usage).isNegative { continue }
                selected = index; break
            }
            guard let selected else {
                // FIXME(INCOMPLETE_IMPLEMENTATION): General endpoint repair and
                // closed-edge classification need retained exact periodic lifts
                // outside the base knot cover before those stations may succeed.
                throw GeometryConversionError.invalidInput("Original endpoint lies outside the retained native knot cover.")
            }
            let polynomial = try OriginalRationalCurvePolynomial(source: spline, spanIndex: selected,
                tolerance: tolerance, usage: &usage)
            let weight = try polynomial.homogeneous[3].evaluated(atU: station, v: .zero, usage: &usage)
            guard weight.isPositive else {
                throw GeometryConversionError.invalidInput("Original endpoint homogeneous denominator is not positive.")
            }
            try retainBytes(3 * MemoryLayout<ExactRationalCoefficient>.stride, stride: storageByteStride, usage: &usage)
            var result: [ExactRationalCoefficient] = []
            result.reserveCapacity(3)
            for axis in 0..<3 {
                result.append(try polynomial.homogeneous[axis].evaluated(atU: station, v: .zero, usage: &usage)
                    .divided(by: weight, usage: &usage))
            }
            return result
        default:
            // FIXME(INCOMPLETE_IMPLEMENTATION): Production endpoint relation
            // consumers need original angular/algebraic/procedural coordinate
            // images before those families may publish exact equality receipts.
            throw GeometryConversionError.invalidInput("Original endpoint has no admitted exact rational coordinate law.")
        }
    }
}

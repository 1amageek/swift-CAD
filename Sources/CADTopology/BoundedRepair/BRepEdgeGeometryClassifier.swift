import HashTreeCollections
import CADCore
import CADGeometry

public struct BRepEdgeGeometryClassifier: Sendable {
    private let maximumSubdivisionDepth: Int
    private let remainingSourceDepth: Int
    private let maximumAlgebraicDepth: Int?

    public init(maximumSubdivisionDepth: Int = 32, remainingSourceDepth: Int = 16,
        maximumAlgebraicDepth: Int? = nil) {
        self.maximumSubdivisionDepth = min(32, maximumSubdivisionDepth)
        self.remainingSourceDepth = min(16, remainingSourceDepth)
        self.maximumAlgebraicDepth = maximumAlgebraicDepth
    }

    private func charge(using execution: inout OriginalQueryExecution) throws {
        try CurrentTaskCancellationChecker().checkCancellation()
        guard maximumSubdivisionDepth >= 0, remainingSourceDepth >= 0,
            maximumAlgebraicDepth.map({ (0...32).contains($0) }) ?? true else {
            throw GeometryConversionError.invalidInput("Original edge classification requires nonnegative caller depths.")
        }
        try execution.consumeWork(1)
    }
    public func kind(curve: Curve3D, from start: Double, to end: Double,
        tolerance: ModelingTolerance) throws -> BRepEdgeGeometryKind {
        let budget = try OriginalQueryBudget()
        var execution = OriginalQueryExecution(budget: budget,
            limits: try .init(maximumValueDepth: maximumAlgebraicDepth ?? 32,
                maximumCoefficientDepth: maximumAlgebraicDepth ?? 32,
                remainingSourceDepth: remainingSourceDepth, maximumSubdivisionDepth: maximumSubdivisionDepth))
        return try kind(curve: curve, from: start, to: end, tolerance: tolerance, using: &execution)
    }

    public func kind(curve: Curve3D, from start: Double, to end: Double,
        tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution) throws -> BRepEdgeGeometryKind {
        try tolerance.validate(); try charge(using: &execution)
        try curve.validate(tolerance: tolerance,
            remainingSourceDepth: remainingSourceDepth, maximumSubdivisionDepth: maximumSubdivisionDepth,
            maximumAlgebraicDepth: maximumAlgebraicDepth, using: &execution)
        return try classifiedKind(curve: curve, from: start, to: end, tolerance: tolerance, using: &execution)
    }

    /// Uses the complete world-source admission without applying its SI metric
    /// again to an unscaled local descendant of a retained spatial word.
    @inline(never)
    private func classifiedKind(curve: Curve3D, from start: Double, to end: Double,
        tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution) throws -> BRepEdgeGeometryKind {
        try charge(using: &execution)
        guard start.isFinite, end.isFinite, start != end else { throw GeometryError.invalidDistance(abs(end-start)) }
        if case .rigidImage(let image) = curve {
            return try classifiedKind(curve: image.source, from: start, to: end, tolerance: tolerance, using: &execution)
        }
        if case .affineImage(let image) = curve {
            return try classifiedKind(curve: image.source, from: start, to: end, tolerance: tolerance, using: &execution)
        }
        if case .originalAffineWord(let image) = curve {
            return try classifiedKind(curve: image.source, from: start, to: end, tolerance: tolerance, using: &execution)
        }
        if case .originalAngularTransport(let image) = curve, image.transport.isIntrinsic {
            return try classifiedKind(curve: image.source, from: start, to: end, tolerance: tolerance, using: &execution)
        }
        return try classifiedSourceKind(curve: curve, from: start, to: end,
            tolerance: tolerance, using: &execution)
    }

    // Keep non-wrapper temporaries out of every transparent wrapper recursion frame.
    @inline(never)
    private func classifiedSourceKind(curve: Curve3D, from start: Double, to end: Double,
        tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution) throws -> BRepEdgeGeometryKind {
        if case .parameterImage(let image) = curve {
            var nativeSource = image.source
            var sourceDepth = 0
            while sourceDepth < remainingSourceDepth {
                try charge(using: &execution)
                switch nativeSource {
                case .parameterImage(let child): nativeSource = child.source
                case .rigidImage(let child): nativeSource = child.source
                case .affineImage(let child): nativeSource = child.source
                case .originalAffineWord(let child): nativeSource = child.source
                default: sourceDepth = remainingSourceDepth; continue
                }
                sourceDepth += 1
            }
            if case .bSpline = nativeSource {
                if try CurveTrim(startParameter: start, endParameter: end).coversOriginalCurvePeriod(on: curve, remainingSourceDepth: remainingSourceDepth,
                    maximumAlgebraicDepth: maximumAlgebraicDepth ?? 32, using: &execution) {
                    return .closed
                }
                if try OriginalCurveEndpointPositionRelation.prove(first: curve, at: start,
                    second: curve, at: end, remainingSourceDepth: remainingSourceDepth,
                    maximumSubdivisionDepth: maximumSubdivisionDepth, tolerance: tolerance, usage: &execution,
                    maximumAlgebraicDepth: maximumAlgebraicDepth) != nil {
                    return .closed
                }
            }
            let whole = try image.sourceParameterBoundsAssumingValidatedOriginalRelation(
                over: ScalarInterval(lower: min(start,end), upper: max(start,end)), usage: &execution)
            let sourceKind = try classifiedKind(curve: image.source, from: whole.lower, to: whole.upper, tolerance: tolerance, using: &execution)
            if sourceKind == .singular { return .singular }
            if try CurveTrim(startParameter: start, endParameter: end).coversOriginalCurvePeriod(
                on: curve, remainingSourceDepth: remainingSourceDepth, maximumAlgebraicDepth: maximumAlgebraicDepth ?? 32, using: &execution) { return .closed }
            let first = try image.sourceParameterBoundsAssumingValidatedOriginalRelation(
                over: ScalarInterval(lower: start, upper: start), usage: &execution)
            let last = try image.sourceParameterBoundsAssumingValidatedOriginalRelation(
                over: ScalarInterval(lower: end, upper: end), usage: &execution)
            guard first.lower == first.upper, last.lower == last.upper else { return .open }
            return try classifiedKind(curve: image.source, from: first.lower, to: last.lower, tolerance: tolerance, using: &execution)
        }
        if case .surfaceLift(let lift) = curve, try singular(lift.parameterCurve, on: lift.surface, tolerance: tolerance, using: &execution) { return .singular }
        switch curve.parameterDomain {
        case .periodic(let period):
            if try exactPeriod(from: start, to: end, period: period, using: &execution) { return .closed }
        case .closed(let lower, let upper):
            if min(start,end) == lower, max(start,end) == upper {
                switch curve {
                case .bSpline(let spline):
                    if spline.isPeriodic { return .closed }
                    if spline.controlPoints.first == spline.controlPoints.last,
                        try clampedBoundaryIndex(lower, degree: spline.degree, knots: spline.knots,
                            count: spline.controlPoints.count, using: &execution) == 0,
                        try clampedBoundaryIndex(upper, degree: spline.degree, knots: spline.knots,
                            count: spline.controlPoints.count, using: &execution) == spline.controlPoints.count - 1 {
                        return .closed
                    }

                case .rigidImage(let image): return try classifiedKind(curve: image.source,from:start,to:end,tolerance:tolerance, using: &execution)
                case .affineImage(let image): return try classifiedKind(curve: image.source,from:start,to:end,tolerance:tolerance, using: &execution)
                case .surfaceLift(let lift):
                    if case .originalImage(let image) = lift.parameterCurve,
                        lift.surface == .parameterImage(image.targetImage),
                        abs(image.endFraction - image.startFraction) == 1 {
                        return try classifiedKind(curve: .surfaceLift(image.source), from: 0, to: 1, tolerance: tolerance, using: &execution)
                    }
                    let a = try lift.parameterCurve.startParameter(tolerance:tolerance)
                    let b = try lift.parameterCurve.endParameter(tolerance:tolerance)
                    if try originalChartPeriodCloses(from: a, to: b, on: lift.surface, using: &execution)
                        || originalGeneratorCloses(from: a, to: b, on: lift.surface, tolerance: tolerance, using: &execution) { return .closed }
                    if try originalNativeLiftCloses(lift, tolerance: tolerance, using: &execution) { return .closed }
                default: break
                }
            }
        case .unbounded: break
        }
        let hasRetainedEndpointAuthority: Bool
        switch curve {
        case .bSpline, .originalPolyline, .originalConstructionChart, .originalEndpointConnector, .originalPlaneDerivative, .originalDrafted, .originalGuideTraversalChain, .originalGuideEndpointConnector, .originalAngularTransport:
            hasRetainedEndpointAuthority = true
        default:
            hasRetainedEndpointAuthority = false
        }
        if hasRetainedEndpointAuthority {
            if try OriginalCurveEndpointPositionRelation.prove(first: curve, at: start,
                second: curve, at: end, remainingSourceDepth: remainingSourceDepth,
                maximumSubdivisionDepth: maximumSubdivisionDepth, tolerance: tolerance, usage: &execution,
                    maximumAlgebraicDepth: maximumAlgebraicDepth) != nil {
                return .closed
            }
        }
        return .open
    }
    public func kind(of edge: Edge, in model: BRepModel, tolerance: ModelingTolerance) throws -> BRepEdgeGeometryKind {
        let budget = try OriginalQueryBudget()
        var execution = OriginalQueryExecution(budget: budget,
            limits: try .init(maximumValueDepth: maximumAlgebraicDepth ?? 32,
                maximumCoefficientDepth: maximumAlgebraicDepth ?? 32,
                remainingSourceDepth: remainingSourceDepth, maximumSubdivisionDepth: maximumSubdivisionDepth))
        return try kind(of: edge, in: model, tolerance: tolerance, using: &execution)
    }

    public func kind(of edge: Edge, in model: BRepModel, tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution) throws -> BRepEdgeGeometryKind {
        guard let curve = model.geometry.curves[edge.curveID], let trim = edge.trim else { return .open }
        return try kind(curve:curve,from:trim.startParameter,to:trim.endParameter,tolerance:tolerance, using: &execution)
    }
    private func singular(_ curve: SurfaceParameterCurve, on surface: Surface3D,
        tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution) throws -> Bool {
        try charge(using: &execution)
        if case .originalImage(let image) = curve {
            guard surface == .parameterImage(image.targetImage) else { return false }
            return try singular(image.source.parameterCurve, on: image.source.surface, tolerance: tolerance, using: &execution)
        }
        if case .originalAffineWord(let image) = curve {
            guard surface == .procedural(.originalAffineWord(image.target)) else { return false }
            return try singular(image.source.parameterCurve, on: image.source.surface, tolerance: tolerance, using: &execution)
        }
        if case .procedural(.originalAffineWord(let image)) = surface {
            return try singular(curve, on: image.source, tolerance: tolerance, using: &execution)
        }
        if case .procedural(.offset(let offset)) = surface {
            guard let equivalent = try offset.exactChartPreservingSurface(tolerance: tolerance) else { return false }
            return try singular(curve, on: equivalent, tolerance: tolerance, using: &execution)
        }
        if case .procedural(.originalImage(let image)) = surface {
            switch curve {
            case .constantU(let u, let start, let end):
                let native = try image.sourceParameterBounds(over: SurfaceParameterBox(
                    u: ScalarInterval(lower: u, upper: u),
                    v: ScalarInterval(lower: min(start,end), upper: max(start,end))), tolerance: tolerance)
                if image.swapAxes {
                    guard native.v.lower == native.v.upper else { return false }
                    return try singular(.constantV(v: native.v.lower, uStart: native.u.lower,
                        uEnd: native.u.upper), on: image.source, tolerance: tolerance, using: &execution)
                }
                guard native.u.lower == native.u.upper else { return false }
                return try singular(.constantU(u: native.u.lower, vStart: native.v.lower,
                    vEnd: native.v.upper), on: image.source, tolerance: tolerance, using: &execution)
            case .constantV(let v, let start, let end):
                let native = try image.sourceParameterBounds(over: SurfaceParameterBox(
                    u: ScalarInterval(lower: min(start,end), upper: max(start,end)),
                    v: ScalarInterval(lower: v, upper: v)), tolerance: tolerance)
                if image.swapAxes {
                    guard native.u.lower == native.u.upper else { return false }
                    return try singular(.constantU(u: native.u.lower, vStart: native.v.lower,
                        vEnd: native.v.upper), on: image.source, tolerance: tolerance, using: &execution)
                }
                guard native.v.lower == native.v.upper else { return false }
                return try singular(.constantV(v: native.v.lower, uStart: native.u.lower,
                    uEnd: native.u.upper), on: image.source, tolerance: tolerance, using: &execution)
            case .periodicTranslation(let base, let uShift, let vShift):
                switch base {
                case .constantU(let u, let a, let b):
                    return try singular(.constantU(u: u+uShift, vStart: a+vShift, vEnd: b+vShift),
                        on: surface, tolerance: tolerance, using: &execution)
                case .constantV(let v, let a, let b):
                    return try singular(.constantV(v: v+vShift, uStart: a+uShift, uEnd: b+uShift),
                        on: surface, tolerance: tolerance, using: &execution)
                default: return false
                }
            default: return false
            }
        }
        switch curve {
        case .constantU(let u,let a,let b):
            guard a != b,case .bSpline(let spline) = surface,let firstRow = spline.controlPoints.first,
                let index = try clampedBoundaryIndex(u,degree: spline.uDegree,knots: spline.uKnots,
                    count: spline.uControlPointCount, using: &execution) else { return false }
            let point = firstRow[index]
            for row in spline.controlPoints { try charge(using: &execution); if row[index] != point { return false } }
            for row in spline.weights { try charge(using: &execution); if !row[index].isFinite || row[index] <= 0 { return false } }
            return true
        case .constantV(let v,let a,let b):
            guard a != b else { return false }
            if case .procedural(.originalRevolution(let revolution)) = surface {
                if v == 0 { return revolution.hasOriginalAxisEndpoint(atEnd: false) }
                if v == 1 { return revolution.hasOriginalAxisEndpoint(atEnd: true) }
                return false
            }
            let topology = try SurfaceParameterTopology(surface: surface, using: &execution)
            if topology.uSingularVValues.contains(v) { return true }
            guard case .bSpline(let spline) = surface,
                let index = try clampedBoundaryIndex(v,degree: spline.vDegree,knots: spline.vKnots,
                    count: spline.vControlPointCount, using: &execution) else { return false }
            let row = spline.controlPoints[index]
            guard let point = row.first else { return false }
            for control in row { try charge(using: &execution); if control != point { return false } }
            for weight in spline.weights[index] { try charge(using: &execution); if !weight.isFinite || weight <= 0 { return false } }
            return true
        case .periodicTranslation(let base,let uShift,let vShift):
            switch base {
            case .constantU(let u,let a,let b):
                return try singular(.constantU(u: u+uShift,vStart: a+vShift,vEnd: b+vShift),on: surface,tolerance: tolerance, using: &execution)
            case .constantV(let v,let a,let b):
                return try singular(.constantV(v: v+vShift,uStart: a+uShift,uEnd: b+uShift),on: surface,tolerance: tolerance, using: &execution)
            default: return false
            }
        default: return false
        }
    }

    /// Position closure consumes the original producer and every incident endpoint side.
    private func originalNativeLiftCloses(_ lift: SurfaceLiftCurve3D,
        tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution) throws -> Bool {
        guard lift.exactBSplineImage == nil, case .bSpline(let surface) = lift.surface,
            !surface.isUPeriodic, !surface.isVPeriodic else { return false }
        switch lift.parameterCurve {
        case .constantU, .constantV: break
        default: return false
        }
        guard remainingSourceDepth > 0 else {
            throw GeometryConversionError.resourceLimitExceeded("Original Native lifted endpoints exhausted source depth.")
        }
        let first = try lift.parameterCurve.startParameter(tolerance:tolerance)
        let last = try lift.parameterCurve.endParameter(tolerance:tolerance)
        func position(_ point: SurfaceParameter, using execution: inout OriginalQueryExecution)
            throws -> [ExactRationalCoefficient] {
            let u = try ExactRationalCoefficient.originalDouble(point.u,usage:&execution)
            let v = try ExactRationalCoefficient.originalDouble(point.v,usage:&execution)
            var retained: [ExactRationalCoefficient]?
            for ui in surface.uDegree..<surface.uControlPointCount {
                for vi in surface.vDegree..<surface.vControlPointCount {
                    try execution.consumeWork(1)
                    guard surface.uKnots[ui] < surface.uKnots[ui+1],
                        surface.vKnots[vi] < surface.vKnots[vi+1] else { continue }
                    let ul = try ExactRationalCoefficient.originalDouble(surface.uKnots[ui],usage:&execution)
                    let uh = try ExactRationalCoefficient.originalDouble(surface.uKnots[ui+1],usage:&execution)
                    let vl = try ExactRationalCoefficient.originalDouble(surface.vKnots[vi],usage:&execution)
                    let vh = try ExactRationalCoefficient.originalDouble(surface.vKnots[vi+1],usage:&execution)
                    if try u.subtracting(ul,usage:&execution).isNegative || uh.subtracting(u,usage:&execution).isNegative
                        || v.subtracting(vl,usage:&execution).isNegative || vh.subtracting(v,usage:&execution).isNegative { continue }
                    let law = try OriginalRationalSurfaceHomogeneous(source:surface,uSpanIndex:ui,vSpanIndex:vi,
                        tolerance:tolerance,usage:&execution)
                    let weight = try law.homogeneous[3].evaluated(atU:u,v:v,usage:&execution)
                    guard weight.isPositive else {
                        throw GeometryConversionError.invalidInput("Original lifted endpoint has no positive homogeneous weight.")
                    }
                    try RationalAlgebraStorage.retain(3,of:ExactRationalCoefficient.self,usage:&execution)
                    var coordinates: [ExactRationalCoefficient] = []; coordinates.reserveCapacity(3)
                    for axis in 0..<3 {
                        coordinates.append(try law.homogeneous[axis].evaluated(atU:u,v:v,usage:&execution)
                            .divided(by:weight,usage:&execution))
                    }
                    if let retained {
                        for axis in 0..<3 {
                            try execution.consumeWork(1)
                            guard try retained[axis].subtracting(coordinates[axis],usage:&execution).isZero else {
                                throw GeometryConversionError.invalidInput("Original lifted endpoint incident position laws disagree.")
                            }
                        }
                    } else { retained = coordinates }
                }
            }
            guard let retained else {
                throw GeometryConversionError.invalidInput("Original lifted endpoint has no complete Native chart.")
            }
            return retained
        }
        let a = try position(first,using:&execution), b = try position(last,using:&execution)
        for axis in 0..<3 {
            try execution.consumeWork(1)
            if try !a[axis].subtracting(b[axis],usage:&execution).isZero {
                try CurrentTaskCancellationChecker().checkCancellation()
                return false
            }
        }
        try CurrentTaskCancellationChecker().checkCancellation()
        return true
    }

    private func originalGeneratorCloses(from first: SurfaceParameter, to last: SurfaceParameter,
        on surface: Surface3D, tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution) throws -> Bool {
        var source = surface
        var start = SurfaceParameterBox(u: try ScalarInterval(lower: first.u, upper: first.u),
            v: try ScalarInterval(lower: first.v, upper: first.v))
        var end = SurfaceParameterBox(u: try ScalarInterval(lower: last.u, upper: last.u),
            v: try ScalarInterval(lower: last.v, upper: last.v))
        var sameU = first.u == last.u, sameV = first.v == last.v
        var depth = 0
        while true {
            guard depth < remainingSourceDepth else { return false }
            depth += 1; try charge(using: &execution)
            switch source {
            case .procedural(.originalImage(let image)):
                start = try image.sourceParameterBounds(over: start, tolerance: tolerance)
                end = try image.sourceParameterBounds(over: end, tolerance: tolerance)
                if image.swapAxes { swap(&sameU, &sameV) }
                source = image.source
            case .procedural(.originalAffineWord(let image)): source = image.source
            case .procedural(.offset): return false
            case .procedural(.originalRevolution(let revolution)):
                return sameU && start.v.width == 0 && end.v.width == 0
                    && ((start.v.lower == 0 && end.v.lower == 1) || (start.v.lower == 1 && end.v.lower == 0))
                    && revolution.generator.hasOriginalClosedAuthoredEndpoints
            default: return false
            }
        }
    }

    private func exactPeriod(from start: Double, to end: Double, period: Double, using execution: inout OriginalQueryExecution) throws -> Bool {
        let difference = try ExactRationalCoefficient.originalDouble(end, usage: &execution)
            .subtracting(.originalDouble(start, usage: &execution), usage: &execution)
        let magnitude = difference.isNegative ? difference.negated : difference
        return try magnitude.subtracting(.originalDouble(period, usage: &execution), usage: &execution).isZero
    }

    private func originalChartPeriodCloses(from start: SurfaceParameter, to end: SurfaceParameter,
        on surface: Surface3D, using execution: inout OriginalQueryExecution) throws -> Bool {
        var source = surface
        var u = try ExactRationalCoefficient.originalDouble(end.u, usage: &execution)
            .subtracting(.originalDouble(start.u, usage: &execution), usage: &execution)
        var v = try ExactRationalCoefficient.originalDouble(end.v, usage: &execution)
            .subtracting(.originalDouble(start.v, usage: &execution), usage: &execution)
        var depth = 0
        while true {
            guard depth < remainingSourceDepth else { return false }
            depth += 1
            try execution.consumeWork(1)
            switch source {
            case .procedural(.originalImage(let image)):
                let mappedU = try u.multiplied(by: image.uParameterGain.exactCoefficient(usage: &execution), usage: &execution)
                let mappedV = try v.multiplied(by: image.vParameterGain.exactCoefficient(usage: &execution), usage: &execution)
                u = image.swapAxes ? mappedV : mappedU
                v = image.swapAxes ? mappedU : mappedV
                source = image.source
            case .procedural(.originalAffineWord(let image)): source = image.source
            case .procedural(.offset(let offset)): source = offset.source
            default:
                let topology = try SurfaceParameterTopology(surface: source, using: &execution)
                if v.isZero, let period = topology.uPeriod {
                    let magnitude = u.isNegative ? u.negated : u
                    if try magnitude.subtracting(.originalDouble(period, usage: &execution), usage: &execution).isZero { return true }
                }
                if u.isZero, let period = topology.vPeriod {
                    let magnitude = v.isNegative ? v.negated : v
                    if try magnitude.subtracting(.originalDouble(period, usage: &execution), usage: &execution).isZero { return true }
                }
                return false
            }
        }
    }

    private func clampedBoundaryIndex(_ parameter: Double,degree: Int,knots: [Double],count: Int, using execution: inout OriginalQueryExecution) throws -> Int? {
        guard degree >= 0,count > degree,knots.count == count+degree+1 else { return nil }
        func matches(_ values: ArraySlice<Double>) throws -> Bool {
            for value in values { try charge(using: &execution); if value != parameter { return false } }
            return true
        }
        if parameter == knots[degree], try matches(knots.prefix(degree+1)) { return 0 }
        if parameter == knots[count], try matches(knots.suffix(degree+1)) { return count-1 }
        return nil
    }
}

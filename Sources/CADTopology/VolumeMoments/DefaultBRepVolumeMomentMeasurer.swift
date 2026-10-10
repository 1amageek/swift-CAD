import HashTreeCollections
import CADCore
import CADGeometry

public struct DefaultBRepVolumeMomentMeasurer: BRepVolumeMomentMeasuring {
    private typealias Interval = TrimmedAnalyticSurfaceVolumeEvaluator.Interval
    private struct FaceDomain {
        let surface: Surface3D
        let prepared: PreparedSurfaceDifferentialEncloser
        let flux: PreparedSurfaceAreaIntegrand
        let sign: Double
        let predicates: [(LoopRole, CertifiedSurfaceParameterLoopPredicate)]
        let curves: [SurfaceParameterCurve]
        let maximumDepth: Int
    }
    private struct FanDomain {
        let curve: SurfaceParameterCurve
        let chart: SurfaceAreaParameterChartEncloser
        let anchor: SurfaceParameter
    }
    private struct Cell {
        let domain: FaceDomain
        let box: SurfaceParameterBox
        let depth: Int
        let values: [Interval]
        var nativeDomain: SurfaceAreaNativeSpanDomain? = nil
        var fan: FanDomain? = nil
    }
    private let powers = [(0,0,0), (1,0,0), (0,1,0), (0,0,1), (2,0,0), (0,2,0), (0,0,2), (1,1,0), (1,0,1), (0,1,1)]
    public init() {}

    public func moments(of bodyID: BodyID, in model: BRepModel, options: BRepVolumeMomentOptions,
        tolerance: ModelingTolerance) throws -> BRepVolumeMoments {
        try options.validate()
        let budget = VolumeMomentProofBudget(options: options, tolerance: tolerance)
        // FIXME(INCOMPLETE_IMPLEMENTATION): Manual moment admission now shares its
        // original work owner, but lower nonlinear/chart validation and temporary-byte
        // ports must be complete before decoded-source accounting can be certified.
        let certificate = try ValidatedBRepModel(model, tolerance: tolerance, validationLevel: .exact,
            maximumSubdivisionDepth: options.maximumSubdivisionDepth, remainingSourceDepth: 16,
            consumeWork: { try budget.charge(depth: 0) }, maximumAlgebraicDepth: 32)
        return try measure(of: bodyID, in: certificate, options: options, budget: budget)
    }

    public func moments(of bodyID: BodyID, in validatedModel: ValidatedBRepModel,
        options: BRepVolumeMomentOptions) throws -> BRepVolumeMoments {
        try options.validate()
        let budget = VolumeMomentProofBudget(options: options, tolerance: validatedModel.tolerance)
        return try measure(of: bodyID, in: validatedModel, options: options, budget: budget)
    }

    private func measure(of bodyID: BodyID, in validatedModel: ValidatedBRepModel,
        options: BRepVolumeMomentOptions, budget: VolumeMomentProofBudget) throws -> BRepVolumeMoments {
        let tolerance = validatedModel.tolerance
        guard validatedModel.validationLevel != .modeling else {
            throw failure("Volume moments require an original exact validation receipt.", tolerance)
        }
        let model = validatedModel.model
        try tolerance.validate()
        guard options.absoluteAccuracy.isFinite, options.absoluteAccuracy > 0,
            options.relativeAccuracy.isFinite, options.relativeAccuracy >= 0,
            options.maximumWork > 0, options.maximumWork <= 262_144,
            options.maximumSubdivisionDepth >= 0, options.maximumSubdivisionDepth <= 32,
            let body = model.bodies[bodyID], body.kind == .solid else { throw failure("Volume moments require a solid and finite nonnegative accuracy.", tolerance) }
        var cells: [Cell] = []
        var work: Int { budget.consumedWork }
        let charge: @Sendable (Int) throws -> Void = { try budget.charge($0) }
        for shellID in body.shellIDs {
            guard let shell = model.shells[shellID] else { throw TopologyError.missingReference("Missing moment shell.") }
            for faceID in shell.faceIDs {
                try charge(1)
                guard let face = model.faces[faceID], let surface = model.geometry.surfaces[face.surfaceID] else { throw TopologyError.missingReference("Missing moment face support.") }
                var predicates: [(LoopRole, CertifiedSurfaceParameterLoopPredicate)] = []
                var allCurves: [SurfaceParameterCurve] = []
                var directedLoops: [(LoopRole,[SurfaceParameterCurve])] = []
                for loopID in face.loops {
                    guard let loop = model.loops[loopID] else { throw TopologyError.missingReference("Missing moment trim loop.") }
                    let curves = try loop.coedges.map { use -> SurfaceParameterCurve in
                        try charge(1)
                        guard let curve = use.surfaceParameterCurve else { throw failure("Volume moments require all original directed trim curves.", tolerance) }
                        return curve
                    }
                    let lifted = try SurfaceParameterLoopUnwrapper().unwrap(curves, on: surface,
                        tolerance: tolerance, context: "Volume moments",
                        maximumSubdivisionDepth: options.maximumSubdivisionDepth, remainingSourceDepth: 16,
                        consumeWork: { try budget.charge(depth: $0) }).map({ $0.translatedCurve })
                    predicates.append((loop.role, try CertifiedSurfaceParameterLoopPredicate(curves: lifted,
                        on: surface, tolerance: tolerance, maximumSubdivisionDepth: options.maximumSubdivisionDepth,
                        remainingSourceDepth: 16, maximumAlgebraicDepth: 32,
                        consumeWork: { try budget.charge(depth: $0) })))
                    allCurves += lifted
                    directedLoops.append((loop.role,lifted))
                }
                let sign = (face.orientation == .forward ? 1.0 : -1.0) * (shell.orientation == .forward ? 1.0 : -1.0)
                let exactRectangle = try ExactRectangularPcurveDomainResolver().resolve(face: face,
                    model: model, tolerance: tolerance, maximumSubdivisionDepth: options.maximumSubdivisionDepth,
                    remainingSourceDepth: 16, consumeWork: { try budget.charge(depth: $0) },
                    consumeStorage: nil) != nil
                // FIXME(INCOMPLETE_IMPLEMENTATION): Original moment preparation
                // now forwards the invocation's source/depth/algebra work owner.
                // Specialized rolling/offset/ruled and general nonlinear chart
                // producers still need their complete bounded lower preparation
                // before this path establishes all-domain query accounting.

                let domain = FaceDomain(surface: surface, prepared: try PreparedSurfaceDifferentialEncloser(surface: surface, tolerance: tolerance, remainingSourceDepth: 16, maximumSubdivisionDepth: options.maximumSubdivisionDepth,
                    consumeWork: { try charge(1) }, maximumAlgebraicDepth: 32), flux: try PreparedSurfaceAreaIntegrand(surface: surface, tolerance: tolerance, consumeWork: { try charge(1) },
                    maximumSubdivisionDepth:options.maximumSubdivisionDepth,remainingSourceDepth:16,maximumAlgebraicDepth:32), sign: sign, predicates: exactRectangle ? [] : predicates, curves: exactRectangle ? [] : allCurves, maximumDepth: options.maximumSubdivisionDepth)
                let box = try DefaultFaceParameterBoundsResolver(maximumSubdivisionDepth: options.maximumSubdivisionDepth, consumeWork: { try budget.charge(depth: $0) }).bounds(for: faceID, in: model, tolerance: tolerance)
                if !exactRectangle {
                    guard let anchorCurve = allCurves.first else { throw failure("Volume fan has no original trim anchor.", tolerance) }
                    let anchor = try anchorCurve.startParameter(tolerance: tolerance)
                    let unit = try ScalarInterval(lower: 0, upper: 1)
                    for (role,curves) in directedLoops {
                        let charts = try curves.map { try SurfaceAreaParameterChartEncloser(curve: $0,
                            on:surface,tolerance:tolerance,maximumSubdivisionDepth:options.maximumSubdivisionDepth,
                            remainingSourceDepth:16,maximumAlgebraicDepth:32,consumeWork:{ _ in try charge(1) }) }
                        let traversal = try signedLoopTraversal(charts, maximumDepth: options.maximumSubdivisionDepth, tolerance: tolerance, charge: charge)
                        let loopSign = sign * (role == .outer ? traversal : -traversal)
                        let loopDomain = FaceDomain(surface: surface, prepared: domain.prepared,
                            flux: domain.flux, sign: loopSign, predicates: [], curves: [], maximumDepth: options.maximumSubdivisionDepth)
                        for i in curves.indices {
                            if domain.flux.fanIsExactlyZero(curve: curves[i], anchor: anchor, parameterChart: charts[i]) { continue }
                            let fan = FanDomain(curve: curves[i], chart: charts[i], anchor: anchor)
                            if let native = try domain.flux.nativeFanDomains(curve: curves[i], anchor: anchor,
                                maximumCount: options.maximumWork-work, tolerance: tolerance, parameterChart: charts[i],
                                maximumSubdivisionDepth: options.maximumSubdivisionDepth,
                                consumeWork: { try budget.charge(depth: $0) }) {
                                for owner in native {
                                    try charge(1)
                                    let fractions = SurfaceParameterBox(u: unit, v: owner.radialRange ?? unit)
                                    cells += try admittedCells(domain: loopDomain, box: fractions, depth: 0,
                                        tolerance: tolerance, charge: charge, maximumDepth: options.maximumSubdivisionDepth, nativeDomain: owner, fan: fan)
                                }
                            } else {
                                cells += try admittedCells(domain: loopDomain, box: SurfaceParameterBox(u: unit,v: unit),
                                    depth: 0, tolerance: tolerance, charge: charge, maximumDepth: options.maximumSubdivisionDepth, fan: fan)
                            }
                        }
                    }
                    continue
                }
                if let native = try domain.flux.nativeRectangleDomains(over: box,
                    maximumCount: options.maximumWork-work, tolerance: tolerance,
                    maximumSubdivisionDepth: options.maximumSubdivisionDepth,
                    consumeWork: { try budget.charge(depth: $0) }) {
                    for owner in native {
                        try charge(1)
                        cells.append(try cell(domain: domain, box: owner.rectangle, depth: 0,
                            tolerance: tolerance, charge: charge, nativeDomain: owner))
                    }
                } else {
                    cells.append(try cell(domain: domain, box: box, depth: 0, tolerance: tolerance, charge: charge))
                }
            }
        }
        guard !cells.isEmpty else { throw failure("A volume-moment body has no boundary cells.", tolerance) }
        while true {
            try charge(1)
            try charge(cells.count)
            var sums = Array(repeating: Interval.exact(0), count: 10)
            for item in cells { for i in 0..<10 { sums[i] = sums[i] + item.values[i] } }
            guard sums.allSatisfy({ $0.lower.isFinite && $0.upper.isFinite && $0.lower <= $0.upper }) else {
                throw failure("Original accumulated volume moments have no finite ordered enclosure.", tolerance)
            }
            let targets = sums.map { value -> Double in
                let minimumAbsolute = value.lower > 0 ? value.lower : value.upper < 0 ? -value.upper : 0
                let relative = OutwardScalarInterval.exact(options.relativeAccuracy) * .exact(minimumAbsolute)
                return max(options.absoluteAccuracy, relative.lower)
            }
            if zip(sums, targets).allSatisfy({ enclosureWidth($0.0) <= $0.1 }) {
                guard sums[0].lower > 0 else { throw failure("Volume-moment enclosure does not prove positive material volume.", tolerance) }
                try CurrentTaskCancellationChecker().checkCancellation()
                return try BRepVolumeMoments(enclosures: sums.map { try ScalarInterval(lower: $0.lower, upper: $0.upper) }, consumedWork: work)
            }
            try charge(cells.count)
            guard let index = cells.indices.max(by: { a, b in
                score(cells[a], targets: targets) < score(cells[b], targets: targets)
            }) else { throw failure("Volume-moment adaptive cover disappeared.", tolerance) }
            let selected = cells.remove(at: index)
            guard selected.depth < options.maximumSubdivisionDepth else { throw failure("Volume-moment depth exhausted before requested enclosure widths.", tolerance) }
            let axisU = selected.box.u.width >= selected.box.v.width
            let interval = axisU ? selected.box.u : selected.box.v
            let middle = interval.midpoint
            guard middle > interval.lower, middle < interval.upper else { throw failure("Volume-moment representable cell resolution exhausted.", tolerance) }
            for range in [try ScalarInterval(lower: interval.lower, upper: middle), try ScalarInterval(lower: middle, upper: interval.upper)] {
                try charge(1)
                let box = SurfaceParameterBox(u: axisU ? range : selected.box.u, v: axisU ? selected.box.v : range)
                cells += try admittedCells(domain: selected.domain, box: box, depth: selected.depth + 1,
                    tolerance: tolerance, charge: charge, maximumDepth: options.maximumSubdivisionDepth, nativeDomain: selected.nativeDomain, fan: selected.fan)
            }
        }
    }

    private func cell(domain: FaceDomain, box: SurfaceParameterBox, depth: Int,
        tolerance: ModelingTolerance, charge: @Sendable (Int) throws -> Void,
        nativeDomain: SurfaceAreaNativeSpanDomain? = nil, fan: FanDomain? = nil) throws -> Cell {
        return try withoutActuallyEscaping(charge) { charge in
            if let fan {
                let range = try domain.flux.volumeMomentFanBounds(curve: fan.curve, parameterChart: fan.chart,
                    anchor: fan.anchor, reference: .origin, boundaryFraction: box.u, radialFraction: box.v,
                    tolerance: tolerance, domain: nativeDomain, consumeWork: { try charge(1) })
                let midpoint = try domain.flux.volumeMomentFanBounds(curve: fan.curve, parameterChart: fan.chart,
                    anchor: fan.anchor, reference: .origin,
                    boundaryFraction: ScalarInterval(lower: box.u.midpoint,upper: box.u.midpoint),
                    radialFraction: ScalarInterval(lower: box.v.midpoint,upper: box.v.midpoint),
                    tolerance: tolerance, domain: nativeDomain, consumeWork: { try charge(1) })
                return Cell(domain: domain, box: box, depth: depth,
                    values: try integratedFields(range: range, midpoint: midpoint, box: box, sign: domain.sign,
                        tolerance: tolerance), nativeDomain: nativeDomain, fan: fan)
            }
            var meetsBoundary = false
            let width = max(box.u.width, box.v.width) / 4
            for curve in domain.curves {
                let remainingDepth = domain.maximumDepth-depth
                let ranges = try CertifiedSurfaceParameterCurveEncloser(maximumSubdivisionDepth: remainingDepth,
                    consumeWork: { _ in try charge(1) }).enclosures(for: curve, on: domain.surface,
                        maximumWidth: width, tolerance: tolerance)
                if ranges.contains(where: { $0.u.intersects(box.u) && $0.v.intersects(box.v) }) { meetsBoundary = true; break }
            }
            var inside = true
            if !meetsBoundary {
                for (role, predicate) in domain.predicates {
                    let classification = try predicate.classify(Point2D(x: box.u.midpoint, y: box.v.midpoint), tolerance: tolerance,
                        consumeWork: { _ in try charge(1) }, maximumSubdivisionDepth: domain.maximumDepth-depth)
                    if role == .outer && classification == .outside || role == .inner && classification == .inside { inside = false; break }
                }
            }
            if !inside { return Cell(domain: domain, box: box, depth: depth, values: Array(repeating: .exact(0), count: 10)) }
            if case .plane = domain.surface, !meetsBoundary {
                return Cell(domain: domain, box: box, depth: depth,
                    values: try planarMoments(domain: domain, box: box, depth: depth, tolerance: tolerance, charge: charge))
            }
            let range = try domain.flux.volumeMomentBounds(over: box, reference: .origin,
                tolerance: tolerance, domain: nativeDomain, consumeWork: { try charge(1) })
            let size = OutwardScalarInterval.exact(box.u.upper) - .exact(box.u.lower)
            let height = OutwardScalarInterval.exact(box.v.upper) - .exact(box.v.lower)
            let measure = size*height*OutwardScalarInterval.exact(domain.sign)
            var integrated = range.map { $0.value*measure }
            if !meetsBoundary {
                let midpoint = SurfaceParameterBox(u: try ScalarInterval(lower: box.u.midpoint, upper: box.u.midpoint),
                    v: try ScalarInterval(lower: box.v.midpoint, upper: box.v.midpoint))
                let values = try domain.flux.volumeMomentBounds(over: midpoint, reference: .origin,
                    tolerance: tolerance, domain: nativeDomain, consumeWork: { try charge(1) })
                for i in integrated.indices {
                    let field = range[i]
                    if let uu = field.secondUU, let uv = field.secondUV, let vv = field.secondVV {
                        let local = values[i].value + uu*size*size*OutwardScalarInterval(1.0/24)
                            + vv*height*height*OutwardScalarInterval(1.0/24)
                        let error = (OutwardScalarInterval.exact((uv.upper-uv.lower).nextUp)*size*height * .exact(0.0625)).upper
                        let taylor = (local+OutwardScalarInterval(lower: -error, upper: error))*measure
                        let lower = max(integrated[i].lower,taylor.lower), upper = min(integrated[i].upper,taylor.upper)
                        guard lower <= upper else { throw failure("Original volume range and Taylor certificates disagree.", tolerance) }
                        integrated[i] = OutwardScalarInterval(lower: lower, upper: upper)
                    }
                }
            }
            let values = integrated.map { value in
                meetsBoundary ? Interval(lower: min(0,value.lower), upper: max(0,value.upper))
                    : Interval(lower: value.lower,upper: value.upper)
            }
            return Cell(domain: domain, box: box, depth: depth, values: values, nativeDomain: nativeDomain)
        }
    }
    private func integratedFields(range: [SurfaceAreaIntegrandBounds], midpoint: [SurfaceAreaIntegrandBounds],
        box: SurfaceParameterBox, sign: Double, tolerance: ModelingTolerance) throws -> [Interval] {
        let size = OutwardScalarInterval.exact(box.u.upper) - .exact(box.u.lower)
        let height = OutwardScalarInterval.exact(box.v.upper) - .exact(box.v.lower)
        let measure = size*height*OutwardScalarInterval.exact(sign)
        return try range.indices.map { i in
            let field = range[i]
            var integral = field.value*measure
            if let uu = field.secondUU, let uv = field.secondUV, let vv = field.secondVV {
                let local = midpoint[i].value + uu*size*size*OutwardScalarInterval(1.0/24)
                    + vv*height*height*OutwardScalarInterval(1.0/24)
                let error = (OutwardScalarInterval.exact((uv.upper-uv.lower).nextUp)*size*height * .exact(0.0625)).upper
                let taylor = (local+OutwardScalarInterval(lower: -error,upper: error))*measure
                let lower = max(integral.lower,taylor.lower), upper = min(integral.upper,taylor.upper)
                guard lower <= upper else { throw failure("Volume fan Taylor and range certificates disagree.",tolerance) }
                integral = OutwardScalarInterval(lower: lower,upper: upper)
            }
            guard integral.isFinite else { throw failure("Volume fan integral is nonfinite.",tolerance) }
            return Interval(lower: integral.lower,upper: integral.upper)
        }
    }

    private func admittedCells(domain: FaceDomain, box: SurfaceParameterBox, depth: Int,
        tolerance: ModelingTolerance, charge: @Sendable (Int) throws -> Void,
        maximumDepth: Int, nativeDomain: SurfaceAreaNativeSpanDomain? = nil, fan: FanDomain? = nil) throws -> [Cell] {
        try charge(1)
        do { return [try cell(domain: domain,box: box,depth: depth,tolerance: tolerance,
            charge: charge,nativeDomain: nativeDomain,fan: fan)] }
        catch is SurfaceAreaEnclosureRefinementRequired {}
        catch let error as KernelError where error.code == .singularSystem || error.code == .singularGeometry {}
        guard depth < maximumDepth else { throw failure("Original volume fan enclosure exhausted its retained depth.",tolerance) }
        let axisU = box.u.width >= box.v.width, interval = axisU ? box.u : box.v
        let midpoint = interval.midpoint
        guard midpoint > interval.lower,midpoint < interval.upper else {
            throw failure("Original volume fan enclosure exhausted representable coordinates.",tolerance)
        }
        var result: [Cell] = []
        for range in [try ScalarInterval(lower: interval.lower,upper: midpoint),
                      try ScalarInterval(lower: midpoint,upper: interval.upper)] {
            result += try admittedCells(domain: domain,
                box: SurfaceParameterBox(u: axisU ? range : box.u,v: axisU ? box.v : range),
                depth: depth+1,tolerance: tolerance,charge: charge,maximumDepth: maximumDepth,nativeDomain: nativeDomain,fan: fan)
        }
        return result
    }

    private func signedLoopTraversal(_ charts: [SurfaceAreaParameterChartEncloser], maximumDepth: Int,
        tolerance: ModelingTolerance, charge: @Sendable (Int) throws -> Void) throws -> Double {
        struct FluxCell { let chart: SurfaceAreaParameterChartEncloser; let range: ScalarInterval; let depth: Int; let integral: OutwardScalarInterval }
        func make(_ chart: SurfaceAreaParameterChartEncloser,_ range: ScalarInterval,_ depth: Int) throws -> FluxCell {
            try charge(1)
            let bounds = try chart.signedFluxIntegrationBounds(over: range, tolerance: tolerance,
                consumeWork: { try charge(1) })
            let width = OutwardScalarInterval.exact(range.upper) - .exact(range.lower)
            var integral = bounds.value * width
            if let midpoint = bounds.midpoint, let second = bounds.secondDerivative {
                let taylor = midpoint * width + second * width * width * width * OutwardScalarInterval(1.0 / 24)
                let lower = max(integral.lower, taylor.lower), upper = min(integral.upper, taylor.upper)
                guard lower <= upper else { throw failure("Original loop flux certificates disagree.", tolerance) }
                integral = OutwardScalarInterval(lower: lower, upper: upper)
            }
            guard integral.isFinite else { throw failure("Original loop flux is nonfinite.", tolerance) }
            return FluxCell(chart: chart, range: range, depth: depth, integral: integral)
        }
        let unit = try ScalarInterval(lower: 0,upper: 1)
        var cells = try charts.map { try make($0,unit,0) }
        while true {
            try charge(1)
            try charge(cells.count)
            let sum = cells.reduce(OutwardScalarInterval.exact(0)) { $0+$1.integral }
            if sum.lower > 0 { return 1 }
            if sum.upper < 0 { return -1 }
            try charge(cells.count)
            guard let index = cells.indices.max(by: { cells[$0].integral.upper-cells[$0].integral.lower < cells[$1].integral.upper-cells[$1].integral.lower }) else {
                throw failure("Original trim loop lost its signed-area cover.",tolerance)
            }
            let selected = cells.remove(at: index), midpoint = selected.range.midpoint
            guard selected.depth < maximumDepth,midpoint > selected.range.lower,midpoint < selected.range.upper else {
                throw failure("Original trim loop traversal is unresolved under retained work/depth bounds.",tolerance)
            }
            cells.append(try make(selected.chart,ScalarInterval(lower: selected.range.lower,upper: midpoint),selected.depth+1))
            cells.append(try make(selected.chart,ScalarInterval(lower: midpoint,upper: selected.range.upper),selected.depth+1))
        }
    }

    private func planarMoments(domain: FaceDomain, box: SurfaceParameterBox, depth: Int,
        tolerance: ModelingTolerance, charge: @Sendable (Int) throws -> Void) throws -> [Interval] {
        let u = box.u.midpoint, v = box.v.midpoint
        let tiny = SurfaceParameterBox(
            u: try ScalarInterval(lower: max(box.u.lower, u.nextDown), upper: min(box.u.upper, u.nextUp)),
            v: try ScalarInterval(lower: max(box.v.lower, v.nextDown), upper: min(box.v.upper, v.nextUp)))
        let e = try domain.prepared.enclosure(over: tiny, tolerance: tolerance,
            maximumSpanCount: 262_144, maximumSubdivisionDepth: domain.maximumDepth-depth,
            remainingSourceDepth: 16, consumeWork: { try charge(1) })
        func interval(_ value: ScalarInterval) -> Interval { Interval(lower: value.lower, upper: value.upper) }
        typealias Polynomial = [[Interval]]
        func coordinate(_ p: ScalarInterval, _ a: ScalarInterval, _ b: ScalarInterval) -> Polynomial {
            var values = Array(repeating: Array(repeating: Interval.exact(0), count: 4), count: 4)
            values[0][0] = interval(p); values[1][0] = interval(a); values[0][1] = interval(b)
            return values
        }
        func multiply(_ a: Polynomial, _ b: Polynomial) -> Polynomial {
            var result = Array(repeating: Array(repeating: Interval.exact(0), count: 4), count: 4)
            for i in 0..<4 { for j in 0..<4 { for k in 0..<(4-i) { for l in 0..<(4-j) {
                result[i+k][j+l] = result[i+k][j+l] + a[i][j] * b[k][l]
            } } } }
            return result
        }
        func polynomialPower(_ a: Polynomial, _ n: Int) -> Polynomial {
            var result = Array(repeating: Array(repeating: Interval.exact(0), count: 4), count: 4)
            result[0][0] = .exact(1)
            for _ in 0..<n { result = multiply(result, a) }
            return result
        }
        let x = coordinate(e.position.x, e.tangentU.x, e.tangentV.x)
        let y = coordinate(e.position.y, e.tangentU.y, e.tangentV.y)
        let z = coordinate(e.position.z, e.tangentU.z, e.tangentV.z)
        let nx = interval(e.tangentU.y) * interval(e.tangentV.z) - interval(e.tangentU.z) * interval(e.tangentV.y)
        func integralPower(_ bounds: ScalarInterval, _ center: Double, _ exponent: Int) -> Interval {
            let low = Interval(lower: (bounds.lower-center).nextDown, upper: (bounds.lower-center).nextUp)
            let high = Interval(lower: (bounds.upper-center).nextDown, upper: (bounds.upper-center).nextUp)
            return (power(high, exponent+1) - power(low, exponent+1)) / .exact(Double(exponent+1))
        }
        return powers.map { a,b,c in
            let p = multiply(multiply(polynomialPower(x, a+1), polynomialPower(y, b)), polynomialPower(z, c))
            var total = Interval.exact(0)
            for i in 0..<4 { for j in 0..<4 {
                total = total + p[i][j] * integralPower(box.u, u, i) * integralPower(box.v, v, j)
            } }
            return total * nx * .exact(domain.sign) / .exact(Double(a+1))
        }
    }
    private func power(_ value: Interval, _ exponent: Int) -> Interval {
        var result = Interval.exact(1)
        for _ in 0..<exponent { result = result * value }
        return result
    }
    private func enclosureWidth(_ value: Interval) -> Double {
        (OutwardScalarInterval.exact(value.upper) - .exact(value.lower)).upper
    }
    private func score(_ cell: Cell, targets: [Double]) -> Double {
        var maximum = 0.0
        for index in cell.values.indices { maximum = max(maximum, enclosureWidth(cell.values[index]) / targets[index]) }
        return maximum
    }
    private func failure(_ message: String, _ tolerance: ModelingTolerance) -> KernelError {
        KernelError(phase: .topology, code: .resourceLimitExceeded, tolerance: tolerance, message: message)
    }
}

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

    package static func originalExecution(options: BRepVolumeMomentOptions) throws -> OriginalQueryExecution {
        try options.validate()
        return OriginalQueryExecution(budget: try OriginalQueryBudget(workLimit: options.maximumWork),
            limits: try .init(maximumValueDepth: 32, maximumCoefficientDepth: 32,
                remainingSourceDepth: 16, maximumSubdivisionDepth: options.maximumSubdivisionDepth))
    }


    public func moments(of bodyID: BodyID, in model: BRepModel, options: BRepVolumeMomentOptions,
        tolerance: ModelingTolerance) throws -> BRepVolumeMoments {
        try options.validate()
        var execution = try Self.originalExecution(options: options)
        return try moments(of: bodyID, in: model, options: options, tolerance: tolerance, using: &execution)
    }

    public func moments(of bodyID: BodyID, in model: BRepModel, options: BRepVolumeMomentOptions,
        tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution) throws -> BRepVolumeMoments {
        try options.validate()
        let request = try execution.makeContributionHandle(workLimit: options.maximumWork,
            allocationPolicy: execution.effectiveAllocationPolicy, executionLimits: try .init(maximumValueDepth: 32, maximumCoefficientDepth: 32,
                remainingSourceDepth: 16, maximumSubdivisionDepth: options.maximumSubdivisionDepth))
        return try execution.withContributionScope(request) { execution in
        // FIXME(INCOMPLETE_IMPLEMENTATION): Manual moment admission now shares its
        // original work owner, but lower nonlinear/chart validation and temporary-byte
        // ports must be complete before decoded-source accounting can be certified.
        let certificate = try ValidatedBRepModel(model, tolerance: tolerance, validationLevel: .exact,
            maximumSubdivisionDepth: options.maximumSubdivisionDepth, remainingSourceDepth: 16, maximumAlgebraicDepth: 32, using: &execution)
        return try measure(of: bodyID, in: certificate, options: options, using: &execution)
        }
    }

    public func moments(of bodyID: BodyID, in validatedModel: ValidatedBRepModel,
        options: BRepVolumeMomentOptions) throws -> BRepVolumeMoments {
        try options.validate()
        var execution = try Self.originalExecution(options: options)
        return try moments(of: bodyID, in: validatedModel, options: options, using: &execution)
    }

    public func moments(of bodyID: BodyID, in validatedModel: ValidatedBRepModel,
        options: BRepVolumeMomentOptions, using execution: inout OriginalQueryExecution) throws -> BRepVolumeMoments {
        try options.validate()
        let request = try execution.makeContributionHandle(workLimit: options.maximumWork,
            allocationPolicy: execution.effectiveAllocationPolicy, executionLimits: try .init(maximumValueDepth: 32, maximumCoefficientDepth: 32,
                remainingSourceDepth: 16, maximumSubdivisionDepth: options.maximumSubdivisionDepth))
        return try execution.withContributionScope(request) { execution in
        return try measure(of: bodyID, in: validatedModel, options: options, using: &execution)
        }
    }

    private func measure(of bodyID: BodyID, in validatedModel: ValidatedBRepModel,
        options: BRepVolumeMomentOptions, using execution: inout OriginalQueryExecution) throws -> BRepVolumeMoments {
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
        var work: Int { execution.activeContributionHandle?.snapshot.work ?? execution.localWork }
        for shellID in try body.originalShellIDs(using: &execution) {
            try execution.consumeWork(1)
            guard let shell = model.shells[shellID] else { throw TopologyError.missingReference("Missing moment shell.") }
            for faceID in shell.faceIDs {
                try execution.consumeWork(1)
                guard let face = model.faces[faceID], let surface = model.geometry.surfaces[face.surfaceID] else { throw TopologyError.missingReference("Missing moment face support.") }
                var predicates: [(LoopRole, CertifiedSurfaceParameterLoopPredicate)] = []
                var allCurves: [SurfaceParameterCurve] = []
                var directedLoops: [(LoopRole,[SurfaceParameterCurve])] = []
                for loopID in face.loops {
                    guard let loop = model.loops[loopID] else { throw TopologyError.missingReference("Missing moment trim loop.") }
                    let curves = try OriginalParameterQueryStorage.map(loop.coedges, using: &execution) { use, execution -> SurfaceParameterCurve in
                        try execution.consumeWork(1)
                        guard let curve = use.surfaceParameterCurve else { throw failure("Volume moments require all original directed trim curves.", tolerance) }
                        return curve
                    }
                    let unwrapped = try SurfaceParameterLoopUnwrapper().unwrap(curves, on: surface,
                        tolerance: tolerance, context: "Volume moments",
                        maximumSubdivisionDepth: options.maximumSubdivisionDepth, remainingSourceDepth: 16,
                        maximumAlgebraicDepth: 32, using: &execution)
                    let lifted = try OriginalParameterQueryStorage.map(unwrapped, using: &execution) { item, execution in item.translatedCurve }
                    try OriginalParameterQueryStorage.append((loop.role, try CertifiedSurfaceParameterLoopPredicate(curves: lifted,
                        on: surface, tolerance: tolerance, maximumSubdivisionDepth: options.maximumSubdivisionDepth,
                        remainingSourceDepth: 16, maximumAlgebraicDepth: 32, using: &execution)), to: &predicates, using: &execution)
                    try OriginalParameterQueryStorage.append(contentsOf: lifted, to: &allCurves, using: &execution)
                    try OriginalParameterQueryStorage.append((loop.role,lifted), to: &directedLoops, using: &execution)
                }
                let sign = (face.orientation == .forward ? 1.0 : -1.0) * (shell.orientation == .forward ? 1.0 : -1.0)
                let exactRectangle = try ExactRectangularPcurveDomainResolver().resolve(face: face,
                    model: model, tolerance: tolerance, maximumSubdivisionDepth: options.maximumSubdivisionDepth,
                    remainingSourceDepth: 16, using: &execution) != nil
                // FIXME(INCOMPLETE_IMPLEMENTATION): Original moment preparation
                // now forwards the invocation's source/depth/algebra work owner.
                // Specialized rolling/offset/ruled and general nonlinear chart
                // producers still need their complete bounded lower preparation
                // before this path establishes all-domain query accounting.

                let domain = FaceDomain(surface: surface, prepared: try PreparedSurfaceDifferentialEncloser(surface: surface, tolerance: tolerance, remainingSourceDepth: 16, maximumSubdivisionDepth: options.maximumSubdivisionDepth, maximumAlgebraicDepth: 32, using: &execution), flux: try PreparedSurfaceAreaIntegrand(surface: surface, tolerance: tolerance,
                    maximumSubdivisionDepth:options.maximumSubdivisionDepth,remainingSourceDepth:16,maximumAlgebraicDepth:32, using: &execution), sign: sign, predicates: exactRectangle ? [] : predicates, curves: exactRectangle ? [] : allCurves, maximumDepth: options.maximumSubdivisionDepth)
                let box = try DefaultFaceParameterBoundsResolver(maximumSubdivisionDepth: options.maximumSubdivisionDepth).bounds(for: faceID, in: model, tolerance: tolerance, using: &execution)
                if !exactRectangle {
                    guard let anchorCurve = allCurves.first else { throw failure("Volume fan has no original trim anchor.", tolerance) }
                    let anchor = try anchorCurve.startParameter(tolerance: tolerance, using: &execution)
                    let unit = try ScalarInterval(lower: 0, upper: 1)
                    for (role,curves) in directedLoops {
                        let charts = try OriginalParameterQueryStorage.map(curves, using: &execution) { curve, execution in try SurfaceAreaParameterChartEncloser(curve: curve,
                            on:surface,tolerance:tolerance,maximumSubdivisionDepth:options.maximumSubdivisionDepth,
                            remainingSourceDepth:16,maximumAlgebraicDepth:32, using: &execution) }
                        let traversal = try signedLoopTraversal(charts, maximumDepth: options.maximumSubdivisionDepth, tolerance: tolerance, using: &execution)
                        let loopSign = sign * (role == .outer ? traversal : -traversal)
                        let loopDomain = FaceDomain(surface: surface, prepared: domain.prepared,
                            flux: domain.flux, sign: loopSign, predicates: [], curves: [], maximumDepth: options.maximumSubdivisionDepth)
                        for i in curves.indices {
                            if try domain.flux.fanIsExactlyZero(curve: curves[i], anchor: anchor, parameterChart: charts[i], using: &execution) { continue }
                            let fan = FanDomain(curve: curves[i], chart: charts[i], anchor: anchor)
                            if let native = try domain.flux.nativeFanDomains(curve: curves[i], anchor: anchor,
                                maximumCount: options.maximumWork-work, tolerance: tolerance, parameterChart: charts[i],
                                maximumSubdivisionDepth: options.maximumSubdivisionDepth, using: &execution) {
                                for owner in native {
                                    try execution.consumeWork(1)
                                    let fractions = SurfaceParameterBox(u: unit, v: owner.radialRange ?? unit)
                                    try OriginalParameterQueryStorage.append(contentsOf: admittedCells(domain: loopDomain, box: fractions, depth: 0,
                                        tolerance: tolerance, using: &execution, maximumDepth: options.maximumSubdivisionDepth, nativeDomain: owner, fan: fan), to: &cells, using: &execution)
                                }
                            } else {
                                try OriginalParameterQueryStorage.append(contentsOf: admittedCells(domain: loopDomain, box: SurfaceParameterBox(u: unit,v: unit),
                                    depth: 0, tolerance: tolerance, using: &execution, maximumDepth: options.maximumSubdivisionDepth, fan: fan), to: &cells, using: &execution)
                            }
                        }
                    }
                    continue
                }
                if let native = try domain.flux.nativeRectangleDomains(over: box,
                    maximumCount: options.maximumWork-work, tolerance: tolerance,
                    maximumSubdivisionDepth: options.maximumSubdivisionDepth, using: &execution) {
                    for owner in native {
                        try execution.consumeWork(1)
                        try OriginalParameterQueryStorage.append(try cell(domain: domain, box: owner.rectangle, depth: 0,
                            tolerance: tolerance, using: &execution, nativeDomain: owner), to: &cells, using: &execution)
                    }
                } else {
                    try OriginalParameterQueryStorage.append(try cell(domain: domain, box: box, depth: 0, tolerance: tolerance, using: &execution), to: &cells, using: &execution)
                }
            }
        }
        guard !cells.isEmpty else { throw failure("A volume-moment body has no boundary cells.", tolerance) }
        while true {
            try execution.consumeWork(1)
            try execution.consumeWork(cells.count)
            var sums = try OriginalParameterQueryStorage.repeated(Interval.exact(0), count: 10, using: &execution)
            for item in cells { for i in 0..<10 { try execution.consumeWork(1); sums[i] = sums[i] + item.values[i] } }
            guard sums.allSatisfy({ $0.lower.isFinite && $0.upper.isFinite && $0.lower <= $0.upper }) else {
                throw failure("Original accumulated volume moments have no finite ordered enclosure.", tolerance)
            }
            let targets = try OriginalParameterQueryStorage.map(sums, using: &execution) { value, execution -> Double in
                let minimumAbsolute = value.lower > 0 ? value.lower : value.upper < 0 ? -value.upper : 0
                let relative = OutwardScalarInterval.exact(options.relativeAccuracy) * .exact(minimumAbsolute)
                return max(options.absoluteAccuracy, relative.lower)
            }
            if zip(sums, targets).allSatisfy({ enclosureWidth($0.0) <= $0.1 }) {
                guard sums[0].lower > 0 else { throw failure("Volume-moment enclosure does not prove positive material volume.", tolerance) }
                try CurrentTaskCancellationChecker().checkCancellation()
                return try BRepVolumeMoments(enclosures: OriginalParameterQueryStorage.map(sums, using: &execution) { value, execution in try ScalarInterval(lower: value.lower, upper: value.upper) }, consumedWork: work)
            }
            try execution.consumeWork(cells.count)
            guard let index = cells.indices.max(by: { a, b in
                score(cells[a], targets: targets) < score(cells[b], targets: targets)
            }) else { throw failure("Volume-moment adaptive cover disappeared.", tolerance) }
            let selected = cells.remove(at: index)
            guard selected.depth < options.maximumSubdivisionDepth else { throw failure("Volume-moment depth exhausted before requested enclosure widths.", tolerance) }
            let axisU = selected.box.u.width >= selected.box.v.width
            let interval = axisU ? selected.box.u : selected.box.v
            let middle = interval.midpoint
            guard middle > interval.lower, middle < interval.upper else { throw failure("Volume-moment representable cell resolution exhausted.", tolerance) }
            try execution.retainStorage(bytes: 2 * MemoryLayout<ScalarInterval>.stride)
            for range in [try ScalarInterval(lower: interval.lower, upper: middle), try ScalarInterval(lower: middle, upper: interval.upper)] {
                try execution.consumeWork(1)
                let box = SurfaceParameterBox(u: axisU ? range : selected.box.u, v: axisU ? selected.box.v : range)
                try OriginalParameterQueryStorage.append(contentsOf: admittedCells(domain: selected.domain, box: box, depth: selected.depth + 1,
                    tolerance: tolerance, using: &execution, maximumDepth: options.maximumSubdivisionDepth, nativeDomain: selected.nativeDomain, fan: selected.fan), to: &cells, using: &execution)
            }
        }
    }

    private func cell(domain: FaceDomain, box: SurfaceParameterBox, depth: Int,
        tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution,
        nativeDomain: SurfaceAreaNativeSpanDomain? = nil, fan: FanDomain? = nil) throws -> Cell {
        return try execution.withGeometricDepthOffset(depth) { execution in
        try execution.admitGeometricDepth(0)
            if let fan {
                let range = try domain.flux.volumeMomentFanBounds(curve: fan.curve, parameterChart: fan.chart,
                    anchor: fan.anchor, reference: .origin, boundaryFraction: box.u, radialFraction: box.v,
                    tolerance: tolerance, domain: nativeDomain, using: &execution)
                let midpoint = try domain.flux.volumeMomentFanBounds(curve: fan.curve, parameterChart: fan.chart,
                    anchor: fan.anchor, reference: .origin,
                    boundaryFraction: ScalarInterval(lower: box.u.midpoint,upper: box.u.midpoint),
                    radialFraction: ScalarInterval(lower: box.v.midpoint,upper: box.v.midpoint),
                    tolerance: tolerance, domain: nativeDomain, using: &execution)
                return Cell(domain: domain, box: box, depth: depth,
                    values: try integratedFields(range: range, midpoint: midpoint, box: box, sign: domain.sign,
                        tolerance: tolerance, using: &execution), nativeDomain: nativeDomain, fan: fan)
            }
            var meetsBoundary = false
            let width = max(box.u.width, box.v.width) / 4
            for curve in domain.curves {
                let remainingDepth = domain.maximumDepth-depth
                let ranges = try CertifiedSurfaceParameterCurveEncloser(maximumSubdivisionDepth: remainingDepth).enclosures(for: curve, on: domain.surface,
                        maximumWidth: width, tolerance: tolerance, using: &execution)
                if try OriginalParameterQueryStorage.contains(ranges, using: &execution, predicate: { range, execution in range.u.intersects(box.u) && range.v.intersects(box.v) }) { meetsBoundary = true; break }
            }
            var inside = true
            if !meetsBoundary {
                for (role, predicate) in domain.predicates {
                    let classification = try predicate.classify(Point2D(x: box.u.midpoint, y: box.v.midpoint), tolerance: tolerance, maximumSubdivisionDepth: domain.maximumDepth-depth, using: &execution)
                    if role == .outer && classification == .outside || role == .inner && classification == .inside { inside = false; break }
                }
            }
            if !inside { return Cell(domain: domain, box: box, depth: depth, values: try OriginalParameterQueryStorage.repeated(Interval.exact(0), count: 10, using: &execution)) }
            if case .plane = domain.surface, !meetsBoundary {
                return Cell(domain: domain, box: box, depth: depth,
                    values: try planarMoments(domain: domain, box: box, depth: depth, tolerance: tolerance, using: &execution))
            }
            let range = try domain.flux.volumeMomentBounds(over: box, reference: .origin,
                tolerance: tolerance, domain: nativeDomain, using: &execution)
            let size = OutwardScalarInterval.exact(box.u.upper) - .exact(box.u.lower)
            let height = OutwardScalarInterval.exact(box.v.upper) - .exact(box.v.lower)
            let measure = size*height*OutwardScalarInterval.exact(domain.sign)
            var integrated = try OriginalParameterQueryStorage.map(range, using: &execution) { field, execution in field.value * measure }
            if !meetsBoundary {
                let midpoint = SurfaceParameterBox(u: try ScalarInterval(lower: box.u.midpoint, upper: box.u.midpoint),
                    v: try ScalarInterval(lower: box.v.midpoint, upper: box.v.midpoint))
                let values = try domain.flux.volumeMomentBounds(over: midpoint, reference: .origin,
                    tolerance: tolerance, domain: nativeDomain, using: &execution)
                for i in integrated.indices {
                    try execution.consumeWork(1)
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
            let values = try OriginalParameterQueryStorage.map(integrated, using: &execution) { value, execution in
                meetsBoundary ? Interval(lower: min(0,value.lower), upper: max(0,value.upper))
                    : Interval(lower: value.lower,upper: value.upper)
            }
            return Cell(domain: domain, box: box, depth: depth, values: values, nativeDomain: nativeDomain)
        }
    }
    private func integratedFields(range: [SurfaceAreaIntegrandBounds], midpoint: [SurfaceAreaIntegrandBounds],
        box: SurfaceParameterBox, sign: Double, tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution) throws -> [Interval] {
        let size = OutwardScalarInterval.exact(box.u.upper) - .exact(box.u.lower)
        let height = OutwardScalarInterval.exact(box.v.upper) - .exact(box.v.lower)
        let measure = size*height*OutwardScalarInterval.exact(sign)
        return try OriginalParameterQueryStorage.map(range.indices, using: &execution) { i, execution in
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
        tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution,
        maximumDepth: Int, nativeDomain: SurfaceAreaNativeSpanDomain? = nil, fan: FanDomain? = nil) throws -> [Cell] {
        try execution.admitGeometricDepth(depth)
        try execution.consumeWork(1)
        do {
            try execution.retainStorage(bytes: MemoryLayout<Cell>.stride)
            return [try cell(domain: domain,box: box,depth: depth,tolerance: tolerance,
            using: &execution,nativeDomain: nativeDomain,fan: fan)] }
        catch is SurfaceAreaEnclosureRefinementRequired {}
        catch let error as KernelError where error.code == .singularSystem || error.code == .singularGeometry {}
        guard depth < maximumDepth else { throw failure("Original volume fan enclosure exhausted its retained depth.",tolerance) }
        let axisU = box.u.width >= box.v.width, interval = axisU ? box.u : box.v
        let midpoint = interval.midpoint
        guard midpoint > interval.lower,midpoint < interval.upper else {
            throw failure("Original volume fan enclosure exhausted representable coordinates.",tolerance)
        }
        var result: [Cell] = []
        try execution.retainStorage(bytes: 2 * MemoryLayout<ScalarInterval>.stride)
        for range in [try ScalarInterval(lower: interval.lower,upper: midpoint),
                      try ScalarInterval(lower: midpoint,upper: interval.upper)] {
            try OriginalParameterQueryStorage.append(contentsOf: admittedCells(domain: domain,
                box: SurfaceParameterBox(u: axisU ? range : box.u,v: axisU ? box.v : range),
                depth: depth+1,tolerance: tolerance,using: &execution,maximumDepth: maximumDepth,nativeDomain: nativeDomain,fan: fan), to: &result, using: &execution)
        }
        return result
    }

    private func signedLoopTraversal(_ charts: [SurfaceAreaParameterChartEncloser], maximumDepth: Int,
        tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution) throws -> Double {
        struct FluxCell { let chart: SurfaceAreaParameterChartEncloser; let range: ScalarInterval; let depth: Int; let integral: OutwardScalarInterval }
        func make(_ chart: SurfaceAreaParameterChartEncloser,_ range: ScalarInterval,_ depth: Int, using execution: inout OriginalQueryExecution) throws -> FluxCell {
            try execution.admitGeometricDepth(depth)
            try execution.consumeWork(1)
            let bounds = try execution.withGeometricDepthOffset(depth) { execution in
                try chart.signedFluxIntegrationBounds(over: range, tolerance: tolerance, using: &execution)
            }
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
        var cells = try OriginalParameterQueryStorage.map(charts, using: &execution) { chart, execution in try make(chart, unit, 0, using: &execution) }
        while true {
            try execution.consumeWork(1)
            try execution.consumeWork(cells.count)
            let sum = try OriginalParameterQueryStorage.reduce(cells, initial: OutwardScalarInterval.exact(0), using: &execution) { sum, cell, execution in sum + cell.integral }
            if sum.lower > 0 { return 1 }
            if sum.upper < 0 { return -1 }
            try execution.consumeWork(cells.count)
            guard let index = cells.indices.max(by: { cells[$0].integral.upper-cells[$0].integral.lower < cells[$1].integral.upper-cells[$1].integral.lower }) else {
                throw failure("Original trim loop lost its signed-area cover.",tolerance)
            }
            let selected = cells.remove(at: index), midpoint = selected.range.midpoint
            guard selected.depth < maximumDepth,midpoint > selected.range.lower,midpoint < selected.range.upper else {
                throw failure("Original trim loop traversal is unresolved under retained work/depth bounds.",tolerance)
            }
            try OriginalParameterQueryStorage.append(try make(selected.chart,ScalarInterval(lower: selected.range.lower,upper: midpoint),selected.depth+1, using: &execution), to: &cells, using: &execution)
            try OriginalParameterQueryStorage.append(try make(selected.chart,ScalarInterval(lower: midpoint,upper: selected.range.upper),selected.depth+1, using: &execution), to: &cells, using: &execution)
        }
    }

    private func planarMoments(domain: FaceDomain, box: SurfaceParameterBox, depth: Int,
        tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution) throws -> [Interval] {
        let u = box.u.midpoint, v = box.v.midpoint
        let tiny = SurfaceParameterBox(
            u: try ScalarInterval(lower: max(box.u.lower, u.nextDown), upper: min(box.u.upper, u.nextUp)),
            v: try ScalarInterval(lower: max(box.v.lower, v.nextDown), upper: min(box.v.upper, v.nextUp)))
        let e = try domain.prepared.enclosure(over: tiny, tolerance: tolerance,
            maximumSpanCount: 262_144, maximumSubdivisionDepth: domain.maximumDepth-depth,
            remainingSourceDepth: 16, using: &execution)
        func interval(_ value: ScalarInterval) -> Interval { Interval(lower: value.lower, upper: value.upper) }
        typealias Polynomial = [[Interval]]
        func zeroPolynomial(using execution: inout OriginalQueryExecution) throws -> Polynomial {
            var rows: Polynomial = []
            for _ in 0..<4 {
                let row = try OriginalParameterQueryStorage.repeated(Interval.exact(0), count: 4, using: &execution)
                try OriginalParameterQueryStorage.append(row, to: &rows, using: &execution)
            }
            return rows
        }
        func coordinate(_ p: ScalarInterval, _ a: ScalarInterval, _ b: ScalarInterval,
            using execution: inout OriginalQueryExecution) throws -> Polynomial {
            var values = try zeroPolynomial(using: &execution)
            values[0][0] = interval(p); values[1][0] = interval(a); values[0][1] = interval(b)
            return values
        }
        func multiply(_ a: Polynomial, _ b: Polynomial, using execution: inout OriginalQueryExecution) throws -> Polynomial {
            var result = try zeroPolynomial(using: &execution)
            for i in 0..<4 { for j in 0..<4 { for k in 0..<(4-i) { for l in 0..<(4-j) {
                try execution.consumeWork(1)
                result[i+k][j+l] = result[i+k][j+l] + a[i][j] * b[k][l]
            } } } }
            return result
        }
        func polynomialPower(_ a: Polynomial, _ n: Int, using execution: inout OriginalQueryExecution) throws -> Polynomial {
            var result = try zeroPolynomial(using: &execution)
            result[0][0] = .exact(1)
            for _ in 0..<n { result = try multiply(result, a, using: &execution) }
            return result
        }
        let x = try coordinate(e.position.x, e.tangentU.x, e.tangentV.x, using: &execution)
        let y = try coordinate(e.position.y, e.tangentU.y, e.tangentV.y, using: &execution)
        let z = try coordinate(e.position.z, e.tangentU.z, e.tangentV.z, using: &execution)
        let nx = interval(e.tangentU.y) * interval(e.tangentV.z) - interval(e.tangentU.z) * interval(e.tangentV.y)
        func integralPower(_ bounds: ScalarInterval, _ center: Double, _ exponent: Int, using execution: inout OriginalQueryExecution) throws -> Interval {
            let low = Interval(lower: (bounds.lower-center).nextDown, upper: (bounds.lower-center).nextUp)
            let high = Interval(lower: (bounds.upper-center).nextDown, upper: (bounds.upper-center).nextUp)
            return try (power(high, exponent+1, using: &execution) - power(low, exponent+1, using: &execution)) / .exact(Double(exponent+1))
        }
        return try OriginalParameterQueryStorage.map(powers, using: &execution) { power, execution in
            let (a, b, c) = power
            let xPower = try polynomialPower(x, a+1, using: &execution)
            let yPower = try polynomialPower(y, b, using: &execution)
            let zPower = try polynomialPower(z, c, using: &execution)
            let xy = try multiply(xPower, yPower, using: &execution)
            let p = try multiply(xy, zPower, using: &execution)
            var total = Interval.exact(0)
            for i in 0..<4 { for j in 0..<4 {
                try execution.consumeWork(1)
                let uPower = try integralPower(box.u, u, i, using: &execution)
                let vPower = try integralPower(box.v, v, j, using: &execution)
                total = total + p[i][j] * uPower * vPower
            } }
            return total * nx * .exact(domain.sign) / .exact(Double(a+1))
        }
    }
    private func power(_ value: Interval, _ exponent: Int, using execution: inout OriginalQueryExecution) throws -> Interval {
        var result = Interval.exact(1)
        for _ in 0..<exponent { try execution.consumeWork(1); result = result * value }
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

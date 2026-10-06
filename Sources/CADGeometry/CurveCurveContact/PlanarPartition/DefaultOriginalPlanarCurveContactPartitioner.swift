import CADCore

/// Complete exact original native planar contacts using the shared source algebra.
public struct DefaultOriginalPlanarCurveContactPartitioner: OriginalPlanarCurveContactPartitioning {
    public init() {}

    public func sideWinding(of span: OriginalCurveRootSpan3D, forward: Bool,
        contours: [[OriginalPlanarDirectedCurve]], on plane: Plane3D,
        retaining partitions: [OriginalPlanarCurveContactPartition],
        allowance: inout OriginalCurveContactAllowance, tolerance: ModelingTolerance)
        throws -> OriginalPlanarCurveSideWinding {
        let exactContext = allowance.budget.enterExactAlgebra()
        defer { allowance.budget.restoreExactAlgebra(exactContext) }
        guard tolerance == allowance.budget.tolerance else {
            throw GeometryConversionError.invalidInput("Original winding requires its retained caller tolerance.")
        }
        let source = try prepareWinding(contours: contours, on: plane, allowance: &allowance, tolerance: tolerance)
        return try sideWinding(of: span, forward: forward, retainingSource: source,
            retaining: partitions, allowance: &allowance, tolerance: tolerance)
    }

    public func prepareWinding(contours: [[OriginalPlanarDirectedCurve]], on plane: Plane3D,
        allowance: inout OriginalCurveContactAllowance, tolerance: ModelingTolerance)
        throws -> OriginalPlanarCurveWindingSource {
        let exactContext = allowance.budget.enterExactAlgebra()
        defer { allowance.budget.restoreExactAlgebra(exactContext) }
        guard tolerance == allowance.budget.tolerance else {
            throw GeometryConversionError.invalidInput("Original winding source requires its caller tolerance.")
        }
        return try OriginalPlanarCurveWindingProducer().prepare(contours: contours, plane: plane, budget: &allowance.budget)
    }

    public func sideWinding(of span: OriginalCurveRootSpan3D, forward: Bool,
        retainingSource: OriginalPlanarCurveWindingSource,
        retaining partitions: [OriginalPlanarCurveContactPartition],
        allowance: inout OriginalCurveContactAllowance, tolerance: ModelingTolerance)
        throws -> OriginalPlanarCurveSideWinding {
        let exactContext = allowance.budget.enterExactAlgebra()
        defer { allowance.budget.restoreExactAlgebra(exactContext) }
        guard tolerance == allowance.budget.tolerance else {
            throw GeometryConversionError.invalidInput("Original winding query requires its caller tolerance.")
        }
        return try OriginalPlanarCurveWindingProducer().produce(span: span, forward: forward,
            source: retainingSource, partitions: partitions, budget: &allowance.budget)
    }

    private struct Owner {
        let index: Int
        let parameters: ScalarInterval
        let homogeneous: [ExactBivariatePolynomial]
    }

    public func monotoneOverlaps(retaining partition: OriginalPlanarCurveContactPartition,
        firstMerged: OriginalPlanarCurveMergedPartition, secondMerged: OriginalPlanarCurveMergedPartition,
        allowance: inout OriginalCurveContactAllowance, tolerance: ModelingTolerance)
        throws -> [OriginalPlanarCurveMonotoneOverlap] {
        let exactContext = allowance.budget.enterExactAlgebra()
        defer { allowance.budget.restoreExactAlgebra(exactContext) }
        guard tolerance == allowance.budget.tolerance else {
            throw GeometryConversionError.invalidInput("Monotone overlaps require the retained invocation tolerance.")
        }
        return try OriginalPlanarCurveOverlapProducer().produce(partition: partition,
            first: firstMerged, second: secondMerged, budget: &allowance.budget)
    }

    public func orderOutgoingGerms(_ germs: [OriginalPlanarCurveOutgoingGerm], on plane: Plane3D,
        retaining partitions: [OriginalPlanarCurveContactPartition],
        allowance: inout OriginalCurveContactAllowance, tolerance: ModelingTolerance)
        throws -> OriginalPlanarCurveGermOrder {
        let exactContext = allowance.budget.enterExactAlgebra()
        defer { allowance.budget.restoreExactAlgebra(exactContext) }
        guard tolerance == allowance.budget.tolerance else {
            throw GeometryConversionError.invalidInput("Outgoing native germs require one retained caller tolerance.")
        }
        return try OriginalPlanarCurveGermOrderProducer().produce(germs: germs, plane: plane,
            partitions: partitions, budget: &allowance.budget)
    }

    public func mergeCuts(source: BSplineCurve3D, parameters: ScalarInterval,
        endpoints: [OriginalCurveRootEndpoint], allowance: inout OriginalCurveContactAllowance,
        tolerance: ModelingTolerance) throws -> OriginalPlanarCurveMergedPartition {
        let exactContext = allowance.budget.enterExactAlgebra()
        defer { allowance.budget.restoreExactAlgebra(exactContext) }
        try tolerance.validate()
        guard tolerance == allowance.budget.tolerance else {
            throw GeometryConversionError.invalidInput("Merged original cuts require the retained caller tolerance.")
        }
        let reserve: (Int) throws -> Void = { try allowance.budget.retainBytes($0) }
        try withoutActuallyEscaping(reserve) { storage in
            try Curve3D.bSpline(source).validateOriginalSource(tolerance: tolerance,
                remainingSourceDepth: 0, maximumSubdivisionDepth: allowance.budget.maximumSubdivisionDepth,
                consumeWork: { _ in try allowance.budget.work(1) }, consumeStorage: storage)
        }
        guard (1...3).contains(source.degree), !source.isPeriodic,
            parameters.width > 0, parameters.lower >= source.knots[source.degree],
            parameters.upper <= source.knots[source.controlPointCount] else {
            throw GeometryConversionError.invalidInput("Merged exact native planar cuts need degree-one/two/three contained positive trims.")
        }
        for endpoint in endpoints {
            try allowance.budget.work(1)
            switch endpoint {
            case .authored(let value):
                guard value.isFinite, value >= parameters.lower, value <= parameters.upper else {
                    throw GeometryConversionError.invalidInput("Authored merged endpoint lies outside its original trim.")
                }
            case .algebraic(let root):
                try GeometryStructuralComparisonWork.charge(curve: .bSpline(source), using: { try allowance.budget.work($0) })
                try GeometryStructuralComparisonWork.charge(curve: .bSpline(root.source), using: { try allowance.budget.work($0) })
                guard root.source == source, root.certificationTolerance == tolerance,
                    root.spanIndex >= source.degree, root.spanIndex < source.controlPointCount,
                    source.knots[root.spanIndex] < parameters.upper,
                    source.knots[root.spanIndex + 1] > parameters.lower else {
                    throw GeometryConversionError.invalidInput("Algebraic merged endpoint lacks the original source/trim owner.")
                }
            }
        }
        let partition = try OriginalPlanarCurveCutProducer().produce(source: source, parameters: parameters,
            events: [], firstSource: true, mergeEndpoints: endpoints, budget: &allowance.budget)
        try RationalAlgebraStorage.retain(partition.cuts.count, of: OriginalPlanarCurveMergedCut.self, usage: &allowance.budget)
        return .init(source: source, parameters: parameters, tolerance: tolerance,
            cuts: partition.cuts.map(OriginalPlanarCurveMergedCut.init), segments: partition.segments)
    }

    public func partition(first: BSplineCurve3D, firstParameters: ScalarInterval,
        second: BSplineCurve3D, secondParameters: ScalarInterval, on plane: Plane3D,
        allowance: inout OriginalCurveContactAllowance, tolerance: ModelingTolerance)
        throws -> OriginalPlanarCurveContactPartition {
        try tolerance.validate(); try plane.validate(tolerance: tolerance)
        guard tolerance == allowance.budget.tolerance else {
            throw GeometryConversionError.invalidInput("Original planar partition requires its caller's retained tolerance.")
        }
        func validate(_ source: BSplineCurve3D, budget: inout NativeCurveCurveContactBudget) throws {
            let reserve: (Int) throws -> Void = { try budget.retainBytes($0) }
            try withoutActuallyEscaping(reserve) { storage in
                try Curve3D.bSpline(source).validateOriginalSource(tolerance: tolerance,
                    remainingSourceDepth: 0, maximumSubdivisionDepth: budget.maximumDepth,
                    consumeWork: { _ in try budget.work(1) }, consumeStorage: storage)
            }
        }
        try validate(first, budget: &allowance.budget)
        try validate(second, budget: &allowance.budget)
        guard
            (1...3).contains(first.degree), (1...3).contains(second.degree),
            !first.isPeriodic, !second.isPeriodic, firstParameters.width > 0, secondParameters.width > 0,
            firstParameters.lower >= first.knots[first.degree],
            firstParameters.upper <= first.knots[first.controlPointCount],
            secondParameters.lower >= second.knots[second.degree],
            secondParameters.upper <= second.knots[second.controlPointCount],
            try first.domain.containsSpan(from: firstParameters.lower, to: firstParameters.upper, tolerance: tolerance),
            try second.domain.containsSpan(from: secondParameters.lower, to: secondParameters.upper, tolerance: tolerance) else {
            throw GeometryConversionError.invalidInput("Exact planar partition requires original nonperiodic degree-one/two/three contained positive trims and one tolerance.")
        }
        let normal = plane.normal
        let axes: (Int, Int)
        if abs(normal.x) >= abs(normal.y), abs(normal.x) >= abs(normal.z) { axes = (1, 2) }
        else if abs(normal.y) >= abs(normal.z) { axes = (0, 2) }
        else { axes = (0, 1) }
        func owners(_ source: BSplineCurve3D, over range: ScalarInterval, alongU: Bool,
            budget: inout NativeCurveCurveContactBudget) throws -> [Owner] {
            var result: [Owner] = []
            for index in source.degree..<source.controlPointCount {
                try budget.work(1)
                guard source.knots[index] < source.knots[index + 1] else { continue }
                let lower = max(range.lower, source.knots[index])
                let upper = min(range.upper, source.knots[index + 1])
                guard lower < upper else { continue }
                let original = try OriginalRationalCurvePolynomial(source: source, spanIndex: index,
                    tolerance: tolerance, usage: &budget)
                let values: [ExactBivariatePolynomial]
                if alongU { values = original.homogeneous }
                else {
                    try RationalAlgebraStorage.retain(4, of: ExactBivariatePolynomial.self, usage: &budget)
                    values = try original.homogeneous.map { try $0.exchangedAxes(usage: &budget) }
                }
                try RationalAlgebraStorage.retain(3, of: (Double, Double).self, usage: &budget)
                var planeResidual = ExactBivariatePolynomial.zero
                for (axis, originalValues) in [(normal.x, plane.origin.x), (normal.y, plane.origin.y),
                    (normal.z, plane.origin.z)].enumerated() {
                    let residual = try values[axis].subtracting(values[3].scaled(
                        by: .originalDouble(originalValues.1, usage: &budget), usage: &budget), usage: &budget)
                    planeResidual = try planeResidual.adding(residual.scaled(
                        by: .originalDouble(originalValues.0, usage: &budget), usage: &budget), usage: &budget)
                }
                guard planeResidual.isZero else {
                    throw GeometryConversionError.invalidInput("Original planar contact partition cannot project a nonplanar native law into its supplied plane.")
                }
                try RationalAlgebraStorage.retain(1, of: Owner.self, usage: &budget)
                result.append(Owner(index: index, parameters: try .init(lower: lower, upper: upper), homogeneous: values))
            }
            guard !result.isEmpty else { throw budget.exhausted() }
            return result
        }
        let a = try owners(first, over: firstParameters, alongU: true, budget: &allowance.budget)
        let b = try owners(second, over: secondParameters, alongU: false, budget: &allowance.budget)
        var events: [OriginalPlanarCurveContactEvent] = []
        var overlaps: [OriginalPlanarCurveContactOverlap] = []
        for firstOwner in a { for secondOwner in b {
            try allowance.budget.cell()
            let domain = SurfaceParameterBox(u: firstOwner.parameters, v: secondOwner.parameters)
            try RationalAlgebraStorage.retain(3, of: ExactBivariatePolynomial.self, usage: &allowance.budget)
            var equations: [ExactBivariatePolynomial] = []
            equations.reserveCapacity(3)
            for axis in 0..<3 {
                equations.append(try firstOwner.homogeneous[axis].multiplied(by: secondOwner.homogeneous[3],
                    usage: &allowance.budget).subtracting(secondOwner.homogeneous[axis].multiplied(
                        by: firstOwner.homogeneous[3], usage: &allowance.budget), usage: &allowance.budget))
            }
            let x = equations[axes.0], y = equations[axes.1]
            let common = try ExactBivariateGCD().greatestCommonDivisor(x, y, usage: &allowance.budget)
            let depth = allowance.budget.maximumDepth
            func endpoint(_ coordinate: ExactMonotoneGraphEndpoint, source: BSplineCurve3D,
                index: Int, budget: inout NativeCurveCurveContactBudget) throws -> OriginalCurveRootEndpoint {
                let root: ExactAlgebraicRealRoot
                switch coordinate {
                case .algebraic(let retained): root = retained
                case .authored(let value):
                    let enclosure = try value.outwardInterval(usage: &budget)
                    if enclosure.lower == enclosure.upper { return .authored(enclosure.lower) }
                    let polynomial = try ExactBivariatePolynomial.coordinate(alongU: true, usage: &budget)
                        .subtracting(.constant(value, usage: &budget), usage: &budget)
                    root = try .init(polynomial: polynomial,
                        isolation: .init(lower: value, upper: value, isRationalStation: true,
                            isolationDepth: coordinate.depth, excludesLowerEndpoint: false, excludesUpperEndpoint: false),
                        usage: &budget)
                }
                return try .algebraic(OriginalCurveRootBoundary.retaining(source: source, spanIndex: index,
                    coordinate: root, maximumSubdivisionDepth: budget.maximumSubdivisionDepth,
                    tolerance: tolerance, usage: &budget, maximumAlgebraicDepth: budget.maximumAlgebraicDepth))
            }
            func event(_ root: ExactBivariateSystemRoot, overlap: Bool, exchanged: Bool = false,
                budget: inout NativeCurveCurveContactBudget) throws -> OriginalPlanarCurveContactEvent {
                for equation in equations {
                    let originalEquation = try exchanged ? equation.exchangedAxes(usage: &budget) : equation
                    guard case .zero = try root.sign(of: originalEquation, maximumDepth: depth, usage: &budget) else {
                        throw GeometryConversionError.invalidInput("Original planar contact is not an exact zero of all original XYZ equations.")
                    }
                }
                let firstCoordinate = try root.originalCoordinate(alongU: !exchanged, maximumDepth: depth, usage: &budget)
                let secondCoordinate = try root.originalCoordinate(alongU: exchanged, maximumDepth: depth, usage: &budget)
                try RationalAlgebraStorage.retain(1, of: OriginalPlanarCurveContactEvent.self, usage: &budget)
                return try .init(firstEndpoint: endpoint(firstCoordinate, source: first, index: firstOwner.index, budget: &budget),
                    secondEndpoint: endpoint(secondCoordinate, source: second, index: secondOwner.index, budget: &budget),
                    firstNativeSpanIndex: firstOwner.index, secondNativeSpanIndex: secondOwner.index,
                    belongsToCommonFactor: overlap, originalPair: root, originalPairAxesExchanged: exchanged)
            }
            func span(_ source: BSplineCurve3D, owner: Owner,
                budget: inout NativeCurveCurveContactBudget) throws -> OriginalCurveRootSpan3D {
                let maximumSpans = max(1, budget.availableWork)
                return try .init(source: .bSpline(source), start: .authored(owner.parameters.lower),
                    end: .authored(owner.parameters.upper), nativeSpanIndex: owner.index,
                    maximumParameterWidth: tolerance.relative, maximumSubdivisionDepth: depth,
                    tolerance: tolerance, storageByteStride: MemoryLayout<UInt32>.stride, usage: &budget,
                    maximumSpanCount: maximumSpans, remainingSourceDepth: 0)
            }
            var componentEvents: [OriginalPlanarCurveContactEvent] = []
            var projection: OriginalRationalPlaneCurveProjection?
            var atlas: OriginalRationalPlaneCurveAtlas?
            var oppositeProjection: OriginalRationalPlaneCurveProjection?
            var hasContinuousComponent = common.isZero
            if common.isZero {
                guard equations.allSatisfy({ $0.isZero }) else { throw allowance.budget.exhausted() }
                for u in [domain.u.lower, domain.u.upper] { for v in [domain.v.lower, domain.v.upper] {
                    try RationalAlgebraStorage.retain(1, of: OriginalPlanarCurveContactEvent.self, usage: &allowance.budget)
                    componentEvents.append(.init(firstEndpoint: .authored(u), secondEndpoint: .authored(v),
                        firstNativeSpanIndex: firstOwner.index, secondNativeSpanIndex: secondOwner.index,
                        belongsToCommonFactor: true, originalPair: nil))
                } }
            } else if common.uDegree > 0 || common.vDegree > 0 {
                for equation in equations {
                    _ = try equation.dividedExactly(by: common, usage: &allowance.budget)
                }
                let zeroLaw = try OriginalRationalZeroSetAuthority(original: common, usage: &allowance.budget)
                let originalProjection = try OriginalRationalPlaneCurveProjection(original: zeroLaw,
                    over: domain, maximumDepth: depth, usage: &allowance.budget)
                projection = originalProjection
                if let finite = try originalProjection.finiteOriginalRoots(usage: &allowance.budget) {
                    for root in finite { events.append(try event(root, overlap: false, budget: &allowance.budget)) }
                } else {
                    hasContinuousComponent = true
                }
                for station in originalProjection.stations {
                    for root in station.roots where hasContinuousComponent {
                        componentEvents.append(try event(root, overlap: true, budget: &allowance.budget))
                    }
                }
                for coordinate in originalProjection.verticalComponents {
                    for v in [domain.v.lower, domain.v.upper] {
                        for equation in equations {
                            let transverse = try equation.restricted(alongU: false,
                                station: .originalDouble(v, usage: &allowance.budget), usage: &allowance.budget)
                            guard case .zero = try coordinate.sign(of: transverse, maximumDepth: depth,
                                usage: &allowance.budget) else { throw allowance.budget.exhausted() }
                        }
                        try RationalAlgebraStorage.retain(1, of: OriginalPlanarCurveContactEvent.self, usage: &allowance.budget)
                        componentEvents.append(try .init(firstEndpoint: endpoint(coordinate, source: first,
                            index: firstOwner.index, budget: &allowance.budget), secondEndpoint: .authored(v),
                            firstNativeSpanIndex: firstOwner.index, secondNativeSpanIndex: secondOwner.index,
                            belongsToCommonFactor: true, originalPair: nil))
                    }
                }
                for v in originalProjection.horizontalComponents {
                    for u in [domain.u.lower, domain.u.upper] {
                        try RationalAlgebraStorage.retain(1, of: OriginalPlanarCurveContactEvent.self, usage: &allowance.budget)
                        componentEvents.append(try .init(firstEndpoint: .authored(u),
                            secondEndpoint: endpoint(.authored(v), source: second, index: secondOwner.index, budget: &allowance.budget),
                            firstNativeSpanIndex: firstOwner.index, secondNativeSpanIndex: secondOwner.index,
                            belongsToCommonFactor: true, originalPair: nil))
                    }
                }
                if hasContinuousComponent {
                    let oppositeLaw = try OriginalRationalZeroSetAuthority(original: common.exchangedAxes(usage: &allowance.budget),
                        usage: &allowance.budget)
                    let opposite = try OriginalRationalPlaneCurveProjection(original: oppositeLaw,
                        over: .init(u: domain.v, v: domain.u), maximumDepth: depth, usage: &allowance.budget)
                    oppositeProjection = opposite
                    for station in opposite.stations {
                        for root in station.roots {
                            componentEvents.append(try event(root, overlap: true, exchanged: true, budget: &allowance.budget))
                        }
                    }
                    for coordinate in opposite.verticalComponents {
                        for u in [domain.u.lower, domain.u.upper] {
                            for equation in equations {
                                let transverse = try equation.restricted(alongU: true,
                                    station: .originalDouble(u, usage: &allowance.budget), usage: &allowance.budget)
                                guard case .zero = try coordinate.sign(of: transverse, maximumDepth: depth,
                                    usage: &allowance.budget) else { throw allowance.budget.exhausted() }
                            }
                            try RationalAlgebraStorage.retain(1, of: OriginalPlanarCurveContactEvent.self, usage: &allowance.budget)
                            componentEvents.append(try .init(firstEndpoint: .authored(u),
                                secondEndpoint: endpoint(coordinate, source: second, index: secondOwner.index, budget: &allowance.budget),
                                firstNativeSpanIndex: firstOwner.index, secondNativeSpanIndex: secondOwner.index,
                                belongsToCommonFactor: true, originalPair: nil))
                        }
                    }
                    for u in opposite.horizontalComponents {
                        for v in [domain.v.lower, domain.v.upper] {
                            try RationalAlgebraStorage.retain(1, of: OriginalPlanarCurveContactEvent.self, usage: &allowance.budget)
                            componentEvents.append(try .init(firstEndpoint: endpoint(.authored(u), source: first,
                                index: firstOwner.index, budget: &allowance.budget), secondEndpoint: .authored(v),
                                firstNativeSpanIndex: firstOwner.index, secondNativeSpanIndex: secondOwner.index,
                                belongsToCommonFactor: true, originalPair: nil))
                        }
                    }
                }
                if originalProjection.sectors.contains(where: { !$0.fiberRoots.isEmpty }) {
                    atlas = try OriginalRationalPlaneCurveAtlas(retaining: originalProjection,
                        maximumDepth: depth, usage: &allowance.budget)
                }
            }
            if hasContinuousComponent {
                try RationalAlgebraStorage.retain(1, of: OriginalPlanarCurveContactOverlap.self, usage: &allowance.budget)
                overlaps.append(try .init(firstSpan: span(first, owner: firstOwner, budget: &allowance.budget),
                    secondSpan: span(second, owner: secondOwner, budget: &allowance.budget), factor: common,
                    coversAllParameterPairs: common.isZero, events: componentEvents,
                    projection: projection, atlas: atlas, oppositeAxisProjection: oppositeProjection))
                try RationalAlgebraStorage.retain(componentEvents.count,
                    of: OriginalPlanarCurveContactEvent.self, usage: &allowance.budget)
                events.append(contentsOf: componentEvents)
            }
            if common.isZero { continue }
            let firstQuotient = try x.dividedExactly(by: common, usage: &allowance.budget)
            let secondQuotient = try y.dividedExactly(by: common, usage: &allowance.budget)
            try RationalAlgebraStorage.retain(2, of: ExactBivariatePolynomial.self, usage: &allowance.budget)
            let remaining: [ExactBivariateSystemRoot]
            do {
                remaining = try ExactBivariateSystemSolver.isolatedRoots(of: [firstQuotient, secondQuotient],
                    over: domain, maximumDepth: depth, usage: &allowance.budget)
            } catch let classification as ExactBivariateSystemClassification {
                switch classification {
                // FIXME(INCOMPLETE_IMPLEMENTATION): A residual nonfinite ideal
                // cannot publish a complete drawing/repair partition. The full
                // component decomposition must be retained before this source
                // branch may succeed; no partial event list is returned.
                case .positiveDimensionalOriginalIdeal:
                    throw allowance.budget.exhausted()
                }
            }
            for root in remaining { events.append(try event(root, overlap: false, budget: &allowance.budget)) }
        } }
        let firstPartition = try OriginalPlanarCurveCutProducer().produce(source: first,
            parameters: firstParameters, events: events, firstSource: true, budget: &allowance.budget)
        let secondPartition = try OriginalPlanarCurveCutProducer().produce(source: second,
            parameters: secondParameters, events: events, firstSource: false, budget: &allowance.budget)
        return .init(first: first, firstParameters: firstParameters, second: second,
            secondParameters: secondParameters, plane: plane, tolerance: tolerance,
            events: events, overlaps: overlaps, firstCuts: firstPartition.cuts, secondCuts: secondPartition.cuts,
            firstSegments: firstPartition.segments, secondSegments: secondPartition.segments)
    }
}

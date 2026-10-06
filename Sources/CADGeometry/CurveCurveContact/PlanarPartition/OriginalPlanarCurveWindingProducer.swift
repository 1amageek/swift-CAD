import CADCore

/// Localizes two original sides and counts complete directed global ray crossings.
struct OriginalPlanarCurveWindingProducer {
    private typealias Owner = OriginalPlanarWindingNativeOwner
    private struct Point {
        let x: ExactRationalCoefficient
        let y: ExactRationalCoefficient
    }

    func prepare(contours: [[OriginalPlanarDirectedCurve]], plane: Plane3D,
        budget: inout NativeCurveCurveContactBudget) throws -> OriginalPlanarCurveWindingSource {
        try plane.validate(tolerance: budget.tolerance)
        guard !contours.isEmpty else {
            throw GeometryConversionError.invalidInput("Original global winding requires closed contours.")
        }
        let owners = try prepare(contours, plane: plane, budget: &budget)
        try RationalAlgebraStorage.retain(1, of: OriginalPlanarCurveWindingSource.self, usage: &budget)
        return .init(contours: contours, plane: plane, tolerance: budget.tolerance, owners: owners)
    }

    func produce(span: OriginalCurveRootSpan3D, forward: Bool,
        source retained: OriginalPlanarCurveWindingSource,
        partitions: [OriginalPlanarCurveContactPartition], budget: inout NativeCurveCurveContactBudget)
        throws -> OriginalPlanarCurveSideWinding {
        let contours = retained.contours, plane = retained.plane
        guard retained.tolerance == budget.tolerance else {
            throw GeometryConversionError.invalidInput("Retained winding source has another original tolerance.")
        }
        try plane.validate(tolerance: budget.tolerance)
        guard case .bSpline(let source) = span.source, let ownerIndex = span.nativeSpanIndex,
            span.certificationTolerance == budget.tolerance, !contours.isEmpty,
            (1...3).contains(source.degree), !source.isPeriodic else {
            throw GeometryConversionError.invalidInput("Original side winding needs a source-bound native planar span and closed contours.")
        }
        let axes = projectionAxes(plane.normal)
        var a = try endpoint(span.start, budget: &budget), b = try endpoint(span.end, budget: &budget)
        let order = try ExactOrderedRealEndpoints.compare(&a, &b, maximumDepth: budget.maximumDepth, usage: &budget)
        guard order != 0 else { throw budget.exhausted() }
        var lower = order < 0 ? a : b, upper = order < 0 ? b : a
        let original = try OriginalRationalCurvePolynomial(source: source, spanIndex: ownerIndex,
            tolerance: budget.tolerance, usage: &budget)
        guard try original.planeIncidenceNumerator(origin: plane.origin, normal: plane.normal, usage: &budget).isZero else {
            throw GeometryConversionError.invalidInput("Original side winding span is not exactly on its source plane.")
        }
        let owners = retained.owners
        try admit(span: span, lower: lower, upper: upper, contours: contours,
            partitions: partitions, plane: plane, budget: &budget)
        var station = try ExactOrderedRealEndpoints.between(&lower, &upper,
            maximumDepth: budget.maximumDepth, usage: &budget)
        let w = original.homogeneous[3]
        let dxLaw = try derivativeNumerator(original.homogeneous[axes.0], weight: w, budget: &budget)
        let dyLaw = try derivativeNumerator(original.homogeneous[axes.1], weight: w, budget: &budget)
        guard !dxLaw.isZero || !dyLaw.isZero else {
            throw GeometryConversionError.invalidInput("A spatially constant original owner has no adjacent physical sides.")
        }
        var dx = try dxLaw.evaluated(atU: station, v: .zero, usage: &budget)
        var dy = try dyLaw.evaluated(atU: station, v: .zero, usage: &budget)
        // A nonconstant rational owner has finitely many stationary parameters.
        // Distinct exact rational stations terminate under the caller work bound.
        while dx.isZero && dy.isZero {
            try budget.work(1)
            lower = .authored(station)
            station = try ExactOrderedRealEndpoints.between(&lower, &upper,
                maximumDepth: budget.maximumDepth, usage: &budget)
            dx = try dxLaw.evaluated(atU: station, v: .zero, usage: &budget)
            dy = try dyLaw.evaluated(atU: station, v: .zero, usage: &budget)
        }
        if (order > 0) == forward { dx = dx.negated; dy = dy.negated }
        let origin = try point(original, at: station, axes: axes, budget: &budget)
        let normal = Point(x: dy.negated, y: dx)
        let normSquared = try normal.x.multiplied(by: normal.x, usage: &budget)
            .adding(normal.y.multiplied(by: normal.y, usage: &budget), usage: &budget)
        var nearestLower = ExactMonotoneGraphEndpoint.authored(.one.negated)
        var nearestUpper = ExactMonotoneGraphEndpoint.authored(.one)
        for owner in owners {
            let x = try displacement(owner.original.homogeneous[axes.0], weight: owner.original.homogeneous[3],
                origin: origin.x, budget: &budget)
            let y = try displacement(owner.original.homogeneous[axes.1], weight: owner.original.homogeneous[3],
                origin: origin.y, budget: &budget)
            let transverse = try x.scaled(by: dx, usage: &budget)
                .adding(y.scaled(by: dy, usage: &budget), usage: &budget)
            let along = try x.scaled(by: normal.x, usage: &budget)
                .adding(y.scaled(by: normal.y, usage: &budget), usage: &budget)
            let denominator = try owner.original.homogeneous[3].scaled(by: normSquared, usage: &budget)
            let coordinates: [ExactMonotoneGraphEndpoint]
            if transverse.isZero {
                // A complete collinear owner's extrema, not finite point probes,
                // establish that its full image stays away from the seed origin.
                let critical = try derivativeNumerator(along, weight: denominator, budget: &budget)
                try RationalAlgebraStorage.retain(2, of: ExactMonotoneGraphEndpoint.self, usage: &budget)
                var parameters: [ExactMonotoneGraphEndpoint] = [.authored(owner.lower), .authored(owner.upper)]
                if !critical.isZero {
                    let isolated = try roots(critical, owner: owner, budget: &budget)
                    try RationalAlgebraStorage.retain(isolated.count, of: ExactMonotoneGraphEndpoint.self, usage: &budget)
                    parameters.append(contentsOf: isolated)
                }
                try RationalAlgebraStorage.retain(parameters.count, of: ExactMonotoneGraphEndpoint.self, usage: &budget)
                var values: [ExactMonotoneGraphEndpoint] = []
                var previousSign: Int?
                for parameter in parameters {
                    let coordinate = try OriginalRationalCoordinateRoot.coordinate(numerator: along,
                        denominator: denominator, at: parameter, maximumDepth: budget.maximumDepth, usage: &budget)
                    let sign = try scalarSign(coordinate, budget: &budget)
                    guard sign != 0, previousSign == nil || previousSign == sign else {
                        throw GeometryConversionError.invalidInput("The purported event-free source span meets an original transverse collinear owner.")
                    }
                    previousSign = sign; values.append(coordinate)
                }
                coordinates = values
            } else {
                let parameters = try roots(transverse, owner: owner, budget: &budget)
                try RationalAlgebraStorage.retain(parameters.count, of: ExactMonotoneGraphEndpoint.self, usage: &budget)
                coordinates = try parameters.map {
                    try OriginalRationalCoordinateRoot.coordinate(numerator: along, denominator: denominator,
                        at: $0, maximumDepth: budget.maximumDepth, usage: &budget)
                }
            }
            for coordinate in coordinates {
                var value = coordinate
                switch try scalarSign(value, budget: &budget) {
                case 1:
                    if try ExactOrderedRealEndpoints.compare(&value, &nearestUpper,
                        maximumDepth: budget.maximumDepth, usage: &budget) < 0 { nearestUpper = value }
                case -1:
                    if try ExactOrderedRealEndpoints.compare(&nearestLower, &value,
                        maximumDepth: budget.maximumDepth, usage: &budget) < 0 { nearestLower = value }
                default: break // Exact incidence at the original boundary station.
                }
            }
        }
        var zero = ExactMonotoneGraphEndpoint.authored(.zero)
        let leftStation = try ExactOrderedRealEndpoints.between(&zero, &nearestUpper,
            maximumDepth: budget.maximumDepth, usage: &budget)
        zero = .authored(.zero)
        let rightStation = try ExactOrderedRealEndpoints.between(&nearestLower, &zero,
            maximumDepth: budget.maximumDepth, usage: &budget)
        let left = try offset(origin, along: normal, by: leftStation, budget: &budget)
        let right = try offset(origin, along: normal, by: rightStation, budget: &budget)
        let leftWinding = try winding(at: left, owners: owners, axes: axes, budget: &budget)
        let rightWinding = try winding(at: right, owners: owners, axes: axes, budget: &budget)
        try RationalAlgebraStorage.retain(1, of: OriginalPlanarCurveSideWinding.self, usage: &budget)
        return .init(span: span, plane: plane, contours: contours, forward: forward, axes: axes,
            left: .init(firstCoordinate: left.x, secondCoordinate: left.y, winding: leftWinding),
            right: .init(firstCoordinate: right.x, secondCoordinate: right.y, winding: rightWinding))
    }

    private func prepare(_ contours: [[OriginalPlanarDirectedCurve]], plane: Plane3D,
        budget: inout NativeCurveCurveContactBudget) throws -> [Owner] {
        var owners: [Owner] = []
        for contour in contours {
            guard !contour.isEmpty else { throw GeometryConversionError.invalidInput("Original winding contours cannot be empty.") }
            var first: [ExactRationalCoefficient]?, previous: [ExactRationalCoefficient]?
            for directed in contour {
                let curve = directed.curve, trim = directed.parameters
                let reserve: (Int) throws -> Void = { try budget.retainBytes($0) }
                try withoutActuallyEscaping(reserve) { storage in
                    try Curve3D.bSpline(curve).validateOriginalSource(tolerance: budget.tolerance,
                        remainingSourceDepth: 0, maximumSubdivisionDepth: budget.maximumDepth,
                        consumeWork: { _ in try budget.work(1) }, consumeStorage: storage)
                }
                guard (1...3).contains(curve.degree), !curve.isPeriodic, trim.width > 0,
                    trim.lower >= curve.knots[curve.degree], trim.upper <= curve.knots[curve.controlPointCount] else {
                    throw GeometryConversionError.invalidInput("Global winding requires contained original native degree-one/two/three trims.")
                }
                var start: [ExactRationalCoefficient]?, end: [ExactRationalCoefficient]?
                var precedingOwnerEnd: [ExactRationalCoefficient]?
                for index in curve.degree..<curve.controlPointCount {
                    try budget.work(1)
                    let lower = max(trim.lower, curve.knots[index]), upper = min(trim.upper, curve.knots[index + 1])
                    guard lower < upper else { continue }
                    let original = try OriginalRationalCurvePolynomial(source: curve, spanIndex: index,
                        tolerance: budget.tolerance, usage: &budget)
                    guard try original.planeIncidenceNumerator(origin: plane.origin, normal: plane.normal, usage: &budget).isZero else {
                        throw GeometryConversionError.invalidInput("Every complete winding owner must lie exactly on its original plane.")
                    }
                    let a = try ExactRationalCoefficient.originalDouble(lower, usage: &budget)
                    let b = try ExactRationalCoefficient.originalDouble(upper, usage: &budget)
                    let firstPoint = try spatialPoint(original, at: a, budget: &budget)
                    let lastPoint = try spatialPoint(original, at: b, budget: &budget)
                    if let precedingOwnerEnd, precedingOwnerEnd != firstPoint {
                        throw GeometryConversionError.invalidInput("An original winding curve has a discontinuous selected-native join.")
                    }
                    precedingOwnerEnd = lastPoint
                    if start == nil { start = firstPoint }; end = lastPoint
                    try RationalAlgebraStorage.retain(1, of: Owner.self, usage: &budget)
                    owners.append(.init(original: original, lower: a, upper: b, reversed: directed.isReversed))
                }
                guard let start, let end else { throw budget.exhausted() }
                let directedStart = directed.isReversed ? end : start, directedEnd = directed.isReversed ? start : end
                if let previous, previous != directedStart {
                    throw GeometryConversionError.invalidInput("The original directed winding contour is not exactly connected.")
                }
                if first == nil { first = directedStart }; previous = directedEnd
            }
            guard first == previous else {
                throw GeometryConversionError.invalidInput("The original directed winding contour is not exactly closed.")
            }
        }
        return owners
    }

    private func winding(at seed: Point, owners: [Owner], axes: (Int, Int),
        budget: inout NativeCurveCurveContactBudget) throws -> Int {
        var slopeIndex = 0
        while true {
            try budget.work(1)
            let slope = try ExactRationalCoefficient.natural(slopeIndex, usage: &budget)
            try RationalAlgebraStorage.retain(owners.count, of: ExactBivariatePolynomial.self, usage: &budget)
            var rays: [ExactBivariatePolynomial] = []
            var admissible = true
            for owner in owners {
                let x = try displacement(owner.original.homogeneous[axes.0], weight: owner.original.homogeneous[3], origin: seed.x, budget: &budget)
                let y = try displacement(owner.original.homogeneous[axes.1], weight: owner.original.homogeneous[3], origin: seed.y, budget: &budget)
                let ray = try y.subtracting(x.scaled(by: slope, usage: &budget), usage: &budget)
                if try ray.isZero || (try ray.evaluated(atU: owner.lower, v: .zero, usage: &budget).isZero)
                    || (try ray.evaluated(atU: owner.upper, v: .zero, usage: &budget).isZero) {
                    admissible = false; break
                }
                rays.append(ray)
            }
            if !admissible {
                let next = slopeIndex.addingReportingOverflow(1)
                guard !next.overflow else { throw budget.exhausted() }
                slopeIndex = next.partialValue; continue
            }
            var count = 0
            for index in owners.indices {
                let owner = owners[index], ray = rays[index]
                let positiveRay = try displacement(owner.original.homogeneous[axes.0],
                    weight: owner.original.homogeneous[3], origin: seed.x, budget: &budget)
                for root in try roots(ray, owner: owner, budget: &budget) {
                    switch try root.sign(of: positiveRay, maximumDepth: budget.maximumDepth, usage: &budget) {
                    case .negative: continue
                    case .zero:
                        throw GeometryConversionError.invalidInput("An exact global winding seed lies on an original contour.")
                    case .positive: break
                    }
                    var derivative = ray, multiplicity = 0, crossing = 0
                    while multiplicity <= ray.uDegree {
                        derivative = try derivative.differentiated(alongU: true, usage: &budget)
                        multiplicity += 1
                        switch try root.sign(of: derivative, maximumDepth: budget.maximumDepth, usage: &budget) {
                        case .zero: continue
                        case .positive: crossing = 1
                        case .negative: crossing = -1
                        }
                        break
                    }
                    guard crossing != 0 else { throw budget.exhausted() }
                    if multiplicity & 1 == 0 { continue }
                    let increment = owner.reversed ? -crossing : crossing
                    let next = count.addingReportingOverflow(increment)
                    guard !next.overflow else { throw budget.exhausted() }
                    count = next.partialValue
                }
            }
            return count
        }
    }

    private func admit(span: OriginalCurveRootSpan3D, lower: ExactMonotoneGraphEndpoint,
        upper: ExactMonotoneGraphEndpoint, contours: [[OriginalPlanarDirectedCurve]],
        partitions: [OriginalPlanarCurveContactPartition], plane: Plane3D,
        budget: inout NativeCurveCurveContactBudget) throws {
        guard case .bSpline(let source) = span.source else { throw budget.exhausted() }
        for contour in contours { for directed in contour {
            var selected: (OriginalPlanarCurveContactPartition, Bool)?
            for partition in partitions {
                try budget.work(1)
                guard partition.plane == plane, partition.tolerance == budget.tolerance else { continue }
                try GeometryStructuralComparisonWork.charge(curve: .bSpline(source), using: { try budget.work($0) })
                try GeometryStructuralComparisonWork.charge(curve: .bSpline(directed.curve), using: { try budget.work($0) })
                try GeometryStructuralComparisonWork.charge(curve: .bSpline(partition.first), using: { try budget.work($0) })
                try GeometryStructuralComparisonWork.charge(curve: .bSpline(partition.second), using: { try budget.work($0) })
                let reversed: Bool, trim: ScalarInterval
                if source == partition.first, directed.curve == partition.second,
                    directed.parameters == partition.secondParameters { reversed = false; trim = partition.firstParameters }
                else if source == partition.second, directed.curve == partition.first,
                    directed.parameters == partition.firstParameters { reversed = true; trim = partition.secondParameters }
                else { continue }
                var a = ExactMonotoneGraphEndpoint.authored(try .originalDouble(trim.lower, usage: &budget))
                var b = ExactMonotoneGraphEndpoint.authored(try .originalDouble(trim.upper, usage: &budget))
                var l = lower, u = upper
                if try ExactOrderedRealEndpoints.compare(&a, &l, maximumDepth: budget.maximumDepth, usage: &budget) <= 0,
                    try ExactOrderedRealEndpoints.compare(&u, &b, maximumDepth: budget.maximumDepth, usage: &budget) <= 0 {
                    selected = (partition, reversed); break
                }
            }
            guard let (partition, reversed) = selected else {
                throw GeometryConversionError.invalidInput("Side localization requires complete original pair receipts against every directed contour source.")
            }
            for event in partition.events {
                var point = try endpoint(reversed ? event.secondEndpoint : event.firstEndpoint, budget: &budget)
                var l = lower, u = upper
                if try ExactOrderedRealEndpoints.compare(&l, &point, maximumDepth: budget.maximumDepth, usage: &budget) < 0,
                    try ExactOrderedRealEndpoints.compare(&point, &u, maximumDepth: budget.maximumDepth, usage: &budget) < 0 {
                    throw GeometryConversionError.invalidInput("Side winding span retains an unsplit original contact or component event.")
                }
            }
        } }
    }

    private func roots(_ polynomial: ExactBivariatePolynomial, owner: Owner,
        budget: inout NativeCurveCurveContactBudget) throws -> [ExactMonotoneGraphEndpoint] {
        let isolated = try ExactUnivariateRootIsolator().isolate(polynomial, lower: owner.lower,
            upper: owner.upper, maximumDepth: budget.maximumDepth, usage: &budget)
        try RationalAlgebraStorage.retain(isolated.count, of: ExactMonotoneGraphEndpoint.self, usage: &budget)
        return try isolated.map {
            if $0.isRationalStation { return .authored($0.lower) }
            return .algebraic(try ExactAlgebraicRealRoot(polynomial: polynomial, isolation: $0, usage: &budget))
        }
    }
    private func endpoint(_ endpoint: OriginalCurveRootEndpoint,
        budget: inout NativeCurveCurveContactBudget) throws -> ExactMonotoneGraphEndpoint {
        switch endpoint {
        case .authored(let value): return try .authored(.originalDouble(value, usage: &budget))
        case .algebraic(let root): return root.retainedRootEndpoint
        }
    }
    private func scalarSign(_ value: ExactMonotoneGraphEndpoint,
        budget: inout NativeCurveCurveContactBudget) throws -> Int {
        switch try value.sign(of: .coordinate(alongU: true, usage: &budget), maximumDepth: budget.maximumDepth, usage: &budget) {
        case .positive: 1
        case .negative: -1
        case .zero: 0
        }
    }
    private func derivativeNumerator(_ numerator: ExactBivariatePolynomial, weight: ExactBivariatePolynomial,
        budget: inout NativeCurveCurveContactBudget) throws -> ExactBivariatePolynomial {
        try numerator.differentiated(alongU: true, usage: &budget).multiplied(by: weight, usage: &budget)
            .subtracting(numerator.multiplied(by: weight.differentiated(alongU: true, usage: &budget), usage: &budget), usage: &budget)
    }
    private func displacement(_ numerator: ExactBivariatePolynomial, weight: ExactBivariatePolynomial,
        origin: ExactRationalCoefficient, budget: inout NativeCurveCurveContactBudget) throws -> ExactBivariatePolynomial {
        try numerator.subtracting(weight.scaled(by: origin, usage: &budget), usage: &budget)
    }
    private func spatialPoint(_ original: OriginalRationalCurvePolynomial, at station: ExactRationalCoefficient,
        budget: inout NativeCurveCurveContactBudget) throws -> [ExactRationalCoefficient] {
        let weight = try original.homogeneous[3].evaluated(atU: station, v: .zero, usage: &budget)
        guard weight.isPositive else { throw budget.exhausted() }
        try RationalAlgebraStorage.retain(3, of: ExactRationalCoefficient.self, usage: &budget)
        return try original.homogeneous.prefix(3).map {
            try $0.evaluated(atU: station, v: .zero, usage: &budget).divided(by: weight, usage: &budget)
        }
    }
    private func point(_ original: OriginalRationalCurvePolynomial, at station: ExactRationalCoefficient,
        axes: (Int, Int), budget: inout NativeCurveCurveContactBudget) throws -> Point {
        let value = try spatialPoint(original, at: station, budget: &budget)
        return .init(x: value[axes.0], y: value[axes.1])
    }
    private func offset(_ source: Point, along direction: Point, by amount: ExactRationalCoefficient,
        budget: inout NativeCurveCurveContactBudget) throws -> Point {
        try .init(x: source.x.adding(direction.x.multiplied(by: amount, usage: &budget), usage: &budget),
            y: source.y.adding(direction.y.multiplied(by: amount, usage: &budget), usage: &budget))
    }
    private func projectionAxes(_ normal: Vector3D) -> (Int, Int) {
        var axes: (Int, Int), orientation: Double
        if abs(normal.x) >= abs(normal.y), abs(normal.x) >= abs(normal.z) { axes = (1, 2); orientation = normal.x }
        else if abs(normal.y) >= abs(normal.z) { axes = (2, 0); orientation = normal.y }
        else { axes = (0, 1); orientation = normal.z }
        return orientation < 0 ? (axes.1, axes.0) : axes
    }
}

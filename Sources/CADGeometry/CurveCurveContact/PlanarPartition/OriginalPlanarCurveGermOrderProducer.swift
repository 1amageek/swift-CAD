import CADCore

/// Orders genuine outgoing branches by an exactly proved local circle section.
struct OriginalPlanarCurveGermOrderProducer {
    private struct Native {
        let source: BSplineCurve3D
        let owner: Int
        var origin: ExactMonotoneGraphEndpoint
        var target: ExactMonotoneGraphEndpoint
        let direction: Int
        let localUpper: ExactRationalCoefficient
    }
    private struct Prepared {
        let homogeneous: [OriginalSingularFieldPolynomial]
        let point: [OriginalSingularFieldElement]
        let radial: OriginalSingularFieldPolynomial
        let localUpper: ExactRationalCoefficient
        let depth: Int
    }
    private struct CirclePoint {
        let index: Int
        let x: OriginalSingularFieldElement
        let y: OriginalSingularFieldElement
    }

    func produce(germs: [OriginalPlanarCurveOutgoingGerm], plane: Plane3D,
        partitions: [OriginalPlanarCurveContactPartition], budget: inout NativeCurveCurveContactBudget)
        throws -> OriginalPlanarCurveGermOrder {
        try plane.validate(tolerance: budget.tolerance)
        if germs.isEmpty { return .init(plane: plane, germs: germs, sectors: []) }
        let maximumDepth = budget.maximumDepth
        try RationalAlgebraStorage.retain(germs.count, of: Native.self, usage: &budget)
        var native: [Native] = []
        for germ in germs {
            guard case .bSpline(let source) = germ.span.source, let owner = germ.span.nativeSpanIndex,
                (1...3).contains(source.degree), !source.isPeriodic,
                germ.span.certificationTolerance == budget.tolerance else {
                throw GeometryConversionError.invalidInput("Outgoing planar sectors require source-bound native degree-one/two/three spans.")
            }
            var origin = try coordinate(germ.atStart ? germ.span.start : germ.span.end, budget: &budget)
            var target = try coordinate(germ.atStart ? germ.span.end : germ.span.start, budget: &budget)
            let order = try ExactOrderedRealEndpoints.compare(&origin, &target, maximumDepth: maximumDepth, usage: &budget)
            guard order != 0 else { throw budget.exhausted() }
            let gap = try order < 0 ? target.lower.subtracting(origin.upper, usage: &budget)
                : origin.lower.subtracting(target.upper, usage: &budget)
            guard gap.isPositive else { throw budget.exhausted() }
            native.append(.init(source: source, owner: owner, origin: origin, target: target,
                direction: order < 0 ? 1 : -1,
                localUpper: try gap.divided(by: .natural(2, usage: &budget), usage: &budget)))
        }
        try admitPairs(native, partitions: partitions, plane: plane, budget: &budget)
        var context = try OriginalSingularFieldContext(usage: &budget)
        var transport = OriginalSingularFieldTransport()
        try RationalAlgebraStorage.retain(native.count, of: OriginalSingularFieldElement.self, usage: &budget)
        var parameters: [OriginalSingularFieldElement] = []
        for source in native {
            let parameter = try transport.originalScalarValue(source.origin, into: context,
                maximumDepth: maximumDepth, usage: &budget)
            parameters.append(parameter); context = parameter.context
        }
        let normal = plane.normal
        var axes: (Int, Int), orientation: Double
        if abs(normal.x) >= abs(normal.y), abs(normal.x) >= abs(normal.z) { axes = (1, 2); orientation = normal.x }
        else if abs(normal.y) >= abs(normal.z) { axes = (2, 0); orientation = normal.y }
        else { axes = (0, 1); orientation = normal.z }
        if orientation < 0 { axes = (axes.1, axes.0) }
        try RationalAlgebraStorage.retain(native.count, of: Prepared.self, usage: &budget)
        var prepared: [Prepared] = []
        for index in native.indices {
            let parameter = try parameters[index].embedded(in: context, maximumDepth: maximumDepth, usage: &budget)
            let original = try OriginalRationalCurvePolynomial(source: native[index].source,
                spanIndex: native[index].owner, tolerance: budget.tolerance, usage: &budget)
            guard try original.planeIncidenceNumerator(origin: plane.origin, normal: plane.normal, usage: &budget).isZero else {
                throw GeometryConversionError.invalidInput("Outgoing germ original law is not exactly on its retained plane.")
            }
            let signed = try OriginalSingularFieldElement.constant(
                native[index].direction > 0 ? .one : .one.negated, in: context,
                maximumDepth: maximumDepth, usage: &budget)
            let local = try OriginalSingularFieldPolynomial(context: context, coefficients: [parameter, signed],
                maximumDepth: maximumDepth, usage: &budget)
            try RationalAlgebraStorage.retain(4, of: OriginalSingularFieldPolynomial.self, usage: &budget)
            var homogeneous: [OriginalSingularFieldPolynomial] = []
            for law in original.homogeneous {
                homogeneous.append(try compose(law, with: local, maximumDepth: maximumDepth, budget: &budget))
            }
            let weight = homogeneous[3]
            guard let w0 = weight.coefficients.first,
                case .positive = try w0.sign(maximumDepth: maximumDepth, usage: &budget) else { throw budget.exhausted() }
            try RationalAlgebraStorage.retain(3, of: OriginalSingularFieldElement.self, usage: &budget)
            var point: [OriginalSingularFieldElement] = []
            for axis in 0..<3 {
                let value = try coefficient(homogeneous[axis], at: 0, maximumDepth: maximumDepth, budget: &budget)
                    .divided(by: w0, maximumDepth: maximumDepth, usage: &budget)
                if let first = prepared.first {
                    guard case .zero = try value.subtracting(first.point[axis], maximumDepth: maximumDepth,
                        usage: &budget).sign(maximumDepth: maximumDepth, usage: &budget) else {
                        throw GeometryConversionError.invalidInput("Outgoing germs do not meet at the same exact original spatial station.")
                    }
                }
                point.append(value)
            }
            let dx = try homogeneous[axes.0].subtracting(scale(weight, by: point[axes.0],
                maximumDepth: maximumDepth, budget: &budget), maximumDepth: maximumDepth, usage: &budget)
            let dy = try homogeneous[axes.1].subtracting(scale(weight, by: point[axes.1],
                maximumDepth: maximumDepth, budget: &budget), maximumDepth: maximumDepth, usage: &budget)
            let radial = try dx.multiplied(by: dx, maximumDepth: maximumDepth, usage: &budget)
                .adding(dy.multiplied(by: dy, maximumDepth: maximumDepth, usage: &budget),
                    maximumDepth: maximumDepth, usage: &budget)
            guard !radial.isZero else {
                throw GeometryConversionError.invalidInput("A constant original curve has no outgoing planar sector.")
            }
            let twiceRadial = try scale(radial, by: .constant(.natural(2, usage: &budget), in: context,
                maximumDepth: maximumDepth, usage: &budget), maximumDepth: maximumDepth, budget: &budget)
            let derivative = try radial.differentiated(maximumDepth: maximumDepth, usage: &budget)
                .multiplied(by: weight, maximumDepth: maximumDepth, usage: &budget)
                .subtracting(twiceRadial.multiplied(by: weight.differentiated(maximumDepth: maximumDepth, usage: &budget),
                    maximumDepth: maximumDepth, usage: &budget), maximumDepth: maximumDepth, usage: &budget)
            var leading = 0
            while leading < derivative.coefficients.count {
                if case .zero = try derivative.coefficients[leading].sign(maximumDepth: maximumDepth, usage: &budget) { leading += 1 }
                else { break }
            }
            guard leading < derivative.coefficients.count,
                case .positive = try derivative.coefficients[leading].sign(maximumDepth: maximumDepth, usage: &budget) else {
                throw budget.exhausted()
            }
            try RationalAlgebraStorage.retain(derivative.coefficients.count - leading,
                of: OriginalSingularFieldElement.self, usage: &budget)
            let regularDerivative = try OriginalSingularFieldPolynomial(context: context,
                coefficients: Array(derivative.coefficients[leading...]), maximumDepth: maximumDepth, usage: &budget)
            let sturm = try OriginalSingularFieldSturm(regularDerivative, maximumDepth: maximumDepth, usage: &budget)
            var upper = native[index].localUpper
            var depth = max(native[index].origin.depth, context.depth)
            while try sturm.count(lower: .zero, upper: upper, excludesLower: false, excludesUpper: false,
                maximumDepth: maximumDepth, usage: &budget) != 0 {
                guard depth < maximumDepth else { throw budget.exhausted() }
                depth += 1; try budget.visitExactCell(depth: depth)
                upper = try upper.divided(by: .natural(2, usage: &budget), usage: &budget)
            }
            prepared.append(.init(homogeneous: homogeneous, point: point, radial: radial, localUpper: upper, depth: depth))
        }
        var radius = ExactRationalCoefficient.one
        var radiusDepth = 0
        for source in prepared {
            try budget.work(1)
            radiusDepth = max(radiusDepth, source.depth)
            let upper = try OriginalSingularFieldElement.constant(source.localUpper, in: context,
                maximumDepth: maximumDepth, usage: &budget)
            let weight = try source.homogeneous[3].evaluated(at: upper, maximumDepth: maximumDepth, usage: &budget)
            let squaredDistance = try source.radial.evaluated(at: upper, maximumDepth: maximumDepth, usage: &budget)
                .divided(by: weight.multiplied(by: weight, maximumDepth: maximumDepth, usage: &budget),
                    maximumDepth: maximumDepth, usage: &budget)
            if let exact = try squaredDistance.rationalValue(usage: &budget) {
                guard exact.isPositive else { throw budget.exhausted() }
                let candidate = try exact.divided(by: .natural(2, usage: &budget), usage: &budget)
                if try radius.subtracting(candidate, usage: &budget).isPositive { radius = candidate }
            }
        }
        while true {
            var fits = true
            for source in prepared {
                let upper = try OriginalSingularFieldElement.constant(source.localUpper, in: context,
                    maximumDepth: maximumDepth, usage: &budget)
                let numerator = try source.radial.evaluated(at: upper, maximumDepth: maximumDepth, usage: &budget)
                let weight = try source.homogeneous[3].evaluated(at: upper, maximumDepth: maximumDepth, usage: &budget)
                let squaredDistance = try numerator.divided(by: weight.multiplied(by: weight,
                    maximumDepth: maximumDepth, usage: &budget), maximumDepth: maximumDepth, usage: &budget)
                let candidate = try OriginalSingularFieldElement.constant(radius, in: context,
                    maximumDepth: maximumDepth, usage: &budget)
                if case .positive = try squaredDistance.subtracting(candidate, maximumDepth: maximumDepth,
                    usage: &budget).sign(maximumDepth: maximumDepth, usage: &budget) {} else { fits = false; break }
            }
            if fits { break }
            guard radiusDepth < maximumDepth else { throw budget.exhausted() }
            radiusDepth += 1; try budget.visitExactCell(depth: radiusDepth)
            radius = try radius.divided(by: .natural(2, usage: &budget), usage: &budget)
        }
        let radiusValue = try OriginalSingularFieldElement.constant(radius, in: context,
            maximumDepth: maximumDepth, usage: &budget)
        try RationalAlgebraStorage.retain(prepared.count, of: CirclePoint.self, usage: &budget)
        var points: [CirclePoint] = []
        var pointContext = context
        for (index, source) in prepared.enumerated() {
            let weightSquared = try source.homogeneous[3].multiplied(by: source.homogeneous[3], maximumDepth: maximumDepth, usage: &budget)
            let circle = try source.radial.subtracting(scale(weightSquared, by: radiusValue,
                maximumDepth: maximumDepth, budget: &budget), maximumDepth: maximumDepth, usage: &budget)
            let sturm = try OriginalSingularFieldSturm(circle, maximumDepth: maximumDepth, usage: &budget)
            guard try sturm.count(lower: .zero, upper: source.localUpper, excludesLower: true, excludesUpper: true,
                maximumDepth: maximumDepth, usage: &budget) == 1 else { throw budget.exhausted() }
            let root = OriginalSingularFieldRoot(polynomial: circle, isolation: .init(lower: .zero,
                upper: source.localUpper, excludesLower: true, excludesUpper: true, depth: max(source.depth, radiusDepth)))
            let parameter = try root.value(maximumDepth: maximumDepth, usage: &budget)
            let weight = try source.homogeneous[3].evaluated(at: parameter, maximumDepth: maximumDepth, usage: &budget)
            let x = try source.homogeneous[axes.0].evaluated(at: parameter, maximumDepth: maximumDepth, usage: &budget)
                .divided(by: weight, maximumDepth: maximumDepth, usage: &budget)
                .subtracting(source.point[axes.0], maximumDepth: maximumDepth, usage: &budget)
            let y = try source.homogeneous[axes.1].evaluated(at: parameter, maximumDepth: maximumDepth, usage: &budget)
                .divided(by: weight, maximumDepth: maximumDepth, usage: &budget)
                .subtracting(source.point[axes.1], maximumDepth: maximumDepth, usage: &budget)
            pointContext = try transport.importing(parameter.context, into: pointContext,
                maximumDepth: maximumDepth, usage: &budget)
            points.append(.init(index: index, x: x, y: y))
        }
        for index in points.indices {
            points[index] = try .init(index: index,
                x: transport.applying(to: points[index].x, in: pointContext, maximumDepth: maximumDepth, usage: &budget),
                y: transport.applying(to: points[index].y, in: pointContext, maximumDepth: maximumDepth, usage: &budget))
        }
        try RationalAlgebraStorage.retain(points.count, of: CirclePoint.self, usage: &budget)
        var ordered: [CirclePoint] = []
        for point in points {
            var insertion = ordered.count
            for index in ordered.indices {
                if try angularOrder(point, ordered[index], maximumDepth: maximumDepth, budget: &budget) < 0 { insertion = index; break }
            }
            ordered.insert(point, at: insertion)
        }
        try RationalAlgebraStorage.retain(ordered.count, of: [Int].self, usage: &budget)
        var sectors: [[Int]] = []
        for index in ordered.indices {
            try RationalAlgebraStorage.retain(1, of: Int.self, usage: &budget)
            if index > 0, try angularOrder(ordered[index - 1], ordered[index], maximumDepth: maximumDepth, budget: &budget) == 0 {
                sectors[sectors.count - 1].append(ordered[index].index)
            } else { sectors.append([ordered[index].index]) }
        }
        return .init(plane: plane, germs: germs, sectors: sectors)
    }

    private func coordinate(_ endpoint: OriginalCurveRootEndpoint, budget: inout NativeCurveCurveContactBudget) throws -> ExactMonotoneGraphEndpoint {
        switch endpoint {
        case .authored(let value): return try .authored(.originalDouble(value, usage: &budget))
        case .algebraic(let root): return root.retainedRootEndpoint
        }
    }

    private func compose(_ law: ExactBivariatePolynomial, with parameter: OriginalSingularFieldPolynomial,
        maximumDepth: Int, budget: inout NativeCurveCurveContactBudget) throws -> OriginalSingularFieldPolynomial {
        guard law.vDegree <= 0 else { throw budget.exhausted() }
        let terms = try law.orderedTerms(usage: &budget)
        var result = try OriginalSingularFieldPolynomial(context: parameter.context, coefficients: [], maximumDepth: maximumDepth, usage: &budget)
        for power in stride(from: max(0, law.uDegree), through: 0, by: -1) {
            try budget.work(terms.count)
            let rational = terms.first(where: { $0.0.u == power })?.1 ?? .zero
            let value = try OriginalSingularFieldElement.constant(rational, in: parameter.context, maximumDepth: maximumDepth, usage: &budget)
            let constant = try OriginalSingularFieldPolynomial(context: parameter.context, coefficients: [value], maximumDepth: maximumDepth, usage: &budget)
            result = try result.multiplied(by: parameter, maximumDepth: maximumDepth, usage: &budget)
                .adding(constant, maximumDepth: maximumDepth, usage: &budget)
        }
        return result
    }

    private func coefficient(_ law: OriginalSingularFieldPolynomial, at index: Int,
        maximumDepth: Int, budget: inout NativeCurveCurveContactBudget) throws -> OriginalSingularFieldElement {
        if index < law.coefficients.count { return law.coefficients[index] }
        return try .constant(.zero, in: law.context, maximumDepth: maximumDepth, usage: &budget)
    }

    private func scale(_ law: OriginalSingularFieldPolynomial, by value: OriginalSingularFieldElement,
        maximumDepth: Int, budget: inout NativeCurveCurveContactBudget) throws -> OriginalSingularFieldPolynomial {
        try RationalAlgebraStorage.retain(law.coefficients.count, of: OriginalSingularFieldElement.self, usage: &budget)
        let values = try law.coefficients.map { try $0.multiplied(by: value, maximumDepth: maximumDepth, usage: &budget) }
        return try .init(context: law.context, coefficients: values, maximumDepth: maximumDepth, usage: &budget)
    }

    private func angularOrder(_ first: CirclePoint, _ second: CirclePoint, maximumDepth: Int,
        budget: inout NativeCurveCurveContactBudget) throws -> Int {
        func upper(_ point: CirclePoint, budget: inout NativeCurveCurveContactBudget) throws -> Bool {
            switch try point.y.sign(maximumDepth: maximumDepth, usage: &budget) {
            case .positive: return true
            case .negative: return false
            case .zero: if case .positive = try point.x.sign(maximumDepth: maximumDepth, usage: &budget) { return true }; return false
            }
        }
        let a = try upper(first, budget: &budget), b = try upper(second, budget: &budget)
        if a != b { return a ? -1 : 1 }
        let cross = try first.x.multiplied(by: second.y, maximumDepth: maximumDepth, usage: &budget)
            .subtracting(first.y.multiplied(by: second.x, maximumDepth: maximumDepth, usage: &budget),
                maximumDepth: maximumDepth, usage: &budget)
        switch try cross.sign(maximumDepth: maximumDepth, usage: &budget) {
        case .positive: return -1
        case .negative: return 1
        case .zero: return 0
        }
    }

    private func admitPairs(_ native: [Native], partitions: [OriginalPlanarCurveContactPartition],
        plane: Plane3D, budget: inout NativeCurveCurveContactBudget) throws {
        func same(_ first: BSplineCurve3D, _ second: BSplineCurve3D, budget: inout NativeCurveCurveContactBudget) throws -> Bool {
            try GeometryStructuralComparisonWork.charge(curve: .bSpline(first), using: { try budget.work($0) })
            try GeometryStructuralComparisonWork.charge(curve: .bSpline(second), using: { try budget.work($0) })
            return first == second
        }
        func within(_ source: Native, trim: ScalarInterval, budget: inout NativeCurveCurveContactBudget) throws -> Bool {
            var lower = ExactMonotoneGraphEndpoint.authored(try .originalDouble(trim.lower, usage: &budget))
            var upper = ExactMonotoneGraphEndpoint.authored(try .originalDouble(trim.upper, usage: &budget))
            var a = source.direction > 0 ? source.origin : source.target
            var b = source.direction > 0 ? source.target : source.origin
            return try ExactOrderedRealEndpoints.compare(&lower, &a, maximumDepth: budget.maximumDepth, usage: &budget) <= 0
                && ExactOrderedRealEndpoints.compare(&b, &upper, maximumDepth: budget.maximumDepth, usage: &budget) <= 0
        }
        func inside(_ endpoint: OriginalCurveRootEndpoint, source: Native, budget: inout NativeCurveCurveContactBudget) throws -> Bool {
            var point = try coordinate(endpoint, budget: &budget)
            var lower = source.direction > 0 ? source.origin : source.target
            var upper = source.direction > 0 ? source.target : source.origin
            return try ExactOrderedRealEndpoints.compare(&lower, &point, maximumDepth: budget.maximumDepth, usage: &budget) < 0
                && ExactOrderedRealEndpoints.compare(&point, &upper, maximumDepth: budget.maximumDepth, usage: &budget) < 0
        }
        for first in native.indices { for second in native.indices where first < second {
            let a = native[first], b = native[second]
            var retained: (OriginalPlanarCurveContactPartition, Bool)?
            for partition in partitions {
                try budget.work(1)
                guard partition.tolerance == budget.tolerance, partition.plane == plane else { continue }
                if try same(a.source, partition.first, budget: &budget), try same(b.source, partition.second, budget: &budget),
                    try within(a, trim: partition.firstParameters, budget: &budget), try within(b, trim: partition.secondParameters, budget: &budget) {
                    retained = (partition, false); break
                }
                if try same(a.source, partition.second, budget: &budget), try same(b.source, partition.first, budget: &budget),
                    try within(a, trim: partition.secondParameters, budget: &budget), try within(b, trim: partition.firstParameters, budget: &budget) {
                    retained = (partition, true); break
                }
            }
            guard let (partition, reversed) = retained else {
                throw GeometryConversionError.invalidInput("Outgoing sector order needs complete original contact partitions covering every supplied pair.")
            }
            for event in partition.events {
                let firstEndpoint = reversed ? event.secondEndpoint : event.firstEndpoint
                let secondEndpoint = reversed ? event.firstEndpoint : event.secondEndpoint
                if try inside(firstEndpoint, source: a, budget: &budget), try inside(secondEndpoint, source: b, budget: &budget) {
                    throw GeometryConversionError.invalidInput("Outgoing native segments were not split at every original contact/component event.")
                }
            }
        } }
    }
}

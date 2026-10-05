import CADCore

/// Reservations derived from the original homogeneous preparation and localization loops.
/// Scalar slots include generated numeric arrays; work counts scalar arithmetic/comparisons.
struct PreparedBSplineSurfaceDifferentialCost {
    struct Budget {
        let limits: NativeSurfacePositionCertificationLimits
        private(set) var scalars = 0
        private(set) var work = 0
        private(set) var boxes = 0

        mutating func charge(scalars count: Int = 0, work units: Int = 0) throws {
            try Task.checkCancellation()
            let nextScalars = try Self.sum(scalars, count)
            let nextWork = try Self.sum(work, units)
            guard nextScalars <= limits.maximumScalarCount, nextWork <= limits.maximumWorkUnits else {
                throw GeometryConversionError.resourceLimitExceeded("Native position certification exhausted its cumulative storage or work allowance.")
            }
            scalars = nextScalars
            work = nextWork
        }

        mutating func visit() throws {
            try Task.checkCancellation()
            guard boxes < limits.maximumCertificationBoxes else {
                throw GeometryConversionError.resourceLimitExceeded("Native position certification exhausted its cell allowance.")
            }
            boxes += 1
        }

        static func sum(_ a: Int, _ b: Int, _ c: Int = 0, _ d: Int = 0, _ e: Int = 0, _ f: Int = 0) throws -> Int {
            try adding(adding(adding(adding(adding(a, b), c), d), e), f)
        }

        static func product(_ a: Int, _ b: Int, _ c: Int = 1, _ d: Int = 1, _ e: Int = 1) throws -> Int {
            try multiplying(multiplying(multiplying(multiplying(a, b), c), d), e)
        }

        private static func adding(_ a: Int, _ b: Int) throws -> Int {
            let next = a.addingReportingOverflow(b)
            guard a >= 0, b >= 0, !next.overflow else { throw overflow() }
            return next.partialValue
        }

        private static func multiplying(_ a: Int, _ b: Int) throws -> Int {
            let next = a.multipliedReportingOverflow(by: b)
            guard a >= 0, b >= 0, !next.overflow else { throw overflow() }
            return next.partialValue
        }

        private static func overflow() -> GeometryConversionError {
            .resourceLimitExceeded("Native position certification resource dimensions overflowed.")
        }
    }

    private typealias Arithmetic = Budget
    private let surface: BSplineSurface3D
    private let spanCount: Int
    private let n: Int
    private let m: Int
    private let singleBezier: Bool
    private let groups: Int

    /// Charge row metadata before walking even malformed/ragged input, then complete validation.
    static func chargeValidation(of surface: BSplineSurface3D, budget: inout Budget) throws -> Int {
        let rows = try Arithmetic.sum(surface.controlPoints.count, surface.weights.count)
        try budget.charge(work: Arithmetic.product(rows, 4))
        var controls = 0, weights = 0
        for row in surface.controlPoints { controls = try Arithmetic.sum(controls, row.count) }
        for row in surface.weights { weights = try Arithmetic.sum(weights, row.count) }
        let knots = try Arithmetic.sum(surface.uKnots.count, surface.vKnots.count)
        // Point validation: three coordinates; weight validation: finite and positive;
        // knot validation: finite, sorted and complete multiplicity scan.
        let scan = try Arithmetic.sum(Arithmetic.product(controls, 3), Arithmetic.product(weights, 2),
            Arithmetic.product(knots, 4), rows)
        // A periodic validation also compares every repeated Cartesian/weight tail
        // and checks translated knot axes. Charge conservative complete-net/axis
        // scans before validation, including both axes when both are periodic.
        let periodicAxes = (surface.isUPeriodic ? 1 : 0) + (surface.isVPeriodic ? 1 : 0)
        let periodicScan = try Arithmetic.product(periodicAxes,
            Arithmetic.sum(Arithmetic.product(controls, 4), Arithmetic.product(knots, 64), 128))
        try budget.charge(work: Arithmetic.sum(scan, periodicScan, 12))
        return try Arithmetic.sum(Arithmetic.product(controls, 3), weights, knots, rows,
            periodicScan, 12)
    }

    init(surface: BSplineSurface3D, budget: inout Budget) throws {
        self.surface = surface
        n = try Arithmetic.sum(surface.uDegree, 1)
        m = try Arithmetic.sum(surface.vDegree, 1)
        try budget.charge(work: Arithmetic.sum(Arithmetic.product(2, surface.uKnots.count), Arithmetic.product(2, surface.vKnots.count),
            Arithmetic.product(surface.uControlPointCount, surface.vControlPointCount)))
        var us = 0, vs = 0
        for i in surface.uDegree..<surface.uControlPointCount where surface.uKnots[i] < surface.uKnots[i + 1] { us += 1 }
        for j in surface.vDegree..<surface.vControlPointCount where surface.vKnots[j] < surface.vKnots[j + 1] { vs += 1 }
        spanCount = try Arithmetic.product(us, vs)
        singleBezier = surface.uControlPointCount == n && surface.vControlPointCount == m
            && surface.uKnots.prefix(n).allSatisfy { $0 == surface.uKnots[surface.uDegree] }
            && surface.uKnots.suffix(n).allSatisfy { $0 == surface.uKnots[surface.uControlPointCount] }
            && surface.vKnots.prefix(m).allSatisfy { $0 == surface.vKnots[surface.vDegree] }
            && surface.vKnots.suffix(m).allSatisfy { $0 == surface.vKnots[surface.vControlPointCount] }
        // Only the single-Bezier path can prepare three additional polynomial-coordinate nets.
        groups = singleBezier && !surface.weights.allSatisfy({ $0.allSatisfy { $0 == 1 } }) ? 4 : 1
    }

    func chargePreparation(budget: inout Budget) throws {
        // Preparation validates once, and general original decomposition validates again.
        _ = try Self.chargeValidation(of: surface, budget: &budget)
        if !singleBezier { _ = try Self.chargeValidation(of: surface, budget: &budget) }
        let net = try Arithmetic.product(n, m)
        var scalars = 0, work = 0
        if singleBezier {
            // Original homogeneous values: eight doubles/control; three interval products,
            // whose four-product scratch arrays allocate twelve doubles/control.
            scalars = try Arithmetic.product(net, 20)
            work = try Arithmetic.product(net, 3 * 12 + 3 * 4)
        } else {
            let uBasis = try basisCost(order: n, knots: surface.uKnots.count)
            let vBasis = try basisCost(order: m, knots: surface.vKnots.count)
            // All Taylor derivatives visit every local basis pair for each derivative pair.
            let taylorTerms = try Arithmetic.product(net, net)
            let bernsteinTerms = try Arithmetic.product(triangle(n), triangle(m))
            let scaleSteps = try Arithmetic.sum(
                Arithmetic.product(triangle(m), scaleSteps(n)),
                Arithmetic.product(triangle(n), scaleSteps(m)))
            scalars = try Arithmetic.sum(uBasis.scalars, vBasis.scalars,
                Arithmetic.product(net, 8, 3), Arithmetic.product(taylorTerms, 20),
                Arithmetic.product(bernsteinTerms, 16), Arithmetic.product(scaleSteps, 18))
            work = try Arithmetic.sum(uBasis.work, vBasis.work,
                Arithmetic.product(taylorTerms, 5 * 12 + 7 * 4),
                Arithmetic.product(bernsteinTerms, 4 * 12 + 4 * 4),
                Arithmetic.product(scaleSteps, 3 * 12 + 20))
        }
        // Ten stored derivative tensors, including nine differentiated tensors.
        for uOrder in 0...3 {
            for vOrder in 0...(3 - uOrder) {
                let count = try Arithmetic.product(max(1, n - uOrder), max(1, m - vOrder))
                scalars = try Arithmetic.sum(scalars, Arithmetic.product(count, 8, groups))
                if uOrder + vOrder > 0 {
                    scalars = try Arithmetic.sum(scalars, Arithmetic.product(count, 16, groups), Arithmetic.product(6, groups))
                    work = try Arithmetic.sum(work, Arithmetic.product(count, 4 * 4 + 4 * 12, groups), Arithmetic.product(20, groups))
                }
            }
        }
        // Span-index lists and metadata in both original and prepared patch records:
        // original origin/weight/indices/bounds (10), prepared indices/bounds (6),
        // tolerance (3), patch origin/weight/domain (8), source degrees/origins (4).
        try budget.charge(scalars: Arithmetic.sum(Arithmetic.product(scalars, spanCount),
            surface.uControlPointCount, surface.vControlPointCount, Arithmetic.product(spanCount, 10 + 6 + 3 + 8 + 4)),
            work: Arithmetic.sum(Arithmetic.product(work, spanCount),
                Arithmetic.product(surface.uControlPointCount, surface.vControlPointCount, 4),
                surface.uKnots.count, surface.vKnots.count))
    }

    func chargeProbe(over box: SurfaceParameterBox, pointOnly: Bool, budget: inout Budget) throws {
        guard !surface.isUPeriodic, !surface.isVPeriodic else {
            throw GeometryConversionError.invalidInput("A periodic original probe reservation requires its actual preparation tolerance and fundamental cover.")
        }
        try chargeProbe(over: box, pointOnly: pointOnly, periodicCover: false, budget: &budget)
    }

    /// Reserves the actual original periodic cover without replacing its chart or controls.
    /// The prepared visitor consumes the same deterministic cover law and tolerance.
    func chargeProbe(over box: SurfaceParameterBox, pointOnly: Bool,
        tolerance: ModelingTolerance, budget: inout Budget) throws {
        guard surface.isUPeriodic || surface.isVPeriodic else {
            try chargeProbe(over: box, pointOnly: pointOnly, budget: &budget)
            return
        }
        // Cost inspection and the actual query each form at most two intervals
        // per axis. Fourfold array capacity, payloads and fixed metadata fit 64
        // slots. Repeated-knot searches and representative arithmetic are reserved
        // twice, before either inspection or execution obtains a base cover.
        let knotWork = try Arithmetic.sum(
            Arithmetic.product(surface.uKnots.count, surface.uKnots.count),
            Arithmetic.product(surface.vKnots.count, surface.vKnots.count))
        try budget.charge(scalars: 64, work: Arithmetic.sum(Arithmetic.product(knotWork, 8), 512))
        let us = try surface.enclosureIntervals(box.u, direction: .u, tolerance: tolerance)
        let vs = try surface.enclosureIntervals(box.v, direction: .v, tolerance: tolerance)
        guard us.count <= 2, vs.count <= 2 else {
            throw GeometryConversionError.resourceLimitExceeded("The original periodic query exceeded its proved fundamental-cover count.")
        }
        for u in us {
            for v in vs {
                try chargeProbe(over: SurfaceParameterBox(u: u, v: v),
                    pointOnly: pointOnly, periodicCover: true, budget: &budget)
            }
        }
    }

    private func chargeProbe(over box: SurfaceParameterBox, pointOnly: Bool,
        periodicCover: Bool, budget: inout Budget) throws {
        // Both cost inspection and the actual prepared query scan the entire retained span set.
        try budget.charge(work: Arithmetic.sum(Arithmetic.product(spanCount, 2, 8),
            surface.uKnots.count, surface.vKnots.count))
        for j in surface.vDegree..<surface.vControlPointCount where surface.vKnots[j] < surface.vKnots[j + 1] {
            for i in surface.uDegree..<surface.uControlPointCount where surface.uKnots[i] < surface.uKnots[i + 1] {
                let u0 = max(box.u.lower, surface.uKnots[i]), u1 = min(box.u.upper, surface.uKnots[i + 1])
                let v0 = max(box.v.lower, surface.vKnots[j]), v1 = min(box.v.upper, surface.vKnots[j + 1])
                guard u0 <= u1, v0 <= v1 else { continue }
                var scalars = 0, work = 0
                let orders = pointOnly ? 0 : 3
                for uOrder in 0...orders {
                    for vOrder in 0...(orders - uOrder) {
                        let a = max(1, n - uOrder), b = max(1, m - vOrder)
                        let count = try Arithmetic.product(a, b)
                        // Every scalar hull allocates its component array plus lower/upper arrays.
                        scalars = try Arithmetic.sum(scalars, Arithmetic.product(count, 4, 6, groups))
                        work = try Arithmetic.sum(work, Arithmetic.product(count, 4, 4, groups))
                        // Periodic singleton stations may have a positive-width
                        // outward cover. Conversely, a closed cover can only touch
                        // a span at a singleton corner. Reserve the actual selected
                        // point/value-localization operation, not the unwrapped tag.
                        let pointExecution = periodicCover
                            ? u0 == u1 && v0 == v1
                            : pointOnly
                        if pointExecution {
                            let steps = try Arithmetic.sum(Arithmetic.product(b, triangle(a - 1)), triangle(b - 1))
                            scalars = try Arithmetic.sum(scalars, Arithmetic.product(steps, 8 + 32, groups),
                                Arithmetic.product(count, 8, groups))
                            work = try Arithmetic.sum(work, Arithmetic.product(steps, 4 + 8 * 12 + 4 * 4, groups))
                        } else {
                            // At most two cuts per axis. A stable outward anchor expansion can
                            // remove cuts; it cannot create a cut where the requested endpoint is native.
                            let uCuts = (u0 > surface.uKnots[i] ? 1 : 0) + (u1 < surface.uKnots[i + 1] ? 1 : 0)
                            let vCuts = (v0 > surface.vKnots[j] ? 1 : 0) + (v1 < surface.vKnots[j + 1] ? 1 : 0)
                            let steps = try Arithmetic.sum(Arithmetic.product(uCuts, b, triangle(a - 1)),
                                Arithmetic.product(vCuts, a, triangle(b - 1)))
                            let outputs = try Arithmetic.product(uCuts + vCuts, count, 2)
                            scalars = try Arithmetic.sum(scalars, Arithmetic.product(Arithmetic.sum(steps, outputs), 8, groups),
                                Arithmetic.product(steps, 32, groups), Arithmetic.product(uCuts + vCuts, 6, groups))
                            work = try Arithmetic.sum(work, Arithmetic.product(steps, 4 + 8 * 12 + 4 * 4, groups),
                                Arithmetic.product(uCuts + vCuts, 2 * 4 + 20, groups))
                        }
                    }
                }
                // Rational jet resolution: four scalar jets, ten orders, each order has
                // at most six product-rule terms and three interval products per term.
                // This includes reciprocal, three Cartesian products, shifts and finite scans.
                let fields = pointOnly ? 1 : 10
                scalars = try Arithmetic.sum(scalars, Arithmetic.product(4, fields, 6, 3, 4), Arithmetic.product(4, fields, 2))
                work = try Arithmetic.sum(work, Arithmetic.product(4, fields, 6, 3 * 12 + 4), Arithmetic.product(4, fields, 4))
                try budget.charge(scalars: scalars, work: work)
            }
        }
    }

    private func basisCost(order: Int, knots: Int) throws -> (scalars: Int, work: Int) {
        var scalars = try Arithmetic.product(order, 2), work = try Arithmetic.product(knots, 3)
        for p in 1..<order {
            let columns = try Arithmetic.sum(p, 1)
            scalars = try Arithmetic.sum(scalars, Arithmetic.product(order, columns, 2),
                Arithmetic.product(columns, 2, Arithmetic.sum(12, Arithmetic.product(columns, 4))))
            work = try Arithmetic.sum(work, Arithmetic.product(columns, 2,
                Arithmetic.sum(2 * 4 + 2 * 20, Arithmetic.product(columns, 12 + 4))))
        }
        return (scalars, work)
    }

    private func triangle(_ count: Int) throws -> Int {
        try Arithmetic.product(count, Arithmetic.sum(count, 1)) / 2
    }

    private func scaleSteps(_ count: Int) throws -> Int {
        var result = 0
        for i in 0..<count { result = try Arithmetic.sum(result, triangle(i)) }
        return result
    }
}

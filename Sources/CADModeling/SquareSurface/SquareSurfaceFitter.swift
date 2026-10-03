import Foundation
import CADCore
import CADGeometry
import CADIR

/// Square's fit: the exact frame sheet in the net of exactly the requested Degree and Spans (refined
/// into it when it lies there, interpolated at its Greville abscissae otherwise), its rows along hard
/// sides kept, and every other control point minimizing the flatness-weighted
/// thin plate and membrane energy plus the Weight-scaled loose terms — a Free side's positions
/// and the boundary flow along sides without a face. A rational sheet keeps its refined weights
/// and is fitted in homogeneous coordinates.
package struct SquareSurfaceFitter {
    /// What a side of the frame asks of the sheet.
    package enum Constraint: Equatable {
        /// The sheet's rows 0…order along the side are the exact sheet's: position (0), tangent
        /// (1) or curvature (2) kept exactly.
        case hard(order: Int)
        /// Followed loosely: its positions weighted by the Weight.
        case loose
        /// Unconstrained (a completed side).
        case none
    }

    package struct Boundary {
        package var constraint: Constraint
        /// Whether the boundary flow applies along the side (a side without a face).
        package var flows: Bool

        package init(constraint: Constraint, flows: Bool) {
            self.constraint = constraint
            self.flows = flows
        }
    }

    private let tolerance: ModelingTolerance

    package init(tolerance: ModelingTolerance) {
        self.tolerance = tolerance
    }

    /// The fitted sheet; `boundaries` in the order v = 0, u = 1, v = 1, u = 0 of `exact`.
    /// `guides`: points the sheet passes near, each a Weight-scaled position row where it projects
    /// onto the exact sheet (XNURBS's profile guides).
    package func fit(exact: BSplineSurface3D, boundaries: [Boundary], options: SquareFitOptions, guides: [Point3D] = [],
                     featureID: FeatureID) throws -> BSplineSurface3D {
        try options.validate()
        guard boundaries.count == 4 else {
            throw failure(.invalidInput, "A Square's fit takes four boundaries.", featureID)
        }
        let space = try netSpace(normalized(exact, featureID: featureID), options: options, featureID: featureID)
        let nu = space.uControlPointCount, nv = space.vControlPointCount
        let count = nu * nv
        func index(_ i: Int, _ j: Int) -> Int { j * nu + i }

        // Hard rows: the exact sheet's control points along each hard side.
        var fixed = Array(repeating: false, count: count)
        for (side, boundary) in boundaries.enumerated() {
            guard case let .hard(order) = boundary.constraint else { continue }
            let across = side % 2 == 0 ? nv : nu
            guard order >= 0, order < across else {
                throw failure(.invalidInput, "A Square's side has fewer rows than its continuity needs.", featureID)
            }
            for depth in 0...order {
                for k in 0..<(side % 2 == 0 ? nu : nv) {
                    switch side {
                    case 0: fixed[index(k, depth)] = true
                    case 1: fixed[index(nu - 1 - depth, k)] = true
                    case 2: fixed[index(k, nv - 1 - depth)] = true
                    default: fixed[index(depth, k)] = true
                    }
                }
            }
        }
        let homogeneous: [[Double]] = (0..<count).map { k in
            let (i, j) = (k % nu, k / nu)
            let w = space.weights[j][i], p = space.controlPoints[j][i]
            return [p.x * w, p.y * w, p.z * w]
        }
        let free = (0..<count).filter { !fixed[$0] }
        guard free.isEmpty == false else { return space }
        var column = Array(repeating: -1, count: count)
        for (position, k) in free.enumerated() { column[k] = position }

        var rows = FairSurfaceSystem()
        let uBasis = FairSurfaceSystem.Basis(knots: space.uKnots, degree: space.uDegree, count: nu)
        let vBasis = FairSurfaceSystem.Basis(knots: space.vKnots, degree: space.vDegree, count: nv)

        // Fairness over the unit square, exact for polynomial nets.
        try rows.addFairness(uBasis: uBasis, vBasis: vBasis, flatness: options.flatness)

        // Loose terms along each side, integrated along it.
        let weight = options.weight
        let meanNormal = options.boundaryFlow == .next
            ? try self.meanNormal(of: space, uBasis: uBasis, vBasis: vBasis, featureID: featureID) : nil
        for (side, boundary) in boundaries.enumerated() {
            let flow = boundary.flows ? options.boundaryFlow : .natural
            guard boundary.constraint == .loose || flow != .natural else { continue }
            let alongU = side % 2 == 0
            let fixedParameter: Double = (side == 0 || side == 3) ? 0 : 1
            for (t, wt) in try FairSurfaceSystem.gaussPoints(knots: alongU ? space.uKnots : space.vKnots,
                                           count: (alongU ? space.uDegree : space.vDegree) + 1) {
                let scale = (weight * wt).squareRoot()
                let (u, v) = alongU ? (t, fixedParameter) : (fixedParameter, t)
                let bu = uBasis.derivatives(at: u, order: 1), bv = vBasis.derivatives(at: v, order: 1)
                let value = FairSurfaceSystem.product(bu, bv, du: 0, dv: 0, nu: nu)
                let denominator = weightSum(value, space: space, nu: nu)
                let local = jet(space, u: u, v: v, uBasis: uBasis, vBasis: vBasis)
                let point = local.point - .origin
                if boundary.constraint == .loose {
                    rows.addScalar(value.map { ($0.0, $0.1 * scale / denominator) },
                                   target: [point.x * scale, point.y * scale, point.z * scale])
                }
                guard flow != .natural else { continue }
                // The cross derivative S_d = (A_d − S·W_d)/W, S the exact sheet's boundary point.
                let cross = alongU ? FairSurfaceSystem.product(bu, bv, du: 0, dv: 1, nu: nu) : FairSurfaceSystem.product(bu, bv, du: 1, dv: 0, nu: nu)
                let crossWeight = weightSum(cross, space: space, nu: nu)
                let offset = point * (crossWeight / denominator)
                let coefficients = cross.map { ($0.0, $0.1 * scale / denominator) }
                switch flow {
                case .natural:
                    break
                case .adjacent:
                    // The neighbouring sides' derivatives at the side's corners, blended along it.
                    let first = alongU ? jet(space, u: 0, v: v, uBasis: uBasis, vBasis: vBasis).v
                        : jet(space, u: u, v: 0, uBasis: uBasis, vBasis: vBasis).u
                    let last = alongU ? jet(space, u: 1, v: v, uBasis: uBasis, vBasis: vBasis).v
                        : jet(space, u: u, v: 1, uBasis: uBasis, vBasis: vBasis).u
                    let target = first * (1 - t) + last * t + offset
                    rows.addScalar(coefficients, target: [target.x * scale, target.y * scale, target.z * scale])
                case .normal, .next:
                    let tangent = try (alongU ? local.u : local.v).normalized(tolerance: tolerance.distance)
                    var directions = [tangent]
                    if let meanNormal { directions.append(meanNormal) }
                    for direction in directions {
                        let components = [direction.x, direction.y, direction.z]
                        rows.addCoupled((0..<3).flatMap { c in coefficients.map { (c, $0.0, $0.1 * components[c]) } },
                                        target: offset.dot(direction) * scale)
                    }
                }
            }
        }

        // Guide points, each where it projects onto the exact sheet.
        if guides.isEmpty == false {
            let exactSheet = Surface3D.bSpline(space)
            let scale = (weight / Double(guides.count)).squareRoot()
            for guide in guides {
                let projected = try exactSheet.parameterProjection(of: guide, tolerance: tolerance)
                let value = FairSurfaceSystem.product(uBasis.derivatives(at: projected.u, order: 0), vBasis.derivatives(at: projected.v, order: 0),
                                                      du: 0, dv: 0, nu: nu)
                let denominator = weightSum(value, space: space, nu: nu)
                rows.addScalar(value.map { ($0.0, $0.1 * scale / denominator) },
                               target: [guide.x * scale, guide.y * scale, guide.z * scale])
            }
        }

        let solution = try rows.solve(free: free, column: column, fixedValues: homogeneous, featureID: featureID, failure: failure)
        var points = space.controlPoints
        for (position, k) in free.enumerated() {
            let (i, j) = (k % nu, k / nu)
            let w = space.weights[j][i]
            points[j][i] = Point3D(x: solution[position][0] / w, y: solution[position][1] / w, z: solution[position][2] / w)
        }
        let surface = BSplineSurface3D(uDegree: space.uDegree, vDegree: space.vDegree, uKnots: space.uKnots, vKnots: space.vKnots,
                                       controlPoints: points, weights: space.weights)
        try surface.validate(tolerance: tolerance)
        return surface
    }

    // MARK: - Space

    private func normalized(_ surface: BSplineSurface3D, featureID: FeatureID) throws -> BSplineSurface3D {
        guard let u0 = surface.uKnots.first, let u1 = surface.uKnots.last, u1 > u0,
              let v0 = surface.vKnots.first, let v1 = surface.vKnots.last, v1 > v0 else {
            throw failure(.invalidInput, "A Square's exact sheet has a degenerate knot vector.", featureID)
        }
        return BSplineSurface3D(uDegree: surface.uDegree, vDegree: surface.vDegree,
                                uKnots: surface.uKnots.map { ($0 - u0) / (u1 - u0) }, vKnots: surface.vKnots.map { ($0 - v0) / (v1 - v0) },
                                controlPoints: surface.controlPoints, weights: surface.weights)
    }

    /// The exact sheet in the net of exactly the requested Degree × Spans (uniform clamped knots):
    /// refined into it exactly when it lies there (no higher degree, no knots of its own off the
    /// net's), otherwise the net's sheet through its points at the net's Greville abscissae, whose
    /// sides then stray from the frame by what the net cannot follow — measured and reported by
    /// the Analysis, as Plasticity reports a side beyond its tolerance.
    private func netSpace(_ surface: BSplineSurface3D, options: SquareFitOptions, featureID: FeatureID) throws -> BSplineSurface3D {
        func uniform(_ degree: Int, _ spans: Int) -> [Double] {
            Array(repeating: 0.0, count: degree + 1) + (1..<max(spans, 1)).map { Double($0) / Double(spans) }
                + Array(repeating: 1.0, count: degree + 1)
        }
        let uKnots = uniform(options.uDegree, options.uSpans), vKnots = uniform(options.vDegree, options.vSpans)
        if surface.uDegree <= options.uDegree, surface.vDegree <= options.vDegree {
            let refinedSheet = try refined(surface, options: options)
            if refinedSheet.uDegree == options.uDegree, refinedSheet.vDegree == options.vDegree,
               zip(refinedSheet.uKnots, uKnots).allSatisfy({ abs($0 - $1) <= 1e-12 }), refinedSheet.uKnots.count == uKnots.count,
               zip(refinedSheet.vKnots, vKnots).allSatisfy({ abs($0 - $1) <= 1e-12 }), refinedSheet.vKnots.count == vKnots.count {
                return refinedSheet
            }
        }
        // Tensor interpolation at the Greville abscissae: each row of samples along u, then each
        // column of those along v.
        func grevilles(_ knots: [Double], _ degree: Int) -> [Double] {
            (0..<(knots.count - degree - 1)).map { knots[($0 + 1)...($0 + degree)].reduce(0, +) / Double(degree) }
        }
        let (gu, gv) = (grevilles(uKnots, options.uDegree), grevilles(vKnots, options.vDegree))
        func solver(_ knots: [Double], _ degree: Int, _ at: [Double]) throws -> SurfaceFittingQR {
            let basis = FairSurfaceSystem.Basis(knots: knots, degree: degree, count: at.count)
            let matrix = at.flatMap { basis.derivatives(at: $0, order: 0)[0] }
            return try SurfaceFittingQR(coefficients: matrix, rows: at.count, columns: at.count,
                                        relativeRankTolerance: 1e-12, maximumElements: 1 << 20)
        }
        let (uSolver, vSolver) = (try solver(uKnots, options.uDegree, gu), try solver(vKnots, options.vDegree, gv))
        let samples = try gv.map { v in try gu.map { u in try surface.point(u: u, v: v, tolerance: tolerance) } }
        func solve(_ qr: SurfaceFittingQR, _ points: [Point3D]) throws -> [Point3D] {
            let (x, y, z) = (try qr.solveFullRankLeastSquares(points.map(\.x)), try qr.solveFullRankLeastSquares(points.map(\.y)),
                             try qr.solveFullRankLeastSquares(points.map(\.z)))
            return points.indices.map { Point3D(x: x[$0], y: y[$0], z: z[$0]) }
        }
        let rows = try samples.map { try solve(uSolver, $0) }
        let columns = try gu.indices.map { i in try solve(vSolver, rows.map { $0[i] }) }
        let net = gv.indices.map { j in gu.indices.map { i in columns[i][j] } }
        let sheet = BSplineSurface3D(uDegree: options.uDegree, vDegree: options.vDegree, uKnots: uKnots, vKnots: vKnots, controlPoints: net)
        try sheet.validate(tolerance: tolerance)
        return sheet
    }

    /// `surface` raised to at least the requested degrees, with the requested spans' uniform knots.
    private func refined(_ surface: BSplineSurface3D, options: SquareFitOptions) throws -> BSplineSurface3D {
        var space = surface
        while space.uDegree < options.uDegree { space = try space.elevatingDegree(direction: .u, tolerance: tolerance) }
        while space.vDegree < options.vDegree { space = try space.elevatingDegree(direction: .v, tolerance: tolerance) }
        for (direction, spans) in [(SurfaceParameterDirection.u, options.uSpans), (.v, options.vSpans)] {
            for k in 1..<max(spans, 1) {
                let value = Double(k) / Double(spans)
                let knots = direction == .u ? space.uKnots : space.vKnots
                if knots.contains(where: { abs($0 - value) <= 1e-12 }) { continue }
                space = try space.insertingKnot(direction: direction, value: value, tolerance: tolerance)
            }
        }
        return space
    }

    private func meanNormal(of surface: BSplineSurface3D, uBasis: FairSurfaceSystem.Basis, vBasis: FairSurfaceSystem.Basis, featureID: FeatureID) throws -> Vector3D {
        var sum = Vector3D.zero
        for a in 0...4 {
            for b in 0...4 {
                let local = jet(surface, u: Double(a) / 4, v: Double(b) / 4, uBasis: uBasis, vBasis: vBasis)
                let normal = local.u.cross(local.v)
                if normal.length > 0 { sum = sum + normal * (1 / normal.length) }
            }
        }
        guard sum.length > 1e-9 else {
            throw failure(.invalidInput, "A Square's Next flow needs a frame with a mean plane.", featureID)
        }
        return sum * (1 / sum.length)
    }

    private func weightSum(_ terms: [(Int, Double)], space: BSplineSurface3D, nu: Int) -> Double {
        terms.reduce(0.0) { $0 + $1.1 * space.weights[$1.0 / nu][$1.0 % nu] }
    }

    /// The sheet's point and first derivatives at (u, v), from its rational net.
    private func jet(_ surface: BSplineSurface3D, u: Double, v: Double, uBasis: FairSurfaceSystem.Basis, vBasis: FairSurfaceSystem.Basis)
        -> (point: Point3D, u: Vector3D, v: Vector3D) {
        let nu = surface.uControlPointCount
        let bu = uBasis.derivatives(at: u, order: 1), bv = vBasis.derivatives(at: v, order: 1)
        func sum(_ du: Int, _ dv: Int) -> (Vector3D, Double) {
            var a = Vector3D.zero, w = 0.0
            for (k, value) in FairSurfaceSystem.product(bu, bv, du: du, dv: dv, nu: nu) {
                let weight = surface.weights[k / nu][k % nu]
                a = a + (surface.controlPoints[k / nu][k % nu] - .origin) * (value * weight)
                w += value * weight
            }
            return (a, w)
        }
        let (a, w) = sum(0, 0), (au, wu) = sum(1, 0), (av, wv) = sum(0, 1)
        let point = a * (1 / w)
        return (.origin + point, (au - point * wu) * (1 / w), (av - point * wv) * (1 / w))
    }

    private func failure(_ code: KernelErrorCode, _ message: String, _ featureID: FeatureID) -> KernelError {
        KernelError(phase: .evaluation, code: code, featureID: featureID, tolerance: tolerance, message: message)
    }
}

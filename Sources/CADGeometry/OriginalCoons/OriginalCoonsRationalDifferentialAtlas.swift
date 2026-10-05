import CADCore

/// Exact native boundary cell laws, retained independently of any tensor image.
struct OriginalCoonsRationalDifferentialAtlas: Sendable {
    struct Cell: Sendable {
        let lowerU: ExactRationalCoefficient
        let upperU: ExactRationalCoefficient
        let lowerV: ExactRationalCoefficient
        let upperV: ExactRationalCoefficient
        let tangentU: [ExactBivariatePolynomial]
        let tangentV: [ExactBivariatePolynomial]
        let normal: [ExactBivariatePolynomial]
    }
    struct Field {
        let tangentU: [OutwardScalarInterval]
        let tangentV: [OutwardScalarInterval]
        let normal: [OutwardScalarInterval]
    }
    let cells: [Cell]

    /// The caller admits complete original C0 before composing these fields.
    static func prepared<B: RationalAlgebraAdmitting>(_ surface: Surface3D,
        maximumSpanCount: Int, tolerance: ModelingTolerance, usage: inout B) throws -> Self? {
        switch surface {
        case .procedural(.originalCoons(let source)):
            return try prepared(source, usage: &usage)
        case .procedural(.originalBoundaryCorrected(let source)):
            return try OriginalBoundaryCorrectedRationalAtlas.prepared(source, usage: &usage)
        case .bSpline(let source):
            guard source.uDomain == .closed(0, 1), source.vDomain == .closed(0, 1) else { return nil }
            func storage(_ bytes: Int) throws {
                let rounded = bytes.addingReportingOverflow(MemoryLayout<UInt32>.stride - 1)
                guard bytes >= 0, !rounded.overflow else {
                    throw GeometryConversionError.resourceLimitExceeded("Original native atlas byte reservation overflows.")
                }
                try usage.retainExactStorage(rounded.partialValue / MemoryLayout<UInt32>.stride)
            }
            let prepared = try PreparedBSplineSurfaceDifferentialEncloser(surface: source,
                tolerance: tolerance, consumeWork: { try usage.consumeExactWork(1) },
                consumeStorage: { try storage($0) })
            let square = try SurfaceParameterBox(u: .init(lower: 0, upper: 1), v: .init(lower: 0, upper: 1))
            let owners = try prepared.originalNativeSpans(over: square, tolerance: tolerance,
                maximumSpanCount: maximumSpanCount, consumeWork: { try usage.consumeExactWork(1) },
                consumeStorage: { try storage($0) })
            try usage.retainExactStorage(owners.count)
            var cells: [Cell] = []
            cells.reserveCapacity(owners.count)
            for owner in owners {
                try usage.consumeExactWork(1)
                let domain = SurfaceParameterBox(u: owner.uBounds, v: owner.vBounds)
                let original = try OriginalRationalSurfacePolynomial(source: source, native: owner,
                    domain: domain, view: .unitZ, tolerance: tolerance, usage: &usage)
                let derivatives = try OriginalRationalSurfaceDerivativeLaw(original: original,
                    throughOrder: 1, usage: &usage)
                guard let u = derivatives.partials.first(where: { $0.uOrder == 1 && $0.vOrder == 0 }),
                      let v = derivatives.partials.first(where: { $0.uOrder == 0 && $0.vOrder == 1 }) else {
                    throw GeometryConversionError.invalidInput("Original native atlas lost its rational tangent law.")
                }
                var first = u.numerators, second = v.numerators
                for upper in [false, true] {
                    first = try strip(first, alongU: true, upper: upper, usage: &usage)
                    second = try strip(second, alongU: false, upper: upper, usage: &usage)
                }
                try usage.retainExactStorage(3)
                var normal: [ExactBivariatePolynomial] = []
                for axis in 0..<3 {
                    let i = (axis + 1) % 3, j = (axis + 2) % 3
                    normal.append(try first[i].multiplied(by: second[j], usage: &usage)
                        .subtracting(first[j].multiplied(by: second[i], usage: &usage), usage: &usage))
                }
                cells.append(try Cell(lowerU: .originalDouble(owner.uBounds.lower, usage: &usage),
                    upperU: .originalDouble(owner.uBounds.upper, usage: &usage),
                    lowerV: .originalDouble(owner.vBounds.lower, usage: &usage),
                    upperV: .originalDouble(owner.vBounds.upper, usage: &usage),
                    tangentU: first, tangentV: second, normal: normal))
            }
            guard !cells.isEmpty else {
                throw GeometryConversionError.invalidInput("Original native atlas has no selected source cell.")
            }
            return Self(cells: cells)
        default: return nil
        }
    }

    static func prepared<B: RationalAlgebraAdmitting>(_ surface: OriginalCoonsSurface3D,
        usage: inout B) throws -> Self? {
        guard surface.hasOriginalPositionContinuity else { return nil }
        let boundaries = [surface.vMinimumBoundary, surface.vMaximumBoundary,
            surface.uMinimumBoundary, surface.uMaximumBoundary]
        try usage.retainExactStorage(4)
        for boundary in boundaries {
            guard try OriginalSplineTraversalPolynomialPiece.supports(boundary, usage: &usage) else { return nil }
        }
        let bottom = try OriginalSplineTraversalPolynomialPiece.pieces(boundaries[0], usage: &usage)
        let top = try OriginalSplineTraversalPolynomialPiece.pieces(boundaries[1], usage: &usage)
        let left = try OriginalSplineTraversalPolynomialPiece.pieces(boundaries[2], usage: &usage)
        let right = try OriginalSplineTraversalPolynomialPiece.pieces(boundaries[3], usage: &usage)
        try usage.retainExactStorage(4)
        var corners: [[ExactRationalCoefficient]] = []
        for boundary in boundaries.prefix(2) {
            for atEnd in [false, true] {
                corners.append(try OriginalSplineTraversalPolynomialPiece.endpoint(boundary,
                    atEnd: atEnd, usage: &usage))
            }
        }
        let u = try ExactBivariatePolynomial.coordinate(alongU: true, usage: &usage)
        let v = try ExactBivariatePolynomial.coordinate(alongU: false, usage: &usage)
        let one = try ExactBivariatePolynomial.constant(.one, usage: &usage)
        let um = try one.subtracting(u, usage: &usage), vm = try one.subtracting(v, usage: &usage)
        try usage.retainExactStorage(4)
        let blends = [vm, v, um, u]
        let cornerBlends = try [um.multiplied(by: vm, usage: &usage), u.multiplied(by: vm, usage: &usage),
            um.multiplied(by: v, usage: &usage), u.multiplied(by: v, usage: &usage)]
        try usage.retainExactStorage(3)
        var bilinear: [ExactBivariatePolynomial] = []
        for axis in 0..<3 {
            var value = ExactBivariatePolynomial.zero
            for corner in 0..<4 {
                value = try value.adding(cornerBlends[corner].scaled(by: corners[corner][axis], usage: &usage), usage: &usage)
            }
            bilinear.append(value)
        }
        func maximum(_ a: ExactRationalCoefficient, _ b: ExactRationalCoefficient,
            usage: inout B) throws -> ExactRationalCoefficient {
            try a.subtracting(b, usage: &usage).isPositive ? a : b
        }
        func minimum(_ a: ExactRationalCoefficient, _ b: ExactRationalCoefficient,
            usage: inout B) throws -> ExactRationalCoefficient {
            try a.subtracting(b, usage: &usage).isNegative ? a : b
        }
        var result: [Cell] = []
        for a in bottom { for b in top {
            let loU = try maximum(a.lower, b.lower, usage: &usage)
            let hiU = try minimum(a.upper, b.upper, usage: &usage)
            guard try hiU.subtracting(loU, usage: &usage).isPositive else { continue }
            for c in left { for d in right {
                try usage.visitExactCell(depth: 0)
                let loV = try maximum(c.lower, d.lower, usage: &usage)
                let hiV = try minimum(c.upper, d.upper, usage: &usage)
                guard try hiV.subtracting(loV, usage: &usage).isPositive else { continue }
                try usage.retainExactStorage(20)
                var laws = [a.homogeneous, b.homogeneous]
                for piece in [c, d] {
                    laws.append(try piece.homogeneous.map { try $0.exchangedAxes(usage: &usage) })
                }
                var denominator = one
                var position = [ExactBivariatePolynomial](repeating: .zero, count: 3)
                for boundary in 0..<4 {
                    try usage.retainExactStorage(3)
                    var next: [ExactBivariatePolynomial] = []
                    for axis in 0..<3 {
                        next.append(try position[axis].multiplied(by: laws[boundary][3], usage: &usage)
                            .adding(laws[boundary][axis].multiplied(by: blends[boundary], usage: &usage)
                                .multiplied(by: denominator, usage: &usage), usage: &usage))
                    }
                    position = next
                    denominator = try denominator.multiplied(by: laws[boundary][3], usage: &usage)
                }
                for axis in 0..<3 {
                    position[axis] = try position[axis].subtracting(
                        bilinear[axis].multiplied(by: denominator, usage: &usage), usage: &usage)
                }
                let du = try denominator.differentiated(alongU: true, usage: &usage)
                let dv = try denominator.differentiated(alongU: false, usage: &usage)
                try usage.retainExactStorage(6)
                var first: [ExactBivariatePolynomial] = [], second: [ExactBivariatePolynomial] = []
                for axis in 0..<3 {
                    first.append(try position[axis].differentiated(alongU: true, usage: &usage)
                        .multiplied(by: denominator, usage: &usage)
                        .subtracting(position[axis].multiplied(by: du, usage: &usage), usage: &usage))
                    second.append(try position[axis].differentiated(alongU: false, usage: &usage)
                        .multiplied(by: denominator, usage: &usage)
                        .subtracting(position[axis].multiplied(by: dv, usage: &usage), usage: &usage))
                }
                for upper in [false, true] {
                    first = try strip(first, alongU: true, upper: upper, usage: &usage)
                    second = try strip(second, alongU: false, upper: upper, usage: &usage)
                }
                try usage.retainExactStorage(3)
                var normal: [ExactBivariatePolynomial] = []
                for axis in 0..<3 {
                    let i = (axis + 1) % 3, j = (axis + 2) % 3
                    normal.append(try first[i].multiplied(by: second[j], usage: &usage)
                        .subtracting(first[j].multiplied(by: second[i], usage: &usage), usage: &usage))
                }
                try usage.retainExactStorage(1)
                result.append(Cell(lowerU: loU, upperU: hiU, lowerV: loV, upperV: hiV,
                    tangentU: first, tangentV: second, normal: normal))
            } }
        } }
        guard !result.isEmpty else {
            throw GeometryConversionError.invalidInput("Original Coons rational atlas has no positive source cells.")
        }
        return Self(cells: result)
    }

    func fields<B: RationalAlgebraAdmitting>(over domain: SurfaceParameterBox,
        usage: inout B) throws -> [Field] {
        let u0 = try ExactRationalCoefficient.originalDouble(domain.u.lower, usage: &usage)
        let u1 = try ExactRationalCoefficient.originalDouble(domain.u.upper, usage: &usage)
        let v0 = try ExactRationalCoefficient.originalDouble(domain.v.lower, usage: &usage)
        let v1 = try ExactRationalCoefficient.originalDouble(domain.v.upper, usage: &usage)
        var result: [Field] = []
        for cell in cells {
            try usage.consumeExactWork(1)
            if try cell.upperU.subtracting(u0, usage: &usage).isNegative
                || u1.subtracting(cell.lowerU, usage: &usage).isNegative
                || cell.upperV.subtracting(v0, usage: &usage).isNegative
                || v1.subtracting(cell.lowerV, usage: &usage).isNegative { continue }
            let box = try SurfaceParameterBox(u: ScalarInterval(
                    lower: max(domain.u.lower, cell.lowerU.outwardInterval(usage: &usage).lower),
                    upper: min(domain.u.upper, cell.upperU.outwardInterval(usage: &usage).upper)),
                v: ScalarInterval(lower: max(domain.v.lower, cell.lowerV.outwardInterval(usage: &usage).lower),
                    upper: min(domain.v.upper, cell.upperV.outwardInterval(usage: &usage).upper)))
            try usage.retainExactStorage(10)
            result.append(try Field(tangentU: cell.tangentU.map { try $0.enclosure(over: box, usage: &usage) },
                tangentV: cell.tangentV.map { try $0.enclosure(over: box, usage: &usage) },
                normal: cell.normal.map { try $0.enclosure(over: box, usage: &usage) }))
        }
        guard !result.isEmpty else {
            throw GeometryConversionError.invalidInput("Original Coons query escaped its retained rational cell cover.")
        }
        return result
    }

    static func strip<B: RationalAlgebraAdmitting>(_ original: [ExactBivariatePolynomial],
        alongU: Bool, upper: Bool, usage: inout B) throws -> [ExactBivariatePolynomial] {
        let boundary = upper ? ExactRationalCoefficient.one : .zero
        var multiplicity: Int?
        for polynomial in original where !polynomial.isZero {
            let factor = try polynomial.dividedByBoundaryFactor(alongU: alongU, boundary: boundary, usage: &usage)
            multiplicity = min(multiplicity ?? factor.multiplicity, factor.multiplicity)
        }
        guard let multiplicity, multiplicity > 0 else { return original }
        let factor = try ExactBivariatePolynomial.coordinate(alongU: alongU, usage: &usage)
            .subtracting(.constant(boundary, usage: &usage), usage: &usage)
        var power = try ExactBivariatePolynomial.constant(.one, usage: &usage)
        for _ in 0..<multiplicity { power = try power.multiplied(by: factor, usage: &usage) }
        let sign = upper && multiplicity & 1 == 1 ? ExactRationalCoefficient.one.negated : .one
        try usage.retainExactStorage(3)
        return try original.map { try $0.dividedExactly(by: power, usage: &usage).scaled(by: sign, usage: &usage) }
    }
}

import CADCore

/// Original rational differential law of a boundary-corrected native tensor.
struct OriginalBoundaryCorrectedRationalAtlas {
    private typealias Piece = OriginalSplineTraversalPolynomialPiece
    private typealias Atlas = OriginalCoonsRationalDifferentialAtlas

    static func prepared<B: RationalAlgebraAdmitting>(_ source: OriginalBoundaryCorrectedSurface3D,
        usage: inout B) throws -> OriginalCoonsRationalDifferentialAtlas? {
        let target = source.boundaries, native = source.retainedConstructionBoundaries
        guard target.hasOriginalPositionContinuity else { return nil }
        try RationalAlgebraStorage.retain(8, of: OriginalCurveRootSpan3D.self, usage: &usage)
        let targets = [target.vMinimumBoundary, target.vMaximumBoundary,
            target.uMinimumBoundary, target.uMaximumBoundary]
        let originals = [native.vMinimumBoundary, native.vMaximumBoundary,
            native.uMinimumBoundary, native.uMaximumBoundary]
        for boundaries in [targets, originals] { for boundary in boundaries {
            guard try Piece.supports(boundary, usage: &usage) else { return nil }
        } }
        try RationalAlgebraStorage.retain(8, of: [Piece].self, usage: &usage)
        var targetPieces: [[Piece]] = [], originalPieces: [[Piece]] = []
        targetPieces.reserveCapacity(4); originalPieces.reserveCapacity(4)
        for index in 0..<4 {
            targetPieces.append(try Piece.pieces(targets[index], usage: &usage))
            originalPieces.append(try Piece.pieces(originals[index], usage: &usage))
        }
        try RationalAlgebraStorage.retain(4, of: [Piece].self, usage: &usage)
        var residuals: [[Piece]] = []; residuals.reserveCapacity(4)
        for index in 0..<4 {
            residuals.append(try residual(targetPieces[index], originalPieces[index], usage: &usage))
        }
        try RationalAlgebraStorage.retain(4, of: [ExactRationalCoefficient].self, usage: &usage)
        var corners: [[ExactRationalCoefficient]] = []; corners.reserveCapacity(4)
        for boundary in 0..<2 { for atEnd in [false, true] {
            let station = atEnd ? ExactRationalCoefficient.one : .zero
            let a = try Piece.coordinates(targetPieces[boundary], at: station, usage: &usage)
            let b = try Piece.coordinates(originalPieces[boundary], at: station, usage: &usage)
            try RationalAlgebraStorage.retain(3, of: ExactRationalCoefficient.self, usage: &usage)
            var delta: [ExactRationalCoefficient] = []; delta.reserveCapacity(3)
            for axis in 0..<3 { delta.append(try a[axis].subtracting(b[axis], usage: &usage)) }
            corners.append(delta)
        } }
        let u = try ExactBivariatePolynomial.coordinate(alongU: true, usage: &usage)
        let v = try ExactBivariatePolynomial.coordinate(alongU: false, usage: &usage)
        let one = try ExactBivariatePolynomial.constant(.one, usage: &usage)
        let hu = try weight(u, usage: &usage), hv = try weight(v, usage: &usage)
        let um = try one.subtracting(hu, usage: &usage), vm = try one.subtracting(hv, usage: &usage)
        try RationalAlgebraStorage.retain(8, of: ExactBivariatePolynomial.self, usage: &usage)
        let blends = [vm, hv, um, hu]
        let cornerBlends = try [um.multiplied(by: vm, usage: &usage), hu.multiplied(by: vm, usage: &usage),
            um.multiplied(by: hv, usage: &usage), hu.multiplied(by: hv, usage: &usage)]
        try RationalAlgebraStorage.retain(3, of: ExactBivariatePolynomial.self, usage: &usage)
        var cornerLaw: [ExactBivariatePolynomial] = []; cornerLaw.reserveCapacity(3)
        for axis in 0..<3 {
            var law = ExactBivariatePolynomial.zero
            for index in 0..<4 {
                law = try law.adding(cornerBlends[index].scaled(by: corners[index][axis], usage: &usage), usage: &usage)
            }
            cornerLaw.append(law)
        }
        var cells: [Atlas.Cell] = []
        var cellCapacity = 0
        for owner in source.retainedNativeOwners {
            let nativeDomain = SurfaceParameterBox(u: owner.uBounds, v: owner.vBounds)
            let tensor = try OriginalRationalSurfacePolynomial(source: source.construction, native: owner,
                domain: nativeDomain, view: .unitZ, tolerance: source.certificationTolerance, usage: &usage)
            let nativeLoU = try ExactRationalCoefficient.originalDouble(owner.uBounds.lower, usage: &usage)
            let nativeHiU = try ExactRationalCoefficient.originalDouble(owner.uBounds.upper, usage: &usage)
            let nativeLoV = try ExactRationalCoefficient.originalDouble(owner.vBounds.lower, usage: &usage)
            let nativeHiV = try ExactRationalCoefficient.originalDouble(owner.vBounds.upper, usage: &usage)
            for bottom in residuals[0] { for top in residuals[1] {
                let loU = try maximum(maximum(bottom.lower, top.lower, usage: &usage), nativeLoU, usage: &usage)
                let hiU = try minimum(minimum(bottom.upper, top.upper, usage: &usage), nativeHiU, usage: &usage)
                guard try hiU.subtracting(loU, usage: &usage).isPositive else { continue }
                for left in residuals[2] { for right in residuals[3] {
                    try usage.visitExactCell(depth: 0)
                    let loV = try maximum(maximum(left.lower, right.lower, usage: &usage), nativeLoV, usage: &usage)
                    let hiV = try minimum(minimum(left.upper, right.upper, usage: &usage), nativeHiV, usage: &usage)
                    guard try hiV.subtracting(loV, usage: &usage).isPositive else { continue }
                    try RationalAlgebraStorage.retain(16, of: ExactBivariatePolynomial.self, usage: &usage)
                    var laws = [bottom.homogeneous, top.homogeneous]
                    for piece in [left, right] {
                        try RationalAlgebraStorage.retain(4, of: ExactBivariatePolynomial.self, usage: &usage)
                        var h: [ExactBivariatePolynomial] = []; h.reserveCapacity(4)
                        for law in piece.homogeneous { h.append(try law.exchangedAxes(usage: &usage)) }
                        laws.append(h)
                    }
                    try RationalAlgebraStorage.retain(3, of: ExactBivariatePolynomial.self, usage: &usage)
                    var position = Array(tensor.homogeneous.prefix(3))
                    var denominator = tensor.homogeneous[3]
                    for boundary in 0..<4 {
                        try RationalAlgebraStorage.retain(3, of: ExactBivariatePolynomial.self, usage: &usage)
                        var next: [ExactBivariatePolynomial] = []; next.reserveCapacity(3)
                        for axis in 0..<3 {
                            next.append(try position[axis].multiplied(by: laws[boundary][3], usage: &usage)
                                .adding(laws[boundary][axis].multiplied(by: blends[boundary], usage: &usage)
                                    .multiplied(by: denominator, usage: &usage), usage: &usage))
                        }
                        position = next
                        denominator = try denominator.multiplied(by: laws[boundary][3], usage: &usage)
                    }
                    for axis in 0..<3 {
                        position[axis] = try position[axis].subtracting(cornerLaw[axis].multiplied(
                            by: denominator, usage: &usage), usage: &usage)
                    }
                    let du = try denominator.differentiated(alongU: true, usage: &usage)
                    let dv = try denominator.differentiated(alongU: false, usage: &usage)
                    try RationalAlgebraStorage.retain(9, of: ExactBivariatePolynomial.self, usage: &usage)
                    var first: [ExactBivariatePolynomial] = [], second: [ExactBivariatePolynomial] = []
                    first.reserveCapacity(3); second.reserveCapacity(3)
                    for axis in 0..<3 {
                        first.append(try position[axis].differentiated(alongU: true, usage: &usage)
                            .multiplied(by: denominator, usage: &usage).subtracting(
                                position[axis].multiplied(by: du, usage: &usage), usage: &usage))
                        second.append(try position[axis].differentiated(alongU: false, usage: &usage)
                            .multiplied(by: denominator, usage: &usage).subtracting(
                                position[axis].multiplied(by: dv, usage: &usage), usage: &usage))
                    }
                    for upper in [false, true] {
                        first = try Atlas.strip(first, alongU: true, upper: upper, usage: &usage)
                        second = try Atlas.strip(second, alongU: false, upper: upper, usage: &usage)
                    }
                    var normal: [ExactBivariatePolynomial] = []; normal.reserveCapacity(3)
                    for axis in 0..<3 {
                        let i = (axis + 1) % 3, j = (axis + 2) % 3
                        normal.append(try first[i].multiplied(by: second[j], usage: &usage)
                            .subtracting(first[j].multiplied(by: second[i], usage: &usage), usage: &usage))
                    }
                    if cells.count == cellCapacity {
                        let doubled = max(1, cellCapacity).multipliedReportingOverflow(by: 2)
                        guard !doubled.overflow else {
                            throw GeometryConversionError.resourceLimitExceeded("Original corrected atlas capacity overflows.")
                        }
                        try RationalAlgebraStorage.retain(doubled.partialValue - cellCapacity, of: Atlas.Cell.self, usage: &usage)
                        cellCapacity = doubled.partialValue; cells.reserveCapacity(cellCapacity)
                    }
                    cells.append(Atlas.Cell(lowerU: loU, upperU: hiU, lowerV: loV, upperV: hiV,
                        tangentU: first, tangentV: second, normal: normal))
                } }
            } }
        }
        guard !cells.isEmpty else {
            throw GeometryConversionError.invalidInput("Original corrected atlas has no positive native source cells.")
        }
        return Atlas(cells: cells)
    }

    private static func residual<B: RationalAlgebraAdmitting>(_ targets: [Piece], _ originals: [Piece],
        usage: inout B) throws -> [Piece] {
        let capacity = targets.count.addingReportingOverflow(originals.count)
        guard !capacity.overflow else {
            throw GeometryConversionError.resourceLimitExceeded("Original residual partition capacity overflows.")
        }
        try RationalAlgebraStorage.retain(capacity.partialValue, of: Piece.self, usage: &usage)
        var result: [Piece] = []; result.reserveCapacity(capacity.partialValue)
        var first = 0, second = 0
        while first < targets.count, second < originals.count {
            try usage.consumeExactWork(1)
            let a = targets[first], b = originals[second]
            let lo = try maximum(a.lower, b.lower, usage: &usage)
            let hi = try minimum(a.upper, b.upper, usage: &usage)
            if try hi.subtracting(lo, usage: &usage).isPositive {
                try RationalAlgebraStorage.retain(4, of: ExactBivariatePolynomial.self, usage: &usage)
                var h: [ExactBivariatePolynomial] = []; h.reserveCapacity(4)
                for axis in 0..<3 {
                    h.append(try a.homogeneous[axis].multiplied(by: b.homogeneous[3], usage: &usage)
                        .subtracting(b.homogeneous[axis].multiplied(by: a.homogeneous[3], usage: &usage), usage: &usage))
                }
                h.append(try a.homogeneous[3].multiplied(by: b.homogeneous[3], usage: &usage))
                result.append(Piece(lower: lo, upper: hi, homogeneous: h))
            }
            let order = try a.upper.subtracting(b.upper, usage: &usage)
            if !order.isPositive { first += 1 }
            if !order.isNegative { second += 1 }
        }
        guard !result.isEmpty else { throw GeometryConversionError.invalidInput("Original boundary residual has no full native partition.") }
        return result
    }

    private static func weight<B: RationalAlgebraAdmitting>(_ coordinate: ExactBivariatePolynomial,
        usage: inout B) throws -> ExactBivariatePolynomial {
        var law = ExactBivariatePolynomial.zero
        var power = try ExactBivariatePolynomial.constant(.one, usage: &usage)
        for degree in 0...5 {
            try usage.consumeExactWork(1)
            let coefficient = OriginalEndpointCorrectionBasis.quinticHermite.coefficient(at: degree)
            if coefficient != 0 {
                law = try law.adding(power.scaled(by: .originalDouble(coefficient, usage: &usage), usage: &usage), usage: &usage)
            }
            if degree < 5 { power = try power.multiplied(by: coordinate, usage: &usage) }
        }
        return law
    }
    private static func maximum<B: RationalAlgebraAdmitting>(_ a: ExactRationalCoefficient,
        _ b: ExactRationalCoefficient, usage: inout B) throws -> ExactRationalCoefficient {
        try a.subtracting(b, usage: &usage).isPositive ? a : b
    }
    private static func minimum<B: RationalAlgebraAdmitting>(_ a: ExactRationalCoefficient,
        _ b: ExactRationalCoefficient, usage: inout B) throws -> ExactRationalCoefficient {
        try a.subtracting(b, usage: &usage).isNegative ? a : b
    }
}

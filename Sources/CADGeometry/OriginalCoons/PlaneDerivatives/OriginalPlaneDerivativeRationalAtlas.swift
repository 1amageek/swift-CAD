import CADCore

/// Exact position expression of the retained rational plane-derivative side.
struct OriginalPlaneDerivativeRationalAtlas: Sendable {
    struct Cell: Sendable {
        let lowerU: ExactRationalCoefficient
        let upperU: ExactRationalCoefficient
        let lowerV: ExactRationalCoefficient
        let upperV: ExactRationalCoefficient
        let homogeneous: [ExactBivariatePolynomial]
    }
    private struct BoundaryField: Sendable {
        let lower: ExactRationalCoefficient
        let upper: ExactRationalCoefficient
        let atEnd: Bool
        let order: Int
        let homogeneous: [ExactBivariatePolynomial]
    }
    private typealias P = ExactBivariatePolynomial
    private typealias Q = ExactRationalCoefficient
    private typealias Piece = OriginalSplineTraversalPolynomialPiece
    let cells: [Cell]
    private let original: OriginalPlaneDerivativeSurface3D
    private let base: OriginalCoonsRationalDifferentialAtlas
    private let fields: [BoundaryField]

    static func prepared<B: RationalAlgebraAdmitting>(_ source: OriginalPlaneDerivativeSurface3D,
        usage: inout B) throws -> Self? {
        try source.validate(tolerance: source.certificationTolerance)
        guard source.remainingSourceDepth > 1 else {
            throw GeometryConversionError.resourceLimitExceeded("Original derivative surface retained source depth is exhausted.")
        }
        guard source.hasOriginalPositionContinuity,
            let base = try OriginalBoundaryCorrectedRationalAtlas.prepared(source.construction, usage: &usage) else { return nil }
        let u = try P.coordinate(alongU: true, usage: &usage)
        let v = try P.coordinate(alongU: false, usage: &usage)
        let one = try P.constant(.one, usage: &usage)
        let h1 = try valueBasis(u, usage: &usage), h0 = try one.subtracting(h1, usage: &usage)
        let fields = try boundaryFields(source, base: base, u: u, h0: h0, h1: h1, usage: &usage)
        try RationalAlgebraStorage.retain(2, of: [Piece].self, usage: &usage)
        var connectorResiduals: [[Piece]] = []; connectorResiduals.reserveCapacity(2)
        for maximum in [false, true] {
            if source.retainsCorrectedConnector(atUMaximum: maximum) {
                let target = maximum ? source.boundaries.uMaximumBoundary : source.boundaries.uMinimumBoundary
                let original = maximum ? source.construction.boundaries.uMaximumBoundary : source.construction.boundaries.uMinimumBoundary
                connectorResiduals.append(try residual(Piece.pieces(target, usage: &usage),
                    Piece.pieces(original, usage: &usage), usage: &usage))
            } else {
                try RationalAlgebraStorage.retain(1, of: Piece.self, usage: &usage)
                try RationalAlgebraStorage.retain(4, of: P.self, usage: &usage)
                connectorResiduals.append([Piece(lower: .zero, upper: .one, homogeneous: [.zero, .zero, .zero, one])])
            }
        }
        var cells: [Cell] = []; var capacity = 0
        for cell in base.cells {
            for left in connectorResiduals[0] { for right in connectorResiduals[1] {
                try usage.visitExactCell(depth: 0)
                let loV = try maximum(maximum(cell.lowerV, left.lower, usage: &usage), right.lower, usage: &usage)
                let hiV = try minimum(minimum(cell.upperV, left.upper, usage: &usage), right.upper, usage: &usage)
                guard try hiV.subtracting(loV, usage: &usage).isPositive else { continue }
                var position = cell.homogeneous
                for index in 0..<2 {
                    let piece = index == 0 ? left : right, weight = index == 0 ? h0 : h1
                    try RationalAlgebraStorage.retain(4, of: P.self, usage: &usage)
                    var moved: [P] = []; moved.reserveCapacity(4)
                    for law in piece.homogeneous { moved.append(try law.exchangedAxes(usage: &usage)) }
                    position = try adding(position, weighted: moved, by: weight, usage: &usage)
                }
                for atEnd in [false, true] { for order in 1...2 {
                    if try !source.hasOriginalDerivativeProjection(atEnd: atEnd, order: order) { continue }
                    var selected: BoundaryField?
                    for field in fields {
                        try usage.consumeExactWork(1)
                        if field.atEnd == atEnd, field.order == order,
                            try !cell.lowerU.subtracting(field.lower, usage: &usage).isNegative,
                            try !field.upper.subtracting(cell.upperU, usage: &usage).isNegative {
                            guard selected == nil else {
                                throw GeometryConversionError.invalidInput("Original derivative surface has ambiguous Native boundary ownership.")
                            }
                            selected = field
                        }
                    }
                    guard let selected else {
                        throw GeometryConversionError.invalidInput("Original derivative surface cell lacks its Native transverse boundary owner.")
                    }
                    let basis = try derivativeBasis(v, atEnd: atEnd, order: order, usage: &usage)
                    position = try adding(position, weighted: selected.homogeneous, by: basis, usage: &usage)
                } }
                if cells.count == capacity {
                    let doubled = capacity.multipliedReportingOverflow(by: 2)
                    guard !doubled.overflow else {
                        throw GeometryConversionError.resourceLimitExceeded("Original derivative surface cell capacity overflows.")
                    }
                    let next = capacity == 0 ? 1 : doubled.partialValue
                    try RationalAlgebraStorage.retain(next, of: Cell.self, usage: &usage)
                    try usage.consumeExactWork(cells.count); cells.reserveCapacity(next); capacity = next
                }
                cells.append(.init(lowerU: cell.lowerU, upperU: cell.upperU, lowerV: loV, upperV: hiV, homogeneous: position))
            } }
        }
        guard !cells.isEmpty else { throw GeometryConversionError.invalidInput("Original derivative surface has no exact position cells.") }
        try RationalAlgebraStorage.retain(1, of: Self.self, usage: &usage)
        try exactScalarTaskCheckpoint()
        return Self(cells: cells, original: source, base: base, fields: fields)
    }

    private static func boundaryFields<B: RationalAlgebraAdmitting>(_ source: OriginalPlaneDerivativeSurface3D,
        base: OriginalCoonsRationalDifferentialAtlas, u: P, h0: P, h1: P, usage: inout B) throws -> [BoundaryField] {
        let count = base.cells.count.multipliedReportingOverflow(by: 4)
        guard !count.overflow else { throw GeometryConversionError.resourceLimitExceeded("Original derivative boundary field capacity overflows.") }
        try RationalAlgebraStorage.retain(count.partialValue, of: BoundaryField.self, usage: &usage)
        var fields: [BoundaryField] = []; fields.reserveCapacity(count.partialValue)
        for atEnd in [false, true] { for order in 1...2 {
            if try !source.hasOriginalDerivativeProjection(atEnd: atEnd, order: order) { continue }
            let station = try P.constant(atEnd ? .one : .zero, usage: &usage)
            try RationalAlgebraStorage.retain(base.cells.count, of: BoundaryField.self, usage: &usage)
            var raw: [BoundaryField] = []; raw.reserveCapacity(base.cells.count)
            for cell in base.cells {
                try usage.consumeExactWork(1)
                let boundary = atEnd ? try cell.upperV.subtracting(.one, usage: &usage).isZero : cell.lowerV.isZero
                guard boundary else { continue }
                raw.append(.init(lower: cell.lowerU, upper: cell.upperU, atEnd: atEnd, order: order,
                    homogeneous: try nativeField(cell.originalConstructionHomogeneous, station: station, u: u, order: order, usage: &usage)))
            }
            try RationalAlgebraStorage.retain(2, of: OriginalSupportingPlaneEquation.Vector.self, usage: &usage)
            var cornerDeltas: [OriginalSupportingPlaneEquation.Vector] = []; cornerDeltas.reserveCapacity(2)
            for maximum in [false, true] {
                var value: OriginalSupportingPlaneEquation.Vector?
                for field in raw {
                    try usage.consumeExactWork(1)
                    let owns = maximum ? try field.upper.subtracting(.one, usage: &usage).isZero : field.lower.isZero
                    guard owns else { continue }
                    guard value == nil else { throw GeometryConversionError.invalidInput("Original transverse corner has ambiguous Native ownership.") }
                    let point: Q = maximum ? .one : .zero
                    let denominator = try field.homogeneous[3].evaluated(atU: point, v: .zero, usage: &usage)
                    guard !denominator.isZero else { throw GeometryConversionError.invalidInput("Original Native corner derivative has zero denominator.") }
                    let original = try OriginalSupportingPlaneEquation.Vector(
                        x: field.homogeneous[0].evaluated(atU: point, v: .zero, usage: &usage).divided(by: denominator, usage: &usage),
                        y: field.homogeneous[1].evaluated(atU: point, v: .zero, usage: &usage).divided(by: denominator, usage: &usage),
                        z: field.homogeneous[2].evaluated(atU: point, v: .zero, usage: &usage).divided(by: denominator, usage: &usage))
                    value = try source.projectedOriginalDerivative(original, atEnd: atEnd, order: order, usage: &usage)
                        .subtracting(original, usage: &usage)
                }
                guard let value else { throw GeometryConversionError.invalidInput("Original transverse corner lacks its Native owner.") }
                cornerDeltas.append(value)
            }
            for field in raw {
                try usage.consumeExactWork(1)
                let original = field.homogeneous
                let projected = try projected(original, source: source, atEnd: atEnd, order: order, usage: &usage)
                try RationalAlgebraStorage.retain(4, of: P.self, usage: &usage)
                var residual: [P] = []; residual.reserveCapacity(4)
                for axis in 0..<3 {
                    let a = component(cornerDeltas[0], axis), b = component(cornerDeltas[1], axis)
                    let corners = try h0.scaled(by: a, usage: &usage).adding(h1.scaled(by: b, usage: &usage), usage: &usage)
                    residual.append(try projected[axis].subtracting(original[axis], usage: &usage)
                        .subtracting(corners.multiplied(by: original[3], usage: &usage), usage: &usage))
                }
                residual.append(original[3])
                fields.append(.init(lower: field.lower, upper: field.upper, atEnd: atEnd, order: order, homogeneous: residual))
            }
        } }
        return fields
    }

    private static func nativeField<B: RationalAlgebraAdmitting>(_ homogeneous: [P], station: P, u: P,
        order: Int, usage: inout B) throws -> [P] {
        let derivatives = try OriginalRationalVectorDerivativeLaw(homogeneous: homogeneous, throughOrder: order, usage: &usage)
        var selected: OriginalRationalVectorDerivativeLaw.Partial?
        for entry in derivatives.partials {
            try usage.consumeExactWork(1)
            if entry.uOrder == 0, entry.vOrder == order { selected = entry; break }
        }
        guard let selected else { throw GeometryConversionError.invalidInput("Original Native law lost its transverse derivative.") }
        try RationalAlgebraStorage.retain(4, of: P.self, usage: &usage)
        var result: [P] = []; result.reserveCapacity(4)
        for p in selected.numerators { result.append(try p.composed(withU: u, v: station, usage: &usage)) }
        result.append(try selected.denominator.composed(withU: u, v: station, usage: &usage))
        return result
    }

    private static func projected<B: RationalAlgebraAdmitting>(_ value: [P], source: OriginalPlaneDerivativeSurface3D,
        atEnd: Bool, order: Int, usage: inout B) throws -> [P] {
        try RationalAlgebraStorage.retain(3, of: OriginalSupportingPlaneEquation.Vector.self, usage: &usage)
        var columns: [OriginalSupportingPlaneEquation.Vector] = []; columns.reserveCapacity(3)
        for axis in 0..<3 {
            let unit = OriginalSupportingPlaneEquation.Vector(x: axis == 0 ? .one : .zero,
                y: axis == 1 ? .one : .zero, z: axis == 2 ? .one : .zero)
            columns.append(try source.projectedOriginalDerivative(unit, atEnd: atEnd, order: order, usage: &usage))
        }
        try RationalAlgebraStorage.retain(3, of: P.self, usage: &usage)
        var result: [P] = []; result.reserveCapacity(3)
        for axis in 0..<3 {
            var law = P.zero
            for input in 0..<3 { law = try law.adding(value[input].scaled(by: component(columns[input], axis), usage: &usage), usage: &usage) }
            result.append(law)
        }
        return result
    }

    private static func component(_ value: OriginalSupportingPlaneEquation.Vector, _ axis: Int) -> Q {
        switch axis { case 0: value.x; case 1: value.y; default: value.z }
    }
    private static func valueBasis<B: RationalAlgebraAdmitting>(_ t: P, usage: inout B) throws -> P {
        var h = P.zero
        for power in (0...5).reversed() {
            h = try h.multiplied(by: t, usage: &usage).adding(.constant(.originalDouble(
                OriginalEndpointCorrectionBasis.quinticHermite.coefficient(at: power), usage: &usage), usage: &usage), usage: &usage)
        }
        return h
    }
    private static func derivativeBasis<B: RationalAlgebraAdmitting>(_ t: P, atEnd: Bool, order: Int,
        usage: inout B) throws -> P {
        var h = P.zero
        for power in (0...5).reversed() {
            h = try h.multiplied(by: t, usage: &usage).adding(.constant(.originalDouble(
                OriginalPlaneHermiteDerivativeBasis.coefficient(power: power, atEnd: atEnd, derivativeOrder: order),
                usage: &usage), usage: &usage), usage: &usage)
        }
        return h
    }
    private static func adding<B: RationalAlgebraAdmitting>(_ position: [P], weighted value: [P], by weight: P,
        usage: inout B) throws -> [P] {
        try RationalAlgebraStorage.retain(4, of: P.self, usage: &usage)
        var result: [P] = []; result.reserveCapacity(4)
        for axis in 0..<3 {
            result.append(try position[axis].multiplied(by: value[3], usage: &usage)
                .adding(value[axis].multiplied(by: weight, usage: &usage).multiplied(by: position[3], usage: &usage), usage: &usage))
        }
        result.append(try position[3].multiplied(by: value[3], usage: &usage))
        return result
    }
    private static func residual<B: RationalAlgebraAdmitting>(_ target: [Piece], _ original: [Piece],
        usage: inout B) throws -> [Piece] {
        var result: [Piece] = []; var capacity = 0
        for a in target { for b in original {
            try usage.consumeExactWork(1)
            let lower = try maximum(a.lower, b.lower, usage: &usage), upper = try minimum(a.upper, b.upper, usage: &usage)
            guard try upper.subtracting(lower, usage: &usage).isPositive else { continue }
            try RationalAlgebraStorage.retain(4, of: P.self, usage: &usage)
            var h: [P] = []; h.reserveCapacity(4)
            for axis in 0..<3 {
                h.append(try a.homogeneous[axis].multiplied(by: b.homogeneous[3], usage: &usage)
                    .subtracting(b.homogeneous[axis].multiplied(by: a.homogeneous[3], usage: &usage), usage: &usage))
            }
            h.append(try a.homogeneous[3].multiplied(by: b.homogeneous[3], usage: &usage))
            if result.count == capacity {
                let doubled = capacity.multipliedReportingOverflow(by: 2)
                guard !doubled.overflow else { throw GeometryConversionError.resourceLimitExceeded("Original connector residual capacity overflows.") }
                let next = capacity == 0 ? 1 : doubled.partialValue
                try RationalAlgebraStorage.retain(next, of: Piece.self, usage: &usage)
                try usage.consumeExactWork(result.count); result.reserveCapacity(next); capacity = next
            }
            result.append(.init(lower: lower, upper: upper, homogeneous: h))
        } }
        guard !result.isEmpty else { throw GeometryConversionError.invalidInput("Original derivative connector lost its rational position coverage.") }
        return result
    }
    private static func maximum<B: RationalAlgebraAdmitting>(_ a: Q, _ b: Q, usage: inout B) throws -> Q {
        try a.subtracting(b, usage: &usage).isNegative ? b : a
    }
    private static func minimum<B: RationalAlgebraAdmitting>(_ a: Q, _ b: Q, usage: inout B) throws -> Q {
        try a.subtracting(b, usage: &usage).isNegative ? a : b
    }
}

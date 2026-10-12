#if ISSUED_GEOMETRY_ISOLATED_VERIFICATION
import L0
import L1
import L2
import L3
#endif

/// Complete one-parameter section with exact original UV, XYZ and auxiliary lifts.
public struct OriginalSurfacePlaneSection: Sendable {
    public typealias Base = OriginalExactScalarDomain
    public typealias Field = ExactAlgebraicScalarDomain<Base>
    public let templateOrdinal: Int
    public let planeFirst: Bool
    public let selection: ExactRealCellSelection<Base>
    public let polynomials: ExactPolynomialDomain<Field>
    public let originalCoordinates: [ExactPolynomial<Field>]
    public let homogeneous: [ExactPolynomial<Field>]
    public let planeNumerators: [ExactPolynomial<Field>]
    public let derivativeNumerators: [ExactPolynomial<Field>]
    public let isConstant: Bool
    private let owner: any Sendable
    init(templateOrdinal: Int, planeFirst: Bool, selection: ExactRealCellSelection<Base>,
        polynomials: ExactPolynomialDomain<Field>, originalCoordinates: [ExactPolynomial<Field>],
        homogeneous: [ExactPolynomial<Field>], planeNumerators: [ExactPolynomial<Field>],
        derivativeNumerators: [ExactPolynomial<Field>], isConstant: Bool, owner: any Sendable) {
        self.templateOrdinal = templateOrdinal; self.planeFirst = planeFirst; self.selection = selection
        self.polynomials = polynomials; self.originalCoordinates = originalCoordinates; self.homogeneous = homogeneous
        self.planeNumerators = planeNumerators; self.derivativeNumerators = derivativeNumerators
        self.isConstant = isConstant; self.owner = owner
    }
    public func imageDimension(at ordinal: Int) -> Int? {
        guard selection.cells.indices.contains(ordinal) else { return nil }
        return isConstant ? 0:selection.cells[ordinal].dimension
    }
    public func fiberDimension(at ordinal: Int) -> Int? {
        guard let image = imageDimension(at:ordinal) else { return nil }
        return selection.cells[ordinal].dimension-image
    }
    public func contains<A: ExactScalarAdmission & ~Copyable>(_ v: Field.Value,
        limits: ExactRealRootLimits, using a: inout A) throws -> Bool {
        try a.checkpoint()
        let cells = try ExactRealCellDomain<Base>(retaining:selection.partition.source,using:&a)
        try a.retainStorage(bytes:exactScalarPayloadBytes(count:1,of:Field.Value.self))
        let point = try cells.point(field:polynomials.field,coordinates:[v],using:&a)
        let located = try cells.locate(point,in:selection.partition,limits:limits,using:&a)
        let accepted = located.map { selection.cells.contains($0) } ?? false
        try a.checkpoint(); return accepted
    }
}

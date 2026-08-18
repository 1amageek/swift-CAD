import CADGeometry

/// Allocates compact process-local identities using complete Curve3D equality.
///
/// Equality deliberately includes representation and parameterization because
/// cached parameters cannot be shared safely between merely coincident curves.
struct ExactCurveIdentityRegistry: Sendable {
    private var curves: [Curve3D] = []

    mutating func identity(for curve: Curve3D) -> ExactCurveIdentity {
        if let index = curves.firstIndex(of: curve) {
            return ExactCurveIdentity(ordinal: index)
        }
        curves.append(curve)
        return ExactCurveIdentity(ordinal: curves.count - 1)
    }
}

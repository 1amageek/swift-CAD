import CADGeometry
import CADTopology

/// Allocates compact process-local identities using complete Curve3D equality.
///
/// Equality deliberately includes representation and parameterization because
/// cached parameters cannot be shared safely between merely coincident curves.
struct ExactCurveIdentityRegistry: Sendable {
    private var curves: [Curve3D] = []

    mutating func identity(for curve: Curve3D,
        using execution: inout OriginalQueryExecution) throws -> ExactCurveIdentity {
        try GeometryStructuralComparisonWork.charge(curve: curve, using: &execution)
        for (index, existing) in curves.enumerated() {
            try execution.consumeWork(1)
            try GeometryStructuralComparisonWork.charge(curve: existing, using: &execution)
            if existing == curve { return ExactCurveIdentity(ordinal: index) }
        }
        try OriginalParameterQueryStorage.append(curve, to: &curves, using: &execution)
        return ExactCurveIdentity(ordinal: curves.count - 1)
    }
}

import CADCore

/// Exact representation aliases sharing the same original parameter chart.
struct OriginalCurveContactLawIdentity {
    func sameLaw(_ first: Curve3D, _ second: Curve3D, depth: Int = 0,
                 budget: inout NativeCurveCurveContactBudget) throws -> Bool {
        try budget.work(1)
        guard depth <= budget.remainingSourceDepth else { throw budget.exhausted() }
        func line(_ source: Curve3D) -> (Point3D, Vector3D)? {
            switch source {
            case .line(let original): return (original.origin, original.direction)
            case .analytic(.line(let origin, let direction)): return (origin, direction)
            default: return nil
            }
        }
        func circular(_ source: Curve3D) -> (Point3D, Vector3D, Double)? {
            switch source {
            case .analytic(.circle(let center, let normal, let radius)),
                 .analytic(.arc(let center, let normal, let radius, _, _)):
                return (center, normal, radius)
            default: return nil
            }
        }
        if let a = line(first), let b = line(second) {
            try budget.work(6)
            return a.0 == b.0 && a.1 == b.1
        }
        if let a = circular(first), let b = circular(second) {
            try budget.work(7)
            return a.0 == b.0 && a.1 == b.1 && a.2 == b.2
        }
        switch (first, second) {
        case (.rigidImage(let a), .rigidImage(let b)):
            try budget.work(12)
            guard a.transform == b.transform else { return false }
            return try sameLaw(a.source, b.source, depth: depth + 1, budget: &budget)
        case (.affineImage(let a), .affineImage(let b)):
            try budget.work(12)
            guard a.transform == b.transform else { return false }
            return try sameLaw(a.source, b.source, depth: depth + 1, budget: &budget)
        case (.parameterImage(let a), .parameterImage(let b)):
            try budget.work(3)
            guard a.offset == b.offset,
                  try a.parameterGain.isEquivalent(to: b.parameterGain, usage: &budget) else { return false }
            return try sameLaw(a.source, b.source, depth: depth + 1, budget: &budget)
        default: return false
        }
    }
}

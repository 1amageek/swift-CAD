import CADCore

package extension CertifiedImplicitIntersectionCurve {
    /// True proves complete structural component identity; false means identity is not proved.
    /// Different atlases and traversal orders require separate correspondence/coverage authority.
    func certifiesSameComponent(as other: CertifiedImplicitIntersectionCurve,
        tolerance: ModelingTolerance) throws -> Bool {
        var execution = try OriginalQueryExecution.independentGeometry()
        return try certifiesSameComponent(as: other, tolerance: tolerance, using: &execution)
    }

    /// Original supports and every graph-cell branch must match exactly after any role exchange.
    /// This query never derives component identity from proximity, residuals or nested boxes.
    func certifiesSameComponent(as other: CertifiedImplicitIntersectionCurve,
        tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution) throws -> Bool {
        try execution.checkpoint()
        try validate(tolerance: tolerance, using: &execution)
        try other.validate(tolerance: tolerance, using: &execution)
        try GeometryStructuralComparisonWork.charge(surface: firstSurface, using: &execution)
        try GeometryStructuralComparisonWork.charge(surface: secondSurface, using: &execution)
        try GeometryStructuralComparisonWork.charge(surface: other.firstSurface, using: &execution)
        try GeometryStructuralComparisonWork.charge(surface: other.secondSurface, using: &execution)
        let swapped: Bool
        if firstSurface == other.firstSurface, secondSurface == other.secondSurface { swapped = false }
        else if firstSurface == other.secondSurface, secondSurface == other.firstSurface { swapped = true }
        else { try execution.checkpoint(); return false }
        try execution.consumeWork(2)
        guard isClosed == other.isClosed, cells.count == other.cells.count else { return false }
        for index in cells.indices {
            let first = cells[index], second = other.cells[index]
            try execution.consumeWork(2)
            let coordinate = swapped ? Self.swapped(second.freeParameter) : second.freeParameter
            guard first.freeParameter == coordinate, first.direction == second.direction else { return false }
            for raw in 0..<4 {
                guard let coordinate = SurfaceIntersectionParameterCoordinate(rawValue: raw) else {
                    throw ExactScalarFailure.invalidEvidence
                }
                try execution.consumeWork(1)
                let otherCoordinate = swapped ? Self.swapped(coordinate) : coordinate
                guard first.parameterBox.interval(for: coordinate)
                    == second.parameterBox.interval(for: otherCoordinate) else { return false }
            }
            guard try Self.sameAnchor(first.lowerAnchor, second.lowerAnchor, swapped: swapped, using: &execution),
                try Self.sameAnchor(first.midpointAnchor, second.midpointAnchor, swapped: swapped, using: &execution),
                try Self.sameAnchor(first.upperAnchor, second.upperAnchor, swapped: swapped, using: &execution)
                else { return false }
        }
        try execution.checkpoint()
        return true
    }

    private static func sameAnchor<A: ExactScalarAdmission & ~Copyable>(_ first: SurfaceIntersectionParameterPair,
        _ second: SurfaceIntersectionParameterPair, swapped: Bool, using execution: inout A) throws -> Bool {
        try execution.consumeWork(4)
        return first.first == (swapped ? second.second : second.first)
            && first.second == (swapped ? second.first : second.second)
    }

    private static func swapped(_ coordinate: SurfaceIntersectionParameterCoordinate)
        -> SurfaceIntersectionParameterCoordinate {
        switch coordinate {
        case .firstU: .secondU
        case .firstV: .secondV
        case .secondU: .firstU
        case .secondV: .firstV
        }
    }
}

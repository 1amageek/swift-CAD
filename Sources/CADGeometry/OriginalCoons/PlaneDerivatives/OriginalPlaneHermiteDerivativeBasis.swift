import CADCore

/// Original quintic endpoint derivative bases with zero endpoint values.
package struct OriginalPlaneHermiteDerivativeBasis {
    package static func coefficient(power: Int, atEnd: Bool, derivativeOrder: Int) throws -> Double {
        guard (0...5).contains(power), (1...2).contains(derivativeOrder) else {
            throw GeometryConversionError.invalidInput("Original Hermite derivative basis has an invalid coefficient index.")
        }
        switch (atEnd, derivativeOrder, power) {
        case (false, 1, 1): return 1
        case (false, 1, 3): return -6
        case (false, 1, 4): return 8
        case (false, 1, 5): return -3
        case (true, 1, 3): return -4
        case (true, 1, 4): return 7
        case (true, 1, 5): return -3
        case (false, 2, 2): return 0.5
        case (false, 2, 3): return -1.5
        case (false, 2, 4): return 1.5
        case (false, 2, 5): return -0.5
        case (true, 2, 3): return 0.5
        case (true, 2, 4): return -1
        case (true, 2, 5): return 0.5
        default: return 0
        }
    }

    package static func jet(over range: ScalarInterval, alongU: Bool, atEnd: Bool,
        derivativeOrder: Int, throughOrder: Int, tolerance: ModelingTolerance,
        consumeWork: () throws -> Void, consumeStorage: ((Int) throws -> Void)?) throws -> SurfaceAreaIntervalTaylorScalarJet {
        var parameter = try SurfaceAreaIntervalTaylorScalarJet.constant(.init(lower: range.lower, upper: range.upper),
            order: throughOrder, axis: alongU ? .u : .v, tolerance: tolerance, consumeWork: consumeWork, consumeStorage: consumeStorage)
        if throughOrder > 0 { try parameter.set(.exact(1), alongU ? 1 : 0, alongU ? 0 : 1) }
        var result = try SurfaceAreaIntervalTaylorScalarJet.constant(.exact(0), order: throughOrder,
            tolerance: tolerance, consumeWork: consumeWork, consumeStorage: consumeStorage)
        for power in (0...5).reversed() {
            try CurrentTaskCancellationChecker().checkCancellation(); try consumeWork()
            let value = try SurfaceAreaIntervalTaylorScalarJet.constant(.exact(coefficient(power: power,
                atEnd: atEnd, derivativeOrder: derivativeOrder)), order: throughOrder, tolerance: tolerance,
                consumeWork: consumeWork, consumeStorage: consumeStorage)
            result = try result.multiplied(by: parameter, consumeWork: consumeWork, consumeStorage: consumeStorage)
                .adding(value, consumeWork: consumeWork, consumeStorage: consumeStorage)
        }
        return result
    }
}

import CADCore

extension BSplineCurve3D {
    func periodicRefinement<A: ExactScalarAdmission & ~Copyable>(
        at value: Double, options: PeriodicBSplineExpansionOptions, tolerance: ModelingTolerance, using execution: inout A
    ) throws -> BSplineCurve3D {
        try execution.consumeWork(1)
        try options.validate(tolerance: tolerance)
        guard value.isFinite else {
            throw KernelError(phase: .geometry, code: .invalidInput, tolerance: tolerance,
                message: "A periodic knot insertion requires a finite parameter.")
        }
        let count = controlPointCount - degree
        let lower = knots[degree]
        let period = knots[controlPointCount] - lower
        let parameter = try basisParameter(value, tolerance: tolerance)
        let multiplicity = try knots.reduce(0) { try execution.consumeWork(1); return $0 + ($1 == parameter ? 1 : 0) }
        guard multiplicity < degree else {
            throw KernelError(phase: .geometry, code: .invalidInput, tolerance: tolerance,
                message: "Periodic knot insertion cannot exceed the degree-fold multiplicity.")
        }
        let isSeam = parameter == lower
        let plan = try PeriodicBSplineEditPlan.refinement(degree: degree,
            controlPointCount: controlPointCount, periodic: true, isSeam: isSeam, tolerance: tolerance)
        try plan.admit(options, tolerance: tolerance)
        let padding = (plan.cycleCount - 1) / 2
        var window = try periodicWindow(firstCycle: plan.firstCycle, cycleCount: plan.cycleCount,
            reservedControlPoints: plan.reservedControlPoints, options: options, tolerance: tolerance, using: &execution)
        let firstInsertionCycle = -padding + (isSeam ? 1 : 0)
        for cycle in firstInsertionCycle...padding {
            try execution.consumeWork(1)
            let translated = parameter + Double(cycle) * period
            guard translated.isFinite, translated > window.knots[degree],
                  translated < window.knots[window.controlPointCount] else {
                throw expansionFailure(tolerance)
            }
            let translatedMultiplicity = try window.knots.reduce(0) { try execution.consumeWork(1); return $0 + ($1 == translated ? 1 : 0) }
            guard translatedMultiplicity < degree else {
                throw expansionFailure(tolerance)
            }
            window = try window.insertingInteriorKnot(translated,
                multiplicity: translatedMultiplicity, tolerance: tolerance, using: &execution)
        }
        let cycleCapacity = count.addingReportingOverflow(2)
        guard !cycleCapacity.overflow else { throw ExactScalarFailure.countOverflow }
        try execution.retainStorage(bytes: exactScalarPayloadBytes(count: cycleCapacity.partialValue, of: Double.self))
        var cycleKnots = Array(knots[degree...controlPointCount])
        cycleKnots.reserveCapacity(cycleCapacity.partialValue)
        let insertionIndex = try cycleKnots.firstIndex(where: { try execution.consumeWork(1); return $0 > parameter }) ?? count
        cycleKnots.insert(parameter, at: insertionIndex)
        let newCount = count + 1
        // A seam copy on the leftmost window boundary was deliberately omitted.
        let offset = padding * newCount - (isSeam ? 1 : 0)
        try execution.retainStorage(bytes: exactScalarPayloadBytes(count: newCount, of: Double.self))
        let expectedKnots = try Self.translatedPeriodicKnots(degree: degree,
            cycleKnots: Array(cycleKnots.dropLast()), period: period,
            independentControlCount: newCount, firstCycle: 0, tolerance: tolerance, using: &execution)
        guard offset >= 0, offset + expectedKnots.count <= window.knots.count,
              offset + newCount + degree <= window.controlPointCount else {
            throw expansionFailure(tolerance)
        }
        for index in expectedKnots.indices {
            try execution.consumeWork(1)
            try requireArithmeticAgreement(window.knots[offset + index], expectedKnots[index], tolerance: tolerance)
        }
        for index in 0..<degree {
            try execution.consumeWork(1)
            let first = offset + index % newCount
            let repeated = offset + newCount + index
            let a = window.controlPoints[first]
            let b = window.controlPoints[repeated]
            for (x, y) in [(a.x, b.x), (a.y, b.y), (a.z, b.z), (window.weights[first], window.weights[repeated])] {
                try execution.consumeWork(1)
                try requireArithmeticAgreement(x, y, tolerance: tolerance)
            }
        }
        try execution.retainStorage(bytes: exactScalarPayloadBytes(count: newCount, of: Point3D.self))
        try execution.retainStorage(bytes: exactScalarPayloadBytes(count: newCount, of: Double.self))
        var result = try Self.periodic(degree: degree, cycleKnots: cycleKnots,
            controlPoints: Array(window.controlPoints[offset..<(offset + newCount)]),
            weights: Array(window.weights[offset..<(offset + newCount)]), tolerance: tolerance, using: &execution)
        result.periodicOrigin = periodicOrigin
        try result.validate(tolerance: tolerance, using: &execution)
        return result
    }

    private func requireArithmeticAgreement(_ first: Double, _ second: Double, tolerance: ModelingTolerance) throws {
        let resolution = max(1, abs(first), abs(second)) * Double.ulpOfOne * 128
        guard first.isFinite, second.isFinite, abs(first - second) <= resolution else {
            throw KernelError(phase: .geometry, code: .resourceLimitExceeded, tolerance: tolerance,
                message: "Periodic refinement could not retain translated knots and controls within arithmetic resolution.")
        }
    }
}

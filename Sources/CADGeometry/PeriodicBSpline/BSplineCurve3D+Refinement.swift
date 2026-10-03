import CADCore

extension BSplineCurve3D {
    func periodicRefinement(
        at value: Double, options: PeriodicBSplineExpansionOptions, tolerance: ModelingTolerance
    ) throws -> BSplineCurve3D {
        try options.validate(tolerance: tolerance)
        guard value.isFinite else {
            throw KernelError(phase: .geometry, code: .invalidInput, tolerance: tolerance,
                message: "A periodic knot insertion requires a finite parameter.")
        }
        let count = controlPointCount - degree
        let lower = knots[degree]
        let period = knots[controlPointCount] - lower
        let parameter = try basisParameter(value, tolerance: tolerance)
        let multiplicity = knots.filter { $0 == parameter }.count
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
            reservedControlPoints: plan.reservedControlPoints, options: options, tolerance: tolerance)
        let firstInsertionCycle = -padding + (isSeam ? 1 : 0)
        for cycle in firstInsertionCycle...padding {
            let translated = parameter + Double(cycle) * period
            guard translated.isFinite, translated > window.knots[degree],
                  translated < window.knots[window.controlPointCount] else {
                throw expansionFailure(tolerance)
            }
            let translatedMultiplicity = window.knots.filter { $0 == translated }.count
            guard translatedMultiplicity < degree else {
                throw expansionFailure(tolerance)
            }
            window = try window.insertingInteriorKnot(translated,
                multiplicity: translatedMultiplicity, tolerance: tolerance)
        }
        var cycleKnots = Array(knots[degree...controlPointCount])
        let insertionIndex = cycleKnots.firstIndex(where: { $0 > parameter }) ?? count
        cycleKnots.insert(parameter, at: insertionIndex)
        let newCount = count + 1
        // A seam copy on the leftmost window boundary was deliberately omitted.
        let offset = padding * newCount - (isSeam ? 1 : 0)
        let expectedKnots = try Self.translatedPeriodicKnots(degree: degree,
            cycleKnots: Array(cycleKnots.dropLast()), period: period,
            independentControlCount: newCount, firstCycle: 0, tolerance: tolerance)
        guard offset >= 0, offset + expectedKnots.count <= window.knots.count,
              offset + newCount + degree <= window.controlPointCount else {
            throw expansionFailure(tolerance)
        }
        for index in expectedKnots.indices {
            try requireArithmeticAgreement(window.knots[offset + index], expectedKnots[index], tolerance: tolerance)
        }
        for index in 0..<degree {
            let first = offset + index % newCount
            let repeated = offset + newCount + index
            let a = window.controlPoints[first]
            let b = window.controlPoints[repeated]
            for (x, y) in [(a.x, b.x), (a.y, b.y), (a.z, b.z), (window.weights[first], window.weights[repeated])] {
                try requireArithmeticAgreement(x, y, tolerance: tolerance)
            }
        }
        var result = try Self.periodic(degree: degree, cycleKnots: cycleKnots,
            controlPoints: Array(window.controlPoints[offset..<(offset + newCount)]),
            weights: Array(window.weights[offset..<(offset + newCount)]), tolerance: tolerance)
        result.periodicOrigin = periodicOrigin
        try result.validate(tolerance: tolerance)
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

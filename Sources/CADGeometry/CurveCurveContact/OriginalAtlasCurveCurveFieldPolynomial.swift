import CADCore

/// Original pair equations over one retained ordered placement coefficient field.
struct OriginalAtlasCurveCurveFieldPolynomial {
    private struct State {
        var context: OriginalSingularFieldContext
        var transport: OriginalSingularFieldTransport
    }

    func equations(first: Curve3D,
        firstOwner: PreparedCurveDifferentialEncloser.ClosedNativeJet.OwnedSpan,
        second: Curve3D,
        secondOwner: PreparedCurveDifferentialEncloser.ClosedNativeJet.OwnedSpan,
        budget: inout NativeCurveCurveContactBudget) throws -> [OriginalSingularFieldPlanePolynomial]? {
        try prepare(first: first, firstOwner: firstOwner, second: second,
            secondOwner: secondOwner, budget: &budget)?.equations
    }

    func prepare(first: Curve3D,
        firstOwner: PreparedCurveDifferentialEncloser.ClosedNativeJet.OwnedSpan,
        second: Curve3D,
        secondOwner: PreparedCurveDifferentialEncloser.ClosedNativeJet.OwnedSpan,
        budget: inout NativeCurveCurveContactBudget) throws -> OriginalAtlasCurveCurveFieldEquationSet? {
        let previous = budget.enterOriginalWordAlgebra()
        defer { budget.restoreOriginalWordAlgebra(previous) }
        var state = State(context: try OriginalSingularFieldContext(usage: &budget),
            transport: OriginalSingularFieldTransport())
        let u = try ExactBivariatePolynomial.coordinate(alongU: true, usage: &budget)
        let v = try ExactBivariatePolynomial.coordinate(alongU: false, usage: &budget)
        guard let a = try homogeneous(first, owner: firstOwner, parameter: u,
            alongU: true, depth: 0, state: &state, budget: &budget),
            let b = try homogeneous(second, owner: secondOwner, parameter: v,
            alongU: false, depth: 0, state: &state, budget: &budget) else { return nil }
        let firstValues = try embedded(a, in: state.context, budget: &budget)
        let secondValues = try embedded(b, in: state.context, budget: &budget)
        try RationalAlgebraStorage.retain(3, of: OriginalSingularFieldPlanePolynomial.self, usage: &budget)
        var result: [OriginalSingularFieldPlanePolynomial] = []
        result.reserveCapacity(3)
        for axis in 0..<3 {
            result.append(try firstValues[axis].multiplied(by: secondValues[3],
                maximumDepth: budget.maximumAlgebraicDepth, usage: &budget).subtracting(
                    secondValues[axis].multiplied(by: firstValues[3], maximumDepth: budget.maximumAlgebraicDepth, usage: &budget),
                    maximumDepth: budget.maximumAlgebraicDepth, usage: &budget))
        }
        let denominator = try firstValues[3].multiplied(by: secondValues[3],
            maximumDepth: budget.maximumAlgebraicDepth, usage: &budget)
        try RationalAlgebraStorage.retain(1, of: OriginalAtlasCurveCurveFieldEquationSet.self, usage: &budget)
        return .init(equations: result, denominator: denominator)
    }

    private func homogeneous(_ source: Curve3D,
        owner: PreparedCurveDifferentialEncloser.ClosedNativeJet.OwnedSpan,
        parameter: ExactBivariatePolynomial, alongU: Bool, depth: Int,
        state: inout State, budget: inout NativeCurveCurveContactBudget)
        throws -> [OriginalSingularFieldPlanePolynomial]? {
        try budget.work(1)
        guard depth <= budget.remainingSourceDepth else { throw budget.exhausted() }
        switch source {
        case .bSpline, .line, .analytic(.line), .originalGuideTraversalChain,
            .originalGuideEndpointConnector, .originalPlaneDerivative:
            guard let original = try OriginalAtlasCurveCurvePolynomial().originalHomogeneous(
                source: source, owner: owner, parameter: parameter, alongU: alongU,
                depth: depth, budget: &budget) else { return nil }
            try RationalAlgebraStorage.retain(4, of: OriginalSingularFieldPlanePolynomial.self, usage: &budget)
            var result: [OriginalSingularFieldPlanePolynomial] = []
            result.reserveCapacity(4)
            for value in original {
                result.append(try .original(value, in: state.context, maximumDepth: budget.maximumAlgebraicDepth, usage: &budget))
            }
            return result
        case .parameterImage(let image):
            let parameter = try parameter.scaled(by: image.parameterGain.exactCoefficient(usage: &budget),
                usage: &budget).adding(.constant(.originalDouble(image.offset, usage: &budget), usage: &budget),
                    usage: &budget)
            return try homogeneous(image.source, owner: owner, parameter: parameter,
                alongU: alongU, depth: depth + 1, state: &state, budget: &budget)
        case .originalConstructionChart(let image):
            guard case .parameterLaw(let chart) = image.chart, chart.law == .affine,
                let map = owner.originalAffineParameterMap else { return nil }
            let mapped = try parameter.scaled(by: map.gain, usage: &budget)
                .adding(.constant(map.offset, usage: &budget), usage: &budget)
            return try homogeneous(chart.source, owner: owner, parameter: mapped,
                alongU: alongU, depth: depth + 1, state: &state, budget: &budget)
        case .rigidImage(let image):
            guard let values = try homogeneous(image.source, owner: owner, parameter: parameter,
                alongU: alongU, depth: depth + 1, state: &state, budget: &budget) else { return nil }
            return try transformed(values, x: image.transform.basisX, y: image.transform.basisY,
                z: image.transform.basisZ, translation: image.transform.translation, budget: &budget)
        case .affineImage(let image):
            guard let values = try homogeneous(image.source, owner: owner, parameter: parameter,
                alongU: alongU, depth: depth + 1, state: &state, budget: &budget) else { return nil }
            return try transformed(values, x: image.transform.basisX, y: image.transform.basisY,
                z: image.transform.basisZ, translation: image.transform.translation, budget: &budget)
        case .originalAffineWord(let image):
            guard let values = try homogeneous(image.source, owner: owner, parameter: parameter,
                alongU: alongU, depth: depth + 1, state: &state, budget: &budget) else { return nil }
            let prepared = image.preparedWord
            let frame = try prepared.originalNormalizedFrame(usage: &budget)
            let algebraDepth = frame.map { min(budget.maximumAlgebraicDepth, $0.maximumAlgebraicDepth) } ?? budget.maximumAlgebraicDepth
            if let frame {
                guard frame.frame.basisX.count == 3, frame.frame.basisY.count == 3,
                    frame.frame.basisZ.count == 3, frame.frame.translation.count == 3 else {
                    throw budget.exhausted()
                }
                state.context = try state.transport.importing(frame.frame.basisX[0].context,
                    into: state.context, maximumDepth: algebraDepth, usage: &budget)
            }
            let original = try embedded(values, in: state.context, budget: &budget)
            try RationalAlgebraStorage.retain(4, of: OriginalSingularFieldPlanePolynomial.self, usage: &budget)
            var result: [OriginalSingularFieldPlanePolynomial] = []
            result.reserveCapacity(4)
            for row in 0..<3 {
                var value = try OriginalSingularFieldPlanePolynomial(context: state.context,
                    coefficients: [:], maximumDepth: algebraDepth, usage: &budget)
                for column in 0..<4 {
                    let coefficient: OriginalSingularFieldElement
                    if let frame {
                        let raw: OriginalSingularFieldElement
                        switch column {
                        case 0: raw = frame.frame.basisX[row]
                        case 1: raw = frame.frame.basisY[row]
                        case 2: raw = frame.frame.basisZ[row]
                        default: raw = frame.frame.translation[row]
                        }
                        coefficient = try state.transport.applying(to: raw, in: state.context,
                            maximumDepth: algebraDepth, usage: &budget)
                    } else {
                        let raw = try column == 3 ? prepared.translationCoefficient(row: row)
                            : prepared.linearCoefficient(row: row, column: column)
                        coefficient = try .constant(raw, in: state.context,
                            maximumDepth: algebraDepth, usage: &budget)
                    }
                    let scale = try OriginalSingularFieldPlanePolynomial.constant(coefficient,
                        maximumDepth: algebraDepth, usage: &budget)
                    value = try value.adding(original[column].multiplied(by: scale,
                        maximumDepth: algebraDepth, usage: &budget), maximumDepth: algebraDepth, usage: &budget)
                }
                result.append(value)
            }
            result.append(original[3])
            return result
        // FIXME(INCOMPLETE_IMPLEMENTATION): Loft's original guide contact route
        // requires exact original angular/procedural coefficient charts here.
        // This field producer handles native rational laws and spatial words;
        // an unavailable original law remains unresolved, never exact absence.
        default: return nil
        }
    }

    private func embedded(_ values: [OriginalSingularFieldPlanePolynomial],
        in context: OriginalSingularFieldContext, budget: inout NativeCurveCurveContactBudget)
        throws -> [OriginalSingularFieldPlanePolynomial] {
        try RationalAlgebraStorage.retain(values.count, of: OriginalSingularFieldPlanePolynomial.self, usage: &budget)
        var result: [OriginalSingularFieldPlanePolynomial] = []
        result.reserveCapacity(values.count)
        for value in values { result.append(try value.embedded(in: context, maximumDepth: budget.maximumAlgebraicDepth, usage: &budget)) }
        return result
    }

    private func transformed(_ original: [OriginalSingularFieldPlanePolynomial],
        x: Vector3D, y: Vector3D, z: Vector3D, translation: Vector3D,
        budget: inout NativeCurveCurveContactBudget) throws -> [OriginalSingularFieldPlanePolynomial] {
        guard let first = original.first, original.count == 4 else { throw budget.exhausted() }
        try RationalAlgebraStorage.retain(4, of: OriginalSingularFieldPlanePolynomial.self, usage: &budget)
        try RationalAlgebraStorage.retain(3, of: (Double, Double, Double, Double).self, usage: &budget)
        var result: [OriginalSingularFieldPlanePolynomial] = []
        result.reserveCapacity(4)
        for (a, b, c, shift) in [(x.x, y.x, z.x, translation.x),
            (x.y, y.y, z.y, translation.y), (x.z, y.z, z.z, translation.z)] {
            var value = try OriginalSingularFieldPlanePolynomial(context: first.context,
                coefficients: [:], maximumDepth: budget.maximumAlgebraicDepth, usage: &budget)
            try RationalAlgebraStorage.retain(4, of: Double.self, usage: &budget)
            for (column, raw) in [a, b, c, shift].enumerated() {
                let exact = try OriginalSingularFieldElement.constant(.originalDouble(raw, usage: &budget),
                    in: first.context, maximumDepth: budget.maximumAlgebraicDepth, usage: &budget)
                value = try value.adding(original[column].multiplied(by:
                    .constant(exact, maximumDepth: budget.maximumAlgebraicDepth, usage: &budget), maximumDepth: budget.maximumAlgebraicDepth, usage: &budget),
                    maximumDepth: budget.maximumAlgebraicDepth, usage: &budget)
            }
            result.append(value)
        }
        result.append(original[3])
        return result
    }
}

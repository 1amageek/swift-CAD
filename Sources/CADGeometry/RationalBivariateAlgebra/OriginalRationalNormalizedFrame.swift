import CADCore

/// Original exact normalized columns and translation; rounded matrices are derived only.
package struct OriginalRationalNormalizedFrame: Sendable {
    package enum Family: Sendable { case axis2, cartesian }
    package enum NormalizationPolicy: Sendable {
        case physicalDistance
        case dimensionlessOriginalDirections
    }
    package let basisX: [OriginalSingularFieldElement]
    package let basisY: [OriginalSingularFieldElement]
    package let basisZ: [OriginalSingularFieldElement]
    package let translation: [OriginalSingularFieldElement]
    private let minimumNormalizationSquare: OriginalSingularFieldElement?

    package init<B: RationalAlgebraAdmitting>(family: Family, location: Vector3D,
        axis1: Vector3D?, axis2: Vector3D?, axis3: Vector3D?, scale: Double?,
        lengthGain: ExactRationalCoefficient, linearGain: ExactRationalCoefficient = .one, adjustments: [(displacement: Vector3D, conjugates: Bool)],
        in base: OriginalSingularFieldContext, tolerance: ModelingTolerance,
        normalizationPolicy: NormalizationPolicy = .physicalDistance,
        inheritedDepth: Int, maximumDepth: Int, usage: inout B) throws {
        guard maximumDepth >= 0, base.coefficientDepth <= maximumDepth else {
            throw rationalAlgebraFailure("Original normalized source exceeds current coefficient admission.")
        }
        var admission = RationalCoefficientDepthAdmission(base: usage, maximumDepth: maximumDepth)
        defer { usage = admission.base }

        try tolerance.validate()
        guard lengthGain.isPositive, linearGain.isPositive, inheritedDepth <= maximumDepth, inheritedDepth >= 0 else {
            throw rationalAlgebraFailure("Original frame requires positive length gain and admitted source depth.")
        }
        var minimum: OriginalSingularFieldElement?
        let z = try Self.normalized(Self.vector(axis3 ?? .unitZ, in: base, maximumDepth: maximumDepth, usage: &admission),
            tolerance: tolerance, policy: normalizationPolicy, inheritedDepth: inheritedDepth, maximumDepth: maximumDepth, minimum: &minimum, usage: &admission)
        let rawZ = axis3 ?? .unitZ
        let fallback = rawZ.y == 0 && rawZ.z == 0 ? Vector3D.unitY : Vector3D.unitX
        let proposed = try Self.normalized(Self.vector(axis1 ?? fallback, in: z[0].context, maximumDepth: maximumDepth, usage: &admission),
            tolerance: tolerance, policy: normalizationPolicy, inheritedDepth: max(inheritedDepth, z[0].context.depth), maximumDepth: maximumDepth, minimum: &minimum, usage: &admission)
        let projected = try Self.subtract(proposed, Self.scaled(z, by: Self.dot(proposed, z,
            maximumDepth: maximumDepth, usage: &admission), maximumDepth: maximumDepth, usage: &admission),
            maximumDepth: maximumDepth, usage: &admission)
        let x = try Self.normalized(projected, tolerance: tolerance, policy: normalizationPolicy,
            inheritedDepth: max(inheritedDepth, proposed[0].context.depth), maximumDepth: maximumDepth, minimum: &minimum, usage: &admission)
        let y: [OriginalSingularFieldElement]
        switch family {
        case .axis2:
            y = try Self.cross(z, x, maximumDepth: maximumDepth, usage: &admission)
        case .cartesian:
            let proposed = try Self.normalized(Self.vector(axis2 ?? .unitY, in: x[0].context,
                maximumDepth: maximumDepth, usage: &admission), tolerance: tolerance, policy: normalizationPolicy,
                inheritedDepth: max(inheritedDepth, x[0].context.depth), maximumDepth: maximumDepth, minimum: &minimum, usage: &admission)
            let first = try Self.subtract(proposed, Self.scaled(z, by: Self.dot(proposed, z,
                maximumDepth: maximumDepth, usage: &admission), maximumDepth: maximumDepth, usage: &admission),
                maximumDepth: maximumDepth, usage: &admission)
            let second = try Self.subtract(first, Self.scaled(x, by: Self.dot(proposed, x,
                maximumDepth: maximumDepth, usage: &admission), maximumDepth: maximumDepth, usage: &admission),
                maximumDepth: maximumDepth, usage: &admission)
            y = try Self.normalized(second, tolerance: tolerance, policy: normalizationPolicy,
                inheritedDepth: max(inheritedDepth, proposed[0].context.depth), maximumDepth: maximumDepth, minimum: &minimum, usage: &admission)
        }
        let context = y[0].context
        let scaleValue = try ExactRationalCoefficient.originalDouble(scale ?? 1, usage: &admission)
            .multiplied(by: linearGain, usage: &admission)
        let gain = try OriginalSingularFieldElement.constant(scaleValue,
            in: context, maximumDepth: maximumDepth, usage: &admission)
        guard case .positive = try gain.sign(maximumDepth: maximumDepth, usage: &admission) else {
            throw rationalAlgebraFailure("Original uniform frame scale must be positive.")
        }
        basisX = try Self.scaled(x, by: gain, maximumDepth: maximumDepth, usage: &admission)
        basisY = try Self.scaled(y, by: gain, maximumDepth: maximumDepth, usage: &admission)
        basisZ = try Self.scaled(z, by: gain, maximumDepth: maximumDepth, usage: &admission)
        let factor = try OriginalSingularFieldElement.constant(lengthGain, in: context, maximumDepth: maximumDepth, usage: &admission)
        var origin = try Self.scaled(Self.vector(location, in: context, maximumDepth: maximumDepth, usage: &admission),
            by: factor, maximumDepth: maximumDepth, usage: &admission)
        for adjustment in adjustments {
            let offset = try Self.vector(adjustment.displacement, in: context, maximumDepth: maximumDepth, usage: &admission)
            var displacement = offset
            if adjustment.conjugates {
                var image = try Self.vector(.zero, in: context, maximumDepth: maximumDepth, usage: &admission)
                for axis in 0..<3 {
                    let column = axis == 0 ? basisX : axis == 1 ? basisY : basisZ
                    image = try Self.add(image, Self.scaled(column, by: offset[axis], maximumDepth: maximumDepth, usage: &admission),
                        maximumDepth: maximumDepth, usage: &admission)
                }
                displacement = try Self.subtract(offset, image, maximumDepth: maximumDepth, usage: &admission)
            }
            origin = try Self.add(origin, displacement, maximumDepth: maximumDepth, usage: &admission)
        }
        translation = origin
        guard let minimum else { throw rationalAlgebraFailure("Original normalized frame lost its normalization premise.") }
        minimumNormalizationSquare = try minimum.embedded(in: context, maximumDepth: maximumDepth, usage: &admission)
    }

    package init<B: RationalAlgebraAdmitting>(authored transform: AffineTransform3D,
        in context: OriginalSingularFieldContext, maximumDepth: Int, usage: inout B) throws {
        _ = try transform.originalDeterminantSign(consumeWork: { try usage.consumeExactWork(1) })
        basisX = try Self.vector(transform.basisX, in: context, maximumDepth: maximumDepth, usage: &usage)
        basisY = try Self.vector(transform.basisY, in: context, maximumDepth: maximumDepth, usage: &usage)
        basisZ = try Self.vector(transform.basisZ, in: context, maximumDepth: maximumDepth, usage: &usage)
        translation = try Self.vector(transform.translation, in: context, maximumDepth: maximumDepth, usage: &usage)
        minimumNormalizationSquare = nil
    }

    package init<B: RationalAlgebraAdmitting>(authoredCoefficients: [ExactRationalCoefficient],
        in context: OriginalSingularFieldContext, maximumDepth: Int, usage: inout B) throws {
        guard authoredCoefficients.count == 12, maximumDepth >= 0,
            context.coefficientDepth <= maximumDepth else {
            throw rationalAlgebraFailure("Original rational affine source requires twelve coefficients and an admitted coefficient context.")
        }
        var admission = RationalCoefficientDepthAdmission(base: usage, maximumDepth: maximumDepth)
        defer { usage = admission.base }
        func column(_ index: Int, usage: inout RationalCoefficientDepthAdmission<B>) throws -> [OriginalSingularFieldElement] {
            try RationalAlgebraStorage.retain(3, of: OriginalSingularFieldElement.self, usage: &usage)
            var values: [OriginalSingularFieldElement] = []; values.reserveCapacity(3)
            for row in 0..<3 {
                try usage.consumeExactWork(1)
                values.append(try .constant(authoredCoefficients[row * 4 + index],
                    in: context, maximumDepth: maximumDepth, usage: &usage))
            }
            return values
        }
        let x = try column(0, usage: &admission), y = try column(1, usage: &admission)
        let z = try column(2, usage: &admission), origin = try column(3, usage: &admission)
        let determinant = try Self.dot(x, Self.cross(y, z, maximumDepth: maximumDepth, usage: &admission),
            maximumDepth: maximumDepth, usage: &admission)
        if case .zero = try determinant.sign(maximumDepth: maximumDepth, usage: &admission) {
            throw rationalAlgebraFailure("Original rational affine source is singular.")
        }
        basisX = x; basisY = y; basisZ = z; translation = origin
        minimumNormalizationSquare = nil
    }

    private init(basisX: [OriginalSingularFieldElement], basisY: [OriginalSingularFieldElement],
        basisZ: [OriginalSingularFieldElement], translation: [OriginalSingularFieldElement],
        minimumNormalizationSquare: OriginalSingularFieldElement? = nil) {
        self.basisX = basisX; self.basisY = basisY; self.basisZ = basisZ; self.translation = translation
        self.minimumNormalizationSquare = minimumNormalizationSquare
    }

    package var context: OriginalSingularFieldContext { translation[0].context }

    package func applying<B: RationalAlgebraAdmitting>(to original: Vector3D, asPoint: Bool,
        maximumDepth: Int, usage: inout B) throws -> [OriginalSingularFieldElement] {
        guard maximumDepth >= 0, context.coefficientDepth <= maximumDepth else {
            throw rationalAlgebraFailure("Original normalized frame exceeds current coefficient admission.")
        }
        var admission = RationalCoefficientDepthAdmission(base: usage, maximumDepth: maximumDepth)
        defer { usage = admission.base }

        let input = try Self.vector(original, in: context, maximumDepth: maximumDepth, usage: &admission)
        var result = try linear(input, maximumDepth: maximumDepth, usage: &admission)
        if asPoint { result = try Self.add(result, translation, maximumDepth: maximumDepth, usage: &admission) }
        return result
    }

    private func linear<B: RationalAlgebraAdmitting>(_ input: [OriginalSingularFieldElement],
        maximumDepth: Int, usage: inout B) throws -> [OriginalSingularFieldElement] {
        var result = try Self.vector(.zero, in: context, maximumDepth: maximumDepth, usage: &usage)
        for axis in 0..<3 {
            let factor = try input[axis].embedded(in: context, maximumDepth: maximumDepth, usage: &usage)
            let column = axis == 0 ? basisX : axis == 1 ? basisY : basisZ
            result = try Self.add(result, Self.scaled(column, by: factor, maximumDepth: maximumDepth, usage: &usage),
                maximumDepth: maximumDepth, usage: &usage)
        }
        return result
    }

    /// Exact inverse retains every radical and authored column; no numeric inverse is authority.
    package func inverse<B: RationalAlgebraAdmitting>(maximumDepth: Int, usage: inout B) throws -> Self {
        guard maximumDepth >= 0, context.coefficientDepth <= maximumDepth else {
            throw rationalAlgebraFailure("Original normalized frame exceeds current coefficient admission.")
        }
        var admission = RationalCoefficientDepthAdmission(base: usage, maximumDepth: maximumDepth)
        defer { usage = admission.base }

        let first = try Self.cross(basisY, basisZ, maximumDepth: maximumDepth, usage: &admission)
        let second = try Self.cross(basisZ, basisX, maximumDepth: maximumDepth, usage: &admission)
        let third = try Self.cross(basisX, basisY, maximumDepth: maximumDepth, usage: &admission)
        let determinant = try Self.dot(basisX, first, maximumDepth: maximumDepth, usage: &admission)
        if case .zero = try determinant.sign(maximumDepth: maximumDepth, usage: &admission) {
            throw rationalAlgebraFailure("Original normalized frame inverse is singular.")
        }
        var columns: [[OriginalSingularFieldElement]] = []
        try RationalAlgebraStorage.retain(3, of: [OriginalSingularFieldElement].self, usage: &admission)
        columns.reserveCapacity(3)
        for axis in 0..<3 {
            try RationalAlgebraStorage.retain(3, of: OriginalSingularFieldElement.self, usage: &admission)
            var column: [OriginalSingularFieldElement] = []; column.reserveCapacity(3)
            for row in 0..<3 {
                let value = row == 0 ? first[axis] : row == 1 ? second[axis] : third[axis]
                column.append(try value.divided(by: determinant, maximumDepth: maximumDepth, usage: &admission))
            }
            columns.append(column)
        }
        let zero = try Self.vector(.zero, in: context, maximumDepth: maximumDepth, usage: &admission)
        let provisional = Self(basisX: columns[0], basisY: columns[1], basisZ: columns[2], translation: zero)
        let origin = try Self.subtract(zero, provisional.linear(translation, maximumDepth: maximumDepth, usage: &admission),
            maximumDepth: maximumDepth, usage: &admission)
        return Self(basisX: columns[0], basisY: columns[1], basisZ: columns[2], translation: origin,
            minimumNormalizationSquare: minimumNormalizationSquare)
    }

    /// Callers extend one field context while traversing authored placement words in order.
    package func followed<B: RationalAlgebraAdmitting>(by next: Self,
        maximumDepth: Int, usage: inout B) throws -> Self {
        guard maximumDepth >= 0, context.coefficientDepth <= maximumDepth, next.context.coefficientDepth <= maximumDepth else {
            throw rationalAlgebraFailure("Original normalized frame exceeds current coefficient admission.")
        }
        var admission = RationalCoefficientDepthAdmission(base: usage, maximumDepth: maximumDepth)
        defer { usage = admission.base }

        let x = try next.linear(basisX, maximumDepth: maximumDepth, usage: &admission)
        let y = try next.linear(basisY, maximumDepth: maximumDepth, usage: &admission)
        let z = try next.linear(basisZ, maximumDepth: maximumDepth, usage: &admission)
        let moved = try next.linear(translation, maximumDepth: maximumDepth, usage: &admission)
        let origin = try Self.add(moved, next.translation, maximumDepth: maximumDepth, usage: &admission)
        let first = try minimumNormalizationSquare?.embedded(in: next.context, maximumDepth: maximumDepth, usage: &admission)
        let minimum = try Self.minimum(first, next.minimumNormalizationSquare,
            maximumDepth: maximumDepth, usage: &admission)
        return Self(basisX: x, basisY: y, basisZ: z, translation: origin, minimumNormalizationSquare: minimum)
    }

    package func validateNormalization<B: RationalAlgebraAdmitting>(tolerance: ModelingTolerance,
        normalizationPolicy: NormalizationPolicy = .physicalDistance,
        maximumDepth: Int, usage: inout B) throws {
        guard maximumDepth >= 0, context.coefficientDepth <= maximumDepth else {
            throw rationalAlgebraFailure("Original normalized frame exceeds current coefficient admission.")
        }
        var admission = RationalCoefficientDepthAdmission(base: usage, maximumDepth: maximumDepth)
        defer { usage = admission.base }

        try tolerance.validate()
        guard let minimumNormalizationSquare else { return }
        let threshold = try Self.threshold(policy: normalizationPolicy, tolerance: tolerance,
            in: minimumNormalizationSquare.context, maximumDepth: maximumDepth, usage: &admission)
        guard case .positive = try minimumNormalizationSquare.subtracting(threshold,
            maximumDepth: maximumDepth, usage: &admission).sign(maximumDepth: maximumDepth, usage: &admission) else {
            throw KernelError(phase: .geometry, code: .invalidInput, tolerance: tolerance,
                message: "Original normalization premise does not satisfy its selected dimension policy.")
        }
    }

    private static func minimum<B: RationalAlgebraAdmitting>(_ first: OriginalSingularFieldElement?,
        _ second: OriginalSingularFieldElement?, maximumDepth: Int, usage: inout B) throws -> OriginalSingularFieldElement? {
        guard let second else { return first }
        guard let first else { return second }
        let rebased = try first.embedded(in: second.context, maximumDepth: maximumDepth, usage: &usage)
        if case .positive = try rebased.subtracting(second, maximumDepth: maximumDepth, usage: &usage)
            .sign(maximumDepth: maximumDepth, usage: &usage) { return second }
        return rebased
    }

    private static func vector<B: RationalAlgebraAdmitting>(_ value: Vector3D, in context: OriginalSingularFieldContext,
        maximumDepth: Int, usage: inout B) throws -> [OriginalSingularFieldElement] {
        try RationalAlgebraStorage.retain(3, of: OriginalSingularFieldElement.self, usage: &usage)
        var result: [OriginalSingularFieldElement] = []
        result.reserveCapacity(3)
        for axis in 0..<3 {
            let scalar = axis == 0 ? value.x : axis == 1 ? value.y : value.z
            result.append(try .constant(.originalDouble(scalar, usage: &usage), in: context, maximumDepth: maximumDepth, usage: &usage))
        }
        return result
    }
    private static func dot<B: RationalAlgebraAdmitting>(_ a: [OriginalSingularFieldElement], _ b: [OriginalSingularFieldElement],
        maximumDepth: Int, usage: inout B) throws -> OriginalSingularFieldElement {
        let context = a[0].context
        var result = try OriginalSingularFieldElement.constant(.zero, in: context, maximumDepth: maximumDepth, usage: &usage)
        for axis in 0..<3 {
            result = try result.adding(a[axis].multiplied(by: b[axis], maximumDepth: maximumDepth, usage: &usage), maximumDepth: maximumDepth, usage: &usage)
        }
        return result
    }
    private static func normalized<B: RationalAlgebraAdmitting>(_ source: [OriginalSingularFieldElement],
        tolerance: ModelingTolerance, policy: NormalizationPolicy, inheritedDepth: Int, maximumDepth: Int,
        minimum: inout OriginalSingularFieldElement?, usage: inout B) throws -> [OriginalSingularFieldElement] {
        let context = source[0].context
        let square = try dot(source, source, maximumDepth: maximumDepth, usage: &usage)
        let threshold = try Self.threshold(policy: policy, tolerance: tolerance,
            in: context, maximumDepth: maximumDepth, usage: &usage)
        guard case .positive = try square.subtracting(threshold, maximumDepth: maximumDepth, usage: &usage)
            .sign(maximumDepth: maximumDepth, usage: &usage) else {
            throw KernelError(phase: .geometry, code: .invalidInput, tolerance: tolerance,
                message: "Original normalized direction has no positive Gram margin under its selected dimension policy.")
        }
        minimum = try Self.minimum(minimum, square, maximumDepth: maximumDepth, usage: &usage)
        // Original direction ratios admit an exact common rational rescaling.
        // This preserves the direction while avoiding root isolation whose
        // separation depends only on the arbitrary magnitude of raw ratios.
        var ratios = source
        var normalizedSquare = square
        if case .dimensionlessOriginalDirections = policy {
            var largest = ExactRationalCoefficient.zero
            var allRational = true
            for component in source {
                guard let value = try component.rationalValue(usage: &usage) else { allRational = false; break }
                let magnitude = value.isNegative ? value.negated : value
                if try magnitude.subtracting(largest, usage: &usage).isPositive { largest = magnitude }
            }
            if allRational, largest.isPositive {
                let gain = try OriginalSingularFieldElement.constant(.one.divided(by: largest, usage: &usage),
                    in: context, maximumDepth: maximumDepth, usage: &usage)
                ratios = try scaled(source, by: gain, maximumDepth: maximumDepth, usage: &usage)
                normalizedSquare = try dot(ratios, ratios, maximumDepth: maximumDepth, usage: &usage)
            }
        }
        let divisor = try normalizedSquare.nonnegativeSquareRoot(inheritedDepth: inheritedDepth,
            maximumDepth: maximumDepth, admissionDomain: .coefficient(maximumDepth: maximumDepth), usage: &usage)
        var result: [OriginalSingularFieldElement] = []
        try RationalAlgebraStorage.retain(3, of: OriginalSingularFieldElement.self, usage: &usage)
        result.reserveCapacity(3)
        for component in ratios {
            result.append(try component.embedded(in: divisor.context, maximumDepth: maximumDepth, usage: &usage)
                .divided(by: divisor, maximumDepth: maximumDepth, usage: &usage))
        }
        return result
    }
    private static func threshold<B: RationalAlgebraAdmitting>(policy: NormalizationPolicy,
        tolerance: ModelingTolerance, in context: OriginalSingularFieldContext,
        maximumDepth: Int, usage: inout B) throws -> OriginalSingularFieldElement {
        let value: ExactRationalCoefficient
        switch policy {
        case .dimensionlessOriginalDirections: value = .zero
        case .physicalDistance:
            let distance = try ExactRationalCoefficient.originalDouble(tolerance.distance, usage: &usage)
            value = try distance.multiplied(by: distance, usage: &usage)
        }
        return try .constant(value, in: context, maximumDepth: maximumDepth, usage: &usage)
    }
    private static func scaled<B: RationalAlgebraAdmitting>(_ source: [OriginalSingularFieldElement], by factor: OriginalSingularFieldElement,
        maximumDepth: Int, usage: inout B) throws -> [OriginalSingularFieldElement] {
        var result: [OriginalSingularFieldElement] = []; try RationalAlgebraStorage.retain(3, of: OriginalSingularFieldElement.self, usage: &usage)
        result.reserveCapacity(3)
        for value in source { result.append(try value.embedded(in: factor.context, maximumDepth: maximumDepth, usage: &usage)
            .multiplied(by: factor, maximumDepth: maximumDepth, usage: &usage)) }; return result
    }
    private static func add<B: RationalAlgebraAdmitting>(_ a: [OriginalSingularFieldElement], _ b: [OriginalSingularFieldElement],
        maximumDepth: Int, usage: inout B) throws -> [OriginalSingularFieldElement] {
        var result: [OriginalSingularFieldElement] = []; try RationalAlgebraStorage.retain(3, of: OriginalSingularFieldElement.self, usage: &usage)
        result.reserveCapacity(3)
        for axis in 0..<3 { result.append(try a[axis].adding(b[axis], maximumDepth: maximumDepth, usage: &usage)) }; return result
    }
    private static func subtract<B: RationalAlgebraAdmitting>(_ a: [OriginalSingularFieldElement], _ b: [OriginalSingularFieldElement],
        maximumDepth: Int, usage: inout B) throws -> [OriginalSingularFieldElement] {
        var result: [OriginalSingularFieldElement] = []; try RationalAlgebraStorage.retain(3, of: OriginalSingularFieldElement.self, usage: &usage)
        result.reserveCapacity(3)
        for axis in 0..<3 { result.append(try a[axis].subtracting(b[axis], maximumDepth: maximumDepth, usage: &usage)) }; return result
    }
    private static func cross<B: RationalAlgebraAdmitting>(_ a: [OriginalSingularFieldElement], _ b: [OriginalSingularFieldElement],
        maximumDepth: Int, usage: inout B) throws -> [OriginalSingularFieldElement] {
        var result: [OriginalSingularFieldElement] = []; try RationalAlgebraStorage.retain(3, of: OriginalSingularFieldElement.self, usage: &usage)
        result.reserveCapacity(3)
        for axis in 0..<3 {
            let first = try a[(axis + 1) % 3].embedded(in: b[0].context, maximumDepth: maximumDepth, usage: &usage)
            let second = try a[(axis + 2) % 3].embedded(in: b[0].context, maximumDepth: maximumDepth, usage: &usage)
            result.append(try first.multiplied(by: b[(axis + 2) % 3], maximumDepth: maximumDepth, usage: &usage)
                .subtracting(second.multiplied(by: b[(axis + 1) % 3], maximumDepth: maximumDepth, usage: &usage), maximumDepth: maximumDepth, usage: &usage))
        }; return result
    }
}

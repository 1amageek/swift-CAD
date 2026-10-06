import CADCore

/// Flat application-order source authority, with an immutable exact derived action.
public struct OriginalAffineOperationWord: Hashable, Sendable {
    public let factors: [OriginalAffineOperation]
    let coefficients: [ExactRationalCoefficient]
    let cofactorCoefficients: [ExactRationalCoefficient]
    let normalizedCofactors: [OriginalSingularFieldElement]
    let determinantCoefficient: ExactRationalCoefficient
    let normalizedDeterminant: OriginalSingularFieldElement?
    let normalizedFrame: OriginalRationalNormalizedFrame?
    let maximumDepth: Int
    public let orientationSign: Int
    var isRational: Bool { if case .none = normalizedFrame { return true }; return false }

    public init<B: RationalAlgebraAdmitting>(factors: [OriginalAffineOperation], usage: inout B) throws {
        guard !factors.isEmpty else { throw rationalAlgebraFailure("An original affine word requires at least one factor.") }
        try usage.consumeExactWork(factors.count)
        try OriginalAffineRationalMatrix.retain(factors.count, of: OriginalAffineOperation.self, usage: &usage)
        var matrix = try OriginalAffineRationalMatrix.identity(usage: &usage)
        var orientation = 1
        for operation in factors {
            try usage.consumeExactWork(1)
            guard let original = try OriginalAffineRationalMatrix.original(operation, usage: &usage) else {
                throw rationalAlgebraFailure("Normalized original factors require explicit tolerance and algebraic depth.")
            }
            let determinant = try OriginalAffineRationalMatrix.determinant(original, usage: &usage)
            guard !determinant.isZero else { throw rationalAlgebraFailure("Original affine factor is exactly singular.") }
            orientation *= determinant.isNegative ? -1 : 1
            let action: [ExactRationalCoefficient]
            switch operation {
            case .forward, .rationalForward: action = original
            case .inverse, .rationalInverse: action = try OriginalAffineRationalMatrix.inverse(original, determinant: determinant, usage: &usage)
            case .normalizedForward, .normalizedInverse:
                throw rationalAlgebraFailure("Normalized original factor requires algebraic preparation.")
            }
            matrix = try OriginalAffineRationalMatrix.compose(action, after: matrix, usage: &usage)
        }
        self.factors = factors; self.coefficients = matrix; self.orientationSign = orientation
        self.cofactorCoefficients = try OriginalAffineRationalMatrix.cofactors(matrix, usage: &usage)
        self.determinantCoefficient = try OriginalAffineRationalMatrix.determinant(matrix, usage: &usage)
        self.normalizedDeterminant = nil
        self.normalizedCofactors = []; self.normalizedFrame = nil; self.maximumDepth = 0
    }

    public init<B: RationalAlgebraAdmitting>(factors: [OriginalAffineOperation],
        tolerance: ModelingTolerance, maximumDepth: Int, usage: inout B) throws {
        try tolerance.validate()
        guard maximumDepth >= 0 else { throw rationalAlgebraFailure("Original algebraic depth must be nonnegative.") }
        try usage.consumeExactWork(factors.count)
        let hasNormalized = factors.contains { operation in
            switch operation { case .normalizedForward, .normalizedInverse: true; default: false }
        }
        if !hasNormalized {
            let rational = try Self(factors: factors, usage: &usage)
            self.init(originalFactors: rational.factors, coefficients: rational.coefficients,
                cofactors: rational.cofactorCoefficients, determinant: rational.determinantCoefficient,
                maximumDepth: maximumDepth, orientationSign: rational.orientationSign)
            return
        }
        guard !factors.isEmpty else { throw rationalAlgebraFailure("An original word requires factors.") }
        try usage.consumeExactWork(factors.count)
        try OriginalAffineRationalMatrix.retain(factors.count, of: OriginalAffineOperation.self, usage: &usage)
        let base = try OriginalSingularFieldContext(usage: &usage)
        let frame = try Self.fieldFrame(factors: factors, in: base, tolerance: tolerance,
            maximumDepth: maximumDepth, usage: &usage)
        let cofactorCache = try OriginalAffineFieldAction.cofactors(frame, maximumDepth: maximumDepth, usage: &usage)
        let determinant = try OriginalAffineFieldAction.determinant(frame, cofactors: cofactorCache, maximumDepth: maximumDepth, usage: &usage)
        let orientation: Int
        switch try determinant.sign(maximumDepth: maximumDepth, usage: &usage) {
        case .positive: orientation = 1
        case .negative: orientation = -1
        case .zero: throw rationalAlgebraFailure("Original normalized word is exactly singular.")
        }
        self.factors = factors; self.coefficients = []; self.normalizedFrame = frame
        self.cofactorCoefficients = []
        self.normalizedCofactors = cofactorCache
        self.normalizedDeterminant = determinant; self.determinantCoefficient = .zero
        self.maximumDepth = maximumDepth; self.orientationSign = orientation
    }

    /// Admits the single-factor array before creating its owned storage.
    public init<B: RationalAlgebraAdmitting>(operation: OriginalAffineOperation, tolerance: ModelingTolerance,
        maximumDepth: Int, usage: inout B) throws {
        try OriginalAffineRationalMatrix.retain(1, of: OriginalAffineOperation.self, usage: &usage)
        self = try Self(factors: [operation], tolerance: tolerance, maximumDepth: maximumDepth, usage: &usage)
    }

    private static func fieldFrame<B: RationalAlgebraAdmitting>(factors: [OriginalAffineOperation],
        in base: OriginalSingularFieldContext, tolerance: ModelingTolerance, maximumDepth: Int,
        usage: inout B) throws -> OriginalRationalNormalizedFrame {
        var context = base
        var frame: OriginalRationalNormalizedFrame?
        for operation in factors {
            try usage.consumeExactWork(1)
            var action: OriginalRationalNormalizedFrame
            switch operation {
            case .forward(let value), .inverse(let value):
                action = try OriginalRationalNormalizedFrame(authored: value, in: context,
                    maximumDepth: maximumDepth, usage: &usage)
            case .rationalForward(let value), .rationalInverse(let value):
                try value.validateOriginalPayload(usage: &usage)
                action = try OriginalRationalNormalizedFrame(authoredCoefficients: value.coefficients, in: context,
                    maximumDepth: maximumDepth, usage: &usage)
            case .normalizedForward(let value), .normalizedInverse(let value):
                action = try value.prepared(in: context, tolerance: tolerance,
                    maximumDepth: maximumDepth, usage: &usage)
            }
            switch operation {
            case .inverse, .rationalInverse, .normalizedInverse: action = try action.inverse(maximumDepth: maximumDepth, usage: &usage)
            default: break
            }
            if let previous = frame { action = try previous.followed(by: action, maximumDepth: maximumDepth, usage: &usage) }
            frame = action; context = action.context
        }
        guard let frame else { throw rationalAlgebraFailure("Original frame preparation is empty.") }
        return frame
    }

    /// Proves complete action equality in one shared original field, including normalization.
    public func isEquivalent<B: RationalAlgebraAdmitting>(to other: Self, tolerance: ModelingTolerance,
        maximumDepth: Int, usage: inout B) throws -> Bool {
        try tolerance.validate()
        guard maximumDepth >= 0 else { throw rationalAlgebraFailure("Original equivalence depth must be nonnegative.") }
        // Cached equality cannot bypass either original payload's caller admission.
        // This also checks each retained dimensionless normalization premise under
        // the selected algebraic cap without preparing the original words again.
        try validateOriginal(tolerance: tolerance, maximumDepth: maximumDepth, usage: &usage)
        try other.validateOriginal(tolerance: tolerance, maximumDepth: maximumDepth, usage: &usage)
        if isRational, other.isRational {
            for index in 0..<12 {
                try usage.consumeExactWork(1)
                if try !coefficients[index].subtracting(other.coefficients[index], usage: &usage).isZero { return false }
            }
            return true
        }
        let left: OriginalRationalNormalizedFrame
        if let frame = normalizedFrame { left = frame }
        else {
            let base = try OriginalSingularFieldContext(usage: &usage)
            left = try Self.fieldFrame(factors: factors, in: base,
                tolerance: tolerance, maximumDepth: maximumDepth, usage: &usage)
        }
        let right = try Self.fieldFrame(factors: other.factors, in: left.context,
            tolerance: tolerance, maximumDepth: maximumDepth, usage: &usage)
        for row in 0..<3 {
            for column in 0..<4 {
                try usage.consumeExactWork(1)
                let a = try OriginalAffineFieldAction.coefficient(left, row: row, column: column,
                    maximumDepth: maximumDepth, usage: &usage).embedded(in: right.context, maximumDepth: maximumDepth, usage: &usage)
                let b = try OriginalAffineFieldAction.coefficient(right, row: row, column: column,
                    maximumDepth: maximumDepth, usage: &usage)
                switch try a.subtracting(b, maximumDepth: maximumDepth, usage: &usage).sign(maximumDepth: maximumDepth, usage: &usage) {
                case .zero: break
                default: return false
                }
            }
        }
        return true
    }

    /// Compares two authored point images exactly, including nonbinary original unit gains.
    public func mapsSameImage<B: RationalAlgebraAdmitting>(of point: Point3D,
        as other: Self, of otherPoint: Point3D, tolerance: ModelingTolerance,
        maximumDepth: Int, usage: inout B) throws -> Bool {
        try point.validate(); try otherPoint.validate()
        try validateOriginal(tolerance: tolerance, maximumDepth: maximumDepth, usage: &usage)
        try other.validateOriginal(tolerance: tolerance, maximumDepth: maximumDepth, usage: &usage)
        if isRational, other.isRational {
            for row in 0..<3 {
                let first = try rationalPointCoordinate(point, row: row, usage: &usage)
                let second = try other.rationalPointCoordinate(otherPoint, row: row, usage: &usage)
                if try !first.subtracting(second, usage: &usage).isZero { return false }
            }
            return true
        }
        let first: OriginalRationalNormalizedFrame
        if let retained = normalizedFrame { first = retained }
        else {
            let base = try OriginalSingularFieldContext(usage: &usage)
            first = try Self.fieldFrame(factors: factors, in: base,
                tolerance: tolerance, maximumDepth: maximumDepth, usage: &usage)
        }
        let second = try Self.fieldFrame(factors: other.factors, in: first.context,
            tolerance: tolerance, maximumDepth: maximumDepth, usage: &usage)
        let firstImage = try first.applying(to: Vector3D(point.x, point.y, point.z),
            asPoint: true, maximumDepth: maximumDepth, usage: &usage)
        let secondImage = try second.applying(to: Vector3D(otherPoint.x, otherPoint.y, otherPoint.z),
            asPoint: true, maximumDepth: maximumDepth, usage: &usage)
        for coordinate in 0..<3 {
            try usage.consumeExactWork(1)
            let embedded = try firstImage[coordinate].embedded(in: second.context,
                maximumDepth: maximumDepth, usage: &usage)
            guard case .zero = try embedded.subtracting(secondImage[coordinate], maximumDepth: maximumDepth, usage: &usage)
                .sign(maximumDepth: maximumDepth, usage: &usage) else { return false }
        }
        return true
    }

    private func rationalPointCoordinate<B: RationalAlgebraAdmitting>(_ point: Point3D,
        row: Int, usage: inout B) throws -> ExactRationalCoefficient {
        var value = coefficients[row * 4 + 3]
        for column in 0..<3 {
            try usage.consumeExactWork(1)
            let component = column == 0 ? point.x : column == 1 ? point.y : point.z
            let original = try ExactRationalCoefficient.originalDouble(component, usage: &usage)
            value = try value.adding(coefficients[row * 4 + column].multiplied(by: original, usage: &usage), usage: &usage)
        }
        return value
    }

    /// Appends an original operation, preserving the retained exact algebra authority.
    public func appending<B: RationalAlgebraAdmitting>(_ operation: OriginalAffineOperation,
        tolerance: ModelingTolerance, usage: inout B) throws -> Self {
        try validateOriginal(tolerance: tolerance, usage: &usage)
        let count = try rationalAlgebraCount(factors.count, 1)
        try usage.consumeExactWork(count)
        try OriginalAffineRationalMatrix.retain(count, of: OriginalAffineOperation.self, usage: &usage)
        var originalFactors = factors
        originalFactors.reserveCapacity(count)
        originalFactors.append(operation)
        if isRational {
            if let original = try OriginalAffineRationalMatrix.original(operation, usage: &usage) {
                let determinant = try OriginalAffineRationalMatrix.determinant(original, usage: &usage)
                guard !determinant.isZero else { throw rationalAlgebraFailure("Original appended affine operation is singular.") }
                let action: [ExactRationalCoefficient]
                switch operation {
                case .inverse, .rationalInverse: action = try OriginalAffineRationalMatrix.inverse(original, determinant: determinant, usage: &usage)
                default: action = original
                }
                let result = try OriginalAffineRationalMatrix.compose(action, after: coefficients, usage: &usage)
                let cofactors = try OriginalAffineRationalMatrix.cofactors(result, usage: &usage)
                let finalDeterminant = try OriginalAffineRationalMatrix.determinant(result, usage: &usage)
                return Self(originalFactors: originalFactors, coefficients: result, cofactors: cofactors,
                    determinant: finalDeterminant, maximumDepth: maximumDepth, orientationSign: orientationSign * (determinant.isNegative ? -1 : 1))
            }
            // A rational-only receipt has no retained field. The original factors
            // are admitted into one field using that same constructor depth.
            let base = try OriginalSingularFieldContext(usage: &usage)
            let frame = try Self.fieldFrame(factors: originalFactors, in: base,
                tolerance: tolerance, maximumDepth: maximumDepth, usage: &usage)
            return try appendedResult(originalFactors: originalFactors, frame: frame, usage: &usage)
        }
        guard let previous = normalizedFrame else { throw rationalAlgebraFailure("Original append lacks its retained field receipt.") }
        var action: OriginalRationalNormalizedFrame
        switch operation {
        case .forward(let value), .inverse(let value):
            action = try OriginalRationalNormalizedFrame(authored: value, in: previous.context,
                maximumDepth: maximumDepth, usage: &usage)
        case .rationalForward(let value), .rationalInverse(let value):
            try value.validateOriginalPayload(usage: &usage)
            action = try OriginalRationalNormalizedFrame(authoredCoefficients: value.coefficients, in: previous.context,
                maximumDepth: maximumDepth, usage: &usage)
        case .normalizedForward(let value), .normalizedInverse(let value):
            action = try value.prepared(in: previous.context, tolerance: tolerance,
                maximumDepth: maximumDepth, usage: &usage)
        }
        switch operation {
        case .inverse, .rationalInverse, .normalizedInverse: action = try action.inverse(maximumDepth: maximumDepth, usage: &usage)
        default: break
        }
        let frame = try previous.followed(by: action, maximumDepth: maximumDepth, usage: &usage)
        return try appendedResult(originalFactors: originalFactors, frame: frame, usage: &usage)
    }

    private func appendedResult<B: RationalAlgebraAdmitting>(originalFactors: [OriginalAffineOperation],
        frame: OriginalRationalNormalizedFrame, usage: inout B) throws -> Self {
        let cofactors = try OriginalAffineFieldAction.cofactors(frame, maximumDepth: maximumDepth, usage: &usage)
        let determinant = try OriginalAffineFieldAction.determinant(frame, cofactors: cofactors,
            maximumDepth: maximumDepth, usage: &usage)
        let sign: Int
        switch try determinant.sign(maximumDepth: maximumDepth, usage: &usage) {
        case .positive: sign = 1
        case .negative: sign = -1
        case .zero: throw rationalAlgebraFailure("Original appended action is singular.")
        }
        return Self(originalFactors: originalFactors, frame: frame, cofactors: cofactors,
            determinant: determinant, maximumDepth: maximumDepth, orientationSign: sign)
    }

    public func prepared<B: RationalAlgebraAdmitting>(usage: inout B) throws -> PreparedOriginalAffineOperationWord {
        try usage.consumeExactWork(1)
        try OriginalAffineRationalMatrix.retain(1, of: PreparedOriginalAffineOperationWord.self, usage: &usage)
        return PreparedOriginalAffineOperationWord(source: self)
    }

    init(originalFactors: [OriginalAffineOperation], coefficients: [ExactRationalCoefficient],
        cofactors: [ExactRationalCoefficient], determinant: ExactRationalCoefficient,
        maximumDepth: Int = 0, orientationSign: Int) {
        self.factors = originalFactors; self.coefficients = coefficients; self.cofactorCoefficients = cofactors
        self.determinantCoefficient = determinant; self.orientationSign = orientationSign
        self.normalizedFrame = nil; self.normalizedCofactors = []; self.normalizedDeterminant = nil; self.maximumDepth = maximumDepth
    }
    init(originalFactors: [OriginalAffineOperation], frame: OriginalRationalNormalizedFrame,
        cofactors: [OriginalSingularFieldElement], determinant: OriginalSingularFieldElement,
        maximumDepth: Int, orientationSign: Int) {
        self.factors = originalFactors; self.coefficients = []; self.cofactorCoefficients = []
        self.determinantCoefficient = .zero; self.orientationSign = orientationSign
        self.normalizedFrame = frame; self.normalizedCofactors = cofactors
        self.normalizedDeterminant = determinant; self.maximumDepth = maximumDepth
    }

    public static func == (lhs: Self, rhs: Self) -> Bool { lhs.factors == rhs.factors }
    public func hash(into hasher: inout Hasher) { hasher.combine(factors) }
}

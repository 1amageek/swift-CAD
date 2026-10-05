import CADCore

/// Proves the circular image on its original plane under one composing admission.
public struct DefaultOriginalCircularMeasurer: OriginalCircularMeasuring {
    public init() {}

    public func measure(_ curve: Curve3D, from startParameter: Double, to endParameter: Double,
        atNormalizedBoundaryParameter fraction: Double, placement: OriginalAffineOperationWord?,
        tolerance: ModelingTolerance, maximumSubdivisionDepth: Int, remainingSourceDepth: Int,
        maximumAlgebraicDepth: Int, consumeWork: @escaping @Sendable (Int) throws -> Void,
        consumeStorage: (@Sendable (Int) throws -> Void)?) throws -> OriginalCircularMeasurement {
        guard startParameter.isFinite, endParameter.isFinite, startParameter != endParameter,
            fraction.isFinite, fraction >= 0, fraction <= 1, remainingSourceDepth > 0 else {
            throw GeometryConversionError.invalidInput("Normalized original circular selection has no finite directed native interval.")
        }
        var usage = OriginalGeometryValidationAdmission(consumeWork: consumeWork,
            consumeStorage: consumeStorage, maximumAlgebraicDepth: maximumAlgebraicDepth)
        // Zero turns are the exact identity; this construction asserts no source curve period.
        let zero = try OriginalParameterPeriodicTranslation(originalSourcePeriod: 1,
            originalTurnCount: 0, parameterGain: .binary(1))
        let gain = try OriginalParameterGain.originalDifference(originalLower: startParameter,
            originalUpper: endParameter, periodicTranslation: zero, usage: &usage)
        try consumeStorage?(MemoryLayout<ParameterImageCurve3D>.stride); try consumeWork(0)
        let selection = Curve3D.parameterImage(ParameterImageCurve3D(validatedSource: curve,
            parameterGain: gain, offset: startParameter))
        return try measure(selection, at: fraction, placement: placement, tolerance: tolerance,
            maximumSubdivisionDepth: maximumSubdivisionDepth, remainingSourceDepth: remainingSourceDepth,
            maximumAlgebraicDepth: maximumAlgebraicDepth, consumeWork: consumeWork, consumeStorage: consumeStorage)
    }

    public func measure(_ curve: Curve3D, at boundaryParameter: Double,
        placement: OriginalAffineOperationWord?, tolerance: ModelingTolerance,
        maximumSubdivisionDepth: Int, remainingSourceDepth: Int, maximumAlgebraicDepth: Int,
        consumeWork: @escaping @Sendable (Int) throws -> Void,
        consumeStorage: (@Sendable (Int) throws -> Void)?) throws -> OriginalCircularMeasurement {
        try tolerance.validate(); try consumeWork(0)
        guard boundaryParameter.isFinite, (0...32).contains(maximumSubdivisionDepth),
              remainingSourceDepth >= 0, (0...32).contains(maximumAlgebraicDepth) else {
            throw GeometryConversionError.invalidInput("Circular measurement requires explicit independent caller capabilities.")
        }
        var admission = OriginalGeometryValidationAdmission(consumeWork: consumeWork,
            consumeStorage: consumeStorage, maximumAlgebraicDepth: maximumAlgebraicDepth)
        var current = curve; var depth = remainingSourceDepth
        var groups: [[OriginalAffineOperation]] = []
        var groupCapacity = 0
        func retain<T>(_ count: Int, _ type: T.Type) throws {
            let bytes = count.multipliedReportingOverflow(by: MemoryLayout<T>.stride)
            guard count >= 0, !bytes.overflow else {
                throw GeometryConversionError.resourceLimitExceeded("Circular source retention overflows.")
            }
            try consumeStorage?(bytes.partialValue); try consumeWork(0)
        }
        func group(_ values: [OriginalAffineOperation]) throws {
            if groups.count == groupCapacity {
                let next = groupCapacity == 0 ? 1 : groupCapacity.multipliedReportingOverflow(by: 2).partialValue
                guard next > groupCapacity else {
                    throw GeometryConversionError.resourceLimitExceeded("Circular source group capacity overflows.")
                }
                try retain(next, [OriginalAffineOperation].self)
                groups.reserveCapacity(next); groupCapacity = next
            }
            groups.append(values)
        }
        func descend() throws {
            guard depth > 0 else {
                throw GeometryConversionError.resourceLimitExceeded("Circular original source depth is exhausted.")
            }
            depth -= 1; try consumeWork(0)
        }
        let center: Point3D, normal: Vector3D, radius: Double
        extraction: while true {
            try consumeWork(0)
            switch current {
            case .circle(let circle):
                center = circle.center; normal = circle.normal; radius = circle.radius
                break extraction
            case .analytic(.circle(let c, let n, let r)), .analytic(.arc(let c, let n, let r, _, _)):
                center = c; normal = n; radius = r
                break extraction
            case .parameterImage(let image):
                try descend(); current = image.source
            case .rigidImage(let image):
                try descend(); try image.transform.validate(tolerance: tolerance)
                let raw = try AffineTransform3D(basisX: image.transform.basisX, basisY: image.transform.basisY,
                    basisZ: image.transform.basisZ, translation: image.transform.translation)
                try retain(1, OriginalAffineOperation.self); try group([.forward(raw)])
                current = image.source
            case .affineImage(let image):
                try descend(); try image.transform.validate()
                try retain(1, OriginalAffineOperation.self); try group([.forward(image.transform)])
                current = image.source
            case .originalAffineWord(let image):
                try descend(); try image.operationWord.validateOriginal(tolerance: tolerance,
                    maximumDepth: maximumAlgebraicDepth, usage: &admission)
                try group(image.operationWord.factors); current = image.source
            default:
                throw GeometryConversionError.invalidInput("Original radial measurement requires an actual circle or arc law.")
            }
        }
        try center.validate(); try normal.validate()
        guard radius.isFinite, radius > 0, max(abs(normal.x), abs(normal.y), abs(normal.z)) > 0 else {
            throw GeometryConversionError.invalidInput("Original circular radius or normal is invalid.")
        }
        var factorCount = placement?.factors.count ?? 0
        for value in groups {
            let sum = factorCount.addingReportingOverflow(value.count)
            guard !sum.overflow else { throw GeometryConversionError.resourceLimitExceeded("Circular original factor count overflows.") }
            factorCount = sum.partialValue; try consumeWork(0)
        }
        try retain(max(1, factorCount), OriginalAffineOperation.self)
        var factors: [OriginalAffineOperation] = []; factors.reserveCapacity(max(1, factorCount))
        for value in groups.reversed() {
            for factor in value { try consumeWork(0); factors.append(factor) }
        }
        if let placement {
            try placement.validateOriginal(tolerance: tolerance, maximumDepth: maximumAlgebraicDepth, usage: &admission)
            for factor in placement.factors { try consumeWork(0); factors.append(factor) }
        }
        if factors.isEmpty {
            factors.append(.forward(try AffineTransform3D(basisX: .unitX, basisY: .unitY, basisZ: .unitZ, translation: .zero)))
        }
        let word = try OriginalAffineOperationWord(factors: factors, tolerance: tolerance,
            maximumDepth: maximumAlgebraicDepth, usage: &admission)
        let prepared = try word.prepared(usage: &admission)
        let frame: OriginalRationalNormalizedFrame
        if let retained = try prepared.originalNormalizedFrame(usage: &admission) { frame = retained.frame }
        else {
            let context = try OriginalSingularFieldContext(usage: &admission)
            frame = try .init(authoredCoefficients: prepared.exactRationalCoefficients(usage: &admission),
                in: context, maximumDepth: maximumAlgebraicDepth, usage: &admission)
        }
        // Each raw plane vector uses only signed original components, never a rounded cross product.
        let first: Vector3D, second: Vector3D
        if abs(normal.x) >= max(abs(normal.y), abs(normal.z)) {
            first = .init(x: -normal.z, y: 0, z: normal.x)
            second = .init(x: normal.y, y: -normal.x, z: 0)
        } else if abs(normal.y) >= abs(normal.z) {
            first = .init(x: normal.y, y: -normal.x, z: 0)
            second = .init(x: 0, y: normal.z, z: -normal.y)
        } else {
            first = .init(x: 0, y: normal.z, z: -normal.y)
            second = .init(x: -normal.z, y: 0, z: normal.x)
        }
        let a = try frame.applying(to: first, asPoint: false, maximumDepth: maximumAlgebraicDepth, usage: &admission)
        let b = try frame.applying(to: second, asPoint: false, maximumDepth: maximumAlgebraicDepth, usage: &admission)
        func originalDot(_ first: Vector3D, _ second: Vector3D) throws -> ExactRationalCoefficient {
            var sum = ExactRationalCoefficient.zero
            for index in 0..<3 {
                let x = index == 0 ? first.x : index == 1 ? first.y : first.z
                let y = index == 0 ? second.x : index == 1 ? second.y : second.z
                sum = try sum.adding(ExactRationalCoefficient.originalDouble(x, usage: &admission)
                    .multiplied(by: .originalDouble(y, usage: &admission), usage: &admission), usage: &admission)
            }
            return sum
        }
        func fieldDot(_ first: [OriginalSingularFieldElement], _ second: [OriginalSingularFieldElement]) throws -> OriginalSingularFieldElement {
            var sum = try OriginalSingularFieldElement.constant(.zero, in: frame.context,
                maximumDepth: maximumAlgebraicDepth, usage: &admission)
            for index in 0..<3 {
                sum = try sum.adding(first[index].multiplied(by: second[index],
                    maximumDepth: maximumAlgebraicDepth, usage: &admission),
                    maximumDepth: maximumAlgebraicDepth, usage: &admission)
            }
            return sum
        }
        func constant(_ value: ExactRationalCoefficient) throws -> OriginalSingularFieldElement {
            try .constant(value, in: frame.context, maximumDepth: maximumAlgebraicDepth, usage: &admission)
        }
        let originalAA = try originalDot(first, first)
        let originalBB = try originalDot(second, second)
        let originalAB = try originalDot(first, second)
        let imageAA = try fieldDot(a, a), imageBB = try fieldDot(b, b), imageAB = try fieldDot(a, b)
        guard originalAA.isPositive, originalBB.isPositive else {
            throw GeometryConversionError.invalidInput("Original circular plane has no independent finite directions.")
        }
        let scale = try imageAA.divided(by: constant(originalAA), maximumDepth: maximumAlgebraicDepth, usage: &admission)
        let differenceBB = try imageBB.subtracting(scale.multiplied(by: constant(originalBB),
            maximumDepth: maximumAlgebraicDepth, usage: &admission), maximumDepth: maximumAlgebraicDepth, usage: &admission)
        let differenceAB = try imageAB.subtracting(scale.multiplied(by: constant(originalAB),
            maximumDepth: maximumAlgebraicDepth, usage: &admission), maximumDepth: maximumAlgebraicDepth, usage: &admission)
        guard case .positive = try scale.sign(maximumDepth: maximumAlgebraicDepth, usage: &admission),
              case .zero = try differenceBB.sign(maximumDepth: maximumAlgebraicDepth, usage: &admission),
              case .zero = try differenceAB.sign(maximumDepth: maximumAlgebraicDepth, usage: &admission) else {
            throw GeometryConversionError.invalidInput("Original affine image is not circular on its source plane.")
        }
        let rawRadius = try ExactRationalCoefficient.originalDouble(radius, usage: &admission)
        let squaredRadius = try scale.multiplied(by: constant(rawRadius.multiplied(by: rawRadius, usage: &admission)),
            maximumDepth: maximumAlgebraicDepth, usage: &admission)
        let radiusUpper = try OriginalAffineFieldAction.squareRootUpper(squaredRadius,
            maximumDepth: maximumAlgebraicDepth, usage: &admission)
        let radiusLower: Double
        let upperQ = try ExactRationalCoefficient.originalDouble(radiusUpper, usage: &admission)
        if case .zero = try OriginalAffineFieldAction.compare(squaredRadius,
            with: upperQ.multiplied(by: upperQ, usage: &admission), maximumDepth: maximumAlgebraicDepth, usage: &admission) {
            radiusLower = radiusUpper
        } else { radiusLower = radiusUpper.nextDown }
        let threshold = try ExactRationalCoefficient.originalDouble(tolerance.distance, usage: &admission)
        guard case .positive = try OriginalAffineFieldAction.compare(squaredRadius,
            with: threshold.multiplied(by: threshold, usage: &admission),
            maximumDepth: maximumAlgebraicDepth, usage: &admission) else {
            throw GeometryConversionError.invalidInput("Original circular image has no positive physical radius margin.")
        }
        let originalCenter = try frame.applying(to: Vector3D(x: center.x, y: center.y, z: center.z),
            asPoint: true, maximumDepth: maximumAlgebraicDepth, usage: &admission)
        func scalar(_ value: OriginalSingularFieldElement) throws -> ScalarInterval {
            let bounds = try OriginalAffineFieldAction.enclosure(value, maximumDepth: maximumAlgebraicDepth, usage: &admission)
            guard bounds.isFinite else { throw GeometryConversionError.invalidInput("Original circular measurement exceeds finite range.") }
            return try .init(lower: bounds.lower, upper: bounds.upper)
        }
        let centerBox = try CoordinateEnclosure3D(x: scalar(originalCenter[0]), y: scalar(originalCenter[1]), z: scalar(originalCenter[2]))
        let inverse = try frame.inverse(maximumDepth: maximumAlgebraicDepth, usage: &admission)
        func normalComponent(_ basis: [OriginalSingularFieldElement]) throws -> OriginalSingularFieldElement {
            var sum = try constant(.zero)
            for index in 0..<3 {
                let raw = index == 0 ? normal.x : index == 1 ? normal.y : normal.z
                sum = try sum.adding(basis[index].multiplied(by: constant(.originalDouble(raw, usage: &admission)),
                    maximumDepth: maximumAlgebraicDepth, usage: &admission), maximumDepth: maximumAlgebraicDepth, usage: &admission)
            }
            return sum
        }
        try retain(3, OriginalSingularFieldElement.self)
        let n = try [normalComponent(inverse.basisX), normalComponent(inverse.basisY), normalComponent(inverse.basisZ)]
        let square = try fieldDot(n, n)
        let norm = try square.nonnegativeSquareRoot(inheritedDepth: square.context.coefficientDepth,
            maximumDepth: maximumAlgebraicDepth, admissionDomain: .coefficient(maximumDepth: maximumAlgebraicDepth), usage: &admission)
        func unit(_ value: OriginalSingularFieldElement) throws -> ScalarInterval {
            let embedded = try value.embedded(in: norm.context, maximumDepth: maximumAlgebraicDepth, usage: &admission)
            var unit = try embedded.divided(by: norm, maximumDepth: maximumAlgebraicDepth, usage: &admission)
            if word.orientationSign < 0 { unit = try unit.negated(maximumDepth: maximumAlgebraicDepth, usage: &admission) }
            return try scalar(unit)
        }
        let normalBox = try CoordinateEnclosure3D(x: unit(n[0]), y: unit(n[1]), z: unit(n[2]))
        let worldCurve: Curve3D
        if let placement {
            worldCurve = .originalAffineWord(try OriginalAffineWordCurve3D(source: curve, operationWord: placement,
                tolerance: tolerance, remainingSourceDepth: remainingSourceDepth,
                maximumSubdivisionDepth: maximumSubdivisionDepth, maximumAlgebraicDepth: maximumAlgebraicDepth, usage: &admission))
        } else { worldCurve = curve }
        let owner = try PreparedCurveDifferentialEncloser(curve: worldCurve, tolerance: tolerance,
            remainingSourceDepth: remainingSourceDepth, maximumSubdivisionDepth: maximumSubdivisionDepth,
            consumeWork: { try consumeWork(0) }, consumeStorage: consumeStorage, maximumAlgebraicDepth: maximumAlgebraicDepth)
        let station = try ScalarInterval(lower: boundaryParameter, upper: boundaryParameter)
        let jets = try owner.closedNativeJets(over: station, tolerance: tolerance, maximumSpanCount: 1,
            maximumSubdivisionDepth: maximumSubdivisionDepth, remainingSourceDepth: remainingSourceDepth,
            consumeWork: { try consumeWork(0) }, consumeStorage: consumeStorage)
        guard let jet = jets.spans.first?.jet else { throw GeometryConversionError.invalidInput("Original circular boundary station is absent.") }
        func position(_ value: OutwardScalarInterval) throws -> ScalarInterval {
            guard value.isFinite else { throw GeometryConversionError.invalidInput("Original circular boundary is nonfinite.") }
            return try .init(lower: value.lower, upper: value.upper)
        }
        let boundary = try CoordinateEnclosure3D(x: position(jet.x.value), y: position(jet.y.value), z: position(jet.z.value))
        try retain(1, OriginalCircularMeasurement.self)
        return OriginalCircularMeasurement(source: curve, boundaryParameter: boundaryParameter, placement: placement,
            effectiveOperationWord: word, centerEnclosure: centerBox,
            radiusEnclosure: try .init(lower: radiusLower, upper: radiusUpper), normalEnclosure: normalBox,
            boundaryPointEnclosure: boundary, tolerance: tolerance)
    }
}

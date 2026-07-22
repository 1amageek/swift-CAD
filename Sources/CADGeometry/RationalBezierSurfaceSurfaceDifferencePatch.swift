import CADCore

struct RationalBezierSurfaceSurfaceDifferencePatch: Sendable {
    enum JacobianRankCertificate: Equatable, Sendable {
        case regular(freeParameterIndex: Int)
        case unresolved
    }

    enum GaugeRootCertificate: Equatable, Sendable {
        case fullGraph(freeParameterIndex: Int)
        case uniqueMidpointRoot(freeParameterIndex: Int)
        case cellEmpty(freeParameterIndex: Int)
        case midpointSliceEmpty(freeParameterIndex: Int)
        case unresolved(freeParameterIndex: Int)
        case rankUnresolved
    }

    enum BoundarySide: CaseIterable, Equatable, Sendable {
        case lower
        case upper
    }

    enum BoundaryRootCertificate: Equatable, Sendable {
        case empty
        case unique
        case unresolved
    }

    private enum SplitDirection {
        case firstU
        case firstV
        case secondU
        case secondV
    }

    private struct OutwardInterval: Sendable {
        let lower: Double
        let upper: Double

        init(_ value: Double) {
            lower = value.nextDown
            upper = value.nextUp
        }

        private init(lower: Double, upper: Double) {
            self.lower = lower
            self.upper = upper
        }

        static func + (
            lhs: OutwardInterval,
            rhs: OutwardInterval
        ) -> OutwardInterval {
            OutwardInterval(
                lower: (lhs.lower + rhs.lower).nextDown,
                upper: (lhs.upper + rhs.upper).nextUp
            )
        }

        static func - (
            lhs: OutwardInterval,
            rhs: OutwardInterval
        ) -> OutwardInterval {
            OutwardInterval(
                lower: (lhs.lower - rhs.upper).nextDown,
                upper: (lhs.upper - rhs.lower).nextUp
            )
        }

        static func * (
            lhs: OutwardInterval,
            rhs: OutwardInterval
        ) -> OutwardInterval {
            let products = [
                lhs.lower * rhs.lower,
                lhs.lower * rhs.upper,
                lhs.upper * rhs.lower,
                lhs.upper * rhs.upper,
            ]
            return OutwardInterval(
                lower: (products.min() ?? -.infinity).nextDown,
                upper: (products.max() ?? .infinity).nextUp
            )
        }

        func divided(by divisor: OutwardInterval) -> OutwardInterval? {
            guard divisor.excludesZero else {
                return nil
            }
            let reciprocal = OutwardInterval(
                lower: (1.0 / divisor.upper).nextDown,
                upper: (1.0 / divisor.lower).nextUp
            )
            return self * reciprocal
        }

        func midpoint(with other: OutwardInterval) -> OutwardInterval {
            let half = OutwardInterval(0.5)
            return self * half + other * half
        }

        var isFinite: Bool {
            lower.isFinite && upper.isFinite
        }

        var excludesZero: Bool {
            lower > 0.0 || upper < 0.0
        }

        var zeroSeparation: Double {
            if lower > 0.0 { return lower }
            if upper < 0.0 { return -upper }
            return 0.0
        }

        static func enclosing(_ values: [OutwardInterval]) -> OutwardInterval {
            guard let lower = values.map(\.lower).min(),
                  let upper = values.map(\.upper).max() else {
                return OutwardInterval(0.0)
            }
            return OutwardInterval(lower: lower, upper: upper)
        }

        static func enclosing(_ lower: Double, _ upper: Double) -> OutwardInterval {
            OutwardInterval(lower: lower.nextDown, upper: upper.nextUp)
        }

        var midpoint: Double {
            lower + (upper - lower) * 0.5
        }

        var width: Double {
            upper - lower
        }
    }

    private struct IntervalVector: Sendable {
        let x: OutwardInterval
        let y: OutwardInterval
        let z: OutwardInterval

        func midpoint(with other: IntervalVector) -> IntervalVector {
            IntervalVector(
                x: x.midpoint(with: other.x),
                y: y.midpoint(with: other.y),
                z: z.midpoint(with: other.z)
            )
        }

        var isFinite: Bool {
            x.isFinite && y.isFinite && z.isFinite
        }

        var widthMeasure: Double {
            x.width + y.width + z.width
        }

        static func - (
            lhs: IntervalVector,
            rhs: IntervalVector
        ) -> IntervalVector {
            IntervalVector(
                x: lhs.x - rhs.x,
                y: lhs.y - rhs.y,
                z: lhs.z - rhs.z
            )
        }

        static func + (
            lhs: IntervalVector,
            rhs: IntervalVector
        ) -> IntervalVector {
            IntervalVector(
                x: lhs.x + rhs.x,
                y: lhs.y + rhs.y,
                z: lhs.z + rhs.z
            )
        }

        func scaled(by value: Double) -> IntervalVector {
            let scale = OutwardInterval(value)
            return IntervalVector(
                x: x * scale,
                y: y * scale,
                z: z * scale
            )
        }

        static func enclosing(_ values: [IntervalVector]) -> IntervalVector {
            IntervalVector(
                x: OutwardInterval.enclosing(values.map(\.x)),
                y: OutwardInterval.enclosing(values.map(\.y)),
                z: OutwardInterval.enclosing(values.map(\.z))
            )
        }
    }

    private let controlNet: [[[[IntervalVector]]]]
    private let denominatorUpperBound: Double
    let firstULower: Double
    let firstUUpper: Double
    let firstVLower: Double
    let firstVUpper: Double
    let secondULower: Double
    let secondUUpper: Double
    let secondVLower: Double
    let secondVUpper: Double

    init(
        first: RationalBezierSurfacePatch3D,
        second: RationalBezierSurfacePatch3D,
        tolerance: ModelingTolerance
    ) throws {
        try Self.validate(patch: first, tolerance: tolerance)
        try Self.validate(patch: second, tolerance: tolerance)
        let result = first.controlPoints.indices.map { firstVIndex in
            first.controlPoints[firstVIndex].indices.map { firstUIndex in
                second.controlPoints.indices.map { secondVIndex in
                    second.controlPoints[secondVIndex].indices.map { secondUIndex in
                        Self.differenceCoefficient(
                            firstPoint: first.controlPoints[firstVIndex][firstUIndex],
                            firstWeight: first.weights[firstVIndex][firstUIndex],
                            secondPoint: second.controlPoints[secondVIndex][secondUIndex],
                            secondWeight: second.weights[secondVIndex][secondUIndex]
                        )
                    }
                }
            }
        }
        guard result.flatMap({ $0 }).flatMap({ $0 }).flatMap({ $0 })
            .allSatisfy(\.isFinite) else {
            throw KernelError(
                phase: .geometry,
                code: .resourceLimitExceeded,
                tolerance: tolerance,
                message: "Rational Bezier surface difference exceeded finite interval arithmetic."
            )
        }
        controlNet = result
        let firstWeightUpperBound = first.weights.flatMap { $0 }.max() ?? .infinity
        let secondWeightUpperBound = second.weights.flatMap { $0 }.max() ?? .infinity
        let denominator = (
            firstWeightUpperBound.nextUp * secondWeightUpperBound.nextUp
        ).nextUp
        guard denominator.isFinite, denominator > 0.0 else {
            throw KernelError(
                phase: .geometry,
                code: .resourceLimitExceeded,
                tolerance: tolerance,
                message: "Rational Bezier surface difference denominator bound is not finite."
            )
        }
        denominatorUpperBound = denominator
        firstULower = first.uLower
        firstUUpper = first.uUpper
        firstVLower = first.vLower
        firstVUpper = first.vUpper
        secondULower = second.uLower
        secondUUpper = second.uUpper
        secondVLower = second.vLower
        secondVUpper = second.vUpper
    }

    private init(
        controlNet: [[[[IntervalVector]]]],
        denominatorUpperBound: Double,
        firstUBounds: (Double, Double),
        firstVBounds: (Double, Double),
        secondUBounds: (Double, Double),
        secondVBounds: (Double, Double)
    ) {
        self.controlNet = controlNet
        self.denominatorUpperBound = denominatorUpperBound
        firstULower = firstUBounds.0
        firstUUpper = firstUBounds.1
        firstVLower = firstVBounds.0
        firstVUpper = firstVBounds.1
        secondULower = secondUBounds.0
        secondUUpper = secondUBounds.1
        secondVLower = secondVBounds.0
        secondVUpper = secondVBounds.1
    }

    func excludesZero() -> Bool {
        excludesZero { $0.x }
            || excludesZero { $0.y }
            || excludesZero { $0.z }
    }

    func excludesZero(tolerance: ModelingTolerance) -> Bool {
        let scaledTolerance = (
            tolerance.distance.nextUp * denominatorUpperBound.nextUp
        ).nextUp
        guard excludesBand(radius: scaledTolerance) == false else { return true }
        let coefficientBoxes = controlNet
            .flatMap { $0 }
            .flatMap { $0 }
            .flatMap { $0 }
        let corners = coefficientBoxes.flatMap { coefficient in
            [coefficient.x.lower, coefficient.x.upper].flatMap { x in
                [coefficient.y.lower, coefficient.y.upper].flatMap { y in
                    [coefficient.z.lower, coefficient.z.upper].map { z in
                        Point3D(x: x, y: y, z: z)
                    }
                }
            }
        }
        return ConvexHullSeparation3D.provesSeparated(
            first: corners,
            second: [.origin],
            tolerance: scaledTolerance
        )
    }

    func rankThreeCertificate() -> JacobianRankCertificate {
        rankThreeCertificate(columns: derivativeColumns())
    }

    func gaugeRootCertificate() -> GaugeRootCertificate {
        let allColumns = derivativeColumns()
        guard case let .regular(freeParameterIndex) = rankThreeCertificate(
            columns: allColumns
        ) else {
            return .rankUnresolved
        }
        return gaugeRootCertificate(
            freeParameterIndex: freeParameterIndex,
            columns: allColumns
        )
    }

    func gaugeRootCertificate(
        freeParameterIndex: Int
    ) -> GaugeRootCertificate {
        let allColumns = derivativeColumns()
        guard allColumns.indices.contains(freeParameterIndex),
              allColumns.allSatisfy(\.isFinite) else {
            return .rankUnresolved
        }
        return gaugeRootCertificate(
            freeParameterIndex: freeParameterIndex,
            columns: allColumns
        )
    }

    func affinePredictorGaugeRootCertificate(
        freeParameterIndex: Int,
        lowerAnchor: [Double],
        upperAnchor: [Double]
    ) -> GaugeRootCertificate {
        let allColumns = derivativeColumns()
        guard allColumns.indices.contains(freeParameterIndex),
              allColumns.allSatisfy(\.isFinite),
              lowerAnchor.count == allColumns.count,
              upperAnchor.count == allColumns.count,
              lowerAnchor.allSatisfy({ $0.isFinite && $0 >= 0.0 && $0 <= 1.0 }),
              upperAnchor.allSatisfy({ $0.isFinite && $0 >= 0.0 && $0 <= 1.0 }) else {
            return .rankUnresolved
        }
        let dependentIndexes = allColumns.indices.filter {
            $0 != freeParameterIndex
        }
        let dependentColumns = dependentIndexes.map { allColumns[$0] }
        let dependentMinor = determinant(
            dependentColumns[0],
            dependentColumns[1],
            dependentColumns[2]
        )
        guard dependentMinor.isFinite, dependentMinor.excludesZero else {
            return .rankUnresolved
        }
        let midpointColumns = dependentColumns.map {
            Vector3D(x: $0.x.midpoint, y: $0.y.midpoint, z: $0.z.midpoint)
        }
        guard let inverse = inverseRows(columns: midpointColumns),
              let functionValue = affinePredictorValueBounds(
                  freeParameterIndex: freeParameterIndex,
                  lowerAnchor: lowerAnchor,
                  upperAnchor: upperAnchor
              ) else {
            return .unresolved(freeParameterIndex: freeParameterIndex)
        }
        let jacobian = [
            dependentColumns.map(\.x),
            dependentColumns.map(\.y),
            dependentColumns.map(\.z),
        ]
        let centerBounds = dependentIndexes.map { index in
            OutwardInterval.enclosing(
                min(lowerAnchor[index], upperAnchor[index]),
                max(lowerAnchor[index], upperAnchor[index])
            )
        }
        if affinePredictorProvesFullGraph(
            inverse: inverse,
            jacobian: jacobian,
            functionValue: functionValue,
            centerBounds: centerBounds
        ) {
            return .fullGraph(freeParameterIndex: freeParameterIndex)
        }
        let box = affinePredictorKrawczykBox(
            inverse: inverse,
            jacobian: jacobian,
            functionValue: functionValue,
            centerBounds: centerBounds
        )
        if isDisjointFromUnitCube(box) {
            return .cellEmpty(freeParameterIndex: freeParameterIndex)
        }
        if isStrictlyInsideUnitCube(box) {
            return .fullGraph(freeParameterIndex: freeParameterIndex)
        }
        return .unresolved(freeParameterIndex: freeParameterIndex)
    }

    func affinePredictorProofDiagnostic(
        freeParameterIndex: Int,
        lowerAnchor: [Double],
        upperAnchor: [Double]
    ) -> String {
        let allColumns = derivativeColumns()
        guard allColumns.indices.contains(freeParameterIndex) else {
            return "invalid free parameter"
        }
        let dependentIndexes = allColumns.indices.filter {
            $0 != freeParameterIndex
        }
        let dependentColumns = dependentIndexes.map { allColumns[$0] }
        let midpointColumns = dependentColumns.map {
            Vector3D(x: $0.x.midpoint, y: $0.y.midpoint, z: $0.z.midpoint)
        }
        guard let inverse = inverseRows(columns: midpointColumns),
              let functionValue = affinePredictorValueBounds(
                  freeParameterIndex: freeParameterIndex,
                  lowerAnchor: lowerAnchor,
                  upperAnchor: upperAnchor
              ) else {
            return "predictor evaluation unavailable"
        }
        let jacobian = [
            dependentColumns.map(\.x),
            dependentColumns.map(\.y),
            dependentColumns.map(\.z),
        ]
        let functionComponents = [functionValue.x, functionValue.y, functionValue.z]
        var corrections = Array(repeating: 0.0, count: 3)
        var rowSums = Array(repeating: 0.0, count: 3)
        for row in 0..<3 {
            var correction = OutwardInterval(0.0)
            for inner in 0..<3 {
                correction = correction
                    + OutwardInterval(vectorComponent(inverse[row], index: inner))
                        * functionComponents[inner]
            }
            corrections[row] = magnitudeUpperBound(correction)
            for column in 0..<3 {
                var preconditioned = OutwardInterval(0.0)
                for inner in 0..<3 {
                    preconditioned = preconditioned
                        + OutwardInterval(vectorComponent(inverse[row], index: inner))
                            * jacobian[inner][column]
                }
                let identity = OutwardInterval(row == column ? 1.0 : 0.0)
                rowSums[row] = (
                    rowSums[row] + magnitudeUpperBound(identity - preconditioned)
                ).nextUp
            }
        }
        let available = dependentIndexes.map { index in
            let lower = min(lowerAnchor[index], upperAnchor[index])
            let upper = max(lowerAnchor[index], upperAnchor[index])
            return min(lower, 1.0 - upper)
        }
        return "correction=\(corrections), rowSums=\(rowSums), available=\(available)"
    }

    private func affinePredictorProvesFullGraph(
        inverse: [Vector3D],
        jacobian: [[OutwardInterval]],
        functionValue: IntervalVector,
        centerBounds: [OutwardInterval]
    ) -> Bool {
        let functionComponents = [functionValue.x, functionValue.y, functionValue.z]
        var corrections = Array(repeating: 0.0, count: 3)
        var contraction = Array(
            repeating: Array(repeating: 0.0, count: 3),
            count: 3
        )
        for row in 0..<3 {
            var correction = OutwardInterval(0.0)
            for inner in 0..<3 {
                correction = correction
                    + OutwardInterval(vectorComponent(inverse[row], index: inner))
                        * functionComponents[inner]
            }
            corrections[row] = magnitudeUpperBound(correction)
            for column in 0..<3 {
                var preconditioned = OutwardInterval(0.0)
                for inner in 0..<3 {
                    preconditioned = preconditioned
                        + OutwardInterval(vectorComponent(inverse[row], index: inner))
                            * jacobian[inner][column]
                }
                let identity = OutwardInterval(row == column ? 1.0 : 0.0)
                contraction[row][column] = magnitudeUpperBound(
                    identity - preconditioned
                )
            }
        }
        let availableRadii = centerBounds.map {
            min($0.lower, 1.0 - $0.upper)
        }
        guard corrections.allSatisfy({ $0.isFinite && $0 >= 0.0 }),
              contraction.flatMap({ $0 }).allSatisfy({ $0.isFinite && $0 >= 0.0 }),
              availableRadii.allSatisfy({ $0.isFinite && $0 > 0.0 }) else {
            return false
        }
        var radii = corrections.map {
            max($0, Double.leastNonzeroMagnitude)
        }
        for _ in 0..<128 {
            let mapped = (0..<3).map { row in
                contraction[row].indices.reduce(corrections[row]) {
                    partial, column in
                    (partial + contraction[row][column] * radii[column]).nextUp
                }
            }
            guard zip(mapped, availableRadii).allSatisfy({ value, available in
                value.isFinite && value < available
            }) else {
                return false
            }
            let trial = mapped.map {
                ($0 * (1.0 + 1.0e-10)).nextUp
                    + Double.ulpOfOne * 1_024.0
            }
            let remapped = (0..<3).map { row in
                contraction[row].indices.reduce(corrections[row]) {
                    partial, column in
                    (partial + contraction[row][column] * trial[column]).nextUp
                }
            }
            if zip(remapped, trial).allSatisfy({ value, bound in value < bound }),
               zip(trial, availableRadii).allSatisfy({ value, bound in value < bound }) {
                return true
            }
            radii = mapped
        }
        return false
    }

    private func magnitudeUpperBound(_ interval: OutwardInterval) -> Double {
        max(abs(interval.lower), abs(interval.upper)).nextUp
    }

    func parameterizedKrawczykContraction(
        freeParameterIndex: Int
    ) -> [(lower: Double, upper: Double)]? {
        let allColumns = derivativeColumns()
        guard allColumns.indices.contains(freeParameterIndex),
              allColumns.allSatisfy(\.isFinite) else {
            return nil
        }
        let dependentIndexes = allColumns.indices.filter {
            $0 != freeParameterIndex
        }
        let dependentColumns = dependentIndexes.map { allColumns[$0] }
        let dependentMinor = determinant(
            dependentColumns[0],
            dependentColumns[1],
            dependentColumns[2]
        )
        guard dependentMinor.isFinite, dependentMinor.excludesZero else {
            return nil
        }
        let midpointColumns = dependentColumns.map {
            Vector3D(x: $0.x.midpoint, y: $0.y.midpoint, z: $0.z.midpoint)
        }
        guard let inverse = inverseRows(columns: midpointColumns) else {
            return nil
        }
        let jacobian = [
            dependentColumns.map(\.x),
            dependentColumns.map(\.y),
            dependentColumns.map(\.z),
        ]
        let box = krawczykBox(
            inverse: inverse,
            jacobian: jacobian,
            functionValue: parameterizedCenterValueBounds(
                freeParameterIndex: freeParameterIndex
            )
        )
        guard isDisjointFromUnitCube(box) == false else { return nil }
        var result = Array(repeating: (lower: 0.0, upper: 1.0), count: 4)
        for index in dependentIndexes.indices {
            let lower = max(0.0, box[index].lower)
            let upper = min(1.0, box[index].upper)
            guard lower.isFinite, upper.isFinite, lower <= upper else {
                return nil
            }
            result[dependentIndexes[index]] = (lower, upper)
        }
        return result
    }

    private func gaugeRootCertificate(
        freeParameterIndex: Int,
        columns allColumns: [IntervalVector]
    ) -> GaugeRootCertificate {
        let dependentColumns = allColumns.indices
            .filter { $0 != freeParameterIndex }
            .map { allColumns[$0] }
        let dependentMinor = determinant(
            dependentColumns[0],
            dependentColumns[1],
            dependentColumns[2]
        )
        guard dependentMinor.isFinite, dependentMinor.excludesZero else {
            return .rankUnresolved
        }
        let midpointColumns = dependentColumns.map {
            Vector3D(x: $0.x.midpoint, y: $0.y.midpoint, z: $0.z.midpoint)
        }
        guard let inverse = inverseRows(columns: midpointColumns) else {
            return .unresolved(freeParameterIndex: freeParameterIndex)
        }
        let jacobian = [
            dependentColumns.map(\.x),
            dependentColumns.map(\.y),
            dependentColumns.map(\.z),
        ]
        let parameterizedBox = krawczykBox(
            inverse: inverse,
            jacobian: jacobian,
            functionValue: parameterizedCenterValueBounds(
                freeParameterIndex: freeParameterIndex
            )
        )
        if isDisjointFromUnitCube(parameterizedBox) {
            return .cellEmpty(freeParameterIndex: freeParameterIndex)
        }
        if isStrictlyInsideUnitCube(parameterizedBox) {
            return .fullGraph(freeParameterIndex: freeParameterIndex)
        }

        let midpointBox = krawczykBox(
            inverse: inverse,
            jacobian: jacobian,
            functionValue: centerValue()
        )
        if isDisjointFromUnitCube(midpointBox) {
            return .midpointSliceEmpty(freeParameterIndex: freeParameterIndex)
        }
        if isStrictlyInsideUnitCube(midpointBox) {
            return .uniqueMidpointRoot(freeParameterIndex: freeParameterIndex)
        }
        return .unresolved(freeParameterIndex: freeParameterIndex)
    }

    func boundaryRootCertificate(
        fixedParameterIndex: Int,
        side: BoundarySide,
        tolerance: ModelingTolerance
    ) -> BoundaryRootCertificate {
        guard parameterCounts.indices.contains(fixedParameterIndex) else {
            return .unresolved
        }
        let coefficients = boundaryCoefficients(
            fixedParameterIndex: fixedParameterIndex,
            side: side
        )
        let scaledTolerance = (
            tolerance.distance.nextUp * denominatorUpperBound.nextUp
        ).nextUp
        if coefficientsExcludeZero(
            coefficients,
            tolerance: scaledTolerance
        ) {
            return .empty
        }

        let dependentParameterIndices = parameterCounts.indices.filter {
            $0 != fixedParameterIndex
        }
        let dependentColumns = dependentParameterIndices.map {
            boundaryDerivativeBounds(
                parameterIndex: $0,
                fixedParameterIndex: fixedParameterIndex,
                side: side
            )
        }
        guard dependentColumns.allSatisfy(\.isFinite),
              determinant(
                  dependentColumns[0],
                  dependentColumns[1],
                  dependentColumns[2]
              ).excludesZero else {
            return .unresolved
        }
        let midpointColumns = dependentColumns.map {
            Vector3D(x: $0.x.midpoint, y: $0.y.midpoint, z: $0.z.midpoint)
        }
        guard let inverse = inverseRows(columns: midpointColumns) else {
            return .unresolved
        }
        let jacobian = [
            dependentColumns.map(\.x),
            dependentColumns.map(\.y),
            dependentColumns.map(\.z),
        ]
        let fixedValue = side == .lower ? 0.0 : 1.0
        var center = Array(repeating: 0.5, count: 4)
        center[fixedParameterIndex] = fixedValue
        let box = krawczykBox(
            inverse: inverse,
            jacobian: jacobian,
            functionValue: evaluated(at: center)
        )
        if isDisjointFromUnitCube(box) {
            return .empty
        }
        if isStrictlyInsideUnitCube(box) {
            return .unique
        }
        return .unresolved
    }

    func preferredBoundarySubdivisionParameter(
        fixedParameterIndex: Int,
        side: BoundarySide
    ) -> Int? {
        guard parameterCounts.indices.contains(fixedParameterIndex) else {
            return nil
        }
        let dependentParameterIndices = parameterCounts.indices.filter {
            $0 != fixedParameterIndex
        }
        let dependentColumns = dependentParameterIndices.map {
            boundaryDerivativeBounds(
                parameterIndex: $0,
                fixedParameterIndex: fixedParameterIndex,
                side: side
            )
        }
        if dependentColumns.allSatisfy(\.isFinite) {
            let midpointColumns = dependentColumns.map {
                Vector3D(x: $0.x.midpoint, y: $0.y.midpoint, z: $0.z.midpoint)
            }
            if let inverse = inverseRows(columns: midpointColumns) {
                let jacobian = [
                    dependentColumns.map(\.x),
                    dependentColumns.map(\.y),
                    dependentColumns.map(\.z),
                ]
                let scores = dependentColumns.indices.map { column in
                    (0..<3).reduce(0.0) { score, row in
                        var preconditioned = OutwardInterval(0.0)
                        for inner in 0..<3 {
                            preconditioned = preconditioned
                                + OutwardInterval(vectorComponent(inverse[row], index: inner))
                                    * jacobian[inner][column]
                        }
                        let identity = OutwardInterval(row == column ? 1.0 : 0.0)
                        return score + magnitudeUpperBound(identity - preconditioned)
                    }
                }
                if scores.allSatisfy(\.isFinite),
                   let selected = scores.indices.max(by: { first, second in
                       if scores[first] != scores[second] {
                           return scores[first] < scores[second]
                       }
                        return dependentParameterIndices[first]
                            > dependentParameterIndices[second]
                   }) {
                    return dependentParameterIndices[selected]
                }
            }
        }
        return dependentParameterIndices
            .map { parameterIndex in
                (
                    parameterIndex: parameterIndex,
                    width: boundaryDerivativeBounds(
                        parameterIndex: parameterIndex,
                        fixedParameterIndex: fixedParameterIndex,
                        side: side
                    ).widthMeasure
                )
            }
            .filter { $0.width.isFinite }
            .max { first, second in
                if first.width != second.width {
                    return first.width < second.width
                }
                return first.parameterIndex > second.parameterIndex
            }?
            .parameterIndex
    }

    func boundaryRootProofDiagnostic(
        fixedParameterIndex: Int,
        side: BoundarySide,
        tolerance: ModelingTolerance
    ) -> String {
        guard parameterCounts.indices.contains(fixedParameterIndex) else {
            return "invalid fixed parameter"
        }
        let coefficients = boundaryCoefficients(
            fixedParameterIndex: fixedParameterIndex,
            side: side
        )
        let scaledTolerance = (
            tolerance.distance.nextUp * denominatorUpperBound.nextUp
        ).nextUp
        if coefficientsExcludeZero(
            coefficients,
            tolerance: scaledTolerance
        ) {
            return "boundary coefficients exclude zero"
        }
        let dependentParameterIndices = parameterCounts.indices.filter {
            $0 != fixedParameterIndex
        }
        let dependentColumns = dependentParameterIndices.map {
            boundaryDerivativeBounds(
                parameterIndex: $0,
                fixedParameterIndex: fixedParameterIndex,
                side: side
            )
        }
        let minor = determinant(
            dependentColumns[0],
            dependentColumns[1],
            dependentColumns[2]
        )
        guard minor.isFinite, minor.excludesZero else {
            return "dependent minor=[\(minor.lower), \(minor.upper)]"
        }
        let midpointColumns = dependentColumns.map {
            Vector3D(x: $0.x.midpoint, y: $0.y.midpoint, z: $0.z.midpoint)
        }
        guard let inverse = inverseRows(columns: midpointColumns) else {
            return "dependent midpoint minor is numerically singular"
        }
        let jacobian = [
            dependentColumns.map(\.x),
            dependentColumns.map(\.y),
            dependentColumns.map(\.z),
        ]
        let fixedValue = side == .lower ? 0.0 : 1.0
        var center = Array(repeating: 0.5, count: 4)
        center[fixedParameterIndex] = fixedValue
        let box = krawczykBox(
            inverse: inverse,
            jacobian: jacobian,
            functionValue: evaluated(at: center)
        )
        return "dependent minor=[\(minor.lower), \(minor.upper)], box=\(box.map { [$0.lower, $0.upper] })"
    }

    func subdivided(parameterIndex: Int) -> [RationalBezierSurfaceSurfaceDifferencePatch] {
        let direction: SplitDirection
        switch parameterIndex {
        case 0: direction = .firstU
        case 1: direction = .firstV
        case 2: direction = .secondU
        case 3: direction = .secondV
        default: return []
        }
        let halves = splitPatch(direction: direction)
        return [halves.lower, halves.upper]
    }

    private func derivativeColumns() -> [IntervalVector] {
        [
            derivativeBounds(direction: .firstU),
            derivativeBounds(direction: .firstV),
            derivativeBounds(direction: .secondU),
            derivativeBounds(direction: .secondV),
        ]
    }

    func normalizedGraphParameterDerivativeBounds(
        freeParameterIndex: Int
    ) throws -> [ScalarInterval]? {
        let columns = derivativeColumns()
        guard columns.indices.contains(freeParameterIndex),
              columns.allSatisfy(\.isFinite) else {
            return nil
        }
        let dependentIndexes = columns.indices.filter {
            $0 != freeParameterIndex
        }
        let dependentColumns = dependentIndexes.map { columns[$0] }
        let denominator = determinant(
            dependentColumns[0],
            dependentColumns[1],
            dependentColumns[2]
        )
        guard denominator.isFinite, denominator.excludesZero else {
            return nil
        }
        let rightHandSide = columns[freeParameterIndex].scaled(by: -1.0)
        var result = Array(
            repeating: try ScalarInterval(lower: 0.0, upper: 0.0),
            count: columns.count
        )
        result[freeParameterIndex] = try ScalarInterval(lower: 1.0, upper: 1.0)
        for dependentIndex in dependentColumns.indices {
            var numeratorColumns = dependentColumns
            numeratorColumns[dependentIndex] = rightHandSide
            let numerator = determinant(
                numeratorColumns[0],
                numeratorColumns[1],
                numeratorColumns[2]
            )
            guard numerator.isFinite,
                  let quotient = numerator.divided(by: denominator),
                  quotient.isFinite else {
                return nil
            }
            result[dependentIndexes[dependentIndex]] = try ScalarInterval(
                lower: quotient.lower,
                upper: quotient.upper
            )
        }
        return result
    }

    private func rankThreeCertificate(
        columns: [IntervalVector]
    ) -> JacobianRankCertificate {
        guard columns.allSatisfy(\.isFinite) else { return .unresolved }

        var strongest: (freeParameterIndex: Int, separation: Double)?
        for freeParameterIndex in columns.indices {
            let dependentColumns = columns.indices
                .filter { $0 != freeParameterIndex }
                .map { columns[$0] }
            let minor = determinant(
                dependentColumns[0],
                dependentColumns[1],
                dependentColumns[2]
            )
            guard minor.isFinite, minor.excludesZero else { continue }
            if strongest.map({ minor.zeroSeparation > $0.separation }) ?? true {
                strongest = (freeParameterIndex, minor.zeroSeparation)
            }
        }
        guard let strongest else { return .unresolved }
        return .regular(freeParameterIndex: strongest.freeParameterIndex)
    }

    private var parameterCounts: [Int] {
        [
            controlNet[0].count,
            controlNet.count,
            controlNet[0][0][0].count,
            controlNet[0][0].count,
        ]
    }

    private func coefficient(at indices: [Int]) -> IntervalVector {
        controlNet[indices[1]][indices[0]][indices[3]][indices[2]]
    }

    private func boundaryCoefficients(
        fixedParameterIndex: Int,
        side: BoundarySide
    ) -> [IntervalVector] {
        let counts = parameterCounts
        let fixedControlIndex = side == .lower
            ? 0
            : counts[fixedParameterIndex] - 1
        var result: [IntervalVector] = []
        for firstU in 0..<counts[0] {
            for firstV in 0..<counts[1] {
                for secondU in 0..<counts[2] {
                    for secondV in 0..<counts[3] {
                        let indices = [firstU, firstV, secondU, secondV]
                        guard indices[fixedParameterIndex] == fixedControlIndex else {
                            continue
                        }
                        result.append(coefficient(at: indices))
                    }
                }
            }
        }
        return result
    }

    private func coefficientsExcludeZero(
        _ coefficients: [IntervalVector],
        tolerance: Double
    ) -> Bool {
        let componentIntervals = [
            coefficients.map(\.x),
            coefficients.map(\.y),
            coefficients.map(\.z),
        ]
        if componentIntervals.contains(where: { intervals in
            let minimum = intervals.map(\.lower).min() ?? -.infinity
            let maximum = intervals.map(\.upper).max() ?? .infinity
            return minimum > tolerance || maximum < -tolerance
        }) {
            return true
        }
        let corners = coefficients.flatMap { coefficient in
            [coefficient.x.lower, coefficient.x.upper].flatMap { x in
                [coefficient.y.lower, coefficient.y.upper].flatMap { y in
                    [coefficient.z.lower, coefficient.z.upper].map { z in
                        Point3D(x: x, y: y, z: z)
                    }
                }
            }
        }
        return ConvexHullSeparation3D.provesSeparated(
            first: corners,
            second: [.origin],
            tolerance: tolerance
        )
    }

    private func boundaryDerivativeBounds(
        parameterIndex: Int,
        fixedParameterIndex: Int,
        side: BoundarySide
    ) -> IntervalVector {
        let counts = parameterCounts
        let degree = counts[parameterIndex] - 1
        guard degree > 0 else { return zeroVector }
        let fixedControlIndex = side == .lower
            ? 0
            : counts[fixedParameterIndex] - 1
        var derivatives: [IntervalVector] = []
        for firstU in 0..<counts[0] {
            for firstV in 0..<counts[1] {
                for secondU in 0..<counts[2] {
                    for secondV in 0..<counts[3] {
                        let lowerIndices = [firstU, firstV, secondU, secondV]
                        guard lowerIndices[fixedParameterIndex] == fixedControlIndex,
                              lowerIndices[parameterIndex] < degree else {
                            continue
                        }
                        var upperIndices = lowerIndices
                        upperIndices[parameterIndex] += 1
                        derivatives.append((
                            coefficient(at: upperIndices)
                                - coefficient(at: lowerIndices)
                        ).scaled(by: Double(degree)))
                    }
                }
            }
        }
        return IntervalVector.enclosing(derivatives)
    }

    private func evaluated(at parameters: [Double]) -> IntervalVector {
        let counts = parameterCounts
        var result = zeroVector
        for firstU in 0..<counts[0] {
            let firstUWeight = bernsteinWeight(
                degree: counts[0] - 1,
                index: firstU,
                parameter: parameters[0]
            )
            guard firstUWeight != 0.0 else { continue }
            for firstV in 0..<counts[1] {
                let firstVWeight = bernsteinWeight(
                    degree: counts[1] - 1,
                    index: firstV,
                    parameter: parameters[1]
                )
                guard firstVWeight != 0.0 else { continue }
                for secondU in 0..<counts[2] {
                    let secondUWeight = bernsteinWeight(
                        degree: counts[2] - 1,
                        index: secondU,
                        parameter: parameters[2]
                    )
                    guard secondUWeight != 0.0 else { continue }
                    for secondV in 0..<counts[3] {
                        let secondVWeight = bernsteinWeight(
                            degree: counts[3] - 1,
                            index: secondV,
                            parameter: parameters[3]
                        )
                        let weight = firstUWeight
                            * firstVWeight
                            * secondUWeight
                            * secondVWeight
                        guard weight != 0.0 else { continue }
                        result = result + coefficient(at: [
                            firstU,
                            firstV,
                            secondU,
                            secondV,
                        ]).scaled(by: weight)
                    }
                }
            }
        }
        return result
    }

    private func bernsteinWeight(
        degree: Int,
        index: Int,
        parameter: Double
    ) -> Double {
        binomial(degree, index)
            * integerPower(parameter, exponent: index)
            * integerPower(1.0 - parameter, exponent: degree - index)
    }

    private func integerPower(_ base: Double, exponent: Int) -> Double {
        guard exponent > 0 else { return 1.0 }
        return (0..<exponent).reduce(1.0) { result, _ in result * base }
    }

    private func binomial(_ degree: Int, _ index: Int) -> Double {
        let reducedIndex = min(index, degree - index)
        guard reducedIndex > 0 else { return 1.0 }
        var result = 1.0
        for step in 1...reducedIndex {
            result *= Double(degree - reducedIndex + step) / Double(step)
        }
        return result
    }

    func subdividedFirstSurface() -> [RationalBezierSurfaceSurfaceDifferencePatch] {
        let uHalves = splitPatch(direction: .firstU)
        let lowerUVHalves = uHalves.lower.splitPatch(direction: .firstV)
        let upperUVHalves = uHalves.upper.splitPatch(direction: .firstV)
        return [
            lowerUVHalves.lower,
            upperUVHalves.lower,
            lowerUVHalves.upper,
            upperUVHalves.upper,
        ]
    }

    func subdividedSecondSurface() -> [RationalBezierSurfaceSurfaceDifferencePatch] {
        let uHalves = splitPatch(direction: .secondU)
        let lowerUVHalves = uHalves.lower.splitPatch(direction: .secondV)
        let upperUVHalves = uHalves.upper.splitPatch(direction: .secondV)
        return [
            lowerUVHalves.lower,
            upperUVHalves.lower,
            lowerUVHalves.upper,
            upperUVHalves.upper,
        ]
    }

    private static func validate(
        patch: RationalBezierSurfacePatch3D,
        tolerance: ModelingTolerance
    ) throws {
        guard patch.controlPoints.count == patch.weights.count,
              patch.controlPoints.isEmpty == false,
              patch.controlPoints.indices.allSatisfy({
                  patch.controlPoints[$0].count == patch.weights[$0].count
                      && patch.controlPoints[$0].isEmpty == false
              }) else {
            throw KernelError(
                phase: .geometry,
                code: .invalidInput,
                tolerance: tolerance,
                message: "Rational Bezier surface difference requires matching non-empty control data."
            )
        }
    }

    private static func differenceCoefficient(
        firstPoint: Point3D,
        firstWeight: Double,
        secondPoint: Point3D,
        secondWeight: Double
    ) -> IntervalVector {
        let firstWeightInterval = OutwardInterval(firstWeight)
        let secondWeightInterval = OutwardInterval(secondWeight)
        func coordinate(_ firstValue: Double, _ secondValue: Double) -> OutwardInterval {
            let weightedFirst = OutwardInterval(firstValue) * firstWeightInterval
            let weightedSecond = OutwardInterval(secondValue) * secondWeightInterval
            return weightedFirst * secondWeightInterval
                - weightedSecond * firstWeightInterval
        }
        return IntervalVector(
            x: coordinate(firstPoint.x, secondPoint.x),
            y: coordinate(firstPoint.y, secondPoint.y),
            z: coordinate(firstPoint.z, secondPoint.z)
        )
    }

    private func excludesZero(
        component: (IntervalVector) -> OutwardInterval
    ) -> Bool {
        let coefficients = controlNet
            .flatMap { $0 }
            .flatMap { $0 }
            .flatMap { $0 }
            .map(component)
        let minimum = coefficients.map(\.lower).min() ?? -.infinity
        let maximum = coefficients.map(\.upper).max() ?? .infinity
        return minimum > 0.0 || maximum < 0.0
    }

    private func excludesBand(radius: Double) -> Bool {
        excludesBand(radius: radius) { $0.x }
            || excludesBand(radius: radius) { $0.y }
            || excludesBand(radius: radius) { $0.z }
    }

    private func excludesBand(
        radius: Double,
        component: (IntervalVector) -> OutwardInterval
    ) -> Bool {
        let coefficients = controlNet
            .flatMap { $0 }
            .flatMap { $0 }
            .flatMap { $0 }
            .map(component)
        let minimum = coefficients.map(\.lower).min() ?? -.infinity
        let maximum = coefficients.map(\.upper).max() ?? .infinity
        return minimum > radius || maximum < -radius
    }

    private func derivativeBounds(direction: SplitDirection) -> IntervalVector {
        var derivatives: [IntervalVector] = []
        switch direction {
        case .firstU:
            let degree = controlNet[0].count - 1
            guard degree > 0 else { return zeroVector }
            for firstVIndex in controlNet.indices {
                for firstUIndex in 0..<degree {
                    for secondVIndex in controlNet[firstVIndex][firstUIndex].indices {
                        for secondUIndex in controlNet[firstVIndex][firstUIndex][secondVIndex].indices {
                            derivatives.append((
                                controlNet[firstVIndex][firstUIndex + 1][secondVIndex][secondUIndex]
                                    - controlNet[firstVIndex][firstUIndex][secondVIndex][secondUIndex]
                            ).scaled(by: Double(degree)))
                        }
                    }
                }
            }
        case .firstV:
            let degree = controlNet.count - 1
            guard degree > 0 else { return zeroVector }
            for firstVIndex in 0..<degree {
                for firstUIndex in controlNet[firstVIndex].indices {
                    for secondVIndex in controlNet[firstVIndex][firstUIndex].indices {
                        for secondUIndex in controlNet[firstVIndex][firstUIndex][secondVIndex].indices {
                            derivatives.append((
                                controlNet[firstVIndex + 1][firstUIndex][secondVIndex][secondUIndex]
                                    - controlNet[firstVIndex][firstUIndex][secondVIndex][secondUIndex]
                            ).scaled(by: Double(degree)))
                        }
                    }
                }
            }
        case .secondU:
            let degree = controlNet[0][0][0].count - 1
            guard degree > 0 else { return zeroVector }
            for firstVIndex in controlNet.indices {
                for firstUIndex in controlNet[firstVIndex].indices {
                    for secondVIndex in controlNet[firstVIndex][firstUIndex].indices {
                        for secondUIndex in 0..<degree {
                            derivatives.append((
                                controlNet[firstVIndex][firstUIndex][secondVIndex][secondUIndex + 1]
                                    - controlNet[firstVIndex][firstUIndex][secondVIndex][secondUIndex]
                            ).scaled(by: Double(degree)))
                        }
                    }
                }
            }
        case .secondV:
            let degree = controlNet[0][0].count - 1
            guard degree > 0 else { return zeroVector }
            for firstVIndex in controlNet.indices {
                for firstUIndex in controlNet[firstVIndex].indices {
                    for secondVIndex in 0..<degree {
                        for secondUIndex in controlNet[firstVIndex][firstUIndex][secondVIndex].indices {
                            derivatives.append((
                                controlNet[firstVIndex][firstUIndex][secondVIndex + 1][secondUIndex]
                                    - controlNet[firstVIndex][firstUIndex][secondVIndex][secondUIndex]
                            ).scaled(by: Double(degree)))
                        }
                    }
                }
            }
        }
        return IntervalVector.enclosing(derivatives)
    }

    private func centerValue() -> IntervalVector {
        let afterFirstU = controlNet.map { firstURows in
            firstURows[0].indices.map { secondVIndex in
                firstURows[0][secondVIndex].indices.map { secondUIndex in
                    evaluatedMidpoint(firstURows.map {
                        $0[secondVIndex][secondUIndex]
                    })
                }
            }
        }
        let afterFirstV = afterFirstU[0].indices.map { secondVIndex in
            afterFirstU[0][secondVIndex].indices.map { secondUIndex in
                evaluatedMidpoint(afterFirstU.map {
                    $0[secondVIndex][secondUIndex]
                })
            }
        }
        let afterSecondU = afterFirstV.map(evaluatedMidpoint)
        return evaluatedMidpoint(afterSecondU)
    }

    private func parameterizedCenterValueBounds(
        freeParameterIndex: Int
    ) -> IntervalVector {
        let freeCoefficients: [IntervalVector]
        switch freeParameterIndex {
        case 0:
            freeCoefficients = controlNet[0].indices.map { firstUIndex in
                evaluatedMidpoint(controlNet.map { $0[firstUIndex] })
            }
        case 1:
            freeCoefficients = controlNet.map(evaluatedMidpoint)
        case 2:
            freeCoefficients = controlNet[0][0][0].indices.map { secondUIndex in
                evaluatedMidpoint(controlNet.map { firstVRow in
                    firstVRow.map { firstURow in
                        firstURow.map { $0[secondUIndex] }
                    }
                })
            }
        default:
            freeCoefficients = controlNet[0][0].indices.map { secondVIndex in
                evaluatedMidpoint(controlNet.map { firstVRow in
                    firstVRow.map { $0[secondVIndex] }
                })
            }
        }
        return IntervalVector.enclosing(freeCoefficients)
    }

    private func affinePredictorValueBounds(
        freeParameterIndex: Int,
        lowerAnchor: [Double],
        upperAnchor: [Double]
    ) -> IntervalVector? {
        let counts = parameterCounts
        let totalDegree = counts.reduce(0) { $0 + $1 - 1 }
        var powerCoefficients = Array(
            repeating: zeroVector,
            count: totalDegree + 1
        )
        for firstU in 0..<counts[0] {
            for firstV in 0..<counts[1] {
                for secondU in 0..<counts[2] {
                    for secondV in 0..<counts[3] {
                        let indices = [firstU, firstV, secondU, secondV]
                        var basis = [1.0]
                        for parameterIndex in counts.indices {
                            let lower = parameterIndex == freeParameterIndex
                                ? 0.0
                                : lowerAnchor[parameterIndex]
                            let upper = parameterIndex == freeParameterIndex
                                ? 1.0
                                : upperAnchor[parameterIndex]
                            basis = multiplyPolynomial(
                                basis,
                                bernsteinBasisPowerCoefficients(
                                    degree: counts[parameterIndex] - 1,
                                    index: indices[parameterIndex],
                                    lower: lower,
                                    upper: upper
                                )
                            )
                        }
                        let value = coefficient(at: indices)
                        for degree in basis.indices {
                            powerCoefficients[degree] = powerCoefficients[degree]
                                + value.scaled(by: basis[degree])
                        }
                    }
                }
            }
        }
        guard powerCoefficients.allSatisfy(\.isFinite) else { return nil }
        let bernsteinCoefficients = (0...totalDegree).map { index in
            (0...index).reduce(zeroVector) { result, powerIndex in
                let scale = binomial(index, powerIndex)
                    / binomial(totalDegree, powerIndex)
                return result + powerCoefficients[powerIndex].scaled(by: scale)
            }
        }
        guard bernsteinCoefficients.allSatisfy(\.isFinite) else { return nil }
        return IntervalVector.enclosing(bernsteinCoefficients)
    }

    private func bernsteinBasisPowerCoefficients(
        degree: Int,
        index: Int,
        lower: Double,
        upper: Double
    ) -> [Double] {
        let parameter = [lower, upper - lower]
        let complement = [1.0 - lower, lower - upper]
        let firstPower = polynomialPower(parameter, exponent: index)
        let secondPower = polynomialPower(
            complement,
            exponent: degree - index
        )
        return multiplyPolynomial(firstPower, secondPower).map {
            $0 * binomial(degree, index)
        }
    }

    private func polynomialPower(
        _ polynomial: [Double],
        exponent: Int
    ) -> [Double] {
        guard exponent > 0 else { return [1.0] }
        return (0..<exponent).reduce([1.0]) { result, _ in
            multiplyPolynomial(result, polynomial)
        }
    }

    private func multiplyPolynomial(
        _ first: [Double],
        _ second: [Double]
    ) -> [Double] {
        var result = Array(repeating: 0.0, count: first.count + second.count - 1)
        for firstIndex in first.indices {
            for secondIndex in second.indices {
                result[firstIndex + secondIndex] += first[firstIndex] * second[secondIndex]
            }
        }
        return result
    }

    private func krawczykBox(
        inverse: [Vector3D],
        jacobian: [[OutwardInterval]],
        functionValue: IntervalVector
    ) -> [OutwardInterval] {
        let functionComponents = [functionValue.x, functionValue.y, functionValue.z]
        let radius = OutwardInterval.enclosing(-0.5, 0.5)
        return (0..<3).map { row in
            var component = OutwardInterval(0.5)
            for inner in 0..<3 {
                component = component
                    - OutwardInterval(vectorComponent(inverse[row], index: inner))
                        * functionComponents[inner]
            }
            for column in 0..<3 {
                var preconditioned = OutwardInterval(0.0)
                for inner in 0..<3 {
                    preconditioned = preconditioned
                        + OutwardInterval(vectorComponent(inverse[row], index: inner))
                            * jacobian[inner][column]
                }
                let identity = OutwardInterval(row == column ? 1.0 : 0.0)
                component = component + (identity - preconditioned) * radius
            }
            return component
        }
    }

    private func affinePredictorKrawczykBox(
        inverse: [Vector3D],
        jacobian: [[OutwardInterval]],
        functionValue: IntervalVector,
        centerBounds: [OutwardInterval]
    ) -> [OutwardInterval] {
        let functionComponents = [functionValue.x, functionValue.y, functionValue.z]
        let unit = OutwardInterval.enclosing(0.0, 1.0)
        return (0..<3).map { row in
            var component = centerBounds[row]
            for inner in 0..<3 {
                component = component
                    - OutwardInterval(vectorComponent(inverse[row], index: inner))
                        * functionComponents[inner]
            }
            for column in 0..<3 {
                var preconditioned = OutwardInterval(0.0)
                for inner in 0..<3 {
                    preconditioned = preconditioned
                        + OutwardInterval(vectorComponent(inverse[row], index: inner))
                            * jacobian[inner][column]
                }
                let identity = OutwardInterval(row == column ? 1.0 : 0.0)
                component = component
                    + (identity - preconditioned) * (unit - centerBounds[column])
            }
            return component
        }
    }

    private func isDisjointFromUnitCube(_ box: [OutwardInterval]) -> Bool {
        box.contains { $0.upper < 0.0 || $0.lower > 1.0 }
    }

    private func isStrictlyInsideUnitCube(_ box: [OutwardInterval]) -> Bool {
        box.allSatisfy { $0.lower > 0.0 && $0.upper < 1.0 }
    }

    private func inverseRows(columns: [Vector3D]) -> [Vector3D]? {
        guard columns.count == 3 else { return nil }
        let firstCross = columns[1].cross(columns[2])
        let determinant = columns[0].dot(firstCross)
        let scale = columns.map(\.length).max() ?? .infinity
        let determinantFloor = max(
            scale * scale * scale * Double.ulpOfOne * 1_024.0,
            Double.leastNonzeroMagnitude
        )
        guard determinant.isFinite,
              scale.isFinite,
              abs(determinant) > determinantFloor else {
            return nil
        }
        return [
            firstCross / determinant,
            columns[2].cross(columns[0]) / determinant,
            columns[0].cross(columns[1]) / determinant,
        ]
    }

    private func vectorComponent(_ vector: Vector3D, index: Int) -> Double {
        switch index {
        case 0: vector.x
        case 1: vector.y
        default: vector.z
        }
    }

    private func evaluatedMidpoint(_ values: [IntervalVector]) -> IntervalVector {
        guard values.isEmpty == false else { return zeroVector }
        var level = values
        while level.count > 1 {
            level = (0..<(level.count - 1)).map { index in
                level[index].midpoint(with: level[index + 1])
            }
        }
        return level[0]
    }

    private func evaluatedMidpoint(
        _ values: [[[IntervalVector]]]
    ) -> IntervalVector {
        guard values.isEmpty == false,
              values[0].isEmpty == false,
              values[0][0].isEmpty == false else {
            return zeroVector
        }
        let afterFirst = values[0].indices.map { secondIndex in
            values[0][secondIndex].indices.map { thirdIndex in
                evaluatedMidpoint(values.map { $0[secondIndex][thirdIndex] })
            }
        }
        let afterSecond = afterFirst[0].indices.map { thirdIndex in
            evaluatedMidpoint(afterFirst.map { $0[thirdIndex] })
        }
        return evaluatedMidpoint(afterSecond)
    }

    private var zeroVector: IntervalVector {
        IntervalVector(
            x: OutwardInterval(0.0),
            y: OutwardInterval(0.0),
            z: OutwardInterval(0.0)
        )
    }

    private func determinant(
        _ first: IntervalVector,
        _ second: IntervalVector,
        _ third: IntervalVector
    ) -> OutwardInterval {
        let crossX = second.y * third.z - second.z * third.y
        let crossY = second.z * third.x - second.x * third.z
        let crossZ = second.x * third.y - second.y * third.x
        return first.x * crossX + first.y * crossY + first.z * crossZ
    }

    private func splitPatch(
        direction: SplitDirection
    ) -> (
        lower: RationalBezierSurfaceSurfaceDifferencePatch,
        upper: RationalBezierSurfaceSurfaceDifferencePatch
    ) {
        let nets: (
            lower: [[[[IntervalVector]]]],
            upper: [[[[IntervalVector]]]]
        )
        switch direction {
        case .firstU:
            nets = splitFirstU()
        case .firstV:
            nets = splitFirstV()
        case .secondU:
            nets = splitSecondU()
        case .secondV:
            nets = splitSecondV()
        }
        let firstUMiddle = firstULower + (firstUUpper - firstULower) * 0.5
        let firstVMiddle = firstVLower + (firstVUpper - firstVLower) * 0.5
        let secondUMiddle = secondULower + (secondUUpper - secondULower) * 0.5
        let secondVMiddle = secondVLower + (secondVUpper - secondVLower) * 0.5
        let lowerBounds: (
            firstU: (Double, Double),
            firstV: (Double, Double),
            secondU: (Double, Double),
            secondV: (Double, Double)
        )
        let upperBounds: (
            firstU: (Double, Double),
            firstV: (Double, Double),
            secondU: (Double, Double),
            secondV: (Double, Double)
        )
        switch direction {
        case .firstU:
            lowerBounds = (
                (firstULower, firstUMiddle),
                (firstVLower, firstVUpper),
                (secondULower, secondUUpper),
                (secondVLower, secondVUpper)
            )
            upperBounds = (
                (firstUMiddle, firstUUpper),
                (firstVLower, firstVUpper),
                (secondULower, secondUUpper),
                (secondVLower, secondVUpper)
            )
        case .firstV:
            lowerBounds = (
                (firstULower, firstUUpper),
                (firstVLower, firstVMiddle),
                (secondULower, secondUUpper),
                (secondVLower, secondVUpper)
            )
            upperBounds = (
                (firstULower, firstUUpper),
                (firstVMiddle, firstVUpper),
                (secondULower, secondUUpper),
                (secondVLower, secondVUpper)
            )
        case .secondU:
            lowerBounds = (
                (firstULower, firstUUpper),
                (firstVLower, firstVUpper),
                (secondULower, secondUMiddle),
                (secondVLower, secondVUpper)
            )
            upperBounds = (
                (firstULower, firstUUpper),
                (firstVLower, firstVUpper),
                (secondUMiddle, secondUUpper),
                (secondVLower, secondVUpper)
            )
        case .secondV:
            lowerBounds = (
                (firstULower, firstUUpper),
                (firstVLower, firstVUpper),
                (secondULower, secondUUpper),
                (secondVLower, secondVMiddle)
            )
            upperBounds = (
                (firstULower, firstUUpper),
                (firstVLower, firstVUpper),
                (secondULower, secondUUpper),
                (secondVMiddle, secondVUpper)
            )
        }
        return (
            replacing(controlNet: nets.lower, bounds: lowerBounds),
            replacing(controlNet: nets.upper, bounds: upperBounds)
        )
    }

    private func splitFirstU() -> (
        lower: [[[[IntervalVector]]]],
        upper: [[[[IntervalVector]]]]
    ) {
        var lower = controlNet
        var upper = controlNet
        for firstVIndex in controlNet.indices {
            for secondVIndex in controlNet[firstVIndex][0].indices {
                for secondUIndex in controlNet[firstVIndex][0][secondVIndex].indices {
                    let halves = split(controlNet[firstVIndex].map {
                        $0[secondVIndex][secondUIndex]
                    })
                    for firstUIndex in controlNet[firstVIndex].indices {
                        lower[firstVIndex][firstUIndex][secondVIndex][secondUIndex]
                            = halves.lower[firstUIndex]
                        upper[firstVIndex][firstUIndex][secondVIndex][secondUIndex]
                            = halves.upper[firstUIndex]
                    }
                }
            }
        }
        return (lower, upper)
    }

    private func splitFirstV() -> (
        lower: [[[[IntervalVector]]]],
        upper: [[[[IntervalVector]]]]
    ) {
        var lower = controlNet
        var upper = controlNet
        for firstUIndex in controlNet[0].indices {
            for secondVIndex in controlNet[0][firstUIndex].indices {
                for secondUIndex in controlNet[0][firstUIndex][secondVIndex].indices {
                    let halves = split(controlNet.map {
                        $0[firstUIndex][secondVIndex][secondUIndex]
                    })
                    for firstVIndex in controlNet.indices {
                        lower[firstVIndex][firstUIndex][secondVIndex][secondUIndex]
                            = halves.lower[firstVIndex]
                        upper[firstVIndex][firstUIndex][secondVIndex][secondUIndex]
                            = halves.upper[firstVIndex]
                    }
                }
            }
        }
        return (lower, upper)
    }

    private func splitSecondU() -> (
        lower: [[[[IntervalVector]]]],
        upper: [[[[IntervalVector]]]]
    ) {
        var lower = controlNet
        var upper = controlNet
        for firstVIndex in controlNet.indices {
            for firstUIndex in controlNet[firstVIndex].indices {
                for secondVIndex in controlNet[firstVIndex][firstUIndex].indices {
                    let halves = split(
                        controlNet[firstVIndex][firstUIndex][secondVIndex]
                    )
                    for secondUIndex in controlNet[firstVIndex][firstUIndex][secondVIndex].indices {
                        lower[firstVIndex][firstUIndex][secondVIndex][secondUIndex]
                            = halves.lower[secondUIndex]
                        upper[firstVIndex][firstUIndex][secondVIndex][secondUIndex]
                            = halves.upper[secondUIndex]
                    }
                }
            }
        }
        return (lower, upper)
    }

    private func splitSecondV() -> (
        lower: [[[[IntervalVector]]]],
        upper: [[[[IntervalVector]]]]
    ) {
        var lower = controlNet
        var upper = controlNet
        for firstVIndex in controlNet.indices {
            for firstUIndex in controlNet[firstVIndex].indices {
                for secondUIndex in controlNet[firstVIndex][firstUIndex][0].indices {
                    let halves = split(
                        controlNet[firstVIndex][firstUIndex].map { $0[secondUIndex] }
                    )
                    for secondVIndex in controlNet[firstVIndex][firstUIndex].indices {
                        lower[firstVIndex][firstUIndex][secondVIndex][secondUIndex]
                            = halves.lower[secondVIndex]
                        upper[firstVIndex][firstUIndex][secondVIndex][secondUIndex]
                            = halves.upper[secondVIndex]
                    }
                }
            }
        }
        return (lower, upper)
    }

    private func split(
        _ values: [IntervalVector]
    ) -> (lower: [IntervalVector], upper: [IntervalVector]) {
        guard values.count > 1 else { return (values, values) }
        var levels = [values]
        while let previous = levels.last, previous.count > 1 {
            levels.append((0..<(previous.count - 1)).map { index in
                previous[index].midpoint(with: previous[index + 1])
            })
        }
        return (
            levels.map { $0[0] },
            levels.reversed().map { $0[$0.count - 1] }
        )
    }

    private func replacing(
        controlNet: [[[[IntervalVector]]]],
        bounds: (
            firstU: (Double, Double),
            firstV: (Double, Double),
            secondU: (Double, Double),
            secondV: (Double, Double)
        )
    ) -> RationalBezierSurfaceSurfaceDifferencePatch {
        RationalBezierSurfaceSurfaceDifferencePatch(
            controlNet: controlNet,
            denominatorUpperBound: denominatorUpperBound,
            firstUBounds: bounds.firstU,
            firstVBounds: bounds.firstV,
            secondUBounds: bounds.secondU,
            secondVBounds: bounds.secondV
        )
    }
}

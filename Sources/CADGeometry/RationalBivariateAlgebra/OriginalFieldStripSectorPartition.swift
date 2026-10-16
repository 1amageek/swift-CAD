/// Complete original open-strip sectors cut by exact rational native-domain boundaries.
package struct OriginalFieldStripSectorPartition: Sendable {
    package struct Sector: Sendable {
        package let stripIndex: Int
        package let first: OriginalSingularFieldValueIsolation
        package let last: OriginalSingularFieldValueIsolation
        package let originalFreeWitness: ExactRationalCoefficient
        package let originalFiber: OriginalSingularFieldRoot
        package let insideClosedRectangle: Bool
        package let sourceDepth: Int
    }
    package let originalCuts: OriginalFieldStripCoordinateCuts
    package let uLower: ExactRationalCoefficient
    package let uUpper: ExactRationalCoefficient
    package let vLower: ExactRationalCoefficient
    package let vUpper: ExactRationalCoefficient
    package let sectors: [Sector]

    package init<B: ExactScalarAdmission & ~Copyable>(retaining cuts: OriginalFieldStripCoordinateCuts,
        uLower: ExactRationalCoefficient, uUpper: ExactRationalCoefficient,
        vLower: ExactRationalCoefficient, vUpper: ExactRationalCoefficient,
        maximumDepth: Int, maximumAlgebraicDepth: Int, usage: inout B) throws {
        guard try uUpper.subtracting(uLower, usage: &usage).isPositive,
            try vUpper.subtracting(vLower, usage: &usage).isPositive,
            maximumDepth >= cuts.originalAtlas.projection.sourceDepth,
            maximumAlgebraicDepth >= cuts.originalAtlas.projection.original.context.coefficientDepth else {
            throw rationalAlgebraFailure("Original strip partition requires positive exact native widths and admitted source depth.")
        }
        let result = try usage.withProofScope(maximum: .init(value: Int.max, coefficient: maximumAlgebraicDepth)) { usage in
            guard try Self.contains(uLower, in: cuts.originalUCuts, maximumDepth: maximumDepth, usage: &usage),
                try Self.contains(uUpper, in: cuts.originalUCuts, maximumDepth: maximumDepth, usage: &usage),
                try Self.contains(vLower, in: cuts.originalVCuts, maximumDepth: maximumDepth, usage: &usage),
                try Self.contains(vUpper, in: cuts.originalVCuts, maximumDepth: maximumDepth, usage: &usage) else {
                throw rationalAlgebraFailure("Original strip partition is missing an exact closed-rectangle boundary cut.")
            }
            let atlas = cuts.originalAtlas, projection = atlas.projection
            var result: [Sector] = []
            for (stripIndex, strip) in atlas.strips.enumerated() {
                let sourceSector = projection.sectors[strip.sectorIndex]
                var values: [OriginalSingularFieldElement] = []
                for side in 0..<2 {
                    let station = projection.stations[side == 0 ? sourceSector.lowerStation : sourceSector.upperStation]
                    let value: OriginalSingularFieldElement
                    switch station.endpoint {
                    case .authored(let rational): value = try .constant(rational, in: projection.original.context,
                        maximumDepth: maximumDepth, usage: &usage)
                    case .algebraic(let root): value = try root.value(maximumDepth: maximumDepth, usage: &usage)
                    }
                    try RationalAlgebraStorage.retain(1, of: OriginalSingularFieldElement.self, usage: &usage)
                    values.append(value)
                }
                for point in cuts.points {
                    guard case .strip(let index) = point.incidence, index == stripIndex else { continue }
                    try RationalAlgebraStorage.retain(1, of: OriginalSingularFieldElement.self, usage: &usage)
                    values.append(point.originalU)
                }
                var ordered: [OriginalSingularFieldElement] = []
                try RationalAlgebraStorage.retain(values.count, of: OriginalSingularFieldElement.self, usage: &usage)
                ordered.reserveCapacity(values.count)
                for value in values {
                    var position = ordered.count, duplicate = false
                    for index in ordered.indices {
                        let order = try Self.compare(value, ordered[index], maximumDepth: maximumDepth, usage: &usage)
                        if order == 0 { duplicate = true; break }
                        if order < 0 { position = index; break }
                    }
                    if duplicate { continue }
                    try usage.consumeWork(try rationalAlgebraCount(ordered.count - position, 1))
                    ordered.insert(value, at: position)
                }
                var endpoints: [OriginalSingularFieldValueIsolation] = []
                try RationalAlgebraStorage.retain(ordered.count, of: OriginalSingularFieldValueIsolation.self, usage: &usage)
                endpoints.reserveCapacity(ordered.count)
                for value in ordered {
                    endpoints.append(try .init(original: value, inheritedDepth: projection.sourceDepth,
                        maximumDepth: maximumDepth, usage: &usage))
                }
                if endpoints.count < 2 { throw rationalAlgebraFailure("Original strip lost its positive projection sector.") }
                for index in 0..<(endpoints.count - 1) {
                    var first = endpoints[index], last = endpoints[index + 1]
                    while !(try last.lower.subtracting(first.upper, usage: &usage).isPositive) {
                        let a = try first.upper.subtracting(first.lower, usage: &usage)
                        let b = try last.upper.subtracting(last.lower, usage: &usage)
                        let widest = try a.subtracting(b, usage: &usage).isPositive ? a : b
                        let width = try widest.divided(by: .natural(2, usage: &usage), usage: &usage)
                        guard width.isPositive else { throw rationalAlgebraFailure("Distinct original strip cuts have no positive isolation gap.") }
                        first = try first.refined(maximumWidth: width, maximumDepth: maximumDepth, usage: &usage)
                        last = try last.refined(maximumWidth: width, maximumDepth: maximumDepth, usage: &usage)
                    }
                    endpoints[index] = first; endpoints[index + 1] = last
                    let witness = try first.upper.adding(last.lower, usage: &usage)
                        .divided(by: .natural(2, usage: &usage), usage: &usage)
                    let fiber = try OriginalSingularFieldPlaneProjection.restricted(projection.primitive,
                        alongU: true, station: witness, maximumDepth: maximumDepth, usage: &usage)
                    let roots = try OriginalSingularFieldPlaneProjection.sliceRoots(fiber,
                        lower: .originalDouble(projection.domain.v.lower, usage: &usage),
                        upper: .originalDouble(projection.domain.v.upper, usage: &usage),
                        inheritedDepth: max(projection.sourceDepth, max(first.sourceDepth, last.sourceDepth)),
                        maximumDepth: maximumDepth, usage: &usage)
                    guard roots.count == sourceSector.fiberRoots.count, strip.branchOrdinal < roots.count else {
                        throw rationalAlgebraFailure("Original partition changed its retained strip fiber ordinal.")
                    }
                    let root = roots[strip.branchOrdinal]
                    let transverse = try root.value(maximumDepth: maximumDepth, usage: &usage)
                    let insideU = try !witness.subtracting(uLower, usage: &usage).isNegative
                        && !uUpper.subtracting(witness, usage: &usage).isNegative
                    let insideV = try Self.inside(transverse, lower: vLower, upper: vUpper,
                        maximumDepth: maximumDepth, usage: &usage)
                    try RationalAlgebraStorage.retain(1, of: Sector.self, usage: &usage)
                    result.append(Sector(stripIndex: stripIndex, first: first, last: last,
                        originalFreeWitness: witness, originalFiber: root, insideClosedRectangle: insideU && insideV,
                        sourceDepth: max(root.isolation.depth, max(first.sourceDepth, last.sourceDepth))))
                }
            }
            return result
        }
        originalCuts = cuts; self.uLower = uLower; self.uUpper = uUpper
        self.vLower = vLower; self.vUpper = vUpper; sectors = result
    }

    private static func contains<B: ExactScalarAdmission & ~Copyable>(_ value: ExactRationalCoefficient,
        in cuts: [ExactMonotoneGraphEndpoint], maximumDepth: Int, usage: inout B) throws -> Bool {
        let context = try OriginalSingularFieldContext(usage: &usage)
        let transport = OriginalSingularFieldTransport()
        for cut in cuts {
            let original = try transport.originalScalarValue(cut, into: context, maximumDepth: maximumDepth, usage: &usage)
            let target = try OriginalSingularFieldElement.constant(value, in: original.context, maximumDepth: maximumDepth, usage: &usage)
            if case .zero = try original.subtracting(target, maximumDepth: maximumDepth, usage: &usage)
                .sign(maximumDepth: maximumDepth, usage: &usage) { return true }
        }
        return false
    }

    private static func compare<B: ExactScalarAdmission & ~Copyable>(_ first: OriginalSingularFieldElement,
        _ second: OriginalSingularFieldElement, maximumDepth: Int, usage: inout B) throws -> Int {
        var transport = OriginalSingularFieldTransport()
        let context = try transport.importing(second.context, into: first.context, maximumDepth: maximumDepth, usage: &usage)
        let a = try first.embedded(in: context, maximumDepth: maximumDepth, usage: &usage)
        let b = try transport.applying(to: second, in: context, maximumDepth: maximumDepth, usage: &usage)
        switch try a.subtracting(b, maximumDepth: maximumDepth, usage: &usage).sign(maximumDepth: maximumDepth, usage: &usage) {
        case .negative: return -1
        case .zero: return 0
        case .positive: return 1
        }
    }

    private static func inside<B: ExactScalarAdmission & ~Copyable>(_ value: OriginalSingularFieldElement,
        lower: ExactRationalCoefficient, upper: ExactRationalCoefficient, maximumDepth: Int, usage: inout B) throws -> Bool {
        let a = try OriginalSingularFieldElement.constant(lower, in: value.context, maximumDepth: maximumDepth, usage: &usage)
        let b = try OriginalSingularFieldElement.constant(upper, in: value.context, maximumDepth: maximumDepth, usage: &usage)
        if case .negative = try value.subtracting(a, maximumDepth: maximumDepth, usage: &usage).sign(maximumDepth: maximumDepth, usage: &usage) { return false }
        if case .positive = try value.subtracting(b, maximumDepth: maximumDepth, usage: &usage).sign(maximumDepth: maximumDepth, usage: &usage) { return false }
        return true
    }
}

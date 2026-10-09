import CADCore

/// Original harmonic normal coefficients after the exact retained spatial action.
struct SurfaceSilhouetteOriginalHarmonicZeroAuthority: Sendable {
    let original: OriginalAffineWordHarmonicSurfaceCoefficients
    let coefficients: [OriginalSingularFieldElement]
    let maximumAlgebraicDepth: Int

    init(original: OriginalAffineWordHarmonicSurfaceCoefficients, view: Vector3D,
        usage: inout SurfaceSilhouetteUsage) throws {
        self.original = original
        let source = original.originalNormalGauge
        // FIXME(INCOMPLETE_IMPLEMENTATION): The new original physical cone source
        // retains its full UV law. This silhouette consumer cannot yet compile
        // the required physical half-angle coefficient field into its exact zero
        // relation and must refuse rather than treating a cone as a torus.
        guard source.kind != .cone else {
            throw KernelError(phase:.geometry,code:.unsupportedCapability,tolerance:nil,
                message:"Original transported cone silhouette requires its physical slope coefficient field.")
        }
        var admission = SurfaceSilhouetteAlgebraicAdmission(usage: usage)
        defer { usage = admission.usage }
        let frame = try source.word.originalNormalizedFrame(usage: &admission)
        let depth = frame.map { min(admission.usage.maximumAlgebraicDepth, $0.maximumAlgebraicDepth) }
            ?? admission.usage.maximumAlgebraicDepth
        var scoped = RationalCoefficientDepthAdmission(base: admission, maximumDepth: depth)
        defer { admission = scoped.base }
        let context: OriginalSingularFieldContext
        if let frame { context = frame.frame.context }
        else { context = try OriginalSingularFieldContext(usage: &scoped) }
        guard context.coefficientDepth <= depth else {
            throw rationalAlgebraFailure("Original harmonic image exceeds its coefficient-root admission.")
        }
        try source.uTransport.validate(usage: &scoped)
        try source.vTransport.validate(usage: &scoped)
        _ = try source.uTransport.orientationSign(usage: &scoped)
        _ = try source.vTransport.orientationSign(usage: &scoped)
        typealias Element = OriginalSingularFieldElement
        typealias Vector = (x: Element, y: Element, z: Element)
        func exact(_ value: Vector3D, usage: inout RationalCoefficientDepthAdmission<SurfaceSilhouetteAlgebraicAdmission>) throws -> Vector {
            let x = try Element.constant(.originalDouble(value.x, usage: &usage), in: context, maximumDepth: depth, usage: &usage)
            let y = try Element.constant(.originalDouble(value.y, usage: &usage), in: context, maximumDepth: depth, usage: &usage)
            let z = try Element.constant(.originalDouble(value.z, usage: &usage), in: context, maximumDepth: depth, usage: &usage)
            return (x, y, z)
        }
        func cross(_ a: Vector, _ b: Vector,
            usage: inout RationalCoefficientDepthAdmission<SurfaceSilhouetteAlgebraicAdmission>) throws -> Vector {
            let x = try a.y.multiplied(by: b.z, maximumDepth: depth, usage: &usage)
                .subtracting(a.z.multiplied(by: b.y, maximumDepth: depth, usage: &usage), maximumDepth: depth, usage: &usage)
            let y = try a.z.multiplied(by: b.x, maximumDepth: depth, usage: &usage)
                .subtracting(a.x.multiplied(by: b.z, maximumDepth: depth, usage: &usage), maximumDepth: depth, usage: &usage)
            let z = try a.x.multiplied(by: b.y, maximumDepth: depth, usage: &usage)
                .subtracting(a.y.multiplied(by: b.x, maximumDepth: depth, usage: &usage), maximumDepth: depth, usage: &usage)
            return (x, y, z)
        }
        func component(_ vector: Vector, _ axis: Int) -> Element {
            axis == 0 ? vector.x : axis == 1 ? vector.y : vector.z
        }
        func linear(_ row: Int, _ column: Int,
            usage: inout RationalCoefficientDepthAdmission<SurfaceSilhouetteAlgebraicAdmission>) throws -> Element {
            try usage.consumeExactWork(1)
            if let frame {
                let values = column == 0 ? frame.frame.basisX : column == 1 ? frame.frame.basisY : frame.frame.basisZ
                guard values.count == 3 else { throw rationalAlgebraFailure("Original harmonic frame lost a linear column.") }
                return try values[row].embedded(in: context, maximumDepth: depth, usage: &usage)
            }
            return try .constant(source.word.linearCoefficient(row: row, column: column),
                in: context, maximumDepth: depth, usage: &usage)
        }
        try RationalAlgebraStorage.retain(9, of: Element.self, usage: &scoped)
        var cofactors: [Element] = []; cofactors.reserveCapacity(9)
        for row in 0..<3 {
            for column in 0..<3 {
                let r0 = row == 0 ? 1 : 0, r1 = row == 2 ? 1 : 2
                let c0 = column == 0 ? 1 : 0, c1 = column == 2 ? 1 : 2
                let a = try linear(r0, c0, usage: &scoped), b = try linear(r1, c1, usage: &scoped)
                let c = try linear(r0, c1, usage: &scoped), d = try linear(r1, c0, usage: &scoped)
                var value = try a.multiplied(by: b, maximumDepth: depth, usage: &scoped)
                    .subtracting(c.multiplied(by: d, maximumDepth: depth, usage: &scoped), maximumDepth: depth, usage: &scoped)
                if (row + column) % 2 != 0 { value = try value.negated(maximumDepth: depth, usage: &scoped) }
                cofactors.append(value)
            }
        }
        let direction = try exact(view, usage: &scoped)
        func projected(_ vector: Vector,
            usage: inout RationalCoefficientDepthAdmission<SurfaceSilhouetteAlgebraicAdmission>) throws -> Element {
            var result = try Element.constant(.zero, in: context, maximumDepth: depth, usage: &usage)
            for row in 0..<3 {
                for column in 0..<3 {
                    try usage.consumeExactWork(1)
                    let term = try cofactors[row * 3 + column].multiplied(by: component(vector, column), maximumDepth: depth, usage: &usage)
                        .multiplied(by: component(direction, row), maximumDepth: depth, usage: &usage)
                    result = try result.adding(term, maximumDepth: depth, usage: &usage)
                }
            }
            return result
        }
        let first = try exact(source.firstDirection, usage: &scoped)
        let second = try exact(source.secondDirection, usage: &scoped)
        let axis = try exact(source.axisDirection, usage: &scoped)
        let count = source.kind == .cylinder ? 2 : 3
        try RationalAlgebraStorage.retain(count, of: Element.self, usage: &scoped)
        var values: [Element] = []; values.reserveCapacity(count)
        switch source.kind {
        case .cylinder, .cone, .torus:
            values.append(try projected(cross(second, axis, usage: &scoped), usage: &scoped))
            let secondCoefficient = try projected(cross(first, axis, usage: &scoped), usage: &scoped)
            values.append(try secondCoefficient.negated(maximumDepth: depth, usage: &scoped))
            if source.kind == .torus {
                values.append(try projected(cross(first, second, usage: &scoped), usage: &scoped))
            }
        case .sphere:
            values.append(try projected(first, usage: &scoped))
            values.append(try projected(second, usage: &scoped))
            values.append(try projected(axis, usage: &scoped))
        }
        coefficients = values; maximumAlgebraicDepth = depth
    }

    func provesIdenticallyZero(usage: inout SurfaceSilhouetteUsage) throws -> Bool {
        var admission = SurfaceSilhouetteAlgebraicAdmission(usage: usage)
        defer { usage = admission.usage }
        var scoped = RationalCoefficientDepthAdmission(base: admission, maximumDepth: maximumAlgebraicDepth)
        defer { admission = scoped.base }
        for coefficient in coefficients {
            try scoped.consumeExactWork(1)
            if case .zero = try coefficient.sign(maximumDepth: maximumAlgebraicDepth, usage: &scoped) { continue }
            return false
        }
        return true
    }
}

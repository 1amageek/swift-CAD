import CADCore

/// Original ideal circular coefficients transformed before harmonic arithmetic.
package struct OriginalAffineWordCircularCoefficients: Sendable {
    let center: IntervalVector3DBounds
    let cosine: IntervalVector3DBounds
    let sine: IntervalVector3DBounds
    let parameterDomain: ParameterDomain
    let transport: OriginalAngularParameterTransport

    package static func prepare<B: ExactScalarAdmission & ~Copyable>(source: Curve3D,
        word: PreparedOriginalAffineOperationWord, tolerance: ModelingTolerance,
        usage: inout B, admitPhysicalMetric: Bool = true) throws -> Self? {
        let primitive: Curve3D, transport: OriginalAngularParameterTransport
        if case .originalAngularTransport(let image) = source { primitive = image.source; transport = image.transport }
        else { primitive = source; transport = .intrinsic }
        try transport.validate(usage: &usage)
        let origin: Point3D, first: Vector3D, second: Vector3D, firstRadius: Double, secondRadius: Double
        switch primitive {
        case .circle(let circle):
            try circle.center.validate(); try circle.normal.validateUnitLength(tolerance: tolerance)
            let basis = try circleOrthonormalBasis(circle.normal, tolerance: tolerance)
            origin = circle.center; first = basis.0; second = basis.1
            firstRadius = circle.radius; secondRadius = circle.radius
        case .analytic(.circle(let center, let normal, let radius)),
             .analytic(.arc(let center, let normal, let radius, _, _)):
            try center.validate(); try normal.validateUnitLength(tolerance: tolerance)
            if case .analytic(.arc(_, _, _, let start, let end)) = primitive {
                let width = OutwardScalarInterval.exact(end) - .exact(start)
                guard start.isFinite, end.isFinite, end > start, width.upper <= 2 * Double.pi + tolerance.angle else {
                    throw GeometryError.invalidAngle(end - start)
                }
            }
            let basis = try analyticOrthonormalBasis(normal, tolerance: tolerance)
            origin = center; first = basis.u; second = basis.v
            firstRadius = radius; secondRadius = radius
        case .analytic(.ellipse(let center, let normal, let majorAxis, let major, let minor)):
            try center.validate(); try normal.validateUnitLength(tolerance: tolerance)
            try majorAxis.validateUnitLength(tolerance: tolerance)
            guard abs(normal.dot(majorAxis)) <= tolerance.angle, major >= minor else {
                throw GeometryConversionError.invalidInput("Original ellipse needs its perpendicular ordered axes.")
            }
            origin = center; first = majorAxis
            second = try normal.cross(majorAxis).normalized(tolerance: tolerance.distance)
            firstRadius = major; secondRadius = minor
        default: return nil
        }
        guard firstRadius.isFinite, secondRadius.isFinite, firstRadius > 0, secondRadius > 0 else {
            throw GeometryError.invalidRadius(min(firstRadius, secondRadius))
        }
        try RationalAlgebraStorage.retain(2, of: Vector3D.self, usage: &usage)
        try RationalAlgebraStorage.retain(2, of: Double.self, usage: &usage)
        guard try !admitPhysicalMetric || word.minimumImageLengthIsGreaterThan(originalAxes: [first, second],
            originalLengths: [firstRadius, secondRadius], physicalThreshold: tolerance.distance, usage: &usage) else {
            throw GeometryError.invalidRadius(min(firstRadius, secondRadius))
        }
        func bounds(_ value: CoordinateEnclosure3D) -> IntervalVector3DBounds {
            .init(x: .init(lower: value.x.lower, upper: value.x.upper),
                y: .init(lower: value.y.lower, upper: value.y.upper), z: .init(lower: value.z.lower, upper: value.z.upper))
        }
        try RationalAlgebraStorage.retain(1, of: Self.self, usage: &usage)
        return try .init(center: bounds(word.enclosure(of: .init(
                x: .init(lower: origin.x, upper: origin.x), y: .init(lower: origin.y, upper: origin.y),
                z: .init(lower: origin.z, upper: origin.z)), isPosition: true, usage: &usage)),
            cosine: bounds(word.enclosure(ofOriginalVector: first, originalScale: firstRadius, usage: &usage)),
            sine: bounds(word.enclosure(ofOriginalVector: second, originalScale: secondRadius, usage: &usage)),
            parameterDomain: source.parameterDomain, transport: transport)
    }

    package func replacingTransport(_ transport: OriginalAngularParameterTransport, parameterDomain: ParameterDomain) -> Self {
        .init(center: center, cosine: cosine, sine: sine, parameterDomain: parameterDomain, transport: transport)
    }

    // FIXME(INCOMPLETE_IMPLEMENTATION): Original world-scaled primitive jets
    // retain radius action before harmonics and charge phase reduction/range visits.
    // Full primitive/source-family coverage and behavioral containment/exhaustion
    // verification remain required before declaring the bounded image domain complete.
    package func intervalTaylorJet<A: ExactScalarAdmission & ~Copyable>(over range: ScalarInterval, throughOrder order: Int,
        tolerance: ModelingTolerance, using execution: inout A) throws -> SurfaceAreaIntervalTaylorVectorJet {
        guard order >= 0, range.lower.isFinite, range.upper.isFinite else {
            throw GeometryConversionError.invalidInput("Original circular coefficient query needs finite stations and order.")
        }
        if case .closed(let lower, let upper) = parameterDomain {
            guard range.lower >= lower, range.upper <= upper else {
                throw GeometryConversionError.invalidInput("Original world circular chart exceeds its authored domain.")
            }
        }
        try execution.consumeWork(1)
        let cosineField = try transport.harmonic(over: range, cosine: true, using: &execution)
        let c = cosineField.value
        let s = try transport.harmonic(over: range, cosine: false, using: &execution).value
        func field(_ origin: OutwardScalarInterval, _ a: OutwardScalarInterval,
            _ b: OutwardScalarInterval) throws -> SurfaceAreaIntervalTaylorScalarJet {
            var result = try SurfaceAreaIntervalTaylorScalarJet(order: order, axis: .u,
                tolerance: tolerance, using: &execution)
            var scale = OutwardScalarInterval.exact(1), factorial = OutwardScalarInterval.exact(1)
            for k in 0...order {
                try execution.consumeWork(1)
                if k > 0 { scale = scale * cosineField.gain; factorial = factorial * .exact(Double(k)) }
                let harmonic: OutwardScalarInterval
                switch k % 4 {
                case 0: harmonic = a * c + b * s
                case 1: harmonic = -a * s + b * c
                case 2: harmonic = -a * c - b * s
                default: harmonic = a * s - b * c
                }
                guard let value = (harmonic * scale).divided(by: factorial), value.isFinite else {
                    throw GeometryConversionError.resourceLimitExceeded("Original world circular coefficient derivative is not finite.")
                }
                try result.set(k == 0 ? origin + value : value, k, 0)
            }
            return result
        }
        return try .init(x: field(center.x, cosine.x, sine.x), y: field(center.y, cosine.y, sine.y), z: field(center.z, cosine.z, sine.z))
    }
}

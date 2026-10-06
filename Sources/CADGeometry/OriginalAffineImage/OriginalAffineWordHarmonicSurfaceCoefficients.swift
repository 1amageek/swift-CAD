import CADCore

/// World coefficients of an original periodic primitive, before harmonic arithmetic.
package struct OriginalAffineWordHarmonicSurfaceCoefficients: Sendable {
    package enum Kind: Sendable, Equatable { case cylinder, sphere, torus }
    private let kind: Kind
    private let majorRadius: Double
    private let minorRadius: Double
    private let gaugeWord: PreparedOriginalAffineOperationWord
    private let uTransport: OriginalAngularParameterTransport
    private let vTransport: OriginalAngularParameterTransport
    private let center: IntervalVector3DBounds
    private let majorCosine: IntervalVector3DBounds
    private let majorSine: IntervalVector3DBounds
    private let minorCosine: IntervalVector3DBounds
    private let minorSine: IntervalVector3DBounds
    private let axial: IntervalVector3DBounds
    private let firstDirection: Vector3D
    private let secondDirection: Vector3D
    private let axisDirection: Vector3D

    /// Original basis and dimensions, with exact cofactor source authority.
    package var originalNormalGauge: (kind: Kind, firstDirection: Vector3D,
        secondDirection: Vector3D, axisDirection: Vector3D, majorRadius: Double,
        minorRadius: Double, uTransport: OriginalAngularParameterTransport,
        vTransport: OriginalAngularParameterTransport, word: PreparedOriginalAffineOperationWord) {
        (kind, firstDirection, secondDirection, axisDirection, majorRadius, minorRadius,
            uTransport, vTransport, gaugeWord)
    }

    package static func prepare<B: RationalAlgebraAdmitting>(source: Surface3D,
        word: PreparedOriginalAffineOperationWord, tolerance: ModelingTolerance,
        usage: inout B, admitPhysicalMetric: Bool = true) throws -> Self? {
        if case .procedural(.originalImage(let image)) = source,
            image.uParameterGain == .binary(1), image.vParameterGain == .binary(1),
            image.uOffset == 0, image.vOffset == 0, !image.swapAxes {
            let base: Surface3D
            if case .procedural(.originalAngularTransport(let angular)) = image.source { base = angular.source }
            else { base = image.source }
            switch base {
            case .cylinder, .analytic(.cylinder), .analytic(.sphere), .analytic(.torus):
                let count = word.source.factors.count.addingReportingOverflow(1)
                guard !count.overflow else {
                    throw GeometryConversionError.resourceLimitExceeded("Original harmonic image factor count overflows.")
                }
                try RationalAlgebraStorage.retain(count.partialValue, of: OriginalAffineOperation.self, usage: &usage)
                var factors: [OriginalAffineOperation] = []
                factors.reserveCapacity(count.partialValue)
                factors.append(.forward(image.transform))
                for factor in word.source.factors { try usage.consumeExactWork(1); factors.append(factor) }
                let effective = try OriginalAffineOperationWord(factors: factors, tolerance: tolerance,
                    maximumDepth: word.source.maximumDepth, usage: &usage).prepared(usage: &usage)
                return try prepare(source: image.source, word: effective, tolerance: tolerance,
                    usage: &usage, admitPhysicalMetric: admitPhysicalMetric)
            default: return nil
            }
        }
        let primitive: Surface3D, uTransport: OriginalAngularParameterTransport, vTransport: OriginalAngularParameterTransport
        if case .procedural(.originalAngularTransport(let image)) = source {
            primitive = image.source; uTransport = image.uTransport; vTransport = image.vTransport
        } else { primitive = source; uTransport = .intrinsic; vTransport = .intrinsic }
        try uTransport.validate(usage: &usage); try vTransport.validate(usage: &usage)
        let kind: Kind, origin: Point3D, axis: Vector3D, first: Vector3D, second: Vector3D
        let major: Double, minor: Double
        switch primitive {
        case .cylinder(let value):
            try value.origin.validate(); try value.axis.validateUnitLength(tolerance: tolerance)
            let basis = try circleOrthonormalBasis(value.axis, tolerance: tolerance)
            kind = .cylinder; origin = value.origin; axis = value.axis
            first = basis.0; second = basis.1; major = value.radius; minor = 0
        case .analytic(.cylinder(let point, let normal, let radius)):
            try point.validate(); try normal.validateUnitLength(tolerance: tolerance)
            let basis = try analyticOrthonormalBasis(normal, tolerance: tolerance)
            kind = .cylinder; origin = point; axis = normal
            first = basis.u; second = basis.v; major = radius; minor = 0
        case .analytic(.sphere(let point, let radius)):
            try point.validate()
            let basis = try analyticOrthonormalBasis(.unitZ, tolerance: tolerance)
            kind = .sphere; origin = point; axis = .unitZ
            first = basis.u; second = basis.v; major = 0; minor = radius
        case .analytic(.torus(let point, let normal, let outer, let tube)):
            try point.validate(); try normal.validateUnitLength(tolerance: tolerance)
            let basis = try analyticOrthonormalBasis(normal, tolerance: tolerance)
            kind = .torus; origin = point; axis = normal
            first = basis.u; second = basis.v; major = outer; minor = tube
        default: return nil
        }
        try usage.consumeExactWork(1)
        guard major.isFinite, minor.isFinite,
            kind == .sphere ? minor > 0 : major > 0,
            kind != .torus || minor > 0 && major > minor else {
            throw GeometryConversionError.invalidInput("Original harmonic support requires finite positive primitive radii.")
        }
        func reserveAxes(_ count: Int) throws {
            try RationalAlgebraStorage.retain(count, of: Vector3D.self, usage: &usage)
            try RationalAlgebraStorage.retain(count, of: Double.self, usage: &usage)
        }
        if admitPhysicalMetric, kind != .sphere {
            try reserveAxes(2)
            guard try word.minimumImageLengthIsGreaterThan(originalAxes: [first, second],
                originalLengths: [major, major], physicalThreshold: tolerance.distance, usage: &usage) else {
                throw GeometryError.invalidRadius(major)
            }
        }
        if admitPhysicalMetric, kind != .cylinder {
            try reserveAxes(3)
            guard try word.minimumImageLengthIsGreaterThan(originalAxes: [first, second, axis],
                originalLengths: [minor, minor, minor], physicalThreshold: tolerance.distance, usage: &usage) else {
                throw GeometryError.invalidRadius(minor)
            }
        }
        if admitPhysicalMetric, kind == .torus {
            try RationalAlgebraStorage.retain(2, of: Vector3D.self, usage: &usage)
            guard try word.minimumProjectedImageDifferenceIsGreaterThan(originalAxes: [first, second],
                originalAxis: axis, originalLower: minor, originalUpper: major,
                physicalThreshold: tolerance.distance, usage: &usage) else {
                throw GeometryConversionError.invalidInput("Original transformed torus has insufficient exact central clearance.")
            }
        }
        func bounds(_ value: CoordinateEnclosure3D) -> IntervalVector3DBounds {
            .init(x: .init(lower: value.x.lower, upper: value.x.upper),
                y: .init(lower: value.y.lower, upper: value.y.upper), z: .init(lower: value.z.lower, upper: value.z.upper))
        }
        func vector(_ direction: Vector3D, _ length: Double) throws -> IntervalVector3DBounds {
            bounds(try word.enclosure(ofOriginalVector: direction, originalScale: length, usage: &usage))
        }
        let zero = IntervalVector3DBounds(x: .exact(0), y: .exact(0), z: .exact(0))
        let point = try word.enclosure(of: .init(x: .init(lower: origin.x, upper: origin.x),
            y: .init(lower: origin.y, upper: origin.y), z: .init(lower: origin.z, upper: origin.z)),
            isPosition: true, usage: &usage)
        let largeC = kind == .sphere ? zero : try vector(first, major)
        let largeS = kind == .sphere ? zero : try vector(second, major)
        let smallC = kind == .cylinder ? zero : try vector(first, minor)
        let smallS = kind == .cylinder ? zero : try vector(second, minor)
        let axial = try vector(axis, kind == .cylinder ? 1 : minor)
        try RationalAlgebraStorage.retain(1, of: Self.self, usage: &usage)
        return .init(kind: kind, majorRadius: major, minorRadius: minor, gaugeWord: word, uTransport: uTransport, vTransport: vTransport, center: bounds(point), majorCosine: largeC, majorSine: largeS,
            minorCosine: smallC, minorSine: smallS, axial: axial,
            firstDirection: first, secondDirection: second, axisDirection: axis)
    }

    package func replacingTransports(u: OriginalAngularParameterTransport, v: OriginalAngularParameterTransport) -> Self {
        .init(kind: kind, majorRadius: majorRadius, minorRadius: minorRadius, gaugeWord: gaugeWord, uTransport: u, vTransport: v, center: center, majorCosine: majorCosine, majorSine: majorSine,
            minorCosine: minorCosine, minorSine: minorSine, axial: axial, firstDirection: firstDirection,
            secondDirection: secondDirection, axisDirection: axisDirection)
    }

    package func collapsedSpherePosition(over box: SurfaceParameterBox) -> IntervalVector3DBounds? {
        guard kind == .sphere, vTransport.isIntrinsic, box.v.lower == box.v.upper,
            box.v.lower == Double.pi * 0.5 || box.v.lower == -Double.pi * 0.5 else { return nil }
        return center + axial * .exact(box.v.lower > 0 ? 1 : -1)
    }

    /// Removes only the original positive primitive scalar factors.
    package func normalField<B: RationalAlgebraAdmitting>(over box: SurfaceParameterBox,
        word: PreparedOriginalAffineOperationWord, usage: inout B) throws -> IntervalVector3DBounds {
        try usage.consumeExactWork(1)
        let cu = try uTransport.harmonic(over: box.u, cosine: true, consumeWork: { try usage.consumeExactWork(1) }).value
        let su = try uTransport.harmonic(over: box.u, cosine: false, consumeWork: { try usage.consumeExactWork(1) }).value
        func raw(_ value: Vector3D) -> IntervalVector3DBounds {
            .init(x: .exact(value.x), y: .exact(value.y), z: .exact(value.z))
        }
        let first = raw(firstDirection), second = raw(secondDirection), axis = raw(axisDirection)
        let radial = first * cu + second * su
        let field: IntervalVector3DBounds
        if kind == .sphere {
            guard vTransport.isIntrinsic, box.v.lower >= -Double.pi * 0.5, box.v.upper <= Double.pi * 0.5 else {
                throw GeometryConversionError.invalidInput("Original sphere normal exceeds its closed latitude domain.")
            }
            let cv = try vTransport.harmonic(over: box.v, cosine: true, consumeWork: { try usage.consumeExactWork(1) }).value
            let sv = try vTransport.harmonic(over: box.v, cosine: false, consumeWork: { try usage.consumeExactWork(1) }).value
            field = radial * cv + axis * sv
        } else {
            let tangent = first * (-su) + second * cu
            if kind == .cylinder { field = tangent.cross(axis) }
            else {
                let cv = try vTransport.harmonic(over: box.v, cosine: true, consumeWork: { try usage.consumeExactWork(1) }).value
                let sv = try vTransport.harmonic(over: box.v, cosine: false, consumeWork: { try usage.consumeExactWork(1) }).value
                field = tangent.cross(radial * (-sv) + axis * cv)
            }
        }
        let orientation = try uTransport.orientationSign(usage: &usage) * vTransport.orientationSign(usage: &usage)
        let directed = field * .exact(Double(orientation))
        let result = try gaugeWord.applyingCofactor(to: .init(x: .init(lower: directed.x.lower, upper: directed.x.upper),
            y: .init(lower: directed.y.lower, upper: directed.y.upper), z: .init(lower: directed.z.lower, upper: directed.z.upper)), usage: &usage)
        return .init(x: .init(lower: result.x.lower, upper: result.x.upper),
            y: .init(lower: result.y.lower, upper: result.y.upper), z: .init(lower: result.z.lower, upper: result.z.upper))
    }

    package func intervalTaylorJet(over box: SurfaceParameterBox, throughOrder order: Int,
        tolerance: ModelingTolerance, consumeWork: () throws -> Void,
        consumeStorage: ((Int) throws -> Void)? = nil) throws -> SurfaceAreaIntervalTaylorVectorJet {
        guard order >= 0, box.u.lower.isFinite, box.u.upper.isFinite,
            box.v.lower.isFinite, box.v.upper.isFinite else {
            throw GeometryConversionError.invalidInput("Original harmonic world query needs finite parameter bounds.")
        }
        if kind == .sphere {
            guard vTransport.isIntrinsic, box.v.lower >= -Double.pi * 0.5, box.v.upper <= Double.pi * 0.5 else {
                throw GeometryConversionError.invalidInput("Original sphere latitude exceeds its canonical closed domain.")
            }
        }
        func harmonic(_ range: ScalarInterval, alongU: Bool, cosine: Bool) throws -> SurfaceAreaIntervalTaylorScalarJet {
            let transport = alongU ? uTransport : vTransport
            let cosineField = try transport.harmonic(over: range, cosine: true, consumeWork: consumeWork, consumeStorage: consumeStorage)
            let c = cosineField.value
            let s = try transport.harmonic(over: range, cosine: false, consumeWork: consumeWork, consumeStorage: consumeStorage).value
            var result = try SurfaceAreaIntervalTaylorScalarJet(order: order, axis: alongU ? .u : .v,
                tolerance: tolerance, consumeWork: consumeWork, consumeStorage: consumeStorage)
            var gain = OutwardScalarInterval.exact(1), factorial = OutwardScalarInterval.exact(1)
            for k in 0...order {
                try consumeWork()
                if k > 0 { gain = gain * cosineField.gain; factorial = factorial * .exact(Double(k)) }
                let value: OutwardScalarInterval
                switch (k + (cosine ? 0 : 3)) % 4 {
                case 0: value = c
                case 1: value = -s
                case 2: value = -c
                default: value = s
                }
                guard let coefficient = (value * gain).divided(by: factorial), coefficient.isFinite else {
                    throw GeometryConversionError.resourceLimitExceeded("Original world harmonic coefficient is not finite.")
                }
                try result.set(coefficient, alongU ? k : 0, alongU ? 0 : k)
            }
            return result
        }
        let cu = try harmonic(box.u, alongU: true, cosine: true)
        let su = try harmonic(box.u, alongU: true, cosine: false)
        let cv = kind == .cylinder ? nil : try harmonic(box.v, alongU: false, cosine: true)
        let sv = kind == .cylinder ? nil : try harmonic(box.v, alongU: false, cosine: false)
        func field(_ point: OutwardScalarInterval, _ largeC: OutwardScalarInterval,
            _ largeS: OutwardScalarInterval, _ smallC: OutwardScalarInterval,
            _ smallS: OutwardScalarInterval, _ axis: OutwardScalarInterval) throws -> SurfaceAreaIntervalTaylorScalarJet {
            var result = try SurfaceAreaIntervalTaylorScalarJet.constant(point, order: order,
                tolerance: tolerance, consumeWork: consumeWork, consumeStorage: consumeStorage)
            if kind != .sphere {
                let radial = try cu.scaled(by: largeC, consumeWork: consumeWork, consumeStorage: consumeStorage)
                    .adding(su.scaled(by: largeS, consumeWork: consumeWork, consumeStorage: consumeStorage),
                        consumeWork: consumeWork, consumeStorage: consumeStorage)
                result = try result.adding(radial, consumeWork: consumeWork, consumeStorage: consumeStorage)
            }
            if let cv, let sv {
                let radial = try cu.scaled(by: smallC, consumeWork: consumeWork, consumeStorage: consumeStorage)
                    .adding(su.scaled(by: smallS, consumeWork: consumeWork, consumeStorage: consumeStorage),
                        consumeWork: consumeWork, consumeStorage: consumeStorage)
                result = try result.adding(radial.multiplied(by: cv, consumeWork: consumeWork, consumeStorage: consumeStorage),
                    consumeWork: consumeWork, consumeStorage: consumeStorage)
                    .adding(sv.scaled(by: axis, consumeWork: consumeWork, consumeStorage: consumeStorage),
                        consumeWork: consumeWork, consumeStorage: consumeStorage)
            } else {
                var height = try SurfaceAreaIntervalTaylorScalarJet(order: order, axis: .v,
                    tolerance: tolerance, consumeWork: consumeWork, consumeStorage: consumeStorage)
                try height.set(.init(lower: box.v.lower, upper: box.v.upper), 0, 0)
                if order > 0 { try height.set(.exact(1), 0, 1) }
                result = try result.adding(height.scaled(by: axis, consumeWork: consumeWork, consumeStorage: consumeStorage),
                    consumeWork: consumeWork, consumeStorage: consumeStorage)
            }
            return result
        }
        return try .init(x: field(center.x, majorCosine.x, majorSine.x, minorCosine.x, minorSine.x, axial.x),
            y: field(center.y, majorCosine.y, majorSine.y, minorCosine.y, minorSine.y, axial.y),
            z: field(center.z, majorCosine.z, majorSine.z, minorCosine.z, minorSine.z, axial.z))
    }
}

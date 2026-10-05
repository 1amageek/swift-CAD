import CADCore

/// Persistent four-boundary source law, independent of a rounded tensor image.
public struct OriginalCoonsSurface3D: Hashable, Sendable {
    public let vMinimumBoundary: OriginalCurveRootSpan3D
    public let vMaximumBoundary: OriginalCurveRootSpan3D
    public let uMinimumBoundary: OriginalCurveRootSpan3D
    public let uMaximumBoundary: OriginalCurveRootSpan3D
    private let corners: [SurfaceIntervalVectorJet]
    private let hasPiecewiseFirstOrderAuthority: Bool

    public init<B: RationalAlgebraAdmitting>(vMinimumBoundary: OriginalCurveRootSpan3D,
        vMaximumBoundary: OriginalCurveRootSpan3D, uMinimumBoundary: OriginalCurveRootSpan3D,
        uMaximumBoundary: OriginalCurveRootSpan3D, tolerance: ModelingTolerance, usage: inout B) throws {
        try Task.checkCancellation(); try tolerance.validate()
        try Self.retainElements(4, of: OriginalCurveRootSpan3D.self, minimumWords: 4, usage: &usage)
        let boundaries = [vMinimumBoundary, vMaximumBoundary, uMinimumBoundary, uMaximumBoundary]
        guard boundaries.allSatisfy({ $0.certificationTolerance == tolerance }) else {
            throw GeometryConversionError.invalidInput("Original Coons boundaries must retain one preparation tolerance.")
        }
        let incidence = OriginalCoonsCornerIncidence()
        func admit(_ a: OriginalCurveRootSpan3D, _ ae: Bool,
            _ b: OriginalCurveRootSpan3D, _ be: Bool) throws {
            guard try incidence.proves(first: a, firstAtEnd: ae, second: b, secondAtEnd: be, usage: &usage) else {
                throw GeometryConversionError.invalidInput("Original Coons boundaries have unequal original corner positions.")
            }
        }
        try admit(vMinimumBoundary, false, uMinimumBoundary, false)
        try admit(vMinimumBoundary, true, uMaximumBoundary, false)
        try admit(vMaximumBoundary, false, uMinimumBoundary, true)
        try admit(vMaximumBoundary, true, uMaximumBoundary, true)
        var continuous = true
        for boundary in boundaries {
            if try !OriginalCurveTraversalContinuityAdmission().proves(boundary, usage: &usage) { continuous = false }
        }
        try Self.retainElements(4, of: SurfaceIntervalVectorJet.self, minimumWords: 240, usage: &usage)
        var originalCorners: [SurfaceIntervalVectorJet] = []
        originalCorners.reserveCapacity(4)
        for boundaryIndex in 0..<2 {
            let boundary = boundaryIndex == 0 ? vMinimumBoundary : vMaximumBoundary
            for stationIndex in 0..<2 {
                let station = Double(stationIndex)
                let q = try boundary.intervalTaylorJet(over: .init(lower: station, upper: station), throughOrder: 0,
                    tolerance: tolerance, storageByteStride: MemoryLayout<UInt32>.stride, usage: &usage,
                    remainingSourceDepth: boundary.remainingSourceDepth)
                originalCorners.append(try .init(x: Self.constant(q.x.coefficient(0, 0)),
                    y: Self.constant(q.y.coefficient(0, 0)), z: Self.constant(q.z.coefficient(0, 0))))
            }
        }
        self.vMinimumBoundary = vMinimumBoundary; self.vMaximumBoundary = vMaximumBoundary
        self.uMinimumBoundary = uMinimumBoundary; self.uMaximumBoundary = uMaximumBoundary
        corners = originalCorners
        hasPiecewiseFirstOrderAuthority = continuous
    }

    private static func retainElements<B: RationalAlgebraAdmitting, T>(_ count: Int,
        of type: T.Type, minimumWords: Int, usage: inout B) throws {
        let bytes = count.multipliedReportingOverflow(by: MemoryLayout<T>.stride)
        let rounded = bytes.partialValue.addingReportingOverflow(MemoryLayout<UInt32>.stride - 1)
        guard count >= 0, !bytes.overflow, !rounded.overflow else {
            throw GeometryConversionError.resourceLimitExceeded("Original Coons retained value dimensions overflow.")
        }
        try usage.retainExactStorage(max(minimumWords, rounded.partialValue / MemoryLayout<UInt32>.stride))
    }

    public var uDomain: ParameterDomain { .closed(0, 1) }
    public var vDomain: ParameterDomain { .closed(0, 1) }
    public var certificationTolerance: ModelingTolerance { vMinimumBoundary.certificationTolerance }
    var hasOriginalPositionContinuity: Bool { hasPiecewiseFirstOrderAuthority }

    private static func constant(_ value: OutwardScalarInterval) -> SurfaceIntervalJet {
        let z = OutwardScalarInterval.exact(0)
        return .init(value: value, derivativeU: z, derivativeV: z,
            secondDerivativeUU: z, secondDerivativeUV: z, secondDerivativeVV: z,
            thirdDerivativeUUU: z, thirdDerivativeUUV: z, thirdDerivativeUVV: z, thirdDerivativeVVV: z)
    }

    public func validate(tolerance: ModelingTolerance) throws {
        try tolerance.validate()
        guard tolerance == certificationTolerance, corners.count == 4 else {
            throw GeometryConversionError.invalidInput("Original Coons queries require the immutable source tolerance.")
        }
    }

    public static func == (a: Self, b: Self) -> Bool {
        a.vMinimumBoundary == b.vMinimumBoundary && a.vMaximumBoundary == b.vMaximumBoundary
            && a.uMinimumBoundary == b.uMinimumBoundary && a.uMaximumBoundary == b.uMaximumBoundary
    }
    public func hash(into hasher: inout Hasher) {
        hasher.combine(vMinimumBoundary); hasher.combine(vMaximumBoundary)
        hasher.combine(uMinimumBoundary); hasher.combine(uMaximumBoundary)
    }

    package func intervalJet(over box: SurfaceParameterBox, tolerance: ModelingTolerance,
        consumeWork: () throws -> Void = {}, consumeStorage: ((Int) throws -> Void)? = nil,
        maximumSpanCount: Int = Int.max, remainingSourceDepth: Int = Int.max) throws -> SurfaceIntervalVectorJet {
        let t = try intervalTaylorJet(over: box, throughOrder: 3, tolerance: tolerance, consumeWork: consumeWork,
            consumeStorage: consumeStorage, maximumSpanCount: maximumSpanCount, remainingSourceDepth: remainingSourceDepth)
        for _ in 0..<30 { try Task.checkCancellation(); try consumeWork() }
        return try t.intervalJet()
    }

    package func intervalTaylorJet<B: RationalAlgebraAdmitting>(over box: SurfaceParameterBox,
        throughOrder order: Int, tolerance: ModelingTolerance, storageByteStride: Int, usage: inout B,
        maximumSpanCount: Int, remainingSourceDepth: Int) throws -> SurfaceAreaIntervalTaylorVectorJet {
        guard storageByteStride > 0 else {
            throw GeometryConversionError.invalidInput("Original Coons query storage stride must be positive.")
        }
        func storage(_ bytes: Int) throws {
            let rounded = bytes.addingReportingOverflow(storageByteStride - 1)
            guard bytes >= 0, !rounded.overflow else {
                throw GeometryConversionError.resourceLimitExceeded("Original Coons query storage conversion overflows.")
            }
            try usage.retainExactStorage(rounded.partialValue / storageByteStride)
        }
        return try withoutActuallyEscaping(storage) { admittedStorage in
            try intervalTaylorJet(over: box, throughOrder: order, tolerance: tolerance,
                consumeWork: { try usage.consumeExactWork(1) }, consumeStorage: admittedStorage,
                maximumSpanCount: maximumSpanCount, remainingSourceDepth: remainingSourceDepth)
        }
    }

    package func intervalTaylorJet(over box: SurfaceParameterBox, throughOrder order: Int,
        tolerance: ModelingTolerance, consumeWork: () throws -> Void,
        consumeStorage: ((Int) throws -> Void)? = nil, maximumSpanCount: Int = Int.max,
        remainingSourceDepth: Int = Int.max) throws -> SurfaceAreaIntervalTaylorVectorJet {
        func work() throws { try Task.checkCancellation(); try consumeWork() }
        try work(); try validate(tolerance: tolerance)
        guard order >= 0, maximumSpanCount > 0, remainingSourceDepth >= 0, box.u.lower >= 0, box.u.upper <= 1, box.v.lower >= 0, box.v.upper <= 1 else {
            throw GeometryConversionError.invalidInput("Original Coons Taylor query exceeds its normalized source square.")
        }
        let bottom = try vMinimumBoundary.intervalTaylorJet(over: box.u, throughOrder: order,
            tolerance: tolerance, consumeWork: work, maximumSpanCount: maximumSpanCount,
            remainingSourceDepth: remainingSourceDepth, consumeStorage: consumeStorage)
        let top = try vMaximumBoundary.intervalTaylorJet(over: box.u, throughOrder: order,
            tolerance: tolerance, consumeWork: work, maximumSpanCount: maximumSpanCount,
            remainingSourceDepth: remainingSourceDepth, consumeStorage: consumeStorage)
        let left = try uMinimumBoundary.intervalTaylorJet(over: box.v, throughOrder: order,
            tolerance: tolerance, consumeWork: work, maximumSpanCount: maximumSpanCount,
            remainingSourceDepth: remainingSourceDepth, consumeStorage: consumeStorage)
        let right = try uMaximumBoundary.intervalTaylorJet(over: box.v, throughOrder: order,
            tolerance: tolerance, consumeWork: work, maximumSpanCount: maximumSpanCount,
            remainingSourceDepth: remainingSourceDepth, consumeStorage: consumeStorage)
        func alongV(_ q: SurfaceAreaIntervalTaylorScalarJet) throws -> SurfaceAreaIntervalTaylorScalarJet {
            var r = try SurfaceAreaIntervalTaylorScalarJet(order: order, axis: .v,
                tolerance: tolerance, consumeWork: work, consumeStorage: consumeStorage)
            for k in 0...order { try work(); try r.set(q.coefficient(k, 0), 0, k) }
            return r
        }
        let l = try SurfaceAreaIntervalTaylorVectorJet(x: alongV(left.x), y: alongV(left.y), z: alongV(left.z))
        let r = try SurfaceAreaIntervalTaylorVectorJet(x: alongV(right.x), y: alongV(right.y), z: alongV(right.z))
        func scalar(_ value: OutwardScalarInterval) throws -> SurfaceAreaIntervalTaylorScalarJet {
            try .constant(value, order: order, tolerance: tolerance, consumeWork: work, consumeStorage: consumeStorage)
        }
        func parameter(_ range: ScalarInterval, alongU: Bool) throws -> SurfaceAreaIntervalTaylorScalarJet {
            var q = try SurfaceAreaIntervalTaylorScalarJet.constant(.init(lower: range.lower, upper: range.upper),
                order: order, axis: alongU ? .u : .v, tolerance: tolerance, consumeWork: work, consumeStorage: consumeStorage)
            if order > 0 { try work(); try q.set(.exact(1), alongU ? 1 : 0, alongU ? 0 : 1) }
            return q
        }
        let u = try parameter(box.u, alongU: true), v = try parameter(box.v, alongU: false)
        let one = try scalar(.exact(1))
        let um = try one.subtracting(u, consumeWork: work, consumeStorage: consumeStorage), vm = try one.subtracting(v, consumeWork: work, consumeStorage: consumeStorage)
        func corner(_ index: Int) throws -> SurfaceAreaIntervalTaylorVectorJet {
            try .init(x: scalar(corners[index].x.value), y: scalar(corners[index].y.value), z: scalar(corners[index].z.value))
        }
        func multiply(_ q: SurfaceAreaIntervalTaylorVectorJet,
            _ scalar: SurfaceAreaIntervalTaylorScalarJet) throws -> SurfaceAreaIntervalTaylorVectorJet {
            try .init(x: q.x.multiplied(by: scalar, consumeWork: work, consumeStorage: consumeStorage),
                y: q.y.multiplied(by: scalar, consumeWork: work, consumeStorage: consumeStorage),
                z: q.z.multiplied(by: scalar, consumeWork: work, consumeStorage: consumeStorage))
        }
        func add(_ a: SurfaceAreaIntervalTaylorVectorJet,
            _ b: SurfaceAreaIntervalTaylorVectorJet) throws -> SurfaceAreaIntervalTaylorVectorJet {
            try .init(x: a.x.adding(b.x, consumeWork: work, consumeStorage: consumeStorage),
                y: a.y.adding(b.y, consumeWork: work, consumeStorage: consumeStorage),
                z: a.z.adding(b.z, consumeWork: work, consumeStorage: consumeStorage))
        }
        let b00 = try multiply(multiply(corner(0), um), vm)
        let b10 = try multiply(multiply(corner(1), u), vm)
        let b01 = try multiply(multiply(corner(2), um), v)
        let b11 = try multiply(multiply(corner(3), u), v)
        let bilinear = try add(add(add(b00, b10), b01), b11)
        let negative = try SurfaceAreaIntervalTaylorVectorJet(
            x: bilinear.x.scaled(by: .exact(-1), consumeWork: work, consumeStorage: consumeStorage),
            y: bilinear.y.scaled(by: .exact(-1), consumeWork: work, consumeStorage: consumeStorage),
            z: bilinear.z.scaled(by: .exact(-1), consumeWork: work, consumeStorage: consumeStorage))
        var result = try add(add(add(add(multiply(bottom, vm), multiply(top, v)),
            multiply(l, um)), multiply(r, u)), negative)
        let boundary: SurfaceAreaIntervalTaylorVectorJet?
        if box.v.width == 0, box.v.lower == 0 { boundary = bottom }
        else if box.v.width == 0, box.v.lower == 1 { boundary = top }
        else if box.u.width == 0, box.u.lower == 0 { boundary = l }
        else if box.u.width == 0, box.u.lower == 1 { boundary = r }
        else { boundary = nil }
        if let boundary {
            func originalValue(_ q: SurfaceAreaIntervalTaylorScalarJet,
                _ original: SurfaceAreaIntervalTaylorScalarJet) throws -> SurfaceAreaIntervalTaylorScalarJet {
                var out = try SurfaceAreaIntervalTaylorScalarJet(order: order, tolerance: tolerance, consumeWork: work, consumeStorage: consumeStorage)
                for total in 0...order { for a in 0...total {
                    try work(); try out.set(q.coefficient(a, total-a), a, total-a)
                } }
                try work(); try out.set(original.coefficient(0, 0), 0, 0)
                return out
            }
            result = try .init(x: originalValue(result.x, boundary.x), y: originalValue(result.y, boundary.y),
                z: originalValue(result.z, boundary.z))
        }
        return result
    }

    func preparedFirstOrder<B: RationalAlgebraAdmitting>(over box: SurfaceParameterBox,
        maximumSpanCount: Int, maximumSubdivisionDepth: Int, remainingSourceDepth: Int,
        tolerance: ModelingTolerance, storageByteStride: Int, usage: inout B)
        throws -> OriginalSurfaceFirstOrderEnclosure {
        guard storageByteStride > 0 else {
            throw GeometryConversionError.invalidInput("Original Coons first-order storage stride must be positive.")
        }
        func storage(_ bytes: Int) throws {
            let rounded = bytes.addingReportingOverflow(storageByteStride - 1)
            guard bytes >= 0, !rounded.overflow else {
                throw GeometryConversionError.resourceLimitExceeded("Original Coons first-order storage conversion overflows.")
            }
            try usage.retainExactStorage(rounded.partialValue / storageByteStride)
        }
        return try withoutActuallyEscaping(storage) { admittedStorage in
            try preparedFirstOrder(over: box, maximumSpanCount: maximumSpanCount,
                maximumSubdivisionDepth: maximumSubdivisionDepth, remainingSourceDepth: remainingSourceDepth,
                tolerance: tolerance, consumeWork: { try usage.consumeExactWork(1) },
                consumeStorage: admittedStorage)
        }
    }

    func preparedFirstOrder(over box: SurfaceParameterBox, maximumSpanCount: Int,
        maximumSubdivisionDepth: Int, remainingSourceDepth: Int, tolerance: ModelingTolerance,
        consumeWork: () throws -> Void, consumeStorage: ((Int) throws -> Void)? = nil)
        throws -> OriginalSurfaceFirstOrderEnclosure {
        try validate(tolerance: tolerance)
        guard box.u.lower >= 0, box.u.upper <= 1, box.v.lower >= 0, box.v.upper <= 1 else {
            throw GeometryConversionError.invalidInput("Original Coons first-order box exceeds its original square.")
        }
        if !hasPiecewiseFirstOrderAuthority {
            return try .init(intervalTaylorJet(over: box, throughOrder: 1,
                tolerance: tolerance, consumeWork: consumeWork, consumeStorage: consumeStorage,
                maximumSpanCount: maximumSpanCount, remainingSourceDepth: remainingSourceDepth))
        }
        func boundary(_ source: OriginalCurveRootSpan3D, _ range: ScalarInterval) throws -> OriginalCurveFirstOrderJet {
            try source.preparedFirstOrder(over: range, tolerance: tolerance,
                maximumSpanCount: maximumSpanCount, maximumSubdivisionDepth: maximumSubdivisionDepth,
                remainingSourceDepth: remainingSourceDepth, consumeWork: consumeWork,
                consumeStorage: consumeStorage)
        }
        let bottom = try boundary(vMinimumBoundary, box.u), top = try boundary(vMaximumBoundary, box.u)
        let left = try boundary(uMinimumBoundary, box.v), right = try boundary(uMaximumBoundary, box.v)
        for _ in 0..<180 { try Task.checkCancellation(); try consumeWork() }
        let u = OutwardScalarInterval(lower: box.u.lower, upper: box.u.upper)
        let v = OutwardScalarInterval(lower: box.v.lower, upper: box.v.upper)
        let um = OutwardScalarInterval.exact(1) - u, vm = OutwardScalarInterval.exact(1) - v
        func axis(_ field: (IntervalVector3DBounds) -> OutwardScalarInterval,
            cornerField: (SurfaceIntervalVectorJet) -> OutwardScalarInterval) -> OriginalSurfaceFirstOrderEnclosure.Axis {
            let b = field(bottom.position), t = field(top.position), l = field(left.position), r = field(right.position)
            let p00 = cornerField(corners[0]), p10 = cornerField(corners[1])
            let p01 = cornerField(corners[2]), p11 = cornerField(corners[3])
            var value = b * vm + t * v + l * um + r * u
                - (p00 * um * vm + p10 * u * vm + p01 * um * v + p11 * u * v)
            if box.v.width == 0, box.v.lower == 0 { value = b }
            else if box.v.width == 0, box.v.lower == 1 { value = t }
            else if box.u.width == 0, box.u.lower == 0 { value = l }
            else if box.u.width == 0, box.u.lower == 1 { value = r }
            return .init(value: value,
                derivativeU: field(bottom.firstDerivative) * vm + field(top.firstDerivative) * v - l + r
                    - ((p10 - p00) * vm + (p11 - p01) * v),
                derivativeV: -b + t + field(left.firstDerivative) * um + field(right.firstDerivative) * u
                    - ((p01 - p00) * um + (p11 - p10) * u))
        }
        return .init(x: axis({ $0.x }, cornerField: { $0.x.value }),
            y: axis({ $0.y }, cornerField: { $0.y.value }), z: axis({ $0.z }, cornerField: { $0.z.value }))
    }

    public func parameterDerivativesThroughThirdOrder(u: Double, v: Double,
        tolerance: ModelingTolerance) throws -> SurfaceParameterThirdOrderDerivatives {
        try parameterDerivativesThroughThirdOrder(u: u, v: v, tolerance: tolerance, consumeWork: {})
    }
    package func parameterDerivativesThroughThirdOrder(u: Double, v: Double,
        tolerance: ModelingTolerance, consumeWork: () throws -> Void) throws -> SurfaceParameterThirdOrderDerivatives {
        let q = try intervalJet(over: .init(u: .init(lower: u, upper: u), v: .init(lower: v, upper: v)),
            tolerance: tolerance, consumeWork: consumeWork)
        func vector(_ field: (SurfaceIntervalJet) -> OutwardScalarInterval) -> Vector3D {
            .init(x: field(q.x).midpoint, y: field(q.y).midpoint, z: field(q.z).midpoint)
        }
        let p = vector { $0.value }
        let radius = IntervalVector3DBounds(x: q.x.value - .exact(p.x), y: q.y.value - .exact(p.y),
            z: q.z.value - .exact(p.z)).lengthUpperBound
        guard radius.isFinite, radius <= tolerance.distance else { throw GeometryConversionError.toleranceRejected }
        return .init(position: .init(x: p.x, y: p.y, z: p.z), tangentU: vector { $0.derivativeU },
            tangentV: vector { $0.derivativeV }, secondDerivativeUU: vector { $0.secondDerivativeUU },
            secondDerivativeUV: vector { $0.secondDerivativeUV }, secondDerivativeVV: vector { $0.secondDerivativeVV },
            thirdDerivativeUUU: vector { $0.thirdDerivativeUUU }, thirdDerivativeUUV: vector { $0.thirdDerivativeUUV },
            thirdDerivativeUVV: vector { $0.thirdDerivativeUVV }, thirdDerivativeVVV: vector { $0.thirdDerivativeVVV })
    }
    public func parameterDerivatives(u: Double, v: Double, tolerance: ModelingTolerance) throws -> SurfaceParameterDerivatives {
        try parameterDerivativesThroughThirdOrder(u: u, v: v, tolerance: tolerance).secondOrder
    }
    public func point(u: Double, v: Double, tolerance: ModelingTolerance) throws -> Point3D {
        try parameterDerivativesThroughThirdOrder(u: u, v: v, tolerance: tolerance).position
    }
    package func point(u: Double, v: Double, tolerance: ModelingTolerance,
        consumeWork: () throws -> Void) throws -> Point3D {
        try parameterDerivativesThroughThirdOrder(u: u, v: v, tolerance: tolerance, consumeWork: consumeWork).position
    }

    public func boundarySource(_ boundary: SurfaceParameterBoundary) -> OriginalCurveRootSpan3D {
        switch boundary {
        case .uLower: uMinimumBoundary
        case .uUpper: uMaximumBoundary
        case .vLower: vMinimumBoundary
        case .vUpper: vMaximumBoundary
        }
    }

    func taylorJet(u: Double, v: Double, throughOrder order: Int,
        tolerance: ModelingTolerance) throws -> SurfaceTaylorVectorJet {
        guard order >= 0, order <= 16 else {
            throw GeometryConversionError.invalidInput("Original Coons numeric Taylor order must remain within the surface facade policy.")
        }
        let original = try intervalTaylorJet(over: .init(u: .init(lower: u, upper: u),
            v: .init(lower: v, upper: v)), throughOrder: order, tolerance: tolerance, consumeWork: {})
        func scalar(_ q: SurfaceAreaIntervalTaylorScalarJet) throws -> SurfaceTaylorScalarJet {
            var numeric = try SurfaceTaylorScalarJet(order: order)
            for total in 0...order { for a in 0...total {
                try Task.checkCancellation()
                try numeric.setCoefficient(q.coefficient(a, total-a).midpoint, uOrder: a, vOrder: total-a)
            } }
            return numeric
        }
        return try .init(x: scalar(original.x), y: scalar(original.y), z: scalar(original.z))
    }
}

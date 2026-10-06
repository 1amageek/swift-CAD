import CADCore

struct RationalBezierSurfaceJetEncloser: Sendable {
    struct FirstOrderEnclosure: Sendable {
        let value: IntervalVector3DBounds
        let derivativeU: IntervalVector3DBounds
        let derivativeV: IntervalVector3DBounds
    }

    fileprivate struct FirstOrderControls: Sendable {
        let value: [[IntervalHomogeneousSurfaceControl]]
        let derivativeU: [[IntervalHomogeneousSurfaceControl]]
        let derivativeV: [[IntervalHomogeneousSurfaceControl]]
    }

    struct PreparedFirstOrderRow: Sendable {
        fileprivate let patch: PreparedPatch
        fileprivate let u: Double
        fileprivate let pointControls: FirstOrderControls
        fileprivate let closedControls: FirstOrderControls
        fileprivate let pointPolynomials: [FirstOrderControls?]
        fileprivate let closedPolynomials: [FirstOrderControls?]
    }

    fileprivate struct HomogeneousJetControls: Sendable {
        let value: [[IntervalHomogeneousSurfaceControl]]
        let derivativeU: [[IntervalHomogeneousSurfaceControl]]
        let derivativeV: [[IntervalHomogeneousSurfaceControl]]
        let secondDerivativeUU: [[IntervalHomogeneousSurfaceControl]]
        let secondDerivativeUV: [[IntervalHomogeneousSurfaceControl]]
        let secondDerivativeVV: [[IntervalHomogeneousSurfaceControl]]
        let thirdDerivativeUUU: [[IntervalHomogeneousSurfaceControl]]
        let thirdDerivativeUUV: [[IntervalHomogeneousSurfaceControl]]
        let thirdDerivativeUVV: [[IntervalHomogeneousSurfaceControl]]
        let thirdDerivativeVVV: [[IntervalHomogeneousSurfaceControl]]
    }

    struct PreparedPatch: Sendable {
        let uLower: Double
        let uUpper: Double
        let vLower: Double
        let vUpper: Double
        fileprivate let origin: Point3D
        fileprivate let controls: HomogeneousJetControls
        fileprivate let polynomialX: HomogeneousJetControls?
        fileprivate let polynomialY: HomogeneousJetControls?
        fileprivate let polynomialZ: HomogeneousJetControls?
        fileprivate let originalCommonWeight: Double?
    }

    /// The native-span owner has already validated source, tolerance and lift.
    /// Immutable array ownership retains the existing original net without extraction.
    func originalCoefficientReceipt(of patch: PreparedPatch, source: BSplineSurface3D,
        tolerance: ModelingTolerance, query: SurfaceParameterBox, baseQuery: SurfaceParameterBox,
        uSpanIndex: Int, vSpanIndex: Int) throws -> SurfaceAreaOriginalCoefficientReceipt {
        return SurfaceAreaOriginalCoefficientReceipt(source:source,tolerance:tolerance,query:query,
            baseQuery:baseQuery,baseDomain:SurfaceParameterBox(
                u:try ScalarInterval(lower:patch.uLower,upper:patch.uUpper),
                v:try ScalarInterval(lower:patch.vLower,upper:patch.vUpper)),
            uSpanIndex:uSpanIndex,vSpanIndex:vSpanIndex,origin:patch.origin,
            commonWeight:patch.originalCommonWeight,net:patch.controls.value)
    }

    func enclosure(
        of patch: RationalBezierSurfacePatch3D,
        tolerance: ModelingTolerance
    ) throws -> SurfaceIntervalVectorJet {
        try enclosure(
            of: patch,
            u: ScalarInterval(lower: patch.uLower, upper: patch.uUpper),
            v: ScalarInterval(lower: patch.vLower, upper: patch.vUpper),
            tolerance: tolerance
        )
    }

    func enclosure(
        of patch: RationalBezierSurfacePatch3D,
        u: ScalarInterval,
        v: ScalarInterval,
        tolerance: ModelingTolerance
    ) throws -> SurfaceIntervalVectorJet {
        try enclosure(of: prepare(patch, tolerance: tolerance), u: u, v: v, tolerance: tolerance)
    }

    func prepare(_ patch: RationalBezierSurfacePatch3D,
                 tolerance: ModelingTolerance,
                 consumeWork: () throws -> Void = { try CurrentTaskCancellationChecker().checkCancellation() },
                 consumeStorage: ((Int) throws -> Void)? = nil) throws -> PreparedPatch {
        guard patch.controlPoints.isEmpty == false,
              patch.controlPoints.count == patch.weights.count,
              let uCount = patch.controlPoints.first?.count,
              uCount > 0,
              try patch.controlPoints.indices.allSatisfy({
                  try consumeWork()
                  return patch.controlPoints[$0].count == uCount
                      && patch.weights[$0].count == uCount
              }) else {
            throw invalidPatchError(tolerance: tolerance)
        }
        var controls: [[IntervalHomogeneousSurfaceControl]] = []
        let origin = patch.controlPoints[0][0]
        try OriginalCoefficientAllocation.reserve(count: patch.controlPoints.count, of: [IntervalHomogeneousSurfaceControl].self, consumeStorage: consumeStorage)
        controls.reserveCapacity(patch.controlPoints.count)
        for vIndex in patch.controlPoints.indices {
            var row: [IntervalHomogeneousSurfaceControl] = []
            try consumeWork()
            try OriginalCoefficientAllocation.reserve(count: uCount, of: IntervalHomogeneousSurfaceControl.self, consumeStorage: consumeStorage)
            row.reserveCapacity(uCount)
            for uIndex in patch.controlPoints[vIndex].indices {
                try consumeWork()
                let point = patch.controlPoints[vIndex][uIndex]
                let weight = patch.weights[vIndex][uIndex]
                guard weight.isFinite, weight > 0.0 else {
                    throw invalidPatchError(tolerance: tolerance)
                }
                // Stored model weights are exact inputs; products round outward below.
                let intervalWeight = OutwardScalarInterval.exact(weight)
                row.append(IntervalHomogeneousSurfaceControl(
                    x: (OutwardScalarInterval.exact(point.x) - .exact(origin.x)) * intervalWeight,
                    y: (OutwardScalarInterval.exact(point.y) - .exact(origin.y)) * intervalWeight,
                    z: (OutwardScalarInterval.exact(point.z) - .exact(origin.z)) * intervalWeight,
                    weight: intervalWeight
                ))
            }
            controls.append(row)
        }
        return try PreparedPatch(
            uLower: patch.uLower, uUpper: patch.uUpper,
            vLower: patch.vLower, vUpper: patch.vUpper,
            origin: origin,
            controls: derivativeJetControls(
                controls,
                uSpan: .exact(patch.uUpper) - .exact(patch.uLower),
                vSpan: .exact(patch.vUpper) - .exact(patch.vLower),
                tolerance: tolerance, consumeWork: consumeWork, consumeStorage: consumeStorage
            ),
            polynomialX: polynomialCoordinate({ $0.x }, origin: origin.x, patch: patch, tolerance: tolerance, consumeWork: consumeWork, consumeStorage: consumeStorage),
            polynomialY: polynomialCoordinate({ $0.y }, origin: origin.y, patch: patch, tolerance: tolerance, consumeWork: consumeWork, consumeStorage: consumeStorage),
            polynomialZ: polynomialCoordinate({ $0.z }, origin: origin.z, patch: patch, tolerance: tolerance, consumeWork: consumeWork, consumeStorage: consumeStorage),
            originalCommonWeight: nil
        )
    }

    func prepare(original patch: BSplineSurfaceBezierDecomposer.OriginalHomogeneousPatch,
                 tolerance: ModelingTolerance,
                 consumeWork: () throws -> Void = { try CurrentTaskCancellationChecker().checkCancellation() },
                 consumeStorage: ((Int) throws -> Void)? = nil) throws -> PreparedPatch {
        try CurrentTaskCancellationChecker().checkCancellation()
        return try PreparedPatch(uLower: patch.uBounds.lower, uUpper: patch.uBounds.upper,
            vLower: patch.vBounds.lower, vUpper: patch.vBounds.upper, origin: patch.origin,
            controls: derivativeJetControls(patch.controls,
                uSpan: .exact(patch.uBounds.upper) - .exact(patch.uBounds.lower),
                vSpan: .exact(patch.vBounds.upper) - .exact(patch.vBounds.lower), tolerance: tolerance,
                consumeWork: consumeWork, consumeStorage: consumeStorage),
            polynomialX: nil, polynomialY: nil, polynomialZ: nil,
            originalCommonWeight: patch.commonWeight)
    }

    private func polynomialCoordinate(_ coordinate: (Point3D) -> Double, origin: Double,
                                      patch: RationalBezierSurfacePatch3D,
                                      tolerance: ModelingTolerance,
                                      consumeWork: () throws -> Void = { try CurrentTaskCancellationChecker().checkCancellation() },
                                      consumeStorage: ((Int) throws -> Void)? = nil) throws -> HomogeneousJetControls? {
        guard !(try patch.weights.allSatisfy({ row in try row.allSatisfy { try consumeWork(); return $0 == 1 } })) else { return nil }
        let points: [[Point3D]]
        if try patch.weights.allSatisfy({ row in
            guard row.count == patch.weights[0].count else { return false }
            for index in row.indices { try consumeWork(); if row[index] != patch.weights[0][index] { return false } }
            return true
        }),
           try patch.controlPoints.allSatisfy({ row in
               try row.allSatisfy { try consumeWork(); return coordinate($0) == coordinate(row[0]) }
           }) {
            try OriginalCoefficientAllocation.reserve(count: patch.controlPoints.count, of: [Point3D].self, consumeStorage: consumeStorage)
            points = try patch.controlPoints.map { row in
                try consumeWork()
                try OriginalCoefficientAllocation.reserve(count: 1, of: Point3D.self, consumeStorage: consumeStorage)
                return [row[0]]
            }
        } else if try patch.weights.allSatisfy({ row in try row.allSatisfy { try consumeWork(); return $0 == row[0] } }),
                  try patch.controlPoints.allSatisfy({ row in
                      try row.indices.allSatisfy { try consumeWork(); return coordinate(row[$0]) == coordinate(patch.controlPoints[0][$0]) }
                  }) {
            try OriginalCoefficientAllocation.reserve(count: 1, of: [Point3D].self, consumeStorage: consumeStorage)
            points = [patch.controlPoints[0]]
        } else { return nil }
        try OriginalCoefficientAllocation.reserve(count: points.count, of: [IntervalHomogeneousSurfaceControl].self, consumeStorage: consumeStorage)
        let controls = try points.map { row in
            try OriginalCoefficientAllocation.reserve(count: row.count, of: IntervalHomogeneousSurfaceControl.self, consumeStorage: consumeStorage)
            return try row.map { point in
            try consumeWork()
            return IntervalHomogeneousSurfaceControl(
                x: .exact(coordinate(point)) - .exact(origin),
                y: .exact(0), z: .exact(0), weight: .exact(1))
        } }
        return try derivativeJetControls(controls,
            uSpan: .exact(patch.uUpper) - .exact(patch.uLower),
            vSpan: .exact(patch.vUpper) - .exact(patch.vLower),
            tolerance: tolerance, consumeWork: consumeWork, consumeStorage: consumeStorage)
    }

    func enclosure(of patch: PreparedPatch, u: ScalarInterval, v: ScalarInterval,
                   tolerance: ModelingTolerance) throws -> SurfaceIntervalVectorJet {
        guard u.lower >= patch.uLower, u.upper <= patch.uUpper,
              v.lower >= patch.vLower, v.upper <= patch.vUpper else {
            throw invalidPatchError(tolerance: tolerance)
        }
        func localize(_ controls: HomogeneousJetControls) throws -> HomogeneousJetControls {
            try localizedJetControls(controls,
                sourceULower: patch.uLower, sourceUUpper: patch.uUpper,
                sourceVLower: patch.vLower, sourceVUpper: patch.vUpper,
                targetU: u, targetV: v, tolerance: tolerance)
        }
        return try resolvedJet(of: patch, localize: localize, tolerance: tolerance)
    }

    /// Requests only original value and tangent nets, with no synthetic higher jet.
    func firstOrderEnclosure(of patch: PreparedPatch, u: ScalarInterval, v: ScalarInterval,
                             tolerance: ModelingTolerance) throws -> FirstOrderEnclosure {
        try CurrentTaskCancellationChecker().checkCancellation()
        guard u.lower.isFinite, u.upper.isFinite, v.lower.isFinite, v.upper.isFinite,
              u.lower <= u.upper, v.lower <= v.upper,
              u.lower >= patch.uLower, u.upper <= patch.uUpper,
              v.lower >= patch.vLower, v.upper <= patch.vUpper else {
            throw invalidPatchError(tolerance: tolerance)
        }
        func localize(_ values: [[IntervalHomogeneousSurfaceControl]]) throws
          -> [[IntervalHomogeneousSurfaceControl]] {
            if u.lower == u.upper, v.lower == v.upper {
                let parameters = try normalizedPointParameters(of: patch, u: u.lower, v: v.lower,
                                                               tolerance: tolerance)
                return try evaluatePointControls(values, localU: parameters.u, localV: parameters.v,
                                                 tolerance: tolerance)
            }
            return try trimmedControls(values, sourceULower: patch.uLower, sourceUUpper: patch.uUpper,
                sourceVLower: patch.vLower, sourceVUpper: patch.vUpper,
                targetU: u, targetV: v, tolerance: tolerance)
        }
        return try resolvedFirstOrder(of: patch, controls: firstOrderControls(patch.controls),
            polynomials: [patch.polynomialX.map(firstOrderControls), patch.polynomialY.map(firstOrderControls),
                          patch.polynomialZ.map(firstOrderControls)], tolerance: tolerance) { controls in
                try FirstOrderControls(value: localize(controls.value), derivativeU: localize(controls.derivativeU),
                                       derivativeV: localize(controls.derivativeV))
            }
    }

    private func firstOrderControls(_ controls: HomogeneousJetControls) -> FirstOrderControls {
        FirstOrderControls(value: controls.value, derivativeU: controls.derivativeU,
                           derivativeV: controls.derivativeV)
    }

    private func resolvedFirstOrder(of patch: PreparedPatch, controls: FirstOrderControls,
        polynomials: [FirstOrderControls?], tolerance: ModelingTolerance,
        localize: (FirstOrderControls) throws -> FirstOrderControls) throws -> FirstOrderEnclosure {
        let original = try localize(controls)
        let value = original.value
        let du = original.derivativeU
        let dv = original.derivativeV
        let weight = patch.originalCommonWeight.map(OutwardScalarInterval.exact)
            ?? scalarValue(value, component: { $0.weight })
        let reciprocal = try positiveValueReciprocal(weight, tolerance: tolerance)
        let weightU = patch.originalCommonWeight == nil ? scalarValue(du, component: { $0.weight }) : .exact(0)
        let weightV = patch.originalCommonWeight == nil ? scalarValue(dv, component: { $0.weight }) : .exact(0)
        func coordinate(_ polynomial: FirstOrderControls?,
                        component: (IntervalHomogeneousSurfaceControl) -> OutwardScalarInterval,
                        origin: Double) throws -> (OutwardScalarInterval, OutwardScalarInterval, OutwardScalarInterval) {
            let relative: OutwardScalarInterval
            let firstU: OutwardScalarInterval
            let firstV: OutwardScalarInterval
            if let polynomial {
                let localized = try localize(polynomial)
                relative = scalarValue(localized.value, component: { $0.x })
                firstU = scalarValue(localized.derivativeU, component: { $0.x })
                firstV = scalarValue(localized.derivativeV, component: { $0.x })
            } else {
                relative = scalarValue(value, component: component) * reciprocal
                firstU = (scalarValue(du, component: component) - relative * weightU) * reciprocal
                firstV = (scalarValue(dv, component: component) - relative * weightV) * reciprocal
            }
            let position = relative + .exact(origin)
            guard position.isFinite, firstU.isFinite, firstV.isFinite else {
                throw KernelError(phase: .geometry, code: .singularSystem, tolerance: tolerance,
                    message: "Original first-order surface enclosure requires finite Cartesian bounds.")
            }
            return (position, firstU, firstV)
        }
        let x = try coordinate(polynomials[0], component: { $0.x }, origin: patch.origin.x)
        let y = try coordinate(polynomials[1], component: { $0.y }, origin: patch.origin.y)
        let z = try coordinate(polynomials[2], component: { $0.z }, origin: patch.origin.z)
        try CurrentTaskCancellationChecker().checkCancellation()
        return FirstOrderEnclosure(value: .init(x: x.0, y: y.0, z: z.0),
            derivativeU: .init(x: x.1, y: y.1, z: z.1), derivativeV: .init(x: x.2, y: y.2, z: z.2))
    }

    func prepareFirstOrderRow(of patch: PreparedPatch, u: Double, tolerance: ModelingTolerance,
                               consumeWork: () throws -> Void) throws -> PreparedFirstOrderRow {
        try consumeWork()
        let normalized = try normalizedPointParameters(of: patch, u: u, v: patch.vLower, tolerance: tolerance).u
        let singletonU = try ScalarInterval(lower: u, upper: u)
        let wholeV = try ScalarInterval(lower: patch.vLower, upper: patch.vUpper)
        func prepare(_ controls: FirstOrderControls) throws -> (point: FirstOrderControls, closed: FirstOrderControls) {
            func net(_ values: [[IntervalHomogeneousSurfaceControl]]) throws
              -> (point: [[IntervalHomogeneousSurfaceControl]], closed: [[IntervalHomogeneousSurfaceControl]]) {
                // Prepay closed and singleton retained slots and each bounded
                // original U de Casteljau preparation before execution/allocation.
                try consumeWork(); try consumeWork()
                for row in values {
                    try consumeWork(); try consumeWork()
                    for _ in row {
                        for _ in 0..<9 { try consumeWork() }
                    }
                    for _ in 0..<9 { try consumeWork() }
                    for level in row.indices {
                        for _ in 0...level {
                            try consumeWork(); try consumeWork(); try consumeWork()
                        }
                    }
                }
                let point = try values.map { [try evaluatePointControlAxis($0, parameter: normalized,
                                                                           tolerance: tolerance)] }
                let closed = try trimmedControls(values, sourceULower: patch.uLower, sourceUUpper: patch.uUpper,
                    sourceVLower: patch.vLower, sourceVUpper: patch.vUpper,
                    targetU: singletonU, targetV: wholeV, tolerance: tolerance)
                return (point, closed)
            }
            let value = try net(controls.value)
            let du = try net(controls.derivativeU)
            let dv = try net(controls.derivativeV)
            return (FirstOrderControls(value: value.point, derivativeU: du.point, derivativeV: dv.point),
                    FirstOrderControls(value: value.closed, derivativeU: du.closed, derivativeV: dv.closed))
        }
        for _ in 0..<16 { try consumeWork() }
        let original = try prepare(firstOrderControls(patch.controls))
        var pointPolynomials: [FirstOrderControls?] = []
        var closedPolynomials: [FirstOrderControls?] = []
        for polynomial in [patch.polynomialX, patch.polynomialY, patch.polynomialZ] {
            if let polynomial {
                let prepared = try prepare(firstOrderControls(polynomial))
                pointPolynomials.append(prepared.point); closedPolynomials.append(prepared.closed)
            } else {
                pointPolynomials.append(nil); closedPolynomials.append(nil)
            }
        }
        try CurrentTaskCancellationChecker().checkCancellation()
        return PreparedFirstOrderRow(patch: patch, u: u, pointControls: original.point,
            closedControls: original.closed, pointPolynomials: pointPolynomials, closedPolynomials: closedPolynomials)
    }

    func firstOrderEnclosure(row: PreparedFirstOrderRow, overClosedV v: ScalarInterval,
                             tolerance: ModelingTolerance) throws -> FirstOrderEnclosure {
        let patch = row.patch
        guard v.lower.isFinite, v.upper.isFinite, v.lower <= v.upper,
              v.lower >= patch.vLower, v.upper <= patch.vUpper else {
            throw invalidPatchError(tolerance: tolerance)
        }
        try CurrentTaskCancellationChecker().checkCancellation()
        let singleton = v.lower == v.upper
        let controls = singleton ? row.pointControls : row.closedControls
        let polynomials = singleton ? row.pointPolynomials : row.closedPolynomials
        func localize(_ values: [[IntervalHomogeneousSurfaceControl]]) throws -> [[IntervalHomogeneousSurfaceControl]] {
            if singleton {
                let localV = try normalizedPointParameters(of: patch, u: row.u, v: v.lower,
                                                          tolerance: tolerance).v
                return try evaluatePointControls(values, localU: .exact(0), localV: localV, tolerance: tolerance)
            }
            return try trimmedControls(values, sourceULower: row.u, sourceUUpper: row.u,
                sourceVLower: patch.vLower, sourceVUpper: patch.vUpper,
                targetU: ScalarInterval(lower: row.u, upper: row.u), targetV: v, tolerance: tolerance)
        }
        return try resolvedFirstOrder(of: patch, controls: controls, polynomials: polynomials,
                                     tolerance: tolerance) { controls in
            try FirstOrderControls(value: localize(controls.value), derivativeU: localize(controls.derivativeU),
                                   derivativeV: localize(controls.derivativeV))
        }
    }

    /// Evaluates the original differentiated nets without dividing by a
    /// shortened localization span. Exact endpoints retain their native jets.
    func pointEnclosure(of patch: PreparedPatch, u: Double, v: Double,
                        tolerance: ModelingTolerance) throws -> SurfaceIntervalVectorJet {
        let parameters = try normalizedPointParameters(of:patch,u:u,v:v,tolerance:tolerance)
        func evaluate(_ values: [[IntervalHomogeneousSurfaceControl]]) throws -> [[IntervalHomogeneousSurfaceControl]] {
            try evaluatePointControls(values,localU:parameters.u,localV:parameters.v,tolerance:tolerance)
        }
        func localize(_ controls: HomogeneousJetControls) throws -> HomogeneousJetControls {
            try HomogeneousJetControls(value:evaluate(controls.value),
                derivativeU:evaluate(controls.derivativeU),derivativeV:evaluate(controls.derivativeV),
                secondDerivativeUU:evaluate(controls.secondDerivativeUU),
                secondDerivativeUV:evaluate(controls.secondDerivativeUV),
                secondDerivativeVV:evaluate(controls.secondDerivativeVV),
                thirdDerivativeUUU:evaluate(controls.thirdDerivativeUUU),
                thirdDerivativeUUV:evaluate(controls.thirdDerivativeUUV),
                thirdDerivativeUVV:evaluate(controls.thirdDerivativeUVV),
                thirdDerivativeVVV:evaluate(controls.thirdDerivativeVVV))
        }
        return try resolvedJet(of:patch,localize:localize,tolerance:tolerance)
    }

    /// Original value nets only; no synthetic derivative jet is constructed.
    func pointValueEnclosure(of patch: PreparedPatch, u: Double, v: Double,
        tolerance: ModelingTolerance) throws -> IntervalVector3DBounds {
        try CurrentTaskCancellationChecker().checkCancellation()
        let parameters = try normalizedPointParameters(of:patch,u:u,v:v,tolerance:tolerance)
        return try resolvedValue(of:patch,tolerance:tolerance) { values in
            try evaluatePointControls(values,localU:parameters.u,localV:parameters.v,tolerance:tolerance)
        }
    }

    /// Positive-width periodic point lift covers retain original localization;
    /// only their value nets are requested, not unneeded derivative nets.
    func valueEnclosure(of patch: PreparedPatch, u: ScalarInterval, v: ScalarInterval,
        tolerance: ModelingTolerance) throws -> IntervalVector3DBounds {
        try CurrentTaskCancellationChecker().checkCancellation()
        guard u.lower.isFinite, u.upper.isFinite, v.lower.isFinite, v.upper.isFinite,
              u.lower <= u.upper, v.lower <= v.upper,
              u.lower >= patch.uLower, u.upper <= patch.uUpper,
              v.lower >= patch.vLower, v.upper <= patch.vUpper else {
            throw invalidPatchError(tolerance:tolerance)
        }
        return try resolvedValue(of:patch,tolerance:tolerance) { values in
            try trimmedControls(values,sourceULower:patch.uLower,sourceUUpper:patch.uUpper,
                sourceVLower:patch.vLower,sourceVUpper:patch.vUpper,targetU:u,targetV:v,tolerance:tolerance)
        }
    }

    private func normalizedPointParameters(of patch: PreparedPatch, u: Double, v: Double,
        tolerance: ModelingTolerance) throws -> (u: OutwardScalarInterval,v: OutwardScalarInterval) {
        guard u.isFinite, v.isFinite,
              u >= patch.uLower, u <= patch.uUpper,
              v >= patch.vLower, v <= patch.vUpper else {
            throw invalidPatchError(tolerance:tolerance)
        }
        func parameter(_ value: Double, lower: Double, upper: Double) throws -> OutwardScalarInterval {
            if value == lower { return .exact(0) }
            if value == upper { return .exact(1) }
            let candidate = (value - lower) / (upper - lower)
            if candidate.isFinite, candidate >= 0, candidate <= 1 {
                let offset = FloatingPointExpansion.difference(value, lower)
                let span = FloatingPointExpansion.difference(upper, lower)
                if offset.allSatisfy({ $0.isFinite }), span.allSatisfy({ $0.isFinite }),
                   span.allSatisfy({ component in
                       if candidate == 0 || component == 0 { return true }
                       // Dekker's splitter is 2^27+1 < 2^28. Normal operands
                       // with this upper headroom keep its intermediates finite.
                       // Two 53-bit operands have lowest product bit E1+E2-104;
                       // keeping that bit normal prevents lost underflow errors.
                       let maximumExponent = Double.greatestFiniteMagnitude.exponent - 28
                       return candidate.isNormal && component.isNormal
                           && candidate.exponent <= maximumExponent
                           && component.exponent <= maximumExponent
                           && candidate.exponent + component.exponent
                               - 2 * Double.significandBitCount >= Double.leastNormalMagnitude.exponent
                   }) {
                    let product = candidate == 0 ? [0.0] : FloatingPointExpansion.product(
                        [candidate], span.filter { $0 != 0 })
                    let residual = FloatingPointExpansion.subtract(offset, product)
                    // The candidate alone is not evidence. Exact equality of
                    // original stored operands proves this singleton refinement;
                    // the witness span is never a rounded difference.
                    if product.allSatisfy({ $0.isFinite }), residual.allSatisfy({ $0.isFinite }),
                       FloatingPointExpansion.sign(residual) == .zero {
                        return .exact(candidate)
                    }
                }
            }
            // Without an exact witness, retain the established outward ratio.
            guard let result = (OutwardScalarInterval.exact(value) - .exact(lower))
                .divided(by: .exact(upper) - .exact(lower)), result.isFinite else {
                throw invalidPatchError(tolerance: tolerance)
            }
            // Stored endpoint containment proves the exact ratio is in [0,1].
            return OutwardScalarInterval(lower:max(0,result.lower),upper:min(1,result.upper))
        }
        return try (parameter(u,lower:patch.uLower,upper:patch.uUpper),
            parameter(v,lower:patch.vLower,upper:patch.vUpper))
    }

    private func evaluatePointControls(_ values: [[IntervalHomogeneousSurfaceControl]],
        localU: OutwardScalarInterval, localV: OutwardScalarInterval, tolerance: ModelingTolerance)
        throws -> [[IntervalHomogeneousSurfaceControl]] {
        let rows = try values.map { try evaluatePointControlAxis($0, parameter: localU, tolerance: tolerance) }
        return [[try evaluatePointControlAxis(rows, parameter: localV, tolerance: tolerance)]]
    }

    private func evaluatePointControlAxis(_ values: [IntervalHomogeneousSurfaceControl],
                  parameter: OutwardScalarInterval, tolerance: ModelingTolerance) throws -> IntervalHomogeneousSurfaceControl {
        if parameter.lower == 0, parameter.upper == 0 { return values[0] }
        if parameter.lower == 1, parameter.upper == 1 { return values[values.count-1] }
        var level = values
        while level.count > 1 {
            level = (0..<(level.count-1)).map {
                level[$0].interpolated(to:level[$0+1],parameter:parameter)
            }
        }
        // Original normalized parameters lie in [0,1], so both the
        // outward evaluation and each coefficient convex hull contain
        // the scalar value, including already differentiated nets.
        func intersect(_ component: (IntervalHomogeneousSurfaceControl) -> OutwardScalarInterval)
            throws -> OutwardScalarInterval {
            let hull = OutwardScalarInterval.enclosing(values.map { component($0) })
            guard let result = component(level[0]).intersection(with: hull) else {
                throw KernelError(phase: .geometry, code: .intersectionFailure, tolerance: tolerance,
                    message: "Surface point Bernstein evaluation and its certified coefficient hull are disjoint.")
            }
            return result
        }
        return try IntervalHomogeneousSurfaceControl(x: intersect({ $0.x }), y: intersect({ $0.y }),
            z: intersect({ $0.z }), weight: intersect({ $0.weight }))
    }


    private func resolvedValue(of patch: PreparedPatch, tolerance: ModelingTolerance,
        localize: ([[IntervalHomogeneousSurfaceControl]]) throws -> [[IntervalHomogeneousSurfaceControl]])
        throws -> IntervalVector3DBounds {
        let localized = try localize(patch.controls.value)
        let weight = patch.originalCommonWeight.map(OutwardScalarInterval.exact)
            ?? scalarValue(localized,component:{ $0.weight })
        let reciprocal = try positiveValueReciprocal(weight,tolerance:tolerance)
        func coordinate(_ polynomial: HomogeneousJetControls?,
            component: (IntervalHomogeneousSurfaceControl) -> OutwardScalarInterval, origin: Double)
            throws -> OutwardScalarInterval {
            let polynomialValue: OutwardScalarInterval?
            if let polynomial { polynomialValue = scalarValue(try localize(polynomial.value),component:{ $0.x }) }
            else { polynomialValue = nil }
            return cartesianValue(numerator:scalarValue(localized,component:component),
                reciprocal:reciprocal,polynomial:polynomialValue,origin:origin)
        }
        let result = try IntervalVector3DBounds(
            x:coordinate(patch.polynomialX,component:{ $0.x },origin:patch.origin.x),
            y:coordinate(patch.polynomialY,component:{ $0.y },origin:patch.origin.y),
            z:coordinate(patch.polynomialZ,component:{ $0.z },origin:patch.origin.z))
        guard result.x.isFinite, result.y.isFinite, result.z.isFinite else {
            throw KernelError(phase:.geometry,code:.singularSystem,tolerance:tolerance,
                message:"Original surface value evaluation could not certify finite Cartesian bounds.")
        }
        return result
    }

    private func positiveValueReciprocal(_ weight: OutwardScalarInterval,
        tolerance: ModelingTolerance) throws -> OutwardScalarInterval {
        guard weight.isFinite, weight.lower > 0 else {
            throw KernelError(phase:.geometry,code:.singularSystem,residual:weight.lower,tolerance:tolerance,
                message:"Original surface value evaluation requires a finite positive weight range.")
        }
        return OutwardScalarInterval(lower:(1.0/weight.upper).nextDown,upper:(1.0/weight.lower).nextUp)
    }

    private func cartesianValue(numerator: OutwardScalarInterval, reciprocal: OutwardScalarInterval,
        polynomial: OutwardScalarInterval?, origin: Double) -> OutwardScalarInterval {
        (polynomial ?? numerator*reciprocal) + OutwardScalarInterval(origin)
    }

    private func scalarValue(_ values: [[IntervalHomogeneousSurfaceControl]],
        component: (IntervalHomogeneousSurfaceControl) -> OutwardScalarInterval) -> OutwardScalarInterval {
        .enclosing(values.flatMap { row in row.map { component($0) } })
    }

    private func resolvedJet(of patch: PreparedPatch,
        localize: (HomogeneousJetControls) throws -> HomogeneousJetControls,
        tolerance: ModelingTolerance) throws -> SurfaceIntervalVectorJet {
        let localized = try localize(patch.controls)
        let x = scalarJet(localized, component: { $0.x })
        let y = scalarJet(localized, component: { $0.y })
        let z = scalarJet(localized, component: { $0.z })
        let enclosedWeight = scalarJet(
            localized,
            component: { $0.weight }
        )
        let weight: SurfaceIntervalJet
        if let common = patch.originalCommonWeight {
            // The original tensor's common positive weight and partition of unity
            // establish this denominator before any extraction or jet evaluation.
            weight = SurfaceIntervalJet(value: .exact(common), derivativeU: .exact(0), derivativeV: .exact(0),
                secondDerivativeUU: .exact(0), secondDerivativeUV: .exact(0), secondDerivativeVV: .exact(0),
                thirdDerivativeUUU: .exact(0), thirdDerivativeUUV: .exact(0), thirdDerivativeUVV: .exact(0), thirdDerivativeVVV: .exact(0))
        } else { weight = enclosedWeight }
        guard weight.value.lower > 0, let reciprocalWeight = weight.reciprocal() else {
            throw KernelError(
                phase: .geometry,
                code: .singularSystem,
                residual: weight.value.lower,
                tolerance: tolerance,
                message: "A rational surface enclosure requires a certified positive weight range."
            )
        }
        let reciprocalValue = try positiveValueReciprocal(weight.value,tolerance:tolerance)
        func coordinate(_ polynomial: HomogeneousJetControls?, rational: SurfaceIntervalJet,
                        origin: Double) throws -> SurfaceIntervalJet {
            let value: SurfaceIntervalJet
            let polynomialValue: OutwardScalarInterval?
            if let polynomial {
                value = scalarJet(try localize(polynomial),component:{ $0.x })
                polynomialValue = value.value
            } else {
                value = rational * reciprocalWeight
                polynomialValue = nil
            }
            let shifted = value + .constant(origin)
            return SurfaceIntervalJet(value:cartesianValue(numerator:rational.value,
                reciprocal:reciprocalValue,polynomial:polynomialValue,origin:origin),
                derivativeU:shifted.derivativeU,derivativeV:shifted.derivativeV,
                secondDerivativeUU:shifted.secondDerivativeUU,secondDerivativeUV:shifted.secondDerivativeUV,
                secondDerivativeVV:shifted.secondDerivativeVV,thirdDerivativeUUU:shifted.thirdDerivativeUUU,
                thirdDerivativeUUV:shifted.thirdDerivativeUUV,thirdDerivativeUVV:shifted.thirdDerivativeUVV,
                thirdDerivativeVVV:shifted.thirdDerivativeVVV)
        }
        let result = try SurfaceIntervalVectorJet(
            x: coordinate(patch.polynomialX, rational: x, origin: patch.origin.x),
            y: coordinate(patch.polynomialY, rational: y, origin: patch.origin.y),
            z: coordinate(patch.polynomialZ, rational: z, origin: patch.origin.z)
        )
        for coordinate in [result.x,result.y,result.z] {
            guard [coordinate.value,coordinate.derivativeU,coordinate.derivativeV,
                coordinate.secondDerivativeUU,coordinate.secondDerivativeUV,coordinate.secondDerivativeVV,
                coordinate.thirdDerivativeUUU,coordinate.thirdDerivativeUUV,
                coordinate.thirdDerivativeUVV,coordinate.thirdDerivativeVVV].allSatisfy({ $0.isFinite }) else {
                throw KernelError(phase:.geometry,code:.singularSystem,tolerance:tolerance,
                    message:"A rational surface jet could not certify finite value and derivative intervals.")
            }
        }
        return result
    }

    private func derivativeJetControls(
        _ controls: [[IntervalHomogeneousSurfaceControl]],
        uSpan: OutwardScalarInterval,
        vSpan: OutwardScalarInterval,
        tolerance: ModelingTolerance,
        consumeWork: () throws -> Void = { try CurrentTaskCancellationChecker().checkCancellation() },
        consumeStorage: ((Int) throws -> Void)? = nil
    ) throws -> HomogeneousJetControls {
        guard uSpan.isFinite, uSpan.lower > 0.0,
              vSpan.isFinite, vSpan.lower > 0.0 else {
            throw invalidPatchError(tolerance: tolerance)
        }
        let derivativeU = try differentiatedU(
            controls,
            span: uSpan,
            tolerance: tolerance, consumeWork: consumeWork, consumeStorage: consumeStorage
        )
        let derivativeV = try differentiatedV(
            controls,
            span: vSpan,
            tolerance: tolerance, consumeWork: consumeWork, consumeStorage: consumeStorage
        )
        let secondDerivativeUU = try differentiatedU(
            derivativeU,
            span: uSpan,
            tolerance: tolerance, consumeWork: consumeWork, consumeStorage: consumeStorage
        )
        let secondDerivativeUV = try differentiatedV(
            derivativeU,
            span: vSpan,
            tolerance: tolerance, consumeWork: consumeWork, consumeStorage: consumeStorage
        )
        let secondDerivativeVV = try differentiatedV(
            derivativeV,
            span: vSpan,
            tolerance: tolerance, consumeWork: consumeWork, consumeStorage: consumeStorage
        )
        let thirdDerivativeUUU = try differentiatedU(
            secondDerivativeUU,
            span: uSpan,
            tolerance: tolerance, consumeWork: consumeWork, consumeStorage: consumeStorage
        )
        let thirdDerivativeUUV = try differentiatedV(
            secondDerivativeUU,
            span: vSpan,
            tolerance: tolerance, consumeWork: consumeWork, consumeStorage: consumeStorage
        )
        let thirdDerivativeUVV = try differentiatedV(
            secondDerivativeUV,
            span: vSpan,
            tolerance: tolerance, consumeWork: consumeWork, consumeStorage: consumeStorage
        )
        let thirdDerivativeVVV = try differentiatedV(
            secondDerivativeVV,
            span: vSpan,
            tolerance: tolerance, consumeWork: consumeWork, consumeStorage: consumeStorage
        )
        return HomogeneousJetControls(
            value: controls,
            derivativeU: derivativeU,
            derivativeV: derivativeV,
            secondDerivativeUU: secondDerivativeUU,
            secondDerivativeUV: secondDerivativeUV,
            secondDerivativeVV: secondDerivativeVV,
            thirdDerivativeUUU: thirdDerivativeUUU,
            thirdDerivativeUUV: thirdDerivativeUUV,
            thirdDerivativeUVV: thirdDerivativeUVV,
            thirdDerivativeVVV: thirdDerivativeVVV
        )
    }

    private func differentiatedU(
        _ controls: [[IntervalHomogeneousSurfaceControl]], span: OutwardScalarInterval,
        tolerance: ModelingTolerance, consumeWork: () throws -> Void = { try CurrentTaskCancellationChecker().checkCancellation() },
        consumeStorage: ((Int) throws -> Void)? = nil
    ) throws -> [[IntervalHomogeneousSurfaceControl]] {
        let count = controls.first?.count ?? 0
        try OriginalCoefficientAllocation.reserve(count: controls.count, of: [IntervalHomogeneousSurfaceControl].self, consumeStorage: consumeStorage)
        var result: [[IntervalHomogeneousSurfaceControl]] = []
        result.reserveCapacity(controls.count)
        if count <= 1 {
            for _ in controls {
                try consumeWork()
                try OriginalCoefficientAllocation.reserve(count: 1, of: IntervalHomogeneousSurfaceControl.self, consumeStorage: consumeStorage)
                result.append([.zero])
            }
            return result
        }
        guard let scale = OutwardScalarInterval.exact(Double(count - 1)).divided(by: span) else {
            throw invalidPatchError(tolerance: tolerance)
        }
        for row in controls {
            try consumeWork()
            try OriginalCoefficientAllocation.reserve(count: count - 1, of: IntervalHomogeneousSurfaceControl.self, consumeStorage: consumeStorage)
            var values: [IntervalHomogeneousSurfaceControl] = []
            values.reserveCapacity(count - 1)
            for index in 0..<(count - 1) {
                try consumeWork()
                values.append(row[index + 1].subtracting(row[index]).scaled(by: scale))
            }
            result.append(values)
        }
        return result
    }

    private func differentiatedV(
        _ controls: [[IntervalHomogeneousSurfaceControl]], span: OutwardScalarInterval,
        tolerance: ModelingTolerance, consumeWork: () throws -> Void = { try CurrentTaskCancellationChecker().checkCancellation() },
        consumeStorage: ((Int) throws -> Void)? = nil
    ) throws -> [[IntervalHomogeneousSurfaceControl]] {
        let count = controls.first?.count ?? 1
        if controls.count <= 1 {
            try consumeWork()
            try OriginalCoefficientAllocation.reserve(count: 1, of: [IntervalHomogeneousSurfaceControl].self, consumeStorage: consumeStorage)
            try OriginalCoefficientAllocation.reserve(count: count, of: IntervalHomogeneousSurfaceControl.self, consumeStorage: consumeStorage)
            return [Array(repeating: .zero, count: count)]
        }
        guard let scale = OutwardScalarInterval.exact(Double(controls.count - 1)).divided(by: span) else {
            throw invalidPatchError(tolerance: tolerance)
        }
        try OriginalCoefficientAllocation.reserve(count: controls.count - 1, of: [IntervalHomogeneousSurfaceControl].self, consumeStorage: consumeStorage)
        var result: [[IntervalHomogeneousSurfaceControl]] = []
        result.reserveCapacity(controls.count - 1)
        for rowIndex in 0..<(controls.count - 1) {
            try consumeWork()
            try OriginalCoefficientAllocation.reserve(count: count, of: IntervalHomogeneousSurfaceControl.self, consumeStorage: consumeStorage)
            var row: [IntervalHomogeneousSurfaceControl] = []
            row.reserveCapacity(count)
            for columnIndex in 0..<count {
                try consumeWork()
                row.append(controls[rowIndex + 1][columnIndex].subtracting(controls[rowIndex][columnIndex]).scaled(by: scale))
            }
            result.append(row)
        }
        return result
    }

    private func localizedJetControls(
        _ controls: HomogeneousJetControls,
        sourceULower: Double,
        sourceUUpper: Double,
        sourceVLower: Double,
        sourceVUpper: Double,
        targetU: ScalarInterval,
        targetV: ScalarInterval,
        tolerance: ModelingTolerance
    ) throws -> HomogeneousJetControls {
        func localized(
            _ values: [[IntervalHomogeneousSurfaceControl]]
        ) throws -> [[IntervalHomogeneousSurfaceControl]] {
            try trimmedControls(
                values,
                sourceULower: sourceULower,
                sourceUUpper: sourceUUpper,
                sourceVLower: sourceVLower,
                sourceVUpper: sourceVUpper,
                targetU: targetU,
                targetV: targetV,
                tolerance: tolerance
            )
        }
        return try HomogeneousJetControls(
            value: localized(controls.value),
            derivativeU: localized(controls.derivativeU),
            derivativeV: localized(controls.derivativeV),
            secondDerivativeUU: localized(controls.secondDerivativeUU),
            secondDerivativeUV: localized(controls.secondDerivativeUV),
            secondDerivativeVV: localized(controls.secondDerivativeVV),
            thirdDerivativeUUU: localized(controls.thirdDerivativeUUU),
            thirdDerivativeUUV: localized(controls.thirdDerivativeUUV),
            thirdDerivativeUVV: localized(controls.thirdDerivativeUVV),
            thirdDerivativeVVV: localized(controls.thirdDerivativeVVV)
        )
    }

    private func scalarJet(
        _ controls: HomogeneousJetControls,
        component: (IntervalHomogeneousSurfaceControl) -> OutwardScalarInterval
    ) -> SurfaceIntervalJet {
        func enclosure(_ values: [[IntervalHomogeneousSurfaceControl]]) -> OutwardScalarInterval {
            scalarValue(values,component:component)
        }
        return SurfaceIntervalJet(
            value: enclosure(controls.value),
            derivativeU: enclosure(controls.derivativeU),
            derivativeV: enclosure(controls.derivativeV),
            secondDerivativeUU: enclosure(controls.secondDerivativeUU),
            secondDerivativeUV: enclosure(controls.secondDerivativeUV),
            secondDerivativeVV: enclosure(controls.secondDerivativeVV),
            thirdDerivativeUUU: enclosure(controls.thirdDerivativeUUU),
            thirdDerivativeUUV: enclosure(controls.thirdDerivativeUUV),
            thirdDerivativeUVV: enclosure(controls.thirdDerivativeUVV),
            thirdDerivativeVVV: enclosure(controls.thirdDerivativeVVV)
        )
    }

    private func trimmedControls(
        _ source: [[IntervalHomogeneousSurfaceControl]],
        sourceULower: Double,
        sourceUUpper: Double,
        sourceVLower: Double,
        sourceVUpper: Double,
        targetU: ScalarInterval,
        targetV: ScalarInterval,
        tolerance: ModelingTolerance
    ) throws -> [[IntervalHomogeneousSurfaceControl]] {
        var controls = source
        var currentULower = sourceULower
        if targetU.lower > currentULower {
            let parameter = try normalizedParameter(
                targetU.lower,
                lower: currentULower,
                upper: sourceUUpper,
                tolerance: tolerance
            )
            controls = splitU(controls, parameter: parameter).upper
            currentULower = targetU.lower
        }
        if targetU.upper < sourceUUpper {
            let parameter = try normalizedParameter(
                targetU.upper,
                lower: currentULower,
                upper: sourceUUpper,
                tolerance: tolerance
            )
            controls = splitU(controls, parameter: parameter).lower
        }
        var currentVLower = sourceVLower
        if targetV.lower > currentVLower {
            let parameter = try normalizedParameter(
                targetV.lower,
                lower: currentVLower,
                upper: sourceVUpper,
                tolerance: tolerance
            )
            controls = splitV(controls, parameter: parameter).upper
            currentVLower = targetV.lower
        }
        if targetV.upper < sourceVUpper {
            let parameter = try normalizedParameter(
                targetV.upper,
                lower: currentVLower,
                upper: sourceVUpper,
                tolerance: tolerance
            )
            controls = splitV(controls, parameter: parameter).lower
        }
        return controls
    }

    private func normalizedParameter(
        _ value: Double,
        lower: Double,
        upper: Double,
        tolerance: ModelingTolerance
    ) throws -> OutwardScalarInterval {
        let numerator = OutwardScalarInterval(value)
            - OutwardScalarInterval(lower)
        let denominator = OutwardScalarInterval(upper)
            - OutwardScalarInterval(lower)
        guard let parameter = numerator.divided(by: denominator),
              parameter.isFinite else {
            throw invalidPatchError(tolerance: tolerance)
        }
        return parameter
    }

    private func splitU(
        _ controls: [[IntervalHomogeneousSurfaceControl]],
        parameter: OutwardScalarInterval
    ) -> (
        lower: [[IntervalHomogeneousSurfaceControl]],
        upper: [[IntervalHomogeneousSurfaceControl]]
    ) {
        let splits = controls.map { split($0, parameter: parameter) }
        return (splits.map({ $0.lower }), splits.map({ $0.upper }))
    }

    private func splitV(
        _ controls: [[IntervalHomogeneousSurfaceControl]],
        parameter: OutwardScalarInterval
    ) -> (
        lower: [[IntervalHomogeneousSurfaceControl]],
        upper: [[IntervalHomogeneousSurfaceControl]]
    ) {
        guard controls.count > 1 else { return (controls, controls) }
        var levels = [controls]
        while let previous = levels.last, previous.count > 1 {
            levels.append((0..<(previous.count - 1)).map { rowIndex in
                previous[rowIndex].indices.map { columnIndex in
                    previous[rowIndex][columnIndex].interpolated(
                        to: previous[rowIndex + 1][columnIndex],
                        parameter: parameter
                    )
                }
            })
        }
        return (
            levels.map { $0[0] },
            levels.reversed().map { $0[$0.count - 1] }
        )
    }

    private func split(
        _ controls: [IntervalHomogeneousSurfaceControl],
        parameter: OutwardScalarInterval
    ) -> (
        lower: [IntervalHomogeneousSurfaceControl],
        upper: [IntervalHomogeneousSurfaceControl]
    ) {
        guard controls.count > 1 else { return (controls, controls) }
        var levels = [controls]
        while let previous = levels.last, previous.count > 1 {
            levels.append((0..<(previous.count - 1)).map { index in
                previous[index].interpolated(
                    to: previous[index + 1],
                    parameter: parameter
                )
            })
        }
        return (
            levels.map { $0[0] },
            levels.reversed().map { $0[$0.count - 1] }
        )
    }

    private func invalidPatchError(tolerance: ModelingTolerance) -> KernelError {
        KernelError(
            phase: .geometry,
            code: .invalidInput,
            tolerance: tolerance,
            message: "A rational Bezier surface enclosure requires a finite rectangular control net."
        )
    }
}

struct IntervalHomogeneousSurfaceControl: Sendable {
    let x: OutwardScalarInterval
    let y: OutwardScalarInterval
    let z: OutwardScalarInterval
    let weight: OutwardScalarInterval

    static let zero = IntervalHomogeneousSurfaceControl(
        x: OutwardScalarInterval(0.0),
        y: OutwardScalarInterval(0.0),
        z: OutwardScalarInterval(0.0),
        weight: OutwardScalarInterval(0.0)
    )

    func subtracting(
        _ other: IntervalHomogeneousSurfaceControl
    ) -> IntervalHomogeneousSurfaceControl {
        IntervalHomogeneousSurfaceControl(
            x: x - other.x,
            y: y - other.y,
            z: z - other.z,
            weight: weight - other.weight
        )
    }

    func scaled(
        by scale: OutwardScalarInterval
    ) -> IntervalHomogeneousSurfaceControl {
        IntervalHomogeneousSurfaceControl(
            x: x * scale,
            y: y * scale,
            z: z * scale,
            weight: weight * scale
        )
    }

    func interpolated(
        to other: IntervalHomogeneousSurfaceControl,
        parameter: OutwardScalarInterval
    ) -> IntervalHomogeneousSurfaceControl {
        let complement = OutwardScalarInterval(1.0) - parameter
        return IntervalHomogeneousSurfaceControl(
            x: x * complement + other.x * parameter,
            y: y * complement + other.y * parameter,
            z: z * complement + other.z * parameter,
            weight: weight * complement + other.weight * parameter
        )
    }
}

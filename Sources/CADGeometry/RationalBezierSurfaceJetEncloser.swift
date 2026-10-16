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
    func originalCoefficientReceipt<A: ExactScalarAdmission & ~Copyable>(of patch: PreparedPatch, source: BSplineSurface3D,
        tolerance: ModelingTolerance, query: SurfaceParameterBox, baseQuery: SurfaceParameterBox,
        uSpanIndex: Int, vSpanIndex: Int, using execution: inout A) throws -> SurfaceAreaOriginalCoefficientReceipt {
        try execution.consumeWork(1)
        try OriginalCoefficientAllocation.reserve(count: 1, of: SurfaceAreaOriginalCoefficientReceipt.self, using: &execution)
        return SurfaceAreaOriginalCoefficientReceipt(source:source,tolerance:tolerance,query:query,
            baseQuery:baseQuery,baseDomain:SurfaceParameterBox(
                u:try ScalarInterval(lower:patch.uLower,upper:patch.uUpper),
                v:try ScalarInterval(lower:patch.vLower,upper:patch.vUpper)),
            uSpanIndex:uSpanIndex,vSpanIndex:vSpanIndex,origin:patch.origin,
            commonWeight:patch.originalCommonWeight,net:patch.controls.value)
    }

    func enclosure<A: ExactScalarAdmission & ~Copyable>(
        of patch: RationalBezierSurfacePatch3D,
        tolerance: ModelingTolerance
    , using execution: inout A) throws -> SurfaceIntervalVectorJet {
        try enclosure(
            of: patch,
            u: ScalarInterval(lower: patch.uLower, upper: patch.uUpper),
            v: ScalarInterval(lower: patch.vLower, upper: patch.vUpper),
            tolerance: tolerance
        , using: &execution)
    }

    func enclosure<A: ExactScalarAdmission & ~Copyable>(
        of patch: RationalBezierSurfacePatch3D,
        u: ScalarInterval,
        v: ScalarInterval,
        tolerance: ModelingTolerance
    , using execution: inout A) throws -> SurfaceIntervalVectorJet {
        try enclosure(of: try prepare(patch, tolerance: tolerance, using: &execution), u: u, v: v, tolerance: tolerance, using: &execution)
    }

    func prepare<A: ExactScalarAdmission & ~Copyable>(_ patch: RationalBezierSurfacePatch3D,
                 tolerance: ModelingTolerance, using execution: inout A) throws -> PreparedPatch {
        guard patch.controlPoints.isEmpty == false,
              patch.controlPoints.count == patch.weights.count,
              let uCount = patch.controlPoints.first?.count,
              uCount > 0,
              try patch.controlPoints.indices.allSatisfy({
                  try execution.consumeWork(1)
                  return patch.controlPoints[$0].count == uCount
                      && patch.weights[$0].count == uCount
              }) else {
            throw invalidPatchError(tolerance: tolerance)
        }
        var controls: [[IntervalHomogeneousSurfaceControl]] = []
        let origin = patch.controlPoints[0][0]
        try OriginalCoefficientAllocation.reserve(count: patch.controlPoints.count, of: [IntervalHomogeneousSurfaceControl].self, using: &execution)
        controls.reserveCapacity(patch.controlPoints.count)
        for vIndex in patch.controlPoints.indices {
            var row: [IntervalHomogeneousSurfaceControl] = []
            try execution.consumeWork(1)
            try OriginalCoefficientAllocation.reserve(count: uCount, of: IntervalHomogeneousSurfaceControl.self, using: &execution)
            row.reserveCapacity(uCount)
            for uIndex in patch.controlPoints[vIndex].indices {
                try execution.consumeWork(1)
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
            controls: try derivativeJetControls(
                controls,
                uSpan: .exact(patch.uUpper) - .exact(patch.uLower),
                vSpan: .exact(patch.vUpper) - .exact(patch.vLower),
                tolerance: tolerance
            , using: &execution),
            polynomialX: try polynomialCoordinate({ $0.x }, origin: origin.x, patch: patch, tolerance: tolerance, using: &execution),
            polynomialY: try polynomialCoordinate({ $0.y }, origin: origin.y, patch: patch, tolerance: tolerance, using: &execution),
            polynomialZ: try polynomialCoordinate({ $0.z }, origin: origin.z, patch: patch, tolerance: tolerance, using: &execution),
            originalCommonWeight: nil
        )
    }

    func prepare<A: ExactScalarAdmission & ~Copyable>(original patch: BSplineSurfaceBezierDecomposer.OriginalHomogeneousPatch,
                 tolerance: ModelingTolerance, using execution: inout A) throws -> PreparedPatch {
        try execution.checkpoint()
        return try PreparedPatch(uLower: patch.uBounds.lower, uUpper: patch.uBounds.upper,
            vLower: patch.vBounds.lower, vUpper: patch.vBounds.upper, origin: patch.origin,
            controls: try derivativeJetControls(patch.controls,
                uSpan: .exact(patch.uBounds.upper) - .exact(patch.uBounds.lower),
                vSpan: .exact(patch.vBounds.upper) - .exact(patch.vBounds.lower), tolerance: tolerance, using: &execution),
            polynomialX: nil, polynomialY: nil, polynomialZ: nil,
            originalCommonWeight: patch.commonWeight)
    }

    private func polynomialCoordinate<A: ExactScalarAdmission & ~Copyable>(_ coordinate: (Point3D) -> Double, origin: Double,
                                      patch: RationalBezierSurfacePatch3D,
                                      tolerance: ModelingTolerance, using execution: inout A) throws -> HomogeneousJetControls? {
        guard !(try patch.weights.allSatisfy({ row in try row.allSatisfy { try execution.consumeWork(1); return $0 == 1 } })) else { return nil }
        let points: [[Point3D]]
        if try patch.weights.allSatisfy({ row in
            guard row.count == patch.weights[0].count else { return false }
            for index in row.indices { try execution.consumeWork(1); if row[index] != patch.weights[0][index] { return false } }
            return true
        }),
           try patch.controlPoints.allSatisfy({ row in
               try row.allSatisfy { try execution.consumeWork(1); return coordinate($0) == coordinate(row[0]) }
           }) {
            try OriginalCoefficientAllocation.reserve(count: patch.controlPoints.count, of: [Point3D].self, using: &execution)
            points = try patch.controlPoints.map { row in
                try execution.consumeWork(1)
                try OriginalCoefficientAllocation.reserve(count: 1, of: Point3D.self, using: &execution)
                return [row[0]]
            }
        } else if try patch.weights.allSatisfy({ row in try row.allSatisfy { try execution.consumeWork(1); return $0 == row[0] } }),
                  try patch.controlPoints.allSatisfy({ row in
                      try row.indices.allSatisfy { try execution.consumeWork(1); return coordinate(row[$0]) == coordinate(patch.controlPoints[0][$0]) }
                  }) {
            try OriginalCoefficientAllocation.reserve(count: 1, of: [Point3D].self, using: &execution)
            points = [patch.controlPoints[0]]
        } else { return nil }
        try OriginalCoefficientAllocation.reserve(count: points.count, of: [IntervalHomogeneousSurfaceControl].self, using: &execution)
        let controls = try points.map { row in
            try OriginalCoefficientAllocation.reserve(count: row.count, of: IntervalHomogeneousSurfaceControl.self, using: &execution)
            return try row.map { point in
            try execution.consumeWork(1)
            return IntervalHomogeneousSurfaceControl(
                x: .exact(coordinate(point)) - .exact(origin),
                y: .exact(0), z: .exact(0), weight: .exact(1))
        } }
        return try derivativeJetControls(controls,
            uSpan: .exact(patch.uUpper) - .exact(patch.uLower),
            vSpan: .exact(patch.vUpper) - .exact(patch.vLower),
            tolerance: tolerance, using: &execution)
    }

    func enclosure<A: ExactScalarAdmission & ~Copyable>(of patch: PreparedPatch, u: ScalarInterval, v: ScalarInterval,
                   tolerance: ModelingTolerance, using execution: inout A) throws -> SurfaceIntervalVectorJet {
        guard u.lower >= patch.uLower, u.upper <= patch.uUpper,
              v.lower >= patch.vLower, v.upper <= patch.vUpper else {
            throw invalidPatchError(tolerance: tolerance)
        }
        func localize(_ controls: HomogeneousJetControls, using execution: inout A) throws -> HomogeneousJetControls {
            try localizedJetControls(controls,
                sourceULower: patch.uLower, sourceUUpper: patch.uUpper,
                sourceVLower: patch.vLower, sourceVUpper: patch.vUpper,
                targetU: u, targetV: v, tolerance: tolerance, using: &execution)
        }
        return try resolvedJet(of: patch, localize: localize, tolerance: tolerance, using: &execution)
    }

    /// Requests only original value and tangent nets, with no synthetic higher jet.
    func firstOrderEnclosure<A: ExactScalarAdmission & ~Copyable>(of patch: PreparedPatch, u: ScalarInterval, v: ScalarInterval,
                             tolerance: ModelingTolerance, using execution: inout A) throws -> FirstOrderEnclosure {
        try execution.checkpoint()
        guard u.lower.isFinite, u.upper.isFinite, v.lower.isFinite, v.upper.isFinite,
              u.lower <= u.upper, v.lower <= v.upper,
              u.lower >= patch.uLower, u.upper <= patch.uUpper,
              v.lower >= patch.vLower, v.upper <= patch.vUpper else {
            throw invalidPatchError(tolerance: tolerance)
        }
        func localize(_ values: [[IntervalHomogeneousSurfaceControl]], using execution: inout A) throws
          -> [[IntervalHomogeneousSurfaceControl]] {
            if u.lower == u.upper, v.lower == v.upper {
                let parameters = try normalizedPointParameters(of: patch, u: u.lower, v: v.lower,
                                                               tolerance: tolerance, using: &execution)
                return try evaluatePointControls(values, localU: parameters.u, localV: parameters.v,
                                                 tolerance: tolerance, using: &execution)
            }
            return try trimmedControls(values, sourceULower: patch.uLower, sourceUUpper: patch.uUpper,
                sourceVLower: patch.vLower, sourceVUpper: patch.vUpper,
                targetU: u, targetV: v, tolerance: tolerance, using: &execution)
        }
        try OriginalCoefficientAllocation.reserve(count: 3, of: FirstOrderControls?.self, using: &execution)
        return try resolvedFirstOrder(of: patch, controls: firstOrderControls(patch.controls),
            polynomials: [patch.polynomialX.map(firstOrderControls), patch.polynomialY.map(firstOrderControls),
                          patch.polynomialZ.map(firstOrderControls)], tolerance: tolerance, using: &execution) { controls, execution in
                try FirstOrderControls(value: try localize(controls.value, using: &execution), derivativeU: try localize(controls.derivativeU, using: &execution),
                                       derivativeV: try localize(controls.derivativeV, using: &execution))
            }
    }

    private func firstOrderControls(_ controls: HomogeneousJetControls) -> FirstOrderControls {
        FirstOrderControls(value: controls.value, derivativeU: controls.derivativeU,
                           derivativeV: controls.derivativeV)
    }

    private func resolvedFirstOrder<A: ExactScalarAdmission & ~Copyable>(of patch: PreparedPatch, controls: FirstOrderControls,
        polynomials: [FirstOrderControls?], tolerance: ModelingTolerance,
        using execution: inout A, localize: (FirstOrderControls, inout A) throws -> FirstOrderControls) throws -> FirstOrderEnclosure {
        let original = try localize(controls, &execution)
        let value = original.value
        let du = original.derivativeU
        let dv = original.derivativeV
        let weight = try patch.originalCommonWeight.map(OutwardScalarInterval.exact)
            ?? (try scalarValue(value, component: { $0.weight }, using: &execution))
        let reciprocal = try positiveValueReciprocal(weight, tolerance: tolerance)
        let weightU = patch.originalCommonWeight == nil ? try scalarValue(du, component: { $0.weight }, using: &execution) : .exact(0)
        let weightV = patch.originalCommonWeight == nil ? try scalarValue(dv, component: { $0.weight }, using: &execution) : .exact(0)
        func coordinate(_ polynomial: FirstOrderControls?,
                        component: (IntervalHomogeneousSurfaceControl) -> OutwardScalarInterval,
                        origin: Double, using execution: inout A) throws -> (OutwardScalarInterval, OutwardScalarInterval, OutwardScalarInterval) {
            let relative: OutwardScalarInterval
            let firstU: OutwardScalarInterval
            let firstV: OutwardScalarInterval
            if let polynomial {
                let localized = try localize(polynomial, &execution)
                relative = try scalarValue(localized.value, component: { $0.x }, using: &execution)
                firstU = try scalarValue(localized.derivativeU, component: { $0.x }, using: &execution)
                firstV = try scalarValue(localized.derivativeV, component: { $0.x }, using: &execution)
            } else {
                relative = try scalarValue(value, component: component, using: &execution) * reciprocal
                firstU = (try scalarValue(du, component: component, using: &execution) - relative * weightU) * reciprocal
                firstV = (try scalarValue(dv, component: component, using: &execution) - relative * weightV) * reciprocal
            }
            let position = relative + .exact(origin)
            guard position.isFinite, firstU.isFinite, firstV.isFinite else {
                throw KernelError(phase: .geometry, code: .singularSystem, tolerance: tolerance,
                    message: "Original first-order surface enclosure requires finite Cartesian bounds.")
            }
            return (position, firstU, firstV)
        }
        let x = try coordinate(polynomials[0], component: { $0.x }, origin: patch.origin.x, using: &execution)
        let y = try coordinate(polynomials[1], component: { $0.y }, origin: patch.origin.y, using: &execution)
        let z = try coordinate(polynomials[2], component: { $0.z }, origin: patch.origin.z, using: &execution)
        try execution.checkpoint()
        return FirstOrderEnclosure(value: .init(x: x.0, y: y.0, z: z.0),
            derivativeU: .init(x: x.1, y: y.1, z: z.1), derivativeV: .init(x: x.2, y: y.2, z: z.2))
    }

    func prepareFirstOrderRow<A: ExactScalarAdmission & ~Copyable>(of patch: PreparedPatch, u: Double, tolerance: ModelingTolerance, using execution: inout A) throws -> PreparedFirstOrderRow {
        try execution.consumeWork(1)
        let normalized = try normalizedPointParameters(of: patch, u: u, v: patch.vLower, tolerance: tolerance, using: &execution).u
        let singletonU = try ScalarInterval(lower: u, upper: u)
        let wholeV = try ScalarInterval(lower: patch.vLower, upper: patch.vUpper)
        func prepare(_ controls: FirstOrderControls, using execution: inout A) throws -> (point: FirstOrderControls, closed: FirstOrderControls) {
            func net(_ values: [[IntervalHomogeneousSurfaceControl]], using execution: inout A) throws
              -> (point: [[IntervalHomogeneousSurfaceControl]], closed: [[IntervalHomogeneousSurfaceControl]]) {
                try OriginalCoefficientAllocation.reserve(count: values.count, of: [IntervalHomogeneousSurfaceControl].self, using: &execution)
                for _ in values { try OriginalCoefficientAllocation.reserve(count: 1, of: IntervalHomogeneousSurfaceControl.self, using: &execution) }
                let point = try values.map { [try evaluatePointControlAxis($0, parameter: normalized,
                                                                           tolerance: tolerance, using: &execution)] }
                let closed = try trimmedControls(values, sourceULower: patch.uLower, sourceUUpper: patch.uUpper,
                    sourceVLower: patch.vLower, sourceVUpper: patch.vUpper,
                    targetU: singletonU, targetV: wholeV, tolerance: tolerance, using: &execution)
                return (point, closed)
            }
            let value = try net(controls.value, using: &execution)
            let du = try net(controls.derivativeU, using: &execution)
            let dv = try net(controls.derivativeV, using: &execution)
            return (FirstOrderControls(value: value.point, derivativeU: du.point, derivativeV: dv.point),
                    FirstOrderControls(value: value.closed, derivativeU: du.closed, derivativeV: dv.closed))
        }
        try OriginalCoefficientAllocation.reserve(count: 3, of: FirstOrderControls?.self, using: &execution)
        try OriginalCoefficientAllocation.reserve(count: 3, of: FirstOrderControls?.self, using: &execution)
        let original = try prepare(firstOrderControls(patch.controls), using: &execution)
        var pointPolynomials: [FirstOrderControls?] = []
        var closedPolynomials: [FirstOrderControls?] = []
        pointPolynomials.reserveCapacity(3); closedPolynomials.reserveCapacity(3)
        try OriginalCoefficientAllocation.reserve(count: 3, of: HomogeneousJetControls?.self, using: &execution)
        for polynomial in [patch.polynomialX, patch.polynomialY, patch.polynomialZ] {
            if let polynomial {
                let prepared = try prepare(firstOrderControls(polynomial), using: &execution)
                pointPolynomials.append(prepared.point); closedPolynomials.append(prepared.closed)
            } else {
                pointPolynomials.append(nil); closedPolynomials.append(nil)
            }
        }
        try execution.checkpoint()
        return PreparedFirstOrderRow(patch: patch, u: u, pointControls: original.point,
            closedControls: original.closed, pointPolynomials: pointPolynomials, closedPolynomials: closedPolynomials)
    }

    func firstOrderEnclosure<A: ExactScalarAdmission & ~Copyable>(row: PreparedFirstOrderRow, overClosedV v: ScalarInterval,
                             tolerance: ModelingTolerance, using execution: inout A) throws -> FirstOrderEnclosure {
        let patch = row.patch
        guard v.lower.isFinite, v.upper.isFinite, v.lower <= v.upper,
              v.lower >= patch.vLower, v.upper <= patch.vUpper else {
            throw invalidPatchError(tolerance: tolerance)
        }
        try execution.checkpoint()
        let singleton = v.lower == v.upper
        let controls = singleton ? row.pointControls : row.closedControls
        let polynomials = singleton ? row.pointPolynomials : row.closedPolynomials
        func localize(_ values: [[IntervalHomogeneousSurfaceControl]], using execution: inout A) throws -> [[IntervalHomogeneousSurfaceControl]] {
            if singleton {
                let localV = try normalizedPointParameters(of: patch, u: row.u, v: v.lower,
                                                          tolerance: tolerance, using: &execution).v
                return try evaluatePointControls(values, localU: .exact(0), localV: localV, tolerance: tolerance, using: &execution)
            }
            return try trimmedControls(values, sourceULower: row.u, sourceUUpper: row.u,
                sourceVLower: patch.vLower, sourceVUpper: patch.vUpper,
                targetU: ScalarInterval(lower: row.u, upper: row.u), targetV: v, tolerance: tolerance, using: &execution)
        }
        return try resolvedFirstOrder(of: patch, controls: controls, polynomials: polynomials,
                                     tolerance: tolerance, using: &execution) { controls, execution in
            try FirstOrderControls(value: try localize(controls.value, using: &execution), derivativeU: try localize(controls.derivativeU, using: &execution),
                                   derivativeV: try localize(controls.derivativeV, using: &execution))
        }
    }

    /// Evaluates the original differentiated nets without dividing by a
    /// shortened localization span. Exact endpoints retain their native jets.
    func pointEnclosure<A: ExactScalarAdmission & ~Copyable>(of patch: PreparedPatch, u: Double, v: Double,
                        tolerance: ModelingTolerance, using execution: inout A) throws -> SurfaceIntervalVectorJet {
        let parameters = try normalizedPointParameters(of:patch,u:u,v:v,tolerance:tolerance, using: &execution)
        func evaluate(_ values: [[IntervalHomogeneousSurfaceControl]], using execution: inout A) throws -> [[IntervalHomogeneousSurfaceControl]] {
            try evaluatePointControls(values,localU:parameters.u,localV:parameters.v,tolerance:tolerance, using: &execution)
        }
        func localize(_ controls: HomogeneousJetControls, using execution: inout A) throws -> HomogeneousJetControls {
            try HomogeneousJetControls(value:try evaluate(controls.value, using: &execution),
                derivativeU:try evaluate(controls.derivativeU, using: &execution),derivativeV:try evaluate(controls.derivativeV, using: &execution),
                secondDerivativeUU:try evaluate(controls.secondDerivativeUU, using: &execution),
                secondDerivativeUV:try evaluate(controls.secondDerivativeUV, using: &execution),
                secondDerivativeVV:try evaluate(controls.secondDerivativeVV, using: &execution),
                thirdDerivativeUUU:try evaluate(controls.thirdDerivativeUUU, using: &execution),
                thirdDerivativeUUV:try evaluate(controls.thirdDerivativeUUV, using: &execution),
                thirdDerivativeUVV:try evaluate(controls.thirdDerivativeUVV, using: &execution),
                thirdDerivativeVVV:try evaluate(controls.thirdDerivativeVVV, using: &execution))
        }
        return try resolvedJet(of:patch,localize:localize,tolerance:tolerance, using: &execution)
    }

    /// Original value nets only; no synthetic derivative jet is constructed.
    func pointValueEnclosure<A: ExactScalarAdmission & ~Copyable>(of patch: PreparedPatch, u: Double, v: Double,
        tolerance: ModelingTolerance, using execution: inout A) throws -> IntervalVector3DBounds {
        try execution.checkpoint()
        let parameters = try normalizedPointParameters(of:patch,u:u,v:v,tolerance:tolerance, using: &execution)
        return try resolvedValue(of:patch,tolerance:tolerance, using: &execution) { values, execution in
            try evaluatePointControls(values,localU:parameters.u,localV:parameters.v,tolerance:tolerance, using: &execution)
        }
    }

    /// Positive-width periodic point lift covers retain original localization;
    /// only their value nets are requested, not unneeded derivative nets.
    func valueEnclosure<A: ExactScalarAdmission & ~Copyable>(of patch: PreparedPatch, u: ScalarInterval, v: ScalarInterval,
        tolerance: ModelingTolerance, using execution: inout A) throws -> IntervalVector3DBounds {
        try execution.checkpoint()
        guard u.lower.isFinite, u.upper.isFinite, v.lower.isFinite, v.upper.isFinite,
              u.lower <= u.upper, v.lower <= v.upper,
              u.lower >= patch.uLower, u.upper <= patch.uUpper,
              v.lower >= patch.vLower, v.upper <= patch.vUpper else {
            throw invalidPatchError(tolerance:tolerance)
        }
        return try resolvedValue(of:patch,tolerance:tolerance, using: &execution) { values, execution in
            try trimmedControls(values,sourceULower:patch.uLower,sourceUUpper:patch.uUpper,
                sourceVLower:patch.vLower,sourceVUpper:patch.vUpper,targetU:u,targetV:v,tolerance:tolerance, using: &execution)
        }
    }

    private func normalizedPointParameters<A: ExactScalarAdmission & ~Copyable>(of patch: PreparedPatch, u: Double, v: Double,
        tolerance: ModelingTolerance, using execution: inout A) throws -> (u: OutwardScalarInterval,v: OutwardScalarInterval) {
        guard u.isFinite, v.isFinite,
              u >= patch.uLower, u <= patch.uUpper,
              v >= patch.vLower, v <= patch.vUpper else {
            throw invalidPatchError(tolerance:tolerance)
        }
        try execution.consumeWork(1)
        func parameter(_ value: Double, lower: Double, upper: Double, using execution: inout A) throws -> OutwardScalarInterval {
            if value == lower { return .exact(0) }
            if value == upper { return .exact(1) }
            let candidate = (value - lower) / (upper - lower)
            if candidate.isFinite, candidate >= 0, candidate <= 1 {
                let offset = try FloatingPointExpansion.difference(value, lower, using: &execution)
                let span = try FloatingPointExpansion.difference(upper, lower, using: &execution)
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
                    try OriginalCoefficientAllocation.reserve(count: 1, of: Double.self, using: &execution)
                    try OriginalCoefficientAllocation.reserve(count: span.count, of: Double.self, using: &execution)
                    var nonzeroSpan: [Double] = []; nonzeroSpan.reserveCapacity(span.count)
                    for component in span { try execution.consumeWork(1); if component != 0 { nonzeroSpan.append(component) } }
                    let product = candidate == 0 ? [0.0] : try FloatingPointExpansion.product(
                        [candidate], nonzeroSpan, using: &execution)
                    let residual = try FloatingPointExpansion.subtract(offset, product, using: &execution)
                    // The candidate alone is not evidence. Exact equality of
                    // original stored operands proves this singleton refinement;
                    // the witness span is never a rounded difference.
                    if product.allSatisfy({ $0.isFinite }), residual.allSatisfy({ $0.isFinite }),
                       try FloatingPointExpansion.sign(residual, using: &execution) == .zero {
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
        return try (try parameter(u,lower:patch.uLower,upper:patch.uUpper, using: &execution),
            try parameter(v,lower:patch.vLower,upper:patch.vUpper, using: &execution))
    }

    private func evaluatePointControls<A: ExactScalarAdmission & ~Copyable>(_ values: [[IntervalHomogeneousSurfaceControl]],
        localU: OutwardScalarInterval, localV: OutwardScalarInterval, tolerance: ModelingTolerance, using execution: inout A)
        throws -> [[IntervalHomogeneousSurfaceControl]] {
        try OriginalCoefficientAllocation.reserve(count: values.count, of: IntervalHomogeneousSurfaceControl.self, using: &execution)
        try OriginalCoefficientAllocation.reserve(count: 1, of: [IntervalHomogeneousSurfaceControl].self, using: &execution)
        try OriginalCoefficientAllocation.reserve(count: 1, of: IntervalHomogeneousSurfaceControl.self, using: &execution)
        let rows = try values.map { try evaluatePointControlAxis($0, parameter: localU, tolerance: tolerance, using: &execution) }
        return [[try evaluatePointControlAxis(rows, parameter: localV, tolerance: tolerance, using: &execution)]]
    }

    private func evaluatePointControlAxis<A: ExactScalarAdmission & ~Copyable>(_ values: [IntervalHomogeneousSurfaceControl],
                  parameter: OutwardScalarInterval, tolerance: ModelingTolerance, using execution: inout A) throws -> IntervalHomogeneousSurfaceControl {
        if parameter.lower == 0, parameter.upper == 0 { return values[0] }
        if parameter.lower == 1, parameter.upper == 1 { return values[values.count-1] }
        var level = values
        while level.count > 1 {
            try OriginalCoefficientAllocation.reserve(count: level.count - 1, of: IntervalHomogeneousSurfaceControl.self, using: &execution)
            level = try (0..<(level.count-1)).map {
                try execution.consumeWork(1)
                return level[$0].interpolated(to:level[$0+1],parameter:parameter)
            }
        }
        // Original normalized parameters lie in [0,1], so both the
        // outward evaluation and each coefficient convex hull contain
        // the scalar value, including already differentiated nets.
        func intersect(_ component: (IntervalHomogeneousSurfaceControl) -> OutwardScalarInterval, using execution: inout A)
            throws -> OutwardScalarInterval {
            var lower = Double.infinity, upper = -Double.infinity
            for value in values {
                try execution.consumeWork(1)
                let interval = component(value)
                lower = min(lower, interval.lower); upper = max(upper, interval.upper)
            }
            let hull = OutwardScalarInterval(lower: lower, upper: upper)
            guard let result = component(level[0]).intersection(with: hull) else {
                throw KernelError(phase: .geometry, code: .intersectionFailure, tolerance: tolerance,
                    message: "Surface point Bernstein evaluation and its certified coefficient hull are disjoint.")
            }
            return result
        }
        return try IntervalHomogeneousSurfaceControl(x: try intersect({ $0.x }, using: &execution), y: try intersect({ $0.y }, using: &execution),
            z: try intersect({ $0.z }, using: &execution), weight: try intersect({ $0.weight }, using: &execution))
    }


    private func resolvedValue<A: ExactScalarAdmission & ~Copyable>(of patch: PreparedPatch, tolerance: ModelingTolerance,
        using execution: inout A, localize: ([[IntervalHomogeneousSurfaceControl]], inout A) throws -> [[IntervalHomogeneousSurfaceControl]])
        throws -> IntervalVector3DBounds {
        let localized = try localize(patch.controls.value, &execution)
        let weight = try patch.originalCommonWeight.map(OutwardScalarInterval.exact)
            ?? (try scalarValue(localized,component:{ $0.weight }, using: &execution))
        let reciprocal = try positiveValueReciprocal(weight,tolerance:tolerance)
        func coordinate(_ polynomial: HomogeneousJetControls?,
            component: (IntervalHomogeneousSurfaceControl) -> OutwardScalarInterval, origin: Double, using execution: inout A)
            throws -> OutwardScalarInterval {
            let polynomialValue: OutwardScalarInterval?
            if let polynomial { polynomialValue = try scalarValue(try localize(polynomial.value, &execution),component:{ $0.x }, using: &execution) }
            else { polynomialValue = nil }
            return cartesianValue(numerator:try scalarValue(localized,component:component, using: &execution),
                reciprocal:reciprocal,polynomial:polynomialValue,origin:origin)
        }
        let result = try IntervalVector3DBounds(
            x:try coordinate(patch.polynomialX,component:{ $0.x },origin:patch.origin.x, using: &execution),
            y:try coordinate(patch.polynomialY,component:{ $0.y },origin:patch.origin.y, using: &execution),
            z:try coordinate(patch.polynomialZ,component:{ $0.z },origin:patch.origin.z, using: &execution))
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

    private func scalarValue<A: ExactScalarAdmission & ~Copyable>(_ values: [[IntervalHomogeneousSurfaceControl]],
        component: (IntervalHomogeneousSurfaceControl) -> OutwardScalarInterval, using execution: inout A) throws -> OutwardScalarInterval {
        var lower = Double.infinity, upper = -Double.infinity
        var observed = false
        for row in values { for value in row {
            try execution.consumeWork(1)
            let interval = component(value); observed = true
            lower = min(lower, interval.lower); upper = max(upper, interval.upper)
        } }
        return observed ? OutwardScalarInterval(lower: lower, upper: upper)
            : OutwardScalarInterval(lower: -.infinity, upper: .infinity)
    }

    private func resolvedJet<A: ExactScalarAdmission & ~Copyable>(of patch: PreparedPatch,
        localize: (HomogeneousJetControls, inout A) throws -> HomogeneousJetControls,
        tolerance: ModelingTolerance, using execution: inout A) throws -> SurfaceIntervalVectorJet {
        let localized = try localize(patch.controls, &execution)
        let x = try scalarJet(localized, component: { $0.x }, using: &execution)
        let y = try scalarJet(localized, component: { $0.y }, using: &execution)
        let z = try scalarJet(localized, component: { $0.z }, using: &execution)
        let enclosedWeight = try scalarJet(
            localized,
            component: { $0.weight }
        , using: &execution)
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
                        origin: Double, using execution: inout A) throws -> SurfaceIntervalJet {
            let value: SurfaceIntervalJet
            let polynomialValue: OutwardScalarInterval?
            if let polynomial {
                value = try scalarJet(try localize(polynomial, &execution),component:{ $0.x }, using: &execution)
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
            x: try coordinate(patch.polynomialX, rational: x, origin: patch.origin.x, using: &execution),
            y: try coordinate(patch.polynomialY, rational: y, origin: patch.origin.y, using: &execution),
            z: try coordinate(patch.polynomialZ, rational: z, origin: patch.origin.z, using: &execution)
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

    private func derivativeJetControls<A: ExactScalarAdmission & ~Copyable>(
        _ controls: [[IntervalHomogeneousSurfaceControl]],
        uSpan: OutwardScalarInterval,
        vSpan: OutwardScalarInterval,
        tolerance: ModelingTolerance
    , using execution: inout A) throws -> HomogeneousJetControls {
        guard uSpan.isFinite, uSpan.lower > 0.0,
              vSpan.isFinite, vSpan.lower > 0.0 else {
            throw invalidPatchError(tolerance: tolerance)
        }
        let derivativeU = try differentiatedU(
            controls,
            span: uSpan,
            tolerance: tolerance
        , using: &execution)
        let derivativeV = try differentiatedV(
            controls,
            span: vSpan,
            tolerance: tolerance
        , using: &execution)
        let secondDerivativeUU = try differentiatedU(
            derivativeU,
            span: uSpan,
            tolerance: tolerance
        , using: &execution)
        let secondDerivativeUV = try differentiatedV(
            derivativeU,
            span: vSpan,
            tolerance: tolerance
        , using: &execution)
        let secondDerivativeVV = try differentiatedV(
            derivativeV,
            span: vSpan,
            tolerance: tolerance
        , using: &execution)
        let thirdDerivativeUUU = try differentiatedU(
            secondDerivativeUU,
            span: uSpan,
            tolerance: tolerance
        , using: &execution)
        let thirdDerivativeUUV = try differentiatedV(
            secondDerivativeUU,
            span: vSpan,
            tolerance: tolerance
        , using: &execution)
        let thirdDerivativeUVV = try differentiatedV(
            secondDerivativeUV,
            span: vSpan,
            tolerance: tolerance
        , using: &execution)
        let thirdDerivativeVVV = try differentiatedV(
            secondDerivativeVV,
            span: vSpan,
            tolerance: tolerance
        , using: &execution)
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

    private func differentiatedU<A: ExactScalarAdmission & ~Copyable>(
        _ controls: [[IntervalHomogeneousSurfaceControl]], span: OutwardScalarInterval,
        tolerance: ModelingTolerance
    , using execution: inout A) throws -> [[IntervalHomogeneousSurfaceControl]] {
        let count = controls.first?.count ?? 0
        try OriginalCoefficientAllocation.reserve(count: controls.count, of: [IntervalHomogeneousSurfaceControl].self, using: &execution)
        var result: [[IntervalHomogeneousSurfaceControl]] = []
        result.reserveCapacity(controls.count)
        if count <= 1 {
            for _ in controls {
                try execution.consumeWork(1)
                try OriginalCoefficientAllocation.reserve(count: 1, of: IntervalHomogeneousSurfaceControl.self, using: &execution)
                result.append([.zero])
            }
            return result
        }
        guard let scale = OutwardScalarInterval.exact(Double(count - 1)).divided(by: span) else {
            throw invalidPatchError(tolerance: tolerance)
        }
        for row in controls {
            try execution.consumeWork(1)
            try OriginalCoefficientAllocation.reserve(count: count - 1, of: IntervalHomogeneousSurfaceControl.self, using: &execution)
            var values: [IntervalHomogeneousSurfaceControl] = []
            values.reserveCapacity(count - 1)
            for index in 0..<(count - 1) {
                try execution.consumeWork(1)
                values.append(row[index + 1].subtracting(row[index]).scaled(by: scale))
            }
            result.append(values)
        }
        return result
    }

    private func differentiatedV<A: ExactScalarAdmission & ~Copyable>(
        _ controls: [[IntervalHomogeneousSurfaceControl]], span: OutwardScalarInterval,
        tolerance: ModelingTolerance
    , using execution: inout A) throws -> [[IntervalHomogeneousSurfaceControl]] {
        let count = controls.first?.count ?? 1
        if controls.count <= 1 {
            try execution.consumeWork(1)
            try OriginalCoefficientAllocation.reserve(count: 1, of: [IntervalHomogeneousSurfaceControl].self, using: &execution)
            try OriginalCoefficientAllocation.reserve(count: count, of: IntervalHomogeneousSurfaceControl.self, using: &execution)
            return [Array(repeating: .zero, count: count)]
        }
        guard let scale = OutwardScalarInterval.exact(Double(controls.count - 1)).divided(by: span) else {
            throw invalidPatchError(tolerance: tolerance)
        }
        try OriginalCoefficientAllocation.reserve(count: controls.count - 1, of: [IntervalHomogeneousSurfaceControl].self, using: &execution)
        var result: [[IntervalHomogeneousSurfaceControl]] = []
        result.reserveCapacity(controls.count - 1)
        for rowIndex in 0..<(controls.count - 1) {
            try execution.consumeWork(1)
            try OriginalCoefficientAllocation.reserve(count: count, of: IntervalHomogeneousSurfaceControl.self, using: &execution)
            var row: [IntervalHomogeneousSurfaceControl] = []
            row.reserveCapacity(count)
            for columnIndex in 0..<count {
                try execution.consumeWork(1)
                row.append(controls[rowIndex + 1][columnIndex].subtracting(controls[rowIndex][columnIndex]).scaled(by: scale))
            }
            result.append(row)
        }
        return result
    }

    private func localizedJetControls<A: ExactScalarAdmission & ~Copyable>(
        _ controls: HomogeneousJetControls,
        sourceULower: Double,
        sourceUUpper: Double,
        sourceVLower: Double,
        sourceVUpper: Double,
        targetU: ScalarInterval,
        targetV: ScalarInterval,
        tolerance: ModelingTolerance
    , using execution: inout A) throws -> HomogeneousJetControls {
        func localized(
            _ values: [[IntervalHomogeneousSurfaceControl]]
        , using execution: inout A) throws -> [[IntervalHomogeneousSurfaceControl]] {
            try trimmedControls(
                values,
                sourceULower: sourceULower,
                sourceUUpper: sourceUUpper,
                sourceVLower: sourceVLower,
                sourceVUpper: sourceVUpper,
                targetU: targetU,
                targetV: targetV,
                tolerance: tolerance
            , using: &execution)
        }
        return try HomogeneousJetControls(
            value: try localized(controls.value, using: &execution),
            derivativeU: try localized(controls.derivativeU, using: &execution),
            derivativeV: try localized(controls.derivativeV, using: &execution),
            secondDerivativeUU: try localized(controls.secondDerivativeUU, using: &execution),
            secondDerivativeUV: try localized(controls.secondDerivativeUV, using: &execution),
            secondDerivativeVV: try localized(controls.secondDerivativeVV, using: &execution),
            thirdDerivativeUUU: try localized(controls.thirdDerivativeUUU, using: &execution),
            thirdDerivativeUUV: try localized(controls.thirdDerivativeUUV, using: &execution),
            thirdDerivativeUVV: try localized(controls.thirdDerivativeUVV, using: &execution),
            thirdDerivativeVVV: try localized(controls.thirdDerivativeVVV, using: &execution)
        )
    }

    private func scalarJet<A: ExactScalarAdmission & ~Copyable>(
        _ controls: HomogeneousJetControls,
        component: (IntervalHomogeneousSurfaceControl) -> OutwardScalarInterval
    , using execution: inout A) throws -> SurfaceIntervalJet {
        func enclosure(_ values: [[IntervalHomogeneousSurfaceControl]], using execution: inout A) throws -> OutwardScalarInterval {
            try scalarValue(values,component:component, using: &execution)
        }
        return SurfaceIntervalJet(
            value: try enclosure(controls.value, using: &execution),
            derivativeU: try enclosure(controls.derivativeU, using: &execution),
            derivativeV: try enclosure(controls.derivativeV, using: &execution),
            secondDerivativeUU: try enclosure(controls.secondDerivativeUU, using: &execution),
            secondDerivativeUV: try enclosure(controls.secondDerivativeUV, using: &execution),
            secondDerivativeVV: try enclosure(controls.secondDerivativeVV, using: &execution),
            thirdDerivativeUUU: try enclosure(controls.thirdDerivativeUUU, using: &execution),
            thirdDerivativeUUV: try enclosure(controls.thirdDerivativeUUV, using: &execution),
            thirdDerivativeUVV: try enclosure(controls.thirdDerivativeUVV, using: &execution),
            thirdDerivativeVVV: try enclosure(controls.thirdDerivativeVVV, using: &execution)
        )
    }

    private func trimmedControls<A: ExactScalarAdmission & ~Copyable>(
        _ source: [[IntervalHomogeneousSurfaceControl]],
        sourceULower: Double,
        sourceUUpper: Double,
        sourceVLower: Double,
        sourceVUpper: Double,
        targetU: ScalarInterval,
        targetV: ScalarInterval,
        tolerance: ModelingTolerance
    , using execution: inout A) throws -> [[IntervalHomogeneousSurfaceControl]] {
        var controls = source
        var currentULower = sourceULower
        if targetU.lower > currentULower {
            let parameter = try normalizedParameter(
                targetU.lower,
                lower: currentULower,
                upper: sourceUUpper,
                tolerance: tolerance
            , using: &execution)
            controls = try splitU(controls, parameter: parameter, using: &execution).upper
            currentULower = targetU.lower
        }
        if targetU.upper < sourceUUpper {
            let parameter = try normalizedParameter(
                targetU.upper,
                lower: currentULower,
                upper: sourceUUpper,
                tolerance: tolerance
            , using: &execution)
            controls = try splitU(controls, parameter: parameter, using: &execution).lower
        }
        var currentVLower = sourceVLower
        if targetV.lower > currentVLower {
            let parameter = try normalizedParameter(
                targetV.lower,
                lower: currentVLower,
                upper: sourceVUpper,
                tolerance: tolerance
            , using: &execution)
            controls = try splitV(controls, parameter: parameter, using: &execution).upper
            currentVLower = targetV.lower
        }
        if targetV.upper < sourceVUpper {
            let parameter = try normalizedParameter(
                targetV.upper,
                lower: currentVLower,
                upper: sourceVUpper,
                tolerance: tolerance
            , using: &execution)
            controls = try splitV(controls, parameter: parameter, using: &execution).lower
        }
        return controls
    }

    private func normalizedParameter<A: ExactScalarAdmission & ~Copyable>(
        _ value: Double,
        lower: Double,
        upper: Double,
        tolerance: ModelingTolerance
    , using execution: inout A) throws -> OutwardScalarInterval {
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

    private func splitU<A: ExactScalarAdmission & ~Copyable>(
        _ controls: [[IntervalHomogeneousSurfaceControl]],
        parameter: OutwardScalarInterval
    , using execution: inout A) throws -> (
        lower: [[IntervalHomogeneousSurfaceControl]],
        upper: [[IntervalHomogeneousSurfaceControl]]
    ) {
        try OriginalCoefficientAllocation.reserve(count: controls.count, of: (lower: [IntervalHomogeneousSurfaceControl], upper: [IntervalHomogeneousSurfaceControl]).self, using: &execution)
        try OriginalCoefficientAllocation.reserve(count: controls.count, of: [IntervalHomogeneousSurfaceControl].self, using: &execution)
        try OriginalCoefficientAllocation.reserve(count: controls.count, of: [IntervalHomogeneousSurfaceControl].self, using: &execution)
        let splits = try controls.map { try split($0, parameter: parameter, using: &execution) }
        return (splits.map({ $0.lower }), splits.map({ $0.upper }))
    }

    private func splitV<A: ExactScalarAdmission & ~Copyable>(
        _ controls: [[IntervalHomogeneousSurfaceControl]],
        parameter: OutwardScalarInterval
    , using execution: inout A) throws -> (
        lower: [[IntervalHomogeneousSurfaceControl]],
        upper: [[IntervalHomogeneousSurfaceControl]]
    ) {
        guard controls.count > 1 else { return (controls, controls) }
        try OriginalCoefficientAllocation.reserve(count: controls.count, of: [[IntervalHomogeneousSurfaceControl]].self, using: &execution)
        try OriginalCoefficientAllocation.reserve(count: controls.count, of: [IntervalHomogeneousSurfaceControl].self, using: &execution)
        try OriginalCoefficientAllocation.reserve(count: controls.count, of: [IntervalHomogeneousSurfaceControl].self, using: &execution)
        var levels: [[[IntervalHomogeneousSurfaceControl]]] = []
        levels.reserveCapacity(controls.count)
        levels.append(controls)
        while let previous = levels.last, previous.count > 1 {
            try OriginalCoefficientAllocation.reserve(count: previous.count - 1, of: [IntervalHomogeneousSurfaceControl].self, using: &execution)
            levels.append(try (0..<(previous.count - 1)).map { rowIndex in
                try OriginalCoefficientAllocation.reserve(count: previous[rowIndex].count, of: IntervalHomogeneousSurfaceControl.self, using: &execution)
                return try previous[rowIndex].indices.map { columnIndex in
                    try execution.consumeWork(1)
                    return previous[rowIndex][columnIndex].interpolated(
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

    private func split<A: ExactScalarAdmission & ~Copyable>(
        _ controls: [IntervalHomogeneousSurfaceControl],
        parameter: OutwardScalarInterval
    , using execution: inout A) throws -> (
        lower: [IntervalHomogeneousSurfaceControl],
        upper: [IntervalHomogeneousSurfaceControl]
    ) {
        guard controls.count > 1 else { return (controls, controls) }
        try OriginalCoefficientAllocation.reserve(count: controls.count, of: [IntervalHomogeneousSurfaceControl].self, using: &execution)
        try OriginalCoefficientAllocation.reserve(count: controls.count, of: IntervalHomogeneousSurfaceControl.self, using: &execution)
        try OriginalCoefficientAllocation.reserve(count: controls.count, of: IntervalHomogeneousSurfaceControl.self, using: &execution)
        var levels: [[IntervalHomogeneousSurfaceControl]] = []
        levels.reserveCapacity(controls.count)
        levels.append(controls)
        while let previous = levels.last, previous.count > 1 {
            try OriginalCoefficientAllocation.reserve(count: previous.count - 1, of: IntervalHomogeneousSurfaceControl.self, using: &execution)
            levels.append(try (0..<(previous.count - 1)).map { index in
                try execution.consumeWork(1)
                return previous[index].interpolated(
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

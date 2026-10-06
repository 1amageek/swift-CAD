import CADCore
import Foundation

/// Prepares original endpoint differential authority once for a mesh operation.
package struct OriginalBSplinePoleNormal: Sendable {
    package enum Direction: Sendable, Equatable { case constantU, constantV }
    private let surface: BSplineSurface3D
    private let tolerance: ModelingTolerance
    private let prepared: PreparedBSplineSurfaceDifferentialEncloser

    package init(surface: BSplineSurface3D, tolerance: ModelingTolerance,
        consumeWork: () throws -> Void) throws {
        self.surface = surface; self.tolerance = tolerance
        prepared = try PreparedBSplineSurfaceDifferentialEncloser(surface: surface,
            tolerance: tolerance, consumeWork: consumeWork)
    }

    package init(surface: BSplineSurface3D, tolerance: ModelingTolerance,
        prepared: PreparedBSplineSurfaceDifferentialEncloser) {
        self.surface = surface; self.tolerance = tolerance; self.prepared = prepared
    }

    /// Optional original collapse recognition; ordinary native edges return nil.
    package func originalCollapsedDirection(over box:SurfaceParameterBox,
        owning span:PreparedBSplineSurfaceDifferentialEncloser.OriginalNativeSpan,
        consumeWork:()throws->Void) throws -> Direction? {
        try span.validate(on:surface,over:box,tolerance:tolerance,consumeWork:consumeWork)
        var candidates:[(Direction,SurfaceParameter)] = []
        if case .closed(let u0, let u1) = surface.uDomain {
            if box.u.lower == u0 { candidates.append((.constantU,.init(u:u0,v:box.v.lower))) }
            if box.u.upper == u1 { candidates.append((.constantU,.init(u:u1,v:box.v.lower))) }
        }
        if case .closed(let v0, let v1) = surface.vDomain {
            if box.v.lower == v0 { candidates.append((.constantV,.init(u:box.u.lower,v:v0))) }
            if box.v.upper == v1 { candidates.append((.constantV,.init(u:box.u.lower,v:v1))) }
        }
        for (direction,parameter) in candidates {
            do {
                _ = try collapseSign(at:parameter,direction:direction,consumeWork:consumeWork)
                return direction
            } catch let error as KernelError where error.code == .invalidInput {
                // Validated source and owning box remain bound. Only a missing
                // exact clamped collapse witness authorizes this optional nil.
                continue
            }
        }
        return nil
    }

    package func prepareExactPanelIfCollapsed<B:RationalAlgebraAdmitting>(over box:SurfaceParameterBox,
        owning span:PreparedBSplineSurfaceDifferentialEncloser.OriginalNativeSpan,
        usage:inout B) throws -> OriginalExactBSplinePoleNormal? {
        try span.validate(on: surface, over: box, tolerance: tolerance,
          consumeWork: { try usage.consumeExactWork(1) })
        var candidates: [(Direction, SurfaceParameter)] = []
        if case .closed(let u0, let u1) = surface.uDomain {
            if box.u.lower == u0 { candidates.append((.constantU, .init(u: u0, v: box.v.lower))) }
            if box.u.upper == u1 { candidates.append((.constantU, .init(u: u1, v: box.v.lower))) }
        }
        if case .closed(let v0, let v1) = surface.vDomain {
            if box.v.lower == v0 { candidates.append((.constantV, .init(u: box.u.lower, v: v0))) }
            if box.v.upper == v1 { candidates.append((.constantV, .init(u: box.u.lower, v: v1))) }
        }
        var result: OriginalExactBSplinePoleNormal?
        for (direction, station) in candidates {
            let sign: Double
            do {
                sign = try collapseSign(at: station, direction: direction,
                    consumeWork: { try usage.consumeExactWork(1) })
            } catch let error as KernelError where error.code == .invalidInput {
                continue
            }
            let boundary = direction == .constantU ? station.u : station.v
            if let current = result {
                result = try current.removingBoundaryFactor(direction: direction, boundary: boundary,
                    inwardSign: sign, usage: &usage)
            } else {
                let original = try OriginalRationalSurfacePolynomial(source: surface, native: span,
                    domain: box, view: .zero, tolerance: tolerance, usage: &usage)
                result = try .init(original: original, span: span, direction: direction,
                    boundary: boundary, inwardSign: sign, tolerance: tolerance, usage: &usage)
            }
        }
        return result
    }

    package func collapsedPoint(at parameter:SurfaceParameter,direction:Direction,
        consumeWork:()throws->Void) throws -> Point3D {
        _ = try collapseSign(at:parameter,direction:direction,consumeWork:consumeWork)
        switch direction {
        case .constantU:
            return surface.controlPoints[0][parameter.u == surface.uKnots[surface.uDegree] ? 0 : surface.uControlPointCount-1]
        case .constantV:
            return surface.controlPoints[parameter.v == surface.vKnots[surface.vDegree] ? 0 : surface.vControlPointCount-1][0]
        }
    }

    // FIXME(INCOMPLETE_IMPLEMENTATION): Mesh pole normals currently use the
    // first original nonzero normal coefficient. Higher-order collapsed supports
    // require exact preceding-coefficient zero proofs before they may succeed.
    package func normal(at parameter: SurfaceParameter, direction: Direction,
        consumeWork: () throws -> Void) throws -> OriginalBSplinePoleNormalReceipt {
        try Task.checkCancellation(); try consumeWork()
        let sign = try collapseSign(at: parameter, direction: direction, consumeWork: consumeWork)
        try consumeWork()
        let jet = try prepared.intervalJet(overClosedBox: .init(
            u: ScalarInterval(lower: parameter.u, upper: parameter.u),
            v: ScalarInterval(lower: parameter.v, upper: parameter.v)), tolerance: tolerance)
        func vector(_ field: KeyPath<SurfaceIntervalJet, OutwardScalarInterval>) -> IntervalVector3DBounds {
            .init(x: jet.x[keyPath: field], y: jet.y[keyPath: field], z: jet.z[keyPath: field])
        }
        let mixed = vector(\.secondDerivativeUV)
        let coefficient = (direction == .constantU
            ? vector(\.derivativeU).cross(mixed)
            : mixed.cross(vector(\.derivativeV))) * .exact(sign)
        let low = coefficient.lengthLowerBound, high = coefficient.lengthUpperBound
        guard low.isFinite, high.isFinite, low > 0 else {
            throw failure(.singularGeometry, "Original first inward normal coefficient is not certified nonzero.")
        }
        let representative = coefficient.midpoint
        let representativeLength = representative.length
        guard representativeLength.isFinite, representativeLength > 0 else {
            throw failure(.singularGeometry, "Original pole normal representative has no finite positive length.")
        }
        let normal = representative / representativeLength
        let length = OutwardScalarInterval(lower: low, upper: high)
        guard let x = coefficient.x.divided(by: length),
              let y = coefficient.y.divided(by: length),
              let z = coefficient.z.divided(by: length) else {
            throw failure(.singularGeometry, "Original inward normal coefficient cannot be normalized.")
        }
        let spread = IntervalVector3DBounds(x: x - .exact(normal.x),
            y: y - .exact(normal.y), z: z - .exact(normal.z)).lengthUpperBound
        let angle = (2 * asin(min(1, spread / 2))).nextUp
        guard angle.isFinite, angle <= tolerance.angle else {
            throw failure(.approximationToleranceRejected, "Original pole normal cone exceeds the requested angle bound.")
        }
        return .init(surface: surface, parameter: parameter, normal: normal,
            angularDeviationUpperBound: angle, coefficientBounds: coefficient, tolerance: tolerance)
    }


    /// Original normal divided by the exact inward endpoint factor on one closed panel.
    package func panelBounds(over box: SurfaceParameterBox, direction: Direction,
        owning originalSpan: PreparedBSplineSurfaceDifferentialEncloser.OriginalNativeSpan? = nil,
        consumeWork: () throws -> Void) throws -> OriginalBSplinePoleNormalPanel {
        try Task.checkCancellation(); try consumeWork()
        let parameter: SurfaceParameter
        switch direction {
        case .constantU:
            guard case .closed(let u0, let u1) = surface.uDomain else {
                throw failure(.invalidInput, "Original constant-U factors require a closed native U domain.")
            }
            guard box.u.lower == u0 || box.u.upper == u1 else {
                throw failure(.invalidInput, "Pole panel does not include its original constant-U endpoint.")
            }
            parameter = .init(u: box.u.lower == u0 ? u0 : u1, v: box.v.lower)
        case .constantV:
            guard case .closed(let v0, let v1) = surface.vDomain else {
                throw failure(.invalidInput, "Original constant-V factors require a closed native V domain.")
            }
            guard box.v.lower == v0 || box.v.upper == v1 else {
                throw failure(.invalidInput, "Pole panel does not include its original constant-V endpoint.")
            }
            parameter = .init(u: box.u.lower, v: box.v.lower == v0 ? v0 : v1)
        }
        let sign = try collapseSign(at: parameter, direction: direction, consumeWork: consumeWork)
        let span: PreparedBSplineSurfaceDifferentialEncloser.OriginalNativeSpan
        if let originalSpan {
            try originalSpan.validate(on: surface, over: box, tolerance: tolerance,consumeWork:consumeWork)
            span = originalSpan
        } else {
            let spans = try prepared.originalNativeSpans(over: box, tolerance: tolerance,
                maximumSpanCount: 1, consumeWork: consumeWork)
            guard spans.count == 1, let original = spans.first else {
                throw failure(.invalidInput, "Pole normal panel requires one original owning native span.")
            }
            span = original
        }
        try consumeWork()
        let jet = try span.intervalJet(overClosedBox: box, on: surface, tolerance: tolerance,consumeWork:consumeWork)
        func vector(_ field: KeyPath<SurfaceIntervalJet, OutwardScalarInterval>) -> IntervalVector3DBounds {
            .init(x: jet.x[keyPath: field], y: jet.y[keyPath: field], z: jet.z[keyPath: field])
        }
        let u = vector(\.derivativeU), v = vector(\.derivativeV)
        let uu = vector(\.secondDerivativeUU), uv = vector(\.secondDerivativeUV)
        let vv = vector(\.secondDerivativeVV), uuu = vector(\.thirdDerivativeUUU)
        let uuv = vector(\.thirdDerivativeUUV), uvv = vector(\.thirdDerivativeUVV)
        let vvv = vector(\.thirdDerivativeVVV)
        try consumeWork()
        let mixed = uuv.cross(v) + uu.cross(vv) + u.cross(uvv)
        let factor: IntervalVector3DBounds
        let derivativeU: Double, derivativeV: Double
        switch direction {
        case .constantU:
            factor = (uu.cross(v) + u.cross(uv)) * .exact(sign)
            derivativeU = ((uuu.cross(v) + uu.cross(uv) * .exact(2) + u.cross(uuv))
                .lengthUpperBound * 0.5).nextUp
            derivativeV = mixed.lengthUpperBound
        case .constantV:
            factor = (uv.cross(v) + u.cross(vv)) * .exact(sign)
            derivativeU = mixed.lengthUpperBound
            derivativeV = ((uvv.cross(v) + uv.cross(vv) * .exact(2) + u.cross(vvv))
                .lengthUpperBound * 0.5).nextUp
        }
        let lower = factor.lengthLowerBound
        guard lower.isFinite, lower > 0, derivativeU.isFinite, derivativeV.isFinite else {
            throw failure(.singularGeometry, "Original first normal factor is not certified nonzero on this whole panel.")
        }
        let normalU = (derivativeU / lower).nextUp, normalV = (derivativeV / lower).nextUp
        guard normalU.isFinite, normalV.isFinite else {
            throw failure(.resourceLimitExceeded, "Original factored normal derivative bounds are nonfinite.")
        }
        return .init(surface: surface, parameters: box, span: span, direction: direction,
            factorBounds: factor, tolerance: tolerance,
            differentialBounds: .init(tangentUMagnitudeUpperBound: u.lengthUpperBound,
                tangentVMagnitudeUpperBound: v.lengthUpperBound,
                secondDerivativeUUMagnitudeUpperBound: uu.lengthUpperBound,
                secondDerivativeUVMagnitudeUpperBound: uv.lengthUpperBound,
                secondDerivativeVVMagnitudeUpperBound: vv.lengthUpperBound,
                unitNormalDerivativeUMagnitudeUpperBound: normalU,
                unitNormalDerivativeVMagnitudeUpperBound: normalV))
    }

    package func prepareExactPanel<B:RationalAlgebraAdmitting>(over box:SurfaceParameterBox,direction:Direction,
        owning span:PreparedBSplineSurfaceDifferentialEncloser.OriginalNativeSpan,
        usage:inout B) throws -> OriginalExactBSplinePoleNormal {
        let station:SurfaceParameter
        switch direction {
        case .constantU:
            guard case .closed(let u0, let u1) = surface.uDomain else {
                throw failure(.invalidInput, "Original constant-U factors require a closed native U domain.")
            }
            guard box.u.lower == u0 || box.u.upper == u1 else { throw failure(.invalidInput,"Exact normal panel does not own an original U boundary.") }
            station = .init(u:box.u.lower == u0 ? u0 : u1,v:box.v.lower)
        case .constantV:
            guard case .closed(let v0, let v1) = surface.vDomain else {
                throw failure(.invalidInput, "Original constant-V factors require a closed native V domain.")
            }
            guard box.v.lower == v0 || box.v.upper == v1 else { throw failure(.invalidInput,"Exact normal panel does not own an original V boundary.") }
            station = .init(u:box.u.lower,v:box.v.lower == v0 ? v0 : v1)
        }
        let sign = try collapseSign(at:station,direction:direction,consumeWork:{ try usage.consumeExactWork(1) })
        let original = try OriginalRationalSurfacePolynomial(source:surface,native:span,domain:box,view:.zero,tolerance:tolerance,usage:&usage)
        return try .init(original:original,span:span,direction:direction,boundary:direction == .constantU ? station.u : station.v,
            inwardSign:sign,tolerance:tolerance,usage:&usage)
    }

    private func collapseSign(at parameter: SurfaceParameter, direction: Direction,
        consumeWork: () throws -> Void) throws -> Double {
        guard parameter.u.isFinite, parameter.v.isFinite,
              containsOriginal(parameter.u, in: surface.uDomain),
              containsOriginal(parameter.v, in: surface.vDomain) else {
            throw failure(.invalidInput, "Original pole normals require a finite native endpoint parameter.")
        }
        let sign: Double
        switch direction {
        case .constantU:
            guard case .closed(let u0, let u1) = surface.uDomain else {
                throw failure(.invalidInput, "A periodic U seam is not an original clamped pole.")
            }
            guard parameter.u == u0 || parameter.u == u1 else {
                throw failure(.invalidInput, "A constant-U pole must be an original native endpoint.")
            }
            let lower = parameter.u == u0
            let knots = lower ? surface.uKnots.prefix(surface.uDegree + 1)
                : surface.uKnots.suffix(surface.uDegree + 1)
            guard knots.allSatisfy({ $0 == parameter.u }) else {
                throw failure(.invalidInput, "A constant-U pole needs an original clamped endpoint.")
            }
            let column = lower ? 0 : surface.uControlPointCount - 1
            let first = surface.controlPoints[0][column]
            for row in surface.controlPoints {
                try consumeWork()
                guard row[column] == first else {
                    throw failure(.invalidInput, "Original endpoint column does not collapse to one point.")
                }
            }
            sign = lower ? 1 : -1
        case .constantV:
            guard case .closed(let v0, let v1) = surface.vDomain else {
                throw failure(.invalidInput, "A periodic V seam is not an original clamped pole.")
            }
            guard parameter.v == v0 || parameter.v == v1 else {
                throw failure(.invalidInput, "A constant-V pole must be an original native endpoint.")
            }
            let lower = parameter.v == v0
            let knots = lower ? surface.vKnots.prefix(surface.vDegree + 1)
                : surface.vKnots.suffix(surface.vDegree + 1)
            guard knots.allSatisfy({ $0 == parameter.v }) else {
                throw failure(.invalidInput, "A constant-V pole needs an original clamped endpoint.")
            }
            let row = surface.controlPoints[lower ? 0 : surface.vControlPointCount - 1]
            guard let first = row.first else { throw failure(.invalidInput, "Original pole row is empty.") }
            for point in row {
                try consumeWork()
                guard point == first else {
                    throw failure(.invalidInput, "Original endpoint row does not collapse to one point.")
                }
            }
            sign = lower ? 1 : -1
        }
        return sign
    }

    private func containsOriginal(_ parameter: Double, in domain: ParameterDomain) -> Bool {
        switch domain {
        case .closed(let lower, let upper): return parameter >= lower && parameter <= upper
        case .periodic: return parameter.isFinite
        case .unbounded: return false
        }
    }

    private func failure(_ code: KernelErrorCode, _ message: String) -> KernelError {
        .init(phase: .geometry, code: code, tolerance: tolerance, message: message)
    }
}

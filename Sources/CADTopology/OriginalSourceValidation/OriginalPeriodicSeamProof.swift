import CADCore
import CADGeometry

/// Whole original chart-law equality under selected direction and a support period shift.
struct OriginalPeriodicSeamProof {
    private struct UV {
        let u: ExactRationalCoefficient
        let v: ExactRationalCoefficient
    }

    static func proves(first: SurfaceParameterCurve, second: SurfaceParameterCurve,
        on surface: Surface3D, tolerance: ModelingTolerance, remainingSourceDepth: Int,
        maximumSubdivisionDepth: Int, consumeWork: @Sendable (Int) throws -> Void,
        consumeStorage: (@Sendable (Int) throws -> Void)? = nil, maximumAlgebraicDepth: Int? = nil,
        secondIsReversed: Bool = true) throws -> Bool {
        try first.validate(on: surface, tolerance: tolerance, remainingSourceDepth: remainingSourceDepth,
            maximumSubdivisionDepth: maximumSubdivisionDepth, consumeWork: consumeWork, consumeStorage: consumeStorage, maximumAlgebraicDepth: maximumAlgebraicDepth)
        try second.validate(on: surface, tolerance: tolerance, remainingSourceDepth: remainingSourceDepth,
            maximumSubdivisionDepth: maximumSubdivisionDepth, consumeWork: consumeWork, consumeStorage: consumeStorage, maximumAlgebraicDepth: maximumAlgebraicDepth)
        var usage = OriginalSourceProofAdmission(consumeWork: consumeWork, consumeStorage: consumeStorage, maximumAlgebraicDepth: maximumAlgebraicDepth)
        func original(_ value: Double) throws -> ExactRationalCoefficient {
            try .originalDouble(value, usage: &usage)
        }
        func uv(_ u: Double, _ v: Double) throws -> UV {
            try .init(u: original(u), v: original(v))
        }
        func directed(_ endpoints: (UV, UV), from start: Double, to end: Double) throws -> (UV, UV) {
            let du = try endpoints.1.u.subtracting(endpoints.0.u, usage: &usage)
            let dv = try endpoints.1.v.subtracting(endpoints.0.v, usage: &usage)
            func station(_ fraction: Double) throws -> UV {
                let f = try original(fraction)
                return try .init(u: endpoints.0.u.adding(du.multiplied(by: f, usage: &usage), usage: &usage),
                    v: endpoints.0.v.adding(dv.multiplied(by: f, usage: &usage), usage: &usage))
            }
            return try (station(start), station(end))
        }
        func linearEnds(_ curve: SurfaceParameterCurve, depth: Int) throws -> (UV, UV)? {
            try usage.consumeExactWork(1)
            switch curve {
            case .constantU(let u, let start, let end):
                return try (uv(u, start), uv(u, end))
            case .constantV(let v, let start, let end):
                return try (uv(start, v), uv(end, v))
            case .affine(let origin, let direction, let start, let end):
                let x = try original(origin.x), y = try original(origin.y)
                let dx = try original(direction.x), dy = try original(direction.y)
                func point(_ parameter: Double) throws -> UV {
                    let t = try original(parameter)
                    return try .init(u: x.adding(dx.multiplied(by: t, usage: &usage), usage: &usage),
                        v: y.adding(dy.multiplied(by: t, usage: &usage), usage: &usage))
                }
                return try (point(start), point(end))
            case .originalAffineWord(let image):
                guard depth > 0 else {
                    throw GeometryConversionError.resourceLimitExceeded("Original word seam chart exhausted source depth.")
                }
                guard let endpoints = try linearEnds(image.source.parameterCurve, depth: depth - 1) else { return nil }
                return try directed(endpoints, from: image.startFraction, to: image.endFraction)
            case .originalImage(let image):
                guard depth > 0 else {
                    throw GeometryConversionError.resourceLimitExceeded("Original image seam chart exhausted source depth.")
                }
                guard let endpoints = try linearEnds(image.source.parameterCurve, depth: depth - 1) else { return nil }
                let selected = try directed(endpoints, from: image.startFraction, to: image.endFraction)
                let gu = try image.targetImage.uParameterGain.exactCoefficient(usage: &usage)
                let gv = try image.targetImage.vParameterGain.exactCoefficient(usage: &usage)
                let ou = try original(image.targetImage.uOffset), ov = try original(image.targetImage.vOffset)
                func foreign(_ point: UV) throws -> UV {
                    let u = image.targetImage.swapAxes ? point.v : point.u
                    let v = image.targetImage.swapAxes ? point.u : point.v
                    return try .init(u: u.subtracting(ou, usage: &usage).divided(by: gu, usage: &usage),
                        v: v.subtracting(ov, usage: &usage).divided(by: gv, usage: &usage))
                }
                return try (foreign(selected.0), foreign(selected.1))
            case .offsetSurfaceImage(let image):
                guard depth > 0 else {
                    throw GeometryConversionError.resourceLimitExceeded("Original offset seam chart exhausted source depth.")
                }
                return try linearEnds(image.source, depth: depth - 1)
            case .periodicTranslation(let base, let u, let v):
                guard depth > 0 else {
                    throw GeometryConversionError.resourceLimitExceeded("Original seam chart exhausted source depth.")
                }
                guard let endpoints = try linearEnds(base, depth: depth - 1) else { return nil }
                let du = try original(u), dv = try original(v)
                func translated(_ point: UV) throws -> UV {
                    try .init(u: point.u.adding(du, usage: &usage), v: point.v.adding(dv, usage: &usage))
                }
                return try (translated(endpoints.0), translated(endpoints.1))
            default: return nil
            }
        }
        func difference(_ first: UV, _ second: UV) throws -> UV {
            try .init(u: first.u.subtracting(second.u, usage: &usage),
                v: first.v.subtracting(second.v, usage: &usage))
        }
        let displacement: UV
        if let firstEnds = try linearEnds(first, depth: remainingSourceDepth),
            let secondEnds = try linearEnds(second, depth: remainingSourceDepth) {
            displacement = try difference(firstEnds.0, secondIsReversed ? secondEnds.1 : secondEnds.0)
            let final = try difference(firstEnds.1, secondIsReversed ? secondEnds.0 : secondEnds.1)
            guard displacement.u == final.u, displacement.v == final.v else { return false }
        } else if case .bSpline(let a) = first, case .bSpline(let b) = second {
            guard a.degree == b.degree, a.controlPoints.count == b.controlPoints.count,
                a.knots.count == b.knots.count, let firstPoint = a.controlPoints.first,
                let secondPoint = secondIsReversed ? b.controlPoints.last : b.controlPoints.first else { return false }
            let aLower = try original(a.knots[a.degree])
            let aUpper = try original(a.knots[a.controlPoints.count])
            let bLower = try original(b.knots[b.degree])
            let bUpper = try original(b.knots[b.controlPoints.count])
            let aWidth = try aUpper.subtracting(aLower, usage: &usage)
            let bWidth = try bUpper.subtracting(bLower, usage: &usage)
            for index in a.knots.indices {
                try usage.consumeExactWork(1)
                let ak = try original(a.knots[index]).subtracting(aLower, usage: &usage)
                let bk = try secondIsReversed
                    ? bUpper.subtracting(original(b.knots[b.knots.count - index - 1]), usage: &usage)
                    : original(b.knots[index]).subtracting(bLower, usage: &usage)
                guard try ak.multiplied(by: bWidth, usage: &usage)
                    == bk.multiplied(by: aWidth, usage: &usage) else { return false }
            }
            displacement = try difference(uv(firstPoint.x, firstPoint.y), uv(secondPoint.x, secondPoint.y))
            let wa = try original(a.weights[0])
            let wb = try original(b.weights[secondIsReversed ? b.weights.count - 1 : 0])
            for index in a.controlPoints.indices {
                try usage.consumeExactWork(1)
                let counterpart = secondIsReversed ? b.controlPoints.count - index - 1 : index
                let delta = try difference(uv(a.controlPoints[index].x, a.controlPoints[index].y),
                    uv(b.controlPoints[counterpart].x, b.controlPoints[counterpart].y))
                guard delta.u == displacement.u, delta.v == displacement.v,
                    try original(a.weights[index]).multiplied(by: wb, usage: &usage)
                        == original(b.weights[counterpart]).multiplied(by: wa, usage: &usage) else { return false }
            }
        } else {
            // FIXME(INCOMPLETE_IMPLEMENTATION): Bounded periodic BRep seams
            // require whole directed chart equality for image, transcendental
            // and implicit families. Linear/native exact laws alone cannot
            // admit those source branches or authorize full validation.
            throw KernelError(phase: .topology, code: .unsupportedCapability, tolerance: tolerance,
                message: "Original seam equality needs the retained whole chart-law producer.")
        }
        guard !displacement.u.isZero || !displacement.v.isZero else { return false }
        return try OriginalSurfacePeriodShift.proves(on: surface, u: displacement.u, v: displacement.v,
            remainingSourceDepth: remainingSourceDepth, maximumSubdivisionDepth: maximumSubdivisionDepth,
            tolerance: tolerance, usage: &usage)
    }
}

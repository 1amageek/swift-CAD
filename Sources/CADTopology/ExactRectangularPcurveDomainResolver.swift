import CADCore
import CADGeometry

package struct ExactRectangularPcurveDomain: Sendable, Hashable {
    package let uLower: Double
    package let uUpper: Double
    package let vLower: Double
    package let vUpper: Double
}

/// Recognizes an exact axis-aligned rectangular outer pcurve loop: four sides, each one pcurve or
/// several running straight on along the same parameter line (a merged face whose sides are
/// made of the edges it shares with several neighbours).
package struct ExactRectangularPcurveDomainResolver:
    ExactRectangularPcurveDomainResolving,
    Sendable
{
    private let consumeWork: (@Sendable (Int) throws -> Void)?
    private let consumeStorage: (@Sendable (Int) throws -> Void)?
    private let remainingSourceDepth: Int

    package init(consumeWork: (@Sendable (Int) throws -> Void)? = nil,
        consumeStorage: (@Sendable (Int) throws -> Void)? = nil,
        remainingSourceDepth: Int = 16) {
        self.consumeWork = consumeWork
        self.consumeStorage = consumeStorage
        self.remainingSourceDepth = remainingSourceDepth
    }

    package func resolve(face: Face, model: BRepModel, tolerance: ModelingTolerance,
        maximumSubdivisionDepth: Int, remainingSourceDepth: Int,
        consumeWork: (@Sendable (Int) throws -> Void)?,
        consumeStorage: (@Sendable (Int) throws -> Void)?) throws -> ExactRectangularPcurveDomain? {
        guard maximumSubdivisionDepth >= 0, remainingSourceDepth >= 0 else {
            throw KernelError(phase: .topology, code: .invalidInput,
                tolerance: tolerance, message: "Original rectangle proof requires nonnegative caller depths.")
        }
        return try Self(consumeWork: consumeWork, consumeStorage: consumeStorage,
            remainingSourceDepth: min(16, remainingSourceDepth))
            .resolve(face: face, model: model, tolerance: tolerance)
    }

    package func axisAlignedEndpoints(of curve: SurfaceParameterCurve, on surface: Surface3D,
        remainingSourceDepth: Int = 16,
        consumeWork: (@Sendable (Int) throws -> Void)? = nil,
        consumeStorage: (@Sendable (Int) throws -> Void)? = nil,
        tolerance: ModelingTolerance) throws -> ExactRectangularPcurveAxisEndpoints? {
        try tolerance.validate()
        let invocation = Self(consumeWork: consumeWork, consumeStorage: consumeStorage,
            remainingSourceDepth: min(16, remainingSourceDepth))
        guard let endpoints = try invocation.axisAlignedVertices(of: curve, on: surface,
            remainingDepth: min(16, remainingSourceDepth), tolerance: tolerance),
            endpoints.0.u.isFinite, endpoints.0.v.isFinite,
            endpoints.1.u.isFinite, endpoints.1.v.isFinite,
            (endpoints.0.u == endpoints.1.u) != (endpoints.0.v == endpoints.1.v) else { return nil }
        return ExactRectangularPcurveAxisEndpoints(curve: curve, surface: surface,
            tolerance: tolerance, start: endpoints.0, end: endpoints.1)
    }

    private func visit() throws {
        try Task.checkCancellation()
        try consumeWork?(0)
    }

    package func resolve(
        face: Face,
        model: BRepModel,
        tolerance: ModelingTolerance
    ) throws -> ExactRectangularPcurveDomain? {
        try tolerance.validate()
        try visit()
        guard face.loops.count == 1,
              let loopID = face.loops.first,
              let loop = model.loops[loopID],
              loop.role == .outer,
              loop.coedges.count >= 4 else {
            return nil
        }
        guard let surface = model.geometry.surfaces[face.surfaceID] else {
            throw TopologyError.missingReference("A rectangular face support is missing.")
        }
        var vertices: [SurfaceParameter] = []
        let capacity = loop.coedges.count.addingReportingOverflow(1)
        guard !capacity.overflow else {
            throw KernelError(phase: .topology, code: .resourceLimitExceeded,
                tolerance: tolerance, message: "Original rectangle endpoint count overflowed.")
        }
        try OriginalParameterQueryStorage.reserve(capacity.partialValue, in: &vertices,
            consumeStorage: consumeStorage)
        for coedge in loop.coedges {
            try visit()
            guard let curve = coedge.surfaceParameterCurve,
                  let endpoints = try axisAlignedVertices(of: curve, on: surface,
                      remainingDepth: remainingSourceDepth, tolerance: tolerance) else { return nil }
            if let previous = vertices.last, previous != endpoints.0 { return nil }
            if vertices.isEmpty { vertices.append(endpoints.0) }
            vertices.append(endpoints.1)
        }
        guard vertices.count == loop.coedges.count + 1,
              let first = vertices.first,
              let last = vertices.last,
              first == last else {
            return nil
        }
        // Corners only: a vertex between two pieces running straight on along one parameter
        // line, the same way, is no corner.
        // The admitted endpoint storage is uniquely owned and reused for corners.
        vertices.removeLast()
        var closedVertices = vertices
        vertices = []
        var index = 0
        while closedVertices.count > 4, index < closedVertices.count {
            try visit()
            let count = closedVertices.count
            let (a, b, c) = (closedVertices[(index + count - 1) % count], closedVertices[index], closedVertices[(index + 1) % count])
            let straightAlongV = a.u == b.u && b.u == c.u && sameDirection(a.v, b.v, c.v)
            let straightAlongU = a.v == b.v && b.v == c.v && sameDirection(a.u, b.u, c.u)
            if straightAlongU || straightAlongV {
                closedVertices.remove(at: index)
                index = 0
            } else {
                index += 1
            }
        }
        guard closedVertices.count == 4 else { return nil }
        var minimumU = Double.infinity, maximumU = -Double.infinity
        var minimumV = Double.infinity, maximumV = -Double.infinity
        for vertex in closedVertices {
            try visit()
            minimumU = min(minimumU, vertex.u); maximumU = max(maximumU, vertex.u)
            minimumV = min(minimumV, vertex.v); maximumV = max(maximumV, vertex.v)
        }
        guard maximumU > minimumU, maximumV > minimumV else { return nil }
        var usedBoundaries: UInt8 = 0
        for index in closedVertices.indices {
            try visit()
            let start = closedVertices[index]
            let end = closedVertices[(index + 1) % closedVertices.count]
            let boundary: Boundary
            if start.u == end.u, start.v != end.v {
                if start.u == minimumU {
                    boundary = .uLower
                } else if start.u == maximumU {
                    boundary = .uUpper
                } else {
                    return nil
                }
                guard ((start.v == minimumV && end.v == maximumV) || (start.v == maximumV && end.v == minimumV)) else {
                    return nil
                }
            } else if start.v == end.v, start.u != end.u {
                if start.v == minimumV {
                    boundary = .vLower
                } else if start.v == maximumV {
                    boundary = .vUpper
                } else {
                    return nil
                }
                guard ((start.u == minimumU && end.u == maximumU) || (start.u == maximumU && end.u == minimumU)) else {
                    return nil
                }
            } else {
                return nil
            }
            let bit = UInt8(1) << boundary.rawValue
            guard usedBoundaries & bit == 0 else { return nil }
            usedBoundaries |= bit
        }
        guard usedBoundaries == 15 else { return nil }
        return ExactRectangularPcurveDomain(
            uLower: minimumU,
            uUpper: maximumU,
            vLower: minimumV,
            vUpper: maximumV
        )
    }

    private func sameDirection(_ a: Double, _ b: Double, _ c: Double) -> Bool {
        (a < b && b < c) || (a > b && b > c)
    }

    private func represented(_ coefficient: ExactRationalCoefficient,
        usage: inout OriginalSourceProofAdmission) throws -> Double? {
        let enclosure = try coefficient.outwardInterval(usage: &usage)
        guard enclosure.isFinite else { return nil }
        if enclosure.lower == enclosure.upper { return enclosure.lower }
        let lower = try ExactRationalCoefficient.originalDouble(enclosure.lower, usage: &usage)
        if try coefficient.subtracting(lower, usage: &usage).isZero { return enclosure.lower }
        let upper = try ExactRationalCoefficient.originalDouble(enclosure.upper, usage: &usage)
        if try coefficient.subtracting(upper, usage: &usage).isZero { return enclosure.upper }
        return nil
    }

    private func affineCoordinate(_ origin: Double, _ direction: Double,
        _ parameter: Double, usage: inout OriginalSourceProofAdmission) throws -> Double? {
        let base = try ExactRationalCoefficient.originalDouble(origin, usage: &usage)
        let slope = try ExactRationalCoefficient.originalDouble(direction, usage: &usage)
        let station = try ExactRationalCoefficient.originalDouble(parameter, usage: &usage)
        let offset = try slope.multiplied(by: station, usage: &usage)
        return try represented(base.adding(offset, usage: &usage), usage: &usage)
    }

    private func axisAlignedVertices(of curve: SurfaceParameterCurve, on surface: Surface3D,
        remainingDepth: Int, tolerance: ModelingTolerance) throws -> (SurfaceParameter, SurfaceParameter)? {
        try visit()
        guard remainingDepth >= 0 else {
            throw KernelError(phase: .topology, code: .resourceLimitExceeded,
                tolerance: tolerance, message: "Original rectangle source nesting exceeded the caller limit.")
        }
        var usage = OriginalSourceProofAdmission(consumeWork: consumeWork, consumeStorage: consumeStorage)
        switch curve {
        case let .constantU(u, vStart, vEnd):
            return (SurfaceParameter(u: u, v: vStart), SurfaceParameter(u: u, v: vEnd))
        case let .constantV(v, uStart, uEnd):
            return (SurfaceParameter(u: uStart, v: v), SurfaceParameter(u: uEnd, v: v))
        case let .affine(origin, direction, startParameter, endParameter):
            guard (direction.x == 0) != (direction.y == 0),
                let u0 = try affineCoordinate(origin.x, direction.x, startParameter, usage: &usage),
                let v0 = try affineCoordinate(origin.y, direction.y, startParameter, usage: &usage),
                let u1 = try affineCoordinate(origin.x, direction.x, endParameter, usage: &usage),
                let v1 = try affineCoordinate(origin.y, direction.y, endParameter, usage: &usage) else { return nil }
            return (SurfaceParameter(u: u0, v: v0), SurfaceParameter(u: u1, v: v1))
        case let .bSpline(spline):
            try spline.validate(tolerance: tolerance, consumeWork: { try visit() })
            guard spline.degree >= 1, spline.controlPoints.count >= spline.degree + 1,
                spline.knots.count == spline.controlPoints.count + spline.degree + 1,
                spline.weights.count == spline.controlPoints.count,
                let first = spline.controlPoints.first, let last = spline.controlPoints.last,
                case let .closed(lower, upper) = spline.domain, lower < upper else { return nil }
            for index in spline.knots.indices {
                try visit()
                let knot = spline.knots[index]
                guard knot.isFinite, index == 0 || spline.knots[index - 1] <= knot else { return nil }
            }
            for index in 0...spline.degree {
                try visit()
                guard spline.knots[index] == lower,
                    spline.knots[spline.knots.count - 1 - index] == upper else { return nil }
            }
            let alongU = first.y == last.y && first.x != last.x
            let alongV = first.x == last.x && first.y != last.y
            guard alongU != alongV else { return nil }
            let increasing = alongU ? first.x < last.x : first.y < last.y
            var previous = alongU ? first.x : first.y
            for index in spline.controlPoints.indices {
                try visit()
                let point = spline.controlPoints[index], weight = spline.weights[index]
                guard point.x.isFinite, point.y.isFinite, weight.isFinite, weight > 0,
                    (alongU ? point.y == first.y : point.x == first.x) else { return nil }
                let value = alongU ? point.x : point.y
                guard (increasing ? value >= previous : value <= previous) else { return nil }
                previous = value
            }
            return (SurfaceParameter(u: first.x, v: first.y), SurfaceParameter(u: last.x, v: last.y))
        case let .polyline(points):
            guard let first = points.first, let last = points.last, points.count >= 2 else { return nil }
            let alongU = first.v == last.v && first.u != last.u
            let alongV = first.u == last.u && first.v != last.v
            guard alongU != alongV else { return nil }
            let increasing = alongU ? first.u < last.u : first.v < last.v
            var previous = alongU ? first.u : first.v
            for index in points.indices {
                try visit()
                let point = points[index], value = alongU ? point.u : point.v
                guard point.u.isFinite, point.v.isFinite,
                    (alongU ? point.v == first.v : point.u == first.u) else { return nil }
                if index > 0 { guard (increasing ? value >= previous : value <= previous) else { return nil } }
                previous = value
            }
            return (first, last)
        case let .originalImage(image):
            // FIXME(INCOMPLETE_IMPLEMENTATION): Original target/source equality
            // remains a deep immutable comparison without per-item admission.
            // This exact endpoint producer does not certify complete query work.
            guard surface == .parameterImage(image.targetImage),
                image.source.surface == image.targetImage.source else { return nil }
            let forward = image.startFraction == 0 && image.endFraction == 1
            let reverse = image.startFraction == 1 && image.endFraction == 0
            guard forward || reverse,
                let endpoints = try axisAlignedVertices(of: image.source.parameterCurve,
                    on: image.source.surface, remainingDepth: remainingDepth - 1, tolerance: tolerance) else { return nil }
            func mapped(_ point: SurfaceParameter) throws -> SurfaceParameter? {
                let nativeU = image.targetImage.swapAxes ? point.v : point.u
                let nativeV = image.targetImage.swapAxes ? point.u : point.v
                func coordinate(_ native: Double, _ offset: Double, _ gain: OriginalParameterGain) throws -> Double? {
                    let source = try ExactRationalCoefficient.originalDouble(native, usage: &usage)
                    let translation = try ExactRationalCoefficient.originalDouble(offset, usage: &usage)
                    let divisor = try gain.exactCoefficient(usage: &usage)
                    return try represented(source.subtracting(translation, usage: &usage)
                        .divided(by: divisor, usage: &usage), usage: &usage)
                }
                guard let u = try coordinate(nativeU, image.targetImage.uOffset, image.targetImage.uParameterGain),
                    let v = try coordinate(nativeV, image.targetImage.vOffset, image.targetImage.vParameterGain) else { return nil }
                return SurfaceParameter(u: u, v: v)
            }
            guard let first = try mapped(endpoints.0), let second = try mapped(endpoints.1) else { return nil }
            return reverse ? (second, first) : (first, second)
        case let .originalAffineWord(image):
            // FIXME(INCOMPLETE_IMPLEMENTATION): Retained target/source equality
            // still needs an invocation-bound identity receipt for complete work.
            guard surface == .procedural(.originalAffineWord(image.target)),
                image.source.surface == image.target.source else { return nil }
            let forward = image.startFraction == 0 && image.endFraction == 1
            let reverse = image.startFraction == 1 && image.endFraction == 0
            guard forward || reverse,
                let endpoints = try axisAlignedVertices(of: image.source.parameterCurve,
                    on: image.source.surface, remainingDepth: remainingDepth - 1, tolerance: tolerance) else { return nil }
            return reverse ? (endpoints.1, endpoints.0) : endpoints
        case let .offsetSurfaceImage(image):
            return try axisAlignedVertices(of: image.source, on: surface,
                remainingDepth: remainingDepth - 1, tolerance: tolerance)
        case let .periodicTranslation(base, uShift, vShift):
            guard let endpoints = try axisAlignedVertices(of: base, on: surface,
                remainingDepth: remainingDepth - 1, tolerance: tolerance) else { return nil }
            func shifted(_ point: SurfaceParameter) throws -> SurfaceParameter? {
                guard let u = try affineCoordinate(point.u, 1, uShift, usage: &usage),
                    let v = try affineCoordinate(point.v, 1, vShift, usage: &usage) else { return nil }
                return SurfaceParameter(u: u, v: v)
            }
            guard let first = try shifted(endpoints.0), let second = try shifted(endpoints.1) else { return nil }
            return (first, second)
        case .harmonic, .sphericalGreatCircle, .certifiedImplicit,
            .certifiedAnalyticImplicit, .certifiedAnalyticPair, .projectedAnalytic,
            .rigidImage, .originalBSplineContinuation:
            // FIXME(INCOMPLETE_IMPLEMENTATION): Exact rectangle recognition for
            // these retained families needs original endpoint and monotone image
            // receipts. Public bounds/mesh/volume callers must use the existing
            // general enclosure route until that authority is connected.
            return nil
        }
    }

    private enum Boundary: UInt8 {
        case uLower, uUpper, vLower, vUpper
    }
}

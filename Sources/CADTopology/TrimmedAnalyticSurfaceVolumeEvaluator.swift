import CADCore
import CADGeometry
import Foundation

/// Integrates volume contributions from exactly trimmed analytic surface patches.
struct TrimmedAnalyticSurfaceVolumeEvaluator {
    private let maximumIntegrationDepth = 12

    func volume(
        of shell: Shell,
        in model: BRepModel,
        tolerance: ModelingTolerance
    ) throws -> Double? {
        try tolerance.validate()
        let reference = try referencePoint(for: shell, in: model)
        let characteristicLength = try characteristicLength(
            of: shell,
            in: model,
            reference: reference,
            tolerance: tolerance
        )
        let boundaryCount = try coedgeCount(of: shell, in: model)
        guard boundaryCount > 0 else {
            return nil
        }
        let volumeTolerance = max(
            tolerance.distance * characteristicLength * characteristicLength * 0.125,
            characteristicLength * characteristicLength * characteristicLength * 1.0e-13
        )
        let areaTolerance = max(
            tolerance.distance * characteristicLength * 0.125,
            characteristicLength * characteristicLength * 1.0e-13
        )

        var signedVolume = 0.0
        var accumulatedVolumeError = 0.0
        for faceID in shell.faceIDs {
            guard let face = model.faces[faceID],
                  let surface = model.geometry.surfaces[face.surfaceID] else {
                throw TopologyError.missingReference(
                    "Trimmed analytic volume references missing face geometry."
                )
            }
            guard let integrand = try Integrand(
                surface: surface,
                reference: reference,
                tolerance: tolerance
            ) else {
                return nil
            }
            var faceContribution = 0.0
            for loopID in face.loops {
                guard let loop = model.loops[loopID] else {
                    throw TopologyError.missingReference(
                        "Trimmed analytic volume references a missing loop."
                    )
                }
                guard loop.coedges.allSatisfy({ $0.surfaceParameterCurve != nil }) else {
                    return nil
                }
                let result = try integrate(
                    loop: loop,
                    integrand: integrand,
                    curveVolumeTolerance: volumeTolerance / Double(boundaryCount),
                    curveAreaTolerance: areaTolerance / Double(boundaryCount),
                    tolerance: tolerance
                )
                let physicalAreaTolerance = tolerance.distance * tolerance.distance
                guard abs(result.value.orientedArea) > physicalAreaTolerance else {
                    throw KernelError(
                        phase: .topology,
                        code: .topologyFailure,
                        residual: abs(result.value.orientedArea),
                        tolerance: tolerance,
                        message: "Trimmed analytic volume encountered a degenerate parameter loop."
                    )
                }
                let actualOrientation = result.value.orientedArea >= 0.0 ? 1.0 : -1.0
                let requiredOrientation = loop.role == .outer ? 1.0 : -1.0
                faceContribution += result.value.volume * requiredOrientation / actualOrientation
                accumulatedVolumeError += result.error.volume
            }
            if face.orientation == .reversed {
                faceContribution = -faceContribution
            }
            signedVolume += faceContribution
        }

        guard signedVolume.isFinite,
              accumulatedVolumeError.isFinite,
              accumulatedVolumeError <= volumeTolerance else {
            throw KernelError(
                phase: .topology,
                code: .intersectionFailure,
                residual: accumulatedVolumeError,
                tolerance: tolerance,
                message: "Trimmed analytic volume did not satisfy its integration error bound."
            )
        }
        return signedVolume
    }

    private func integrate(
        loop: Loop,
        integrand: Integrand,
        curveVolumeTolerance: Double,
        curveAreaTolerance: Double,
        tolerance: ModelingTolerance
    ) throws -> IntegrationResult {
        var result = IntegrationResult.zero
        var previousU: Double?
        for coedge in loop.coedges {
            guard let curve = coedge.surfaceParameterCurve else {
                throw TopologyError.invalidTrim(coedge.edgeID)
            }
            let start = try curve.parameter(
                atNormalizedFraction: 0.0,
                tolerance: tolerance
            )
            let shift = integrand.period.map { period in
                periodicShift(of: start.u, nearest: previousU, period: period)
            } ?? 0.0
            let breakpoints = try integrationBreakpoints(
                for: curve,
                tolerance: tolerance
            )
            let spanCount = max(1, breakpoints.count - 1)
            for index in 0..<spanCount {
                let lower = breakpoints[index]
                let upper = breakpoints[index + 1]
                result += try adaptiveIntegral(
                    curve: curve,
                    integrand: integrand,
                    shift: shift,
                    lower: lower,
                    upper: upper,
                    volumeTolerance: curveVolumeTolerance / Double(spanCount),
                    areaTolerance: curveAreaTolerance / Double(spanCount),
                    depth: 0,
                    tolerance: tolerance
                )
            }
            let end = try curve.parameter(
                atNormalizedFraction: 1.0,
                tolerance: tolerance
            )
            previousU = end.u + shift
        }
        return result
    }

    private func adaptiveIntegral(
        curve: SurfaceParameterCurve,
        integrand: Integrand,
        shift: Double,
        lower: Double,
        upper: Double,
        volumeTolerance: Double,
        areaTolerance: Double,
        depth: Int,
        tolerance: ModelingTolerance
    ) throws -> IntegrationResult {
        let midpoint = (lower + upper) * 0.5
        let coarse = try gaussIntegral(
            curve: curve,
            integrand: integrand,
            shift: shift,
            lower: lower,
            upper: upper,
            tolerance: tolerance
        )
        let lowerFine = try gaussIntegral(
            curve: curve,
            integrand: integrand,
            shift: shift,
            lower: lower,
            upper: midpoint,
            tolerance: tolerance
        )
        let upperFine = try gaussIntegral(
            curve: curve,
            integrand: integrand,
            shift: shift,
            lower: midpoint,
            upper: upper,
            tolerance: tolerance
        )
        let fine = lowerFine + upperFine
        let error = IntegrationValue(
            orientedArea: abs(fine.orientedArea - coarse.orientedArea),
            volume: abs(fine.volume - coarse.volume)
        )
        if error.orientedArea <= areaTolerance,
           error.volume <= volumeTolerance {
            return IntegrationResult(value: fine, error: error)
        }
        guard depth < maximumIntegrationDepth else {
            throw KernelError(
                phase: .topology,
                code: .resourceLimitExceeded,
                residual: max(error.orientedArea, error.volume),
                tolerance: tolerance,
                message: "Trimmed analytic volume exhausted its adaptive integration depth."
            )
        }
        let lowerResult = try adaptiveIntegral(
            curve: curve,
            integrand: integrand,
            shift: shift,
            lower: lower,
            upper: midpoint,
            volumeTolerance: volumeTolerance * 0.5,
            areaTolerance: areaTolerance * 0.5,
            depth: depth + 1,
            tolerance: tolerance
        )
        let upperResult = try adaptiveIntegral(
            curve: curve,
            integrand: integrand,
            shift: shift,
            lower: midpoint,
            upper: upper,
            volumeTolerance: volumeTolerance * 0.5,
            areaTolerance: areaTolerance * 0.5,
            depth: depth + 1,
            tolerance: tolerance
        )
        return lowerResult + upperResult
    }

    private func gaussIntegral(
        curve: SurfaceParameterCurve,
        integrand: Integrand,
        shift: Double,
        lower: Double,
        upper: Double,
        tolerance: ModelingTolerance
    ) throws -> IntegrationValue {
        let nodes = [
            -0.906_179_845_938_664,
            -0.538_469_310_105_683_1,
            0.0,
            0.538_469_310_105_683_1,
            0.906_179_845_938_664,
        ]
        let weights = [
            0.236_926_885_056_189_1,
            0.478_628_670_499_366_5,
            0.568_888_888_888_888_9,
            0.478_628_670_499_366_5,
            0.236_926_885_056_189_1,
        ]
        let midpoint = (lower + upper) * 0.5
        let halfSpan = (upper - lower) * 0.5
        var value = IntegrationValue.zero
        for index in nodes.indices {
            let fraction = midpoint + halfSpan * nodes[index]
            let differential = try curve.differentialGeometry(
                atNormalizedFraction: fraction,
                tolerance: tolerance
            )
            let u = differential.parameter.u + shift
            let primitives = integrand.primitives(
                atU: u,
                v: differential.parameter.v
            )
            let differentialV = differential.firstDerivative.y
            value.orientedArea += weights[index] * primitives.area * differentialV
            value.volume += weights[index] * primitives.volume * differentialV
        }
        return value * halfSpan
    }

    private func integrationBreakpoints(
        for curve: SurfaceParameterCurve,
        tolerance: ModelingTolerance
    ) throws -> [Double] {
        switch curve {
        case let .bSpline(spline):
            guard case let .closed(lower, upper) = spline.domain else {
                throw GeometryError.invalidDistance(0.0)
            }
            let span = upper - lower
            var result = [0.0]
            for knot in spline.knots where knot > lower && knot < upper {
                let fraction = (knot - lower) / span
                if result.last.map({ abs($0 - fraction) > tolerance.angle }) != false {
                    result.append(fraction)
                }
            }
            result.append(1.0)
            return result
        case let .polyline(points):
            guard points.count >= 2 else {
                throw GeometryError.invalidDistance(Double(points.count))
            }
            var lengths: [Double] = []
            var totalLength = 0.0
            for index in 1..<points.count {
                let length = hypot(
                    points[index].u - points[index - 1].u,
                    points[index].v - points[index - 1].v
                )
                if length > Double.ulpOfOne {
                    lengths.append(length)
                    totalLength += length
                }
            }
            guard totalLength > Double.ulpOfOne else {
                throw GeometryError.invalidDistance(totalLength)
            }
            var accumulated = 0.0
            var result = [0.0]
            for length in lengths.dropLast() {
                accumulated += length
                result.append(accumulated / totalLength)
            }
            result.append(1.0)
            return result
        default:
            return [0.0, 1.0]
        }
    }

    private func periodicShift(
        of value: Double,
        nearest reference: Double?,
        period: Double
    ) -> Double {
        guard let reference else {
            return 0.0
        }
        return ((reference - value) / period).rounded() * period
    }

    private func referencePoint(
        for shell: Shell,
        in model: BRepModel
    ) throws -> Point3D {
        for faceID in shell.faceIDs {
            guard let face = model.faces[faceID] else {
                throw TopologyError.missingReference(
                    "Trimmed analytic volume references a missing face."
                )
            }
            for loopID in face.loops {
                guard let loop = model.loops[loopID] else {
                    throw TopologyError.missingReference(
                        "Trimmed analytic volume references a missing loop."
                    )
                }
                for coedge in loop.coedges {
                    guard let edge = model.edges[coedge.edgeID],
                          let point = model.vertices[edge.startVertexID]?.point else {
                        throw TopologyError.missingReference(
                            "Trimmed analytic volume references a missing boundary vertex."
                        )
                    }
                    return point
                }
            }
        }
        throw TopologyError.openShell(shell.id)
    }

    private func characteristicLength(
        of shell: Shell,
        in model: BRepModel,
        reference: Point3D,
        tolerance: ModelingTolerance
    ) throws -> Double {
        var maximumLength = tolerance.distance
        for faceID in shell.faceIDs {
            guard let face = model.faces[faceID] else {
                throw TopologyError.missingReference(
                    "Trimmed analytic volume references a missing face."
                )
            }
            for loopID in face.loops {
                guard let loop = model.loops[loopID] else {
                    throw TopologyError.missingReference(
                        "Trimmed analytic volume references a missing loop."
                    )
                }
                for coedge in loop.coedges {
                    guard let edge = model.edges[coedge.edgeID],
                          let start = model.vertices[edge.startVertexID]?.point,
                          let end = model.vertices[edge.endVertexID]?.point else {
                        throw TopologyError.missingReference(
                            "Trimmed analytic volume references a missing boundary vertex."
                        )
                    }
                    maximumLength = max(
                        maximumLength,
                        max(
                            (start - reference).length,
                            (end - reference).length
                        )
                    )
                }
            }
        }
        return maximumLength
    }

    private func coedgeCount(
        of shell: Shell,
        in model: BRepModel
    ) throws -> Int {
        var count = 0
        for faceID in shell.faceIDs {
            guard let face = model.faces[faceID] else {
                throw TopologyError.missingReference(
                    "Trimmed analytic volume references a missing face."
                )
            }
            for loopID in face.loops {
                guard let loop = model.loops[loopID] else {
                    throw TopologyError.missingReference(
                        "Trimmed analytic volume references a missing loop."
                    )
                }
                count += loop.coedges.count
            }
        }
        return count
    }

    private enum Integrand {
        case plane(volumeScale: Double)
        case cylinder(
            radius: Double,
            offsetU: Double,
            offsetV: Double
        )
        case cone(
            sine: Double,
            cosine: Double,
            radialOffsetU: Double,
            radialOffsetV: Double,
            axialOffset: Double
        )
        case sphere(
            radius: Double,
            radialOffsetU: Double,
            radialOffsetV: Double,
            axialOffset: Double
        )
        case torus(
            majorRadius: Double,
            minorRadius: Double,
            radialOffsetU: Double,
            radialOffsetV: Double,
            axialOffset: Double
        )

        init?(
            surface: Surface3D,
            reference: Point3D,
            tolerance: ModelingTolerance
        ) throws {
            let kind: Kind
            switch surface {
            case let .plane(plane):
                kind = .plane(origin: plane.origin)
            case let .cylinder(cylinder):
                kind = .cylinder(origin: cylinder.origin, radius: cylinder.radius)
            case let .analytic(.plane(origin, _)):
                kind = .plane(origin: origin)
            case let .analytic(.cylinder(origin, _, radius)):
                kind = .cylinder(origin: origin, radius: radius)
            case let .analytic(.cone(apex, axis, halfAngle)):
                kind = .cone(apex: apex, axis: axis, halfAngle: halfAngle)
            case let .analytic(.sphere(center, radius)):
                kind = .sphere(center: center, radius: radius)
            case let .analytic(.torus(center, axis, majorRadius, minorRadius)):
                kind = .torus(
                    center: center,
                    axis: axis,
                    majorRadius: majorRadius,
                    minorRadius: minorRadius
                )
            case .analytic, .bSpline:
                return nil
            }
            let sampleV: Double
            if case .cone = kind {
                sampleV = 1.0
            } else {
                sampleV = 0.0
            }
            let geometry = try surface.differentialGeometry(
                atU: 0.0,
                v: sampleV,
                tolerance: tolerance
            )
            switch kind {
            case let .plane(origin):
                let areaVector = geometry.tangentU.cross(geometry.tangentV)
                self = .plane(volumeScale: (origin - reference).dot(areaVector) / 3.0)
            case let .cylinder(origin, radius):
                let radialU = try (geometry.position - origin).normalized(
                    tolerance: tolerance.distance
                )
                let radialV = try geometry.tangentU.normalized(
                    tolerance: tolerance.distance
                )
                let offset = origin - reference
                self = .cylinder(
                    radius: radius,
                    offsetU: offset.dot(radialU),
                    offsetV: offset.dot(radialV)
                )
            case let .cone(apex, axis, halfAngle):
                let radialU = try (
                    geometry.position
                        - apex
                        - axis * (geometry.position - apex).dot(axis)
                ).normalized(tolerance: tolerance.distance)
                let radialV = try geometry.tangentU.normalized(
                    tolerance: tolerance.distance
                )
                let offset = apex - reference
                self = .cone(
                    sine: sin(halfAngle),
                    cosine: cos(halfAngle),
                    radialOffsetU: offset.dot(radialU),
                    radialOffsetV: offset.dot(radialV),
                    axialOffset: offset.dot(axis)
                )
            case let .sphere(center, radius):
                let radialU = try (geometry.position - center).normalized(
                    tolerance: tolerance.distance
                )
                let radialV = try geometry.tangentU.normalized(
                    tolerance: tolerance.distance
                )
                let axis = try geometry.tangentV.normalized(
                    tolerance: tolerance.distance
                )
                let offset = center - reference
                self = .sphere(
                    radius: radius,
                    radialOffsetU: offset.dot(radialU),
                    radialOffsetV: offset.dot(radialV),
                    axialOffset: offset.dot(axis)
                )
            case let .torus(center, axis, majorRadius, minorRadius):
                let radialU = try (
                    geometry.position
                        - center
                        - axis * (geometry.position - center).dot(axis)
                ).normalized(tolerance: tolerance.distance)
                let radialV = try geometry.tangentU.normalized(
                    tolerance: tolerance.distance
                )
                let offset = center - reference
                self = .torus(
                    majorRadius: majorRadius,
                    minorRadius: minorRadius,
                    radialOffsetU: offset.dot(radialU),
                    radialOffsetV: offset.dot(radialV),
                    axialOffset: offset.dot(axis)
                )
            }
        }

        var period: Double? {
            switch self {
            case .plane:
                return nil
            case .cylinder, .cone, .sphere, .torus:
                return 2.0 * Double.pi
            }
        }

        func primitives(atU u: Double, v: Double) -> (area: Double, volume: Double) {
            switch self {
            case let .plane(volumeScale):
                return (area: u, volume: volumeScale * u)
            case let .cylinder(radius, offsetU, offsetV):
                let volumePrimitive = radius / 3.0 * (
                    offsetU * sin(u)
                        - offsetV * cos(u)
                    + radius * u
                )
                return (area: radius * u, volume: volumePrimitive)
            case let .cone(
                sine,
                cosine,
                radialOffsetU,
                radialOffsetV,
                axialOffset
            ):
                let areaScale = v * sine
                let volumePrimitive = areaScale / 3.0 * (
                    cosine * (
                        radialOffsetU * sin(u)
                            - radialOffsetV * cos(u)
                    )
                        - sine * axialOffset * u
                )
                return (area: areaScale * u, volume: volumePrimitive)
            case let .sphere(
                radius,
                radialOffsetU,
                radialOffsetV,
                axialOffset
            ):
                let cosineV = cos(v)
                let areaScale = radius * radius * cosineV
                let volumePrimitive = areaScale / 3.0 * (
                    cosineV * (
                        radialOffsetU * sin(u)
                            - radialOffsetV * cos(u)
                    )
                        + (axialOffset * sin(v) + radius) * u
                )
                return (area: areaScale * u, volume: volumePrimitive)
            case let .torus(
                majorRadius,
                minorRadius,
                radialOffsetU,
                radialOffsetV,
                axialOffset
            ):
                let cosineV = cos(v)
                let sineV = sin(v)
                let areaScale = minorRadius * (majorRadius + minorRadius * cosineV)
                let volumePrimitive = areaScale / 3.0 * (
                    cosineV * (
                        radialOffsetU * sin(u)
                            - radialOffsetV * cos(u)
                    )
                        + (
                            axialOffset * sineV
                                + majorRadius * cosineV
                                + minorRadius
                        ) * u
                )
                return (area: areaScale * u, volume: volumePrimitive)
            }
        }

        private enum Kind {
            case plane(origin: Point3D)
            case cylinder(origin: Point3D, radius: Double)
            case cone(apex: Point3D, axis: Vector3D, halfAngle: Double)
            case sphere(center: Point3D, radius: Double)
            case torus(
                center: Point3D,
                axis: Vector3D,
                majorRadius: Double,
                minorRadius: Double
            )
        }
    }

    private struct IntegrationValue {
        static let zero = IntegrationValue(orientedArea: 0.0, volume: 0.0)

        var orientedArea: Double
        var volume: Double

        static func + (lhs: IntegrationValue, rhs: IntegrationValue) -> IntegrationValue {
            IntegrationValue(
                orientedArea: lhs.orientedArea + rhs.orientedArea,
                volume: lhs.volume + rhs.volume
            )
        }

        static func * (lhs: IntegrationValue, rhs: Double) -> IntegrationValue {
            IntegrationValue(
                orientedArea: lhs.orientedArea * rhs,
                volume: lhs.volume * rhs
            )
        }
    }

    private struct IntegrationResult {
        static let zero = IntegrationResult(
            value: .zero,
            error: .zero
        )

        var value: IntegrationValue
        var error: IntegrationValue

        static func + (lhs: IntegrationResult, rhs: IntegrationResult) -> IntegrationResult {
            IntegrationResult(
                value: lhs.value + rhs.value,
                error: lhs.error + rhs.error
            )
        }

        static func += (lhs: inout IntegrationResult, rhs: IntegrationResult) {
            lhs = lhs + rhs
        }
    }
}

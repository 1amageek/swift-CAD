import CADCore
import CADGeometry
import Foundation

/// Certifies volumes for the tensor-product rational surfaces emitted by an
/// exact planar revolve. The proof reconstructs one meridian profile from each
/// angular sector and applies the boundary form of the first radial moment:
/// `V = abs(theta) * abs(integral 0.5 * radius^2 d(axial))`.
struct RationalRevolutionVolumeEvaluator {
    private struct Row {
        let center: Point3D
        let start: Point3D
        let middle: Point3D
        let end: Point3D
        let profileWeight: Double
    }

    private struct RevolvedFace {
        let face: Face
        let surface: BSplineSurface3D
        let halfAngleCosine: Double
        let rows: [Row]
        var startDirection: Vector3D?
    }

    private struct PlanarCap {
        let origin: Point3D
        let normal: Vector3D
    }

    private struct DirectionGroup {
        let direction: Vector3D
        var faces: [RevolvedFace]
    }

    private struct ProfileSpanDescriptor {
        let degree: Int
        let knots: [Double]
        let radii: [Double]
        let axials: [Double]
        let weights: [Double]
    }

    func volume(
        of shell: Shell,
        in model: BRepModel,
        tolerance: ModelingTolerance
    ) throws -> Double? {
        try tolerance.validate()
        var revolvedFaces: [RevolvedFace] = []
        var caps: [PlanarCap] = []
        for faceID in shell.faceIDs.sorted() {
            guard let face = model.faces[faceID],
                  let geometry = model.geometry.surfaces[face.surfaceID],
                  case let .bSpline(surface) = geometry else {
                return nil
            }
            if let revolved = try revolvedFace(
                face: face,
                surface: surface,
                tolerance: tolerance
            ) {
                revolvedFaces.append(revolved)
            } else if let cap = try planarCap(
                surface: surface,
                tolerance: tolerance
            ) {
                caps.append(cap)
            } else {
                return nil
            }
        }
        guard revolvedFaces.isEmpty == false else { return nil }

        let axis = try commonAxis(for: revolvedFaces, tolerance: tolerance)
        revolvedFaces = try revolvedFaces.map { face in
            try validated(
                face,
                axisOrigin: axis.origin,
                axisDirection: axis.direction,
                tolerance: tolerance
            )
        }
        let groups = try directionGroups(
            for: revolvedFaces,
            tolerance: tolerance
        )
        guard groups.isEmpty == false else { return nil }
        let halfAngleCosine = revolvedFaces[0].halfAngleCosine
        guard revolvedFaces.allSatisfy({
            abs($0.halfAngleCosine - halfAngleCosine)
                <= max(tolerance.relative * 16.0, Double.ulpOfOne * 128.0)
        }) else {
            return nil
        }
        let sectorAngle = 2.0 * acos(max(-1.0, min(1.0, halfAngleCosine)))
        let sweepAngle = sectorAngle * Double(groups.count)
        let angleTolerance = max(
            tolerance.angle * Double(groups.count) * 32.0,
            Double.ulpOfOne * 512.0
        )
        guard sectorAngle > tolerance.angle,
              sweepAngle <= 2.0 * Double.pi + angleTolerance else {
            return nil
        }
        let isFullTurn = abs(sweepAngle - 2.0 * Double.pi) <= angleTolerance
        guard (isFullTurn && caps.isEmpty) || (!isFullTurn && caps.count == 2) else {
            return nil
        }
        guard caps.allSatisfy({ cap in
            abs(cap.normal.dot(axis.direction)) <= tolerance.angle * 16.0
                && abs((axis.origin - cap.origin).dot(cap.normal))
                    <= tolerance.distance
        }) else {
            return nil
        }

        let scale = try characteristicLength(of: shell, in: model, tolerance: tolerance)
        let volumeError = max(
            tolerance.distance * scale * scale * 0.0625,
            scale * scale * scale * 1.0e-13
        )
        let requestedMomentWidth = max(
            volumeError * 1.8 / sweepAngle,
            Double.ulpOfOne * scale * scale * 512.0
        )
        try validateEquivalentProfiles(
            groups,
            axisOrigin: axis.origin,
            axisDirection: axis.direction,
            tolerance: tolerance
        )
        guard let referenceGroup = groups.first else { return nil }
        let referenceMoment = try profileMomentBounds(
            group: referenceGroup,
            axisOrigin: axis.origin,
            axisDirection: axis.direction,
            requestedWidth: requestedMomentWidth,
            tolerance: tolerance
        )
        let moment = referenceMoment.midpoint
        let volume = sweepAngle * moment
        let volumeWidth = sweepAngle * referenceMoment.width
        guard volume.isFinite,
              volume > tolerance.distance * tolerance.distance * tolerance.distance,
              volumeWidth <= volumeError * 2.0 else {
            throw KernelError(
                phase: .topology,
                code: .resourceLimitExceeded,
                residual: volumeWidth,
                tolerance: tolerance,
                message: "Certified rational revolve volume exceeded its requested enclosure width."
            )
        }
        return volume
    }

    private func revolvedFace(
        face: Face,
        surface: BSplineSurface3D,
        tolerance: ModelingTolerance
    ) throws -> RevolvedFace? {
        guard surface.uDegree == 2,
              surface.uControlPointCount == 3,
              surface.uKnots.count == 6,
              surface.controlPoints.count == surface.weights.count,
              surface.controlPoints.isEmpty == false else {
            return nil
        }
        var rows: [Row] = []
        var referenceCosine: Double?
        for (points, weights) in zip(surface.controlPoints, surface.weights) {
            guard points.count == 3,
                  weights.count == 3,
                  weights.allSatisfy({ $0.isFinite && $0 > 0.0 }) else {
                return nil
            }
            let endpointScale = max(weights[0], weights[2], 1.0)
            guard abs(weights[0] - weights[2])
                    <= tolerance.relative * endpointScale * 16.0 else {
                return nil
            }
            let cosine = weights[1] / sqrt(weights[0] * weights[2])
            guard cosine.isFinite,
                  cosine > Double.ulpOfOne,
                  cosine < 1.0 else {
                return nil
            }
            if let referenceCosine {
                guard abs(cosine - referenceCosine)
                        <= max(tolerance.relative * 16.0, Double.ulpOfOne * 128.0) else {
                    return nil
                }
            } else {
                referenceCosine = cosine
            }
            let squaredCosine = cosine * cosine
            let denominator = 1.0 - squaredCosine
            guard denominator > Double.ulpOfOne * 64.0 else { return nil }
            let endpointMidpoint = midpoint(points[0], points[2])
            let center = Point3D(
                x: (endpointMidpoint.x - squaredCosine * points[1].x) / denominator,
                y: (endpointMidpoint.y - squaredCosine * points[1].y) / denominator,
                z: (endpointMidpoint.z - squaredCosine * points[1].z) / denominator
            )
            rows.append(Row(
                center: center,
                start: points[0],
                middle: points[1],
                end: points[2],
                profileWeight: 0.5 * (weights[0] + weights[2])
            ))
        }
        guard let cosine = referenceCosine else { return nil }
        return RevolvedFace(
            face: face,
            surface: surface,
            halfAngleCosine: cosine,
            rows: rows,
            startDirection: nil
        )
    }

    private func planarCap(
        surface: BSplineSurface3D,
        tolerance: ModelingTolerance
    ) throws -> PlanarCap? {
        guard surface.uDegree == 1,
              surface.vDegree == 1,
              surface.uControlPointCount == 2,
              surface.vControlPointCount == 2,
              surface.weights.allSatisfy({ row in
                  row.allSatisfy { abs($0 - 1.0) <= tolerance.relative * 16.0 }
              }) else {
            return nil
        }
        let origin = surface.controlPoints[0][0]
        let u = surface.controlPoints[0][1] - origin
        let v = surface.controlPoints[1][0] - origin
        guard u.length > tolerance.distance,
              v.length > tolerance.distance else {
            return nil
        }
        let areaVector = u.cross(v)
        let minimumArea = tolerance.distance * max(u.length, v.length)
        guard areaVector.length > minimumArea else {
            return nil
        }
        let normal = try areaVector.normalized(tolerance: minimumArea)
        let expectedCorner = origin + u + v
        guard expectedCorner.isApproximatelyEqual(
            to: surface.controlPoints[1][1],
            tolerance: tolerance.distance
        ) else {
            return nil
        }
        return PlanarCap(origin: origin, normal: normal)
    }

    private func commonAxis(
        for faces: [RevolvedFace],
        tolerance: ModelingTolerance
    ) throws -> (origin: Point3D, direction: Vector3D) {
        let centers = faces.flatMap(\.rows).map(\.center)
        guard let origin = centers.first else {
            throw TopologyError.missingReference("Rational revolve contains no profile rows.")
        }
        var farthest = origin
        var farthestDistance = 0.0
        for center in centers.dropFirst() {
            let distance = (center - origin).length
            if distance > farthestDistance {
                farthest = center
                farthestDistance = distance
            }
        }
        guard farthestDistance > tolerance.distance else {
            throw KernelError(
                phase: .topology,
                code: .topologyFailure,
                residual: farthestDistance,
                tolerance: tolerance,
                message: "Rational revolve could not recover a non-degenerate rotation axis."
            )
        }
        let direction = try (farthest - origin).normalized(
            tolerance: tolerance.distance
        )
        guard centers.allSatisfy({ center in
            (center - origin).cross(direction).length <= tolerance.distance * 8.0
        }) else {
            throw KernelError(
                phase: .topology,
                code: .topologyFailure,
                tolerance: tolerance,
                message: "Rational revolve surface rows do not share one rotation axis."
            )
        }
        return (origin, direction)
    }

    private func validated(
        _ face: RevolvedFace,
        axisOrigin: Point3D,
        axisDirection: Vector3D,
        tolerance: ModelingTolerance
    ) throws -> RevolvedFace {
        let cosine = face.halfAngleCosine
        let fullAngleCosine = 2.0 * cosine * cosine - 1.0
        let weightedStartVector = face.rows.reduce(Vector3D.zero) {
            $0 + ($1.start - $1.center) * $1.profileWeight
        }
        let totalWeight = face.rows.reduce(0.0) { $0 + $1.profileWeight }
        guard weightedStartVector.length > tolerance.distance * totalWeight else {
            throw KernelError(
                phase: .topology,
                code: .topologyFailure,
                residual: weightedStartVector.length,
                tolerance: tolerance,
                message: "Rational revolve face has no non-collapsed homogeneous start meridian witness."
            )
        }
        let startDirection = try weightedStartVector.normalized(
            tolerance: tolerance.distance * totalWeight
        )
        for row in face.rows {
            let centerOffset = row.center - axisOrigin
            guard centerOffset.cross(axisDirection).length <= tolerance.distance * 8.0 else {
                throw KernelError(
                    phase: .topology,
                    code: .topologyFailure,
                    tolerance: tolerance,
                    message: "Rational revolve surface row leaves the recovered rotation axis."
                )
            }
            let start = row.start - row.center
            let middle = row.middle - row.center
            let end = row.end - row.center
            let radius = start.length
            if radius <= tolerance.distance {
                guard middle.length <= tolerance.distance,
                      end.length <= tolerance.distance else {
                    throw KernelError(
                        phase: .topology,
                        code: .topologyFailure,
                        tolerance: tolerance,
                        message: "A collapsed rational revolve row leaves the rotation axis."
                    )
                }
                continue
            }
            let expectedMiddleRadius = radius / cosine
            guard abs(start.dot(axisDirection)) <= tolerance.distance,
                  abs(end.dot(axisDirection)) <= tolerance.distance,
                  abs(middle.dot(axisDirection)) <= tolerance.distance,
                  start.cross(startDirection).length <= tolerance.distance * 8.0,
                  abs(end.length - radius) <= tolerance.distance * 8.0,
                  abs(middle.length - expectedMiddleRadius) <= tolerance.distance * 8.0,
                  abs(start.dot(end) / (radius * radius) - fullAngleCosine)
                    <= max(tolerance.angle * 32.0, tolerance.relative * 32.0) else {
                throw KernelError(
                    phase: .topology,
                    code: .topologyFailure,
                    tolerance: tolerance,
                    message: "Rational revolve surface row failed its circular-arc identity."
                )
            }
        }
        var updated = face
        updated.startDirection = startDirection
        return updated
    }

    private func directionGroups(
        for faces: [RevolvedFace],
        tolerance: ModelingTolerance
    ) throws -> [DirectionGroup] {
        var result: [DirectionGroup] = []
        let alignment = 1.0 - max(
            tolerance.angle * 32.0,
            tolerance.relative * 32.0,
            Double.ulpOfOne * 256.0
        )
        for face in faces {
            guard let direction = face.startDirection else {
                throw KernelError(
                    phase: .topology,
                    code: .topologyFailure,
                    tolerance: tolerance,
                    message: "Rational revolve face has no start meridian."
                )
            }
            if let index = result.firstIndex(where: {
                $0.direction.dot(direction) >= alignment
            }) {
                result[index].faces.append(face)
            } else {
                result.append(DirectionGroup(direction: direction, faces: [face]))
            }
        }
        guard let expectedCount = result.first?.faces.count,
              result.allSatisfy({ $0.faces.count == expectedCount }) else {
            throw KernelError(
                phase: .topology,
                code: .topologyFailure,
                tolerance: tolerance,
                message: "Rational revolve angular sectors do not contain identical profile spans."
            )
        }
        return result
    }

    private func validateEquivalentProfiles(
        _ groups: [DirectionGroup],
        axisOrigin: Point3D,
        axisDirection: Vector3D,
        tolerance: ModelingTolerance
    ) throws {
        guard let first = groups.first else {
            throw KernelError(
                phase: .topology,
                code: .topologyFailure,
                tolerance: tolerance,
                message: "Rational revolve contains no angular sector profiles."
            )
        }
        let reference = try profileDescriptors(
            for: first,
            axisOrigin: axisOrigin,
            axisDirection: axisDirection,
            tolerance: tolerance
        )
        for group in groups.dropFirst() {
            let candidate = try profileDescriptors(
                for: group,
                axisOrigin: axisOrigin,
                axisDirection: axisDirection,
                tolerance: tolerance
            )
            guard candidate.count == reference.count,
                  zip(reference, candidate).allSatisfy({
                      equivalent($0.0, $0.1, tolerance: tolerance)
                  }) else {
                throw KernelError(
                    phase: .topology,
                    code: .topologyFailure,
                    tolerance: tolerance,
                    message: "Rational revolve angular sectors do not carry identical exact meridian profiles."
                )
            }
        }
    }

    private func profileDescriptors(
        for group: DirectionGroup,
        axisOrigin: Point3D,
        axisDirection: Vector3D,
        tolerance: ModelingTolerance
    ) throws -> [ProfileSpanDescriptor] {
        var descriptors: [ProfileSpanDescriptor] = []
        for face in group.faces {
            guard let firstWeight = face.rows.first?.profileWeight,
                  firstWeight.isFinite,
                  firstWeight > Double.ulpOfOne else {
                throw KernelError(
                    phase: .topology,
                    code: .singularGeometry,
                    tolerance: tolerance,
                    message: "Rational revolve meridian has no positive reference weight."
                )
            }
            var radii: [Double] = []
            var axials: [Double] = []
            var weights: [Double] = []
            for row in face.rows {
                let radius = (row.start - row.center).dot(group.direction)
                radii.append(radius)
                axials.append((row.center - axisOrigin).dot(axisDirection))
                weights.append(row.profileWeight / firstWeight)
            }
            switch try DefaultRationalBezierHalfSpaceClassifier().classify(
                controlValues: radii,
                weights: weights,
                nonnegativeMargin: tolerance.distance,
                tolerance: tolerance
            ) {
            case .nonnegative:
                break
            case let .violates(residual):
                throw KernelError(
                    phase: .validation,
                    code: .invalidInput,
                    residual: residual,
                    tolerance: tolerance,
                    message: "Rational revolve profile leaves the certified generator half-plane."
                )
            }
            descriptors.append(ProfileSpanDescriptor(
                degree: face.surface.vDegree,
                knots: face.surface.vKnots,
                radii: radii,
                axials: axials,
                weights: weights
            ))
        }
        return descriptors.sorted {
            lexicographicallyPrecedes(descriptorKey($0), descriptorKey($1))
        }
    }

    private func descriptorKey(_ descriptor: ProfileSpanDescriptor) -> [Double] {
        [Double(descriptor.degree)]
            + descriptor.radii
            + descriptor.axials
            + descriptor.weights
            + descriptor.knots
    }

    private func lexicographicallyPrecedes(
        _ first: [Double],
        _ second: [Double]
    ) -> Bool {
        for (left, right) in zip(first, second) where left != right {
            return left < right
        }
        return first.count < second.count
    }

    private func equivalent(
        _ first: ProfileSpanDescriptor,
        _ second: ProfileSpanDescriptor,
        tolerance: ModelingTolerance
    ) -> Bool {
        guard first.degree == second.degree,
              first.knots.count == second.knots.count,
              first.radii.count == second.radii.count,
              first.axials.count == second.axials.count,
              first.weights.count == second.weights.count else {
            return false
        }
        let parameterTolerance = max(
            tolerance.relative * 32.0,
            Double.ulpOfOne * 256.0
        )
        return zip(first.knots, second.knots).allSatisfy {
            abs($0.0 - $0.1) <= parameterTolerance * max(abs($0.0), abs($0.1), 1.0)
        } && zip(first.radii, second.radii).allSatisfy {
            abs($0.0 - $0.1) <= tolerance.distance * 8.0
        } && zip(first.axials, second.axials).allSatisfy {
            abs($0.0 - $0.1) <= tolerance.distance * 8.0
        } && zip(first.weights, second.weights).allSatisfy {
            abs($0.0 - $0.1) <= parameterTolerance * max(abs($0.0), abs($0.1), 1.0)
        }
    }

    private func profileMomentBounds(
        group: DirectionGroup,
        axisOrigin: Point3D,
        axisDirection: Vector3D,
        requestedWidth: Double,
        tolerance: ModelingTolerance
    ) throws -> MomentBounds {
        var total = SurfaceParameterAreaBounds.zero
        let perCurveWidth = requestedWidth / Double(group.faces.count)
        for face in group.faces {
            let patches = try squaredRadiusMomentPatches(
                face: face,
                radialDirection: group.direction,
                axisOrigin: axisOrigin,
                axisDirection: axisDirection,
                tolerance: tolerance
            )
            total = total.adding(
                try CertifiedAnalyticPcurveFluxIntegrator().parameterAreaBounds(
                    for: patches,
                    requestedWidth: perCurveWidth,
                    tolerance: tolerance
                )
            )
        }
        if total.lower > 0.0 {
            return MomentBounds(lower: total.lower, upper: total.upper)
        }
        if total.upper < 0.0 {
            return MomentBounds(lower: -total.upper, upper: -total.lower)
        }
        throw KernelError(
            phase: .topology,
            code: .topologyFailure,
            residual: total.minimumAbsoluteValue,
            tolerance: tolerance,
            message: "Rational revolve could not certify a nonzero profile first moment."
        )
    }

    private func squaredRadiusMomentPatches(
        face: RevolvedFace,
        radialDirection: Vector3D,
        axisOrigin: Point3D,
        axisDirection: Vector3D,
        tolerance: ModelingTolerance
    ) throws -> [CertifiedHomogeneousBezierCurvePatch] {
        let degree = face.surface.vDegree
        guard degree >= 1,
              face.rows.count == face.surface.vControlPointCount,
              case let .closed(lower, upper) = face.surface.vDomain else {
            throw KernelError(
                phase: .topology,
                code: .invalidInput,
                tolerance: tolerance,
                message: "Rational revolve moment requires a positive bounded profile domain."
            )
        }
        var controlPoints: [Point2D] = []
        var weights: [Double] = []
        for row in face.rows {
            let radius = (row.start - row.center).dot(radialDirection)
            let weight = row.profileWeight
            let axial = (row.center - axisOrigin).dot(axisDirection)
            controlPoints.append(Point2D(x: radius, y: axial))
            weights.append(weight)
        }
        let profile = BSplineCurve2D(
            degree: degree,
            knots: face.surface.vKnots,
            controlPoints: controlPoints,
            weights: weights
        )
        guard profile.domain == .closed(lower, upper) else {
            throw KernelError(
                phase: .topology,
                code: .topologyFailure,
                tolerance: tolerance,
                message: "Rational revolve profile domain does not match its surface domain."
            )
        }
        return try RationalRevolutionProfileMomentBuilder().patches(
            for: profile,
            tolerance: tolerance
        )
    }

    private func characteristicLength(
        of shell: Shell,
        in model: BRepModel,
        tolerance: ModelingTolerance
    ) throws -> Double {
        var points: [Point3D] = []
        for faceID in shell.faceIDs {
            guard let face = model.faces[faceID],
                  let surface = model.geometry.surfaces[face.surfaceID],
                  case let .bSpline(spline) = surface else {
                throw TopologyError.missingReference(
                    "Rational revolve characteristic length references missing geometry."
                )
            }
            points.append(contentsOf: spline.controlPoints.flatMap { $0 })
        }
        let bounds = try BoundingBox3D(points: points)
        let size = bounds.size
        let scale = max(size.x, size.y, size.z)
        guard scale.isFinite, scale > tolerance.distance else {
            throw KernelError(
                phase: .topology,
                code: .topologyFailure,
                residual: scale,
                tolerance: tolerance,
                message: "Rational revolve has no measurable characteristic length."
            )
        }
        return scale
    }

    private func midpoint(_ first: Point3D, _ second: Point3D) -> Point3D {
        Point3D(
            x: 0.5 * (first.x + second.x),
            y: 0.5 * (first.y + second.y),
            z: 0.5 * (first.z + second.z)
        )
    }

    private struct MomentBounds {
        let lower: Double
        let upper: Double

        var midpoint: Double {
            lower + 0.5 * (upper - lower)
        }

        var width: Double {
            (upper - lower).nextUp
        }
    }
}

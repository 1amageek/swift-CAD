import CADCore
import CADGeometry
import CADIR
import CADTopology

/// Where a ray crosses a set of faces transversally, inside their trims: the shared ray cast of
/// point-in-solid and sheet-side classification.
struct BRepRayFaceCrossings: Sendable {
    struct Crossing: Sendable {
        let point: Point3D
        let faceID: FaceID
        /// Distance along the ray.
        let distance: Double
        let parameter: SurfaceParameter
        /// The face's outward normal there.
        let normal: Vector3D
    }

    let intersector: any CurveSurfaceIntersecting
    let facePointContainment: any FacePointContainmentTesting
    let maximumSubdivisionDepth: Int?
    let consumeWork: (@Sendable (Int) throws -> Void)?
    let consumeStorage: (@Sendable (Int) throws -> Void)?
    let remainingSourceDepth: Int?
    let maximumAlgebraicDepth: Int

    init(intersector: any CurveSurfaceIntersecting,
        facePointContainment: any FacePointContainmentTesting,
        maximumSubdivisionDepth: Int? = nil,
        consumeWork: (@Sendable (Int) throws -> Void)? = nil,
        consumeStorage: (@Sendable (Int) throws -> Void)? = nil,
        remainingSourceDepth: Int? = nil, maximumAlgebraicDepth: Int = 32) {
        self.intersector = intersector
        self.facePointContainment = facePointContainment
        self.maximumSubdivisionDepth = maximumSubdivisionDepth
        self.consumeWork = consumeWork
        self.consumeStorage = consumeStorage
        self.remainingSourceDepth = remainingSourceDepth
        self.maximumAlgebraicDepth = maximumAlgebraicDepth
    }

    private func consume() throws {
        try Task.checkCancellation()
        if let consumeWork {
            guard let maximumSubdivisionDepth, (0...32).contains(maximumSubdivisionDepth) else {
                throw KernelError(phase: .classification, code: .invalidInput, tolerance: nil,
                    message: "Bounded ray classification requires its caller depth ceiling.")
            }
            try consumeWork(0)
        }
    }

    /// The distinct transverse crossings of the ray from `point` along the unit `direction`
    /// between twice the modeling distance and `upperBound`, nearest first.
    func crossings(
        from point: Point3D,
        direction: Vector3D,
        upperBound: Double,
        faceIDs: [FaceID],
        model: BRepModel,
        containmentSession: (any FacePointContainmentSession)?,
        faceParameterBounds: [FaceID: SurfaceParameterBox]? = nil,
        tolerance: ModelingTolerance
    ) throws -> [Crossing] {
        try consume()
        let ray = Curve3D.line(Line3D(origin: point, direction: direction))
        let range = try ScalarInterval(lower: tolerance.distance * 2.0, upper: upperBound)
        var crossings: [Crossing] = []
        var crossingCapacity = 0
        for faceID in faceIDs {
            try consume()
            guard let face = model.faces[faceID],
                  let surface = model.geometry.surfaces[face.surfaceID] else {
                throw KernelError(
                    phase: .classification,
                    code: .missingReference,
                    tolerance: tolerance,
                    message: "Ray classification references missing face geometry."
                )
            }
            let parameters = try faceParameterBounds?[faceID] ?? Self.parameterBounds(
                for: faceID, surface: surface, model: model, tolerance: tolerance,
                maximumSubdivisionDepth: maximumSubdivisionDepth ?? 48, consumeWork: consumeWork,
                consumeStorage: consumeStorage, remainingSourceDepth: remainingSourceDepth ?? 16,
                maximumAlgebraicDepth: maximumAlgebraicDepth)
            let options = CurveSurfaceIntersectionOptions(
                    curveRange: range,
                    surfaceURange: parameters.u,
                    surfaceVRange: parameters.v
                )
            let intersections: [CurveSurfaceIntersection]
            if let consumeWork, let maximumSubdivisionDepth {
                intersections = try intersector.intersections(curve: ray, surface: surface,
                    options: options, tolerance: tolerance,
                    maximumSpanCount: options.maximumSubdivisionCells,
                    maximumSubdivisionDepth: maximumSubdivisionDepth,
                    remainingSourceDepth: remainingSourceDepth ?? 16,
                    consumeWork: consumeWork, consumeStorage: consumeStorage,
                    maximumAlgebraicDepth: maximumAlgebraicDepth)
            } else {
                intersections = try intersector.intersections(curve: ray, surface: surface,
                    options: options, tolerance: tolerance)
            }
            for intersection in intersections {
                try consume()
                let parameter = SurfaceParameter(u: intersection.surfaceU, v: intersection.surfaceV)
                guard try contains(
                    parameter,
                    fallbackPoint: intersection.point,
                    on: faceID,
                    model: model,
                    containmentSession: containmentSession,
                    tolerance: tolerance
                ) else {
                    continue
                }
                if intersection.kind == .mixed {
                    throw KernelError(phase: .classification, code: .classificationFailure,
                        tolerance: tolerance,
                        message: "An original ray event has unresolved transverse or tangent incidence.")
                }
                guard intersection.kind == .transverse else { continue }
                // A ray through an edge meets both faces it bounds at one point: one crossing.
                // Two faces lying on each other with opposite normals (solids touching along a
                // face) are two crossings at one point: out of one and into the other.
                let normal = try orientedNormal(of: face, surface: surface, at: parameter, tolerance: tolerance)
                let isRepeat = try crossings.contains { existing in
                    try consume()
                    guard (existing.point - intersection.point).length <= tolerance.distance else { return false }
                    return existing.normal.dot(normal) > -1 + tolerance.angle
                }
                if isRepeat == false {
                    if consumeWork != nil, crossings.count == crossingCapacity {
                        let next = crossingCapacity == 0
                            ? (partialValue: 1, overflow: false)
                            : crossingCapacity.multipliedReportingOverflow(by: 2)
                        let bytes = next.partialValue.multipliedReportingOverflow(by: MemoryLayout<Crossing>.stride)
                        guard !next.overflow, !bytes.overflow else {
                            throw KernelError(phase: .classification, code: .resourceLimitExceeded,
                                tolerance: tolerance, message: "Original ray crossing storage overflows.")
                        }
                        try consumeStorage?(bytes.partialValue)
                        crossings.reserveCapacity(next.partialValue)
                        crossingCapacity = next.partialValue
                    }
                    crossings.append(Crossing(
                        point: intersection.point,
                        faceID: faceID,
                        distance: intersection.curveParameter,
                        parameter: parameter,
                        normal: normal
                    ))
                }
            }
        }
        if consumeWork != nil {
            for index in crossings.indices.dropFirst() {
                var position = index
                while position > 0 {
                    try consume()
                    if crossings[position - 1].distance <= crossings[position].distance { break }
                    crossings.swapAt(position - 1, position)
                    position -= 1
                }
            }
            return crossings
        }
        return crossings.sorted { $0.distance < $1.distance }
    }

    /// Complete authored trim extent, with bounded-domain authority retained.
    static func parameterBounds(for faceID: FaceID, surface: Surface3D,
        model: BRepModel, tolerance: ModelingTolerance,
        maximumSubdivisionDepth: Int = 48,
        consumeWork: (@Sendable (Int) throws -> Void)? = nil,
        consumeStorage: (@Sendable (Int) throws -> Void)? = nil,
        remainingSourceDepth: Int = 16, maximumAlgebraicDepth: Int = 32) throws -> SurfaceParameterBox {
        try OriginalFaceParameterBounds.resolve(for: faceID, surface: surface,
            model: model, tolerance: tolerance, maximumSubdivisionDepth: maximumSubdivisionDepth,
            consumeWork: consumeWork, consumeStorage: consumeStorage,
            remainingSourceDepth: remainingSourceDepth, maximumAlgebraicDepth: maximumAlgebraicDepth)
    }

    private func orientedNormal(
        of face: Face,
        surface: Surface3D,
        at parameter: SurfaceParameter,
        tolerance: ModelingTolerance
    ) throws -> Vector3D {
        try consume()
        let geometric: Vector3D
        if let consumeWork, let maximumSubdivisionDepth {
            let prepared = try PreparedSurfaceDifferentialEncloser(surface: surface,
                tolerance: tolerance, remainingSourceDepth: remainingSourceDepth ?? maximumSubdivisionDepth,
                maximumSubdivisionDepth: maximumSubdivisionDepth,
                consumeWork: { try consumeWork(0) }, consumeStorage: consumeStorage,
                maximumAlgebraicDepth: remainingSourceDepth == nil ? nil : maximumAlgebraicDepth)
            let jet = try prepared.intervalJet(overClosedBox: SurfaceParameterBox(
                u: ScalarInterval(lower: parameter.u, upper: parameter.u),
                v: ScalarInterval(lower: parameter.v, upper: parameter.v)), tolerance: tolerance,
                maximumSpanCount: 262_144, maximumSubdivisionDepth: maximumSubdivisionDepth,
                remainingSourceDepth: remainingSourceDepth ?? maximumSubdivisionDepth,
                consumeWork: { try consumeWork(0) }, consumeStorage: consumeStorage)
            let u = Vector3D(x: jet.x.derivativeU.midpoint, y: jet.y.derivativeU.midpoint,
                z: jet.z.derivativeU.midpoint)
            let v = Vector3D(x: jet.x.derivativeV.midpoint, y: jet.y.derivativeV.midpoint,
                z: jet.z.derivativeV.midpoint)
            geometric = try u.cross(v).normalized(tolerance: tolerance.distance)
        } else {
            geometric = try surface.normal(u: parameter.u, v: parameter.v, tolerance: tolerance)
                .normalized(tolerance: tolerance.distance)
        }
        return face.orientation == .forward ? geometric : geometric * -1.0
    }

    /// Whether `point` lies on one of the faces.
    func liesOnFace(
        _ point: Point3D,
        faceIDs: [FaceID],
        faceBounds: [FaceID: BoundingBox3D],
        model: BRepModel,
        containmentSession: (any FacePointContainmentSession)?,
        tolerance: ModelingTolerance
    ) throws -> Bool {
        for faceID in faceIDs {
            try consume()
            if let bounds = faceBounds[faceID], bounds.contains(point, tolerance: tolerance.distance) == false {
                continue
            }
            do {
                let contained: Bool
                if let containmentSession {
                    contained = try containmentSession.contains(point, on: faceID)
                } else {
                    contained = try facePointContainment.contains(point, on: faceID, in: model, tolerance: tolerance)
                }
                if contained { return true }
            } catch let error as KernelError where consumeWork == nil && error.code == .intersectionFailure {
                continue
            } catch GeometryError.invalidVectorLength {
                guard consumeWork == nil else {
                    throw KernelError(phase: .classification, code: .classificationFailure,
                        tolerance: tolerance,
                        message: "Bounded original face containment could not establish a regular source witness.")
                }
                continue
            }
        }
        return false
    }

    /// Twice the largest distance from `point` to a corner of `bounds`: a ray this long leaves them.
    func upperBound(from point: Point3D, bounds: BoundingBox3D, tolerance: ModelingTolerance) -> Double {
        let corners = [bounds.minimum.x, bounds.maximum.x].flatMap { x in
            [bounds.minimum.y, bounds.maximum.y].flatMap { y in
                [bounds.minimum.z, bounds.maximum.z].map { z in Point3D(x: x, y: y, z: z) }
            }
        }
        let maximumDistance = corners.map { ($0 - point).length }.max() ?? 0.0
        return max(maximumDistance * 2.0, tolerance.distance * 16.0)
    }

    /// The three fixed, mutually oblique ray directions classification casts along.
    static func directions(tolerance: ModelingTolerance) throws -> [Vector3D] {
        try [
            Vector3D(x: 1.0, y: 0.371_390_676_354, z: 0.618_033_988_750),
            Vector3D(x: 0.414_213_562_373, y: 1.0, z: 0.732_050_807_569),
            Vector3D(x: 0.577_215_664_902, y: 0.693_147_180_560, z: 1.0),
        ].map { try $0.normalized(tolerance: tolerance.distance) }
    }

    private func contains(
        _ parameter: SurfaceParameter,
        fallbackPoint: Point3D,
        on faceID: FaceID,
        model: BRepModel,
        containmentSession: (any FacePointContainmentSession)?,
        tolerance: ModelingTolerance
    ) throws -> Bool {
        try consume()
        if let decision = try containmentSession?.containsParameter(parameter, on: faceID) {
            return decision
        }
        if let containmentSession {
            return try containmentSession.contains(fallbackPoint, on: faceID)
        }
        return try facePointContainment.contains(fallbackPoint, on: faceID, in: model, tolerance: tolerance)
    }

}

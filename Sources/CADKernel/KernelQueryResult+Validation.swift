import CADCore
import CADIR

public extension KernelQueryResult {
    func validate() throws {
        switch self {
        case let .evaluatedDocument(document):
            try document.validate()
        case let .lineage(lineage):
            guard lineage?.isStructurallyValid != false else {
                throw invalidResult("Kernel query result contains invalid topology lineage.")
            }
        case let .diagnostics(report):
            try report.validate()
        case let .snap(result):
            try validateSnap(result)
        case let .measurement(result):
            try validateMeasurement(result)
        case let .selectionDimensionEvaluation(result):
            try validateSelectionDimensionEvaluation(result)
        case let .projection(result):
            try validateProjection(result)
        }
    }
}

private func validateSnap(_ result: SnapQueryResult) throws {
    try result.sourcePoint.validate()
    for candidate in result.candidates {
        try candidate.selection.validate()
        try candidate.point.validate()
        try candidate.tangent?.validate()
        try candidate.normal?.validate()
        try validateFiniteNonnegative(candidate.distance, field: "snap distance")
        if let curvature = candidate.curvature {
            try validateFiniteNonnegative(curvature, field: "snap curvature")
        }
        if let subshapeID = candidate.subshapeID, subshapeID.isValid == false {
            throw invalidResult("Kernel snap result contains an invalid subshape identity.")
        }
    }
}

private func validateMeasurement(_ result: MeasurementQueryResult) throws {
    switch result {
    case let .point(point):
        try validateMeasurementPoint(point)
    case let .distance(distance):
        try validateMeasurementPoint(distance.first)
        try validateMeasurementPoint(distance.second)
        let expectedVector = distance.second.point - distance.first.point
        guard distance.vector == expectedVector,
              distance.distance == expectedVector.length,
              distance.distance.isFinite,
              distance.distance >= 0.0 else {
            throw invalidResult("Kernel distance result contains inconsistent derived fields.")
        }
    case let .angle(angle):
        try validateMeasurementPoint(angle.first)
        try validateMeasurementPoint(angle.second)
        try angle.firstDirection.validate()
        try angle.secondDirection.validate()
        guard angle.firstDirection.length > 0.0,
              angle.secondDirection.length > 0.0,
              angle.angleRadians.isFinite,
              angle.angleRadians >= 0.0,
              angle.angleRadians <= Double.pi else {
            throw invalidResult("Kernel angle result contains invalid directions or angle.")
        }
    }
}

private func validateMeasurementPoint(_ result: SelectionMeasurementPoint) throws {
    try result.selection.validate()
    try result.point.validate()
    try result.tangent?.validate()
    try result.normal?.validate()
    if let curvature = result.curvature {
        try validateFiniteNonnegative(curvature, field: "selection curvature")
    }
}

private func validateSelectionDimensionEvaluation(
    _ result: SelectionDimensionEvaluation
) throws {
    for measurement in result.measurements {
        try measurement.dimension.first.validate()
        try measurement.dimension.second.validate()
        try validateMeasurementPoint(measurement.first)
        try validateMeasurementPoint(measurement.second)
        try measurement.measured.validate()
        try measurement.target.validate()
        try measurement.residual.validate()
        guard measurement.measured.kind == measurement.target.kind,
              measurement.target.kind == measurement.residual.kind else {
            throw invalidResult("Selection dimension result contains incompatible quantities.")
        }
    }
}

private func validateProjection(_ result: ProjectionQueryResult) throws {
    switch result {
    case let .curveClosest(projection):
        try validateCurvePoint(projection.queryPoint)
        try projection.sourcePoint.validate()
        try projection.projectedPoint.validate()
        try projection.residual.validate()
        guard projection.parameterReference == projection.queryPoint.reference,
              projection.projectedPoint == projection.queryPoint.point,
              projection.residual == projection.sourcePoint - projection.projectedPoint,
              projection.distance == projection.residual.length else {
            throw invalidResult("Closest curve projection contains inconsistent derived fields.")
        }
        try validateProjectionProgress(
            distance: projection.distance,
            iterations: projection.iterations
        )
    case let .curveDirectional(projection):
        try validateCurvePoint(projection.queryPoint)
        try validateDirectionalProjection(
            sourcePoint: projection.sourcePoint,
            direction: projection.direction,
            signedDistance: projection.signedDistanceAlongDirection,
            linePoint: projection.linePoint,
            parameterReferenceMatches: projection.parameterReference == projection.queryPoint.reference,
            projectedPoint: projection.projectedPoint,
            expectedProjectedPoint: projection.queryPoint.point,
            lineResidual: projection.lineResidual,
            lineDistance: projection.lineDistance,
            iterations: projection.iterations
        )
    case let .edgeClosest(projection):
        try validateEdgeFrame(projection.frame)
        try projection.sourcePoint.validate()
        try projection.projectedPoint.validate()
        try projection.residual.validate()
        guard projection.parameterReference == projection.frame.reference,
              projection.projectedPoint == projection.frame.point,
              projection.residual == projection.sourcePoint - projection.projectedPoint,
              projection.distance == projection.residual.length else {
            throw invalidResult("Closest edge projection contains inconsistent derived fields.")
        }
        try validateProjectionProgress(
            distance: projection.distance,
            iterations: projection.iterations
        )
    case let .edgeDirectional(projection):
        try validateEdgeFrame(projection.frame)
        try validateDirectionalProjection(
            sourcePoint: projection.sourcePoint,
            direction: projection.direction,
            signedDistance: projection.signedDistanceAlongDirection,
            linePoint: projection.linePoint,
            parameterReferenceMatches: projection.parameterReference == projection.frame.reference,
            projectedPoint: projection.projectedPoint,
            expectedProjectedPoint: projection.frame.point,
            lineResidual: projection.lineResidual,
            lineDistance: projection.lineDistance,
            iterations: projection.iterations
        )
    case let .surfaceClosest(projection):
        try validateSurfaceFrame(projection.frame)
        try projection.sourcePoint.validate()
        try projection.projectedPoint.validate()
        try projection.residual.validate()
        guard projection.parameterReference == projection.frame.reference,
              projection.projectedPoint == projection.frame.point,
              projection.residual == projection.sourcePoint - projection.projectedPoint,
              projection.distance == projection.residual.length else {
            throw invalidResult("Closest surface projection contains inconsistent derived fields.")
        }
        try validateProjectionProgress(
            distance: projection.distance,
            iterations: projection.iterations
        )
    case let .surfaceDirectional(projection):
        try validateSurfaceFrame(projection.frame)
        try validateDirectionalProjection(
            sourcePoint: projection.sourcePoint,
            direction: projection.direction,
            signedDistance: projection.signedDistanceAlongDirection,
            linePoint: projection.linePoint,
            parameterReferenceMatches: projection.parameterReference == projection.frame.reference,
            projectedPoint: projection.projectedPoint,
            expectedProjectedPoint: projection.frame.point,
            lineResidual: projection.lineResidual,
            lineDistance: projection.lineDistance,
            iterations: projection.iterations
        )
    }
}

private func validateCurvePoint(_ point: CurveQueryPoint) throws {
    try point.reference.validate()
    try point.point.validate()
    try point.tangent?.validate()
    if let curvature = point.curvature {
        try validateFiniteNonnegative(curvature, field: "curve curvature")
    }
}

private func validateEdgeFrame(_ frame: EdgeQueryFrame) throws {
    try frame.reference.validate()
    try frame.point.validate()
    try frame.tangent.validate()
    try frame.curvatureVector.validate()
    try validateFiniteNonnegative(frame.curvature, field: "edge curvature")
}

private func validateSurfaceFrame(_ frame: SurfaceQueryFrame) throws {
    try frame.reference.validate()
    try frame.point.validate()
    try frame.tangentU.validate()
    try frame.tangentV.validate()
    try frame.normal.validate()
    try frame.minimumPrincipalDirection.validate()
    try frame.maximumPrincipalDirection.validate()
    for scalar in [
        frame.normalCurvatureU,
        frame.normalCurvatureV,
        frame.meanCurvature,
        frame.gaussianCurvature,
        frame.minimumPrincipalCurvature,
        frame.maximumPrincipalCurvature,
    ] where scalar.isFinite == false {
        throw invalidResult("Surface projection frame contains a non-finite curvature.")
    }
}

private func validateDirectionalProjection(
    sourcePoint: Point3D,
    direction: Vector3D,
    signedDistance: Double,
    linePoint: Point3D,
    parameterReferenceMatches: Bool,
    projectedPoint: Point3D,
    expectedProjectedPoint: Point3D,
    lineResidual: Vector3D,
    lineDistance: Double,
    iterations: Int
) throws {
    try sourcePoint.validate()
    try direction.validate()
    try linePoint.validate()
    try projectedPoint.validate()
    try lineResidual.validate()
    guard direction.length > 0.0,
          signedDistance.isFinite,
          linePoint == sourcePoint + direction * signedDistance,
          parameterReferenceMatches,
          projectedPoint == expectedProjectedPoint,
          lineResidual == projectedPoint - linePoint,
          lineDistance == lineResidual.length else {
        throw invalidResult("Directional projection contains inconsistent derived fields.")
    }
    try validateProjectionProgress(distance: lineDistance, iterations: iterations)
}

private func validateProjectionProgress(distance: Double, iterations: Int) throws {
    guard distance.isFinite, distance >= 0.0, iterations >= 0 else {
        throw invalidResult("Projection result contains invalid distance or iteration metadata.")
    }
}

private func validateFiniteNonnegative(_ value: Double, field: String) throws {
    guard value.isFinite, value >= 0.0 else {
        throw invalidResult("Kernel query result contains invalid \(field).")
    }
}

private func invalidResult(_ message: String) -> KernelError {
    KernelError(
        phase: .validation,
        code: .invalidInput,
        tolerance: nil,
        message: message
    )
}

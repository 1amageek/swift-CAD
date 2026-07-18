import CADCore

struct DefaultPlanarDraftConstraintSolver: PlanarDraftConstraintSolving {
    func displacements(
        for constraints: [VertexID: [PlanarDraftConstraint]],
        neutralNormal: Vector3D,
        featureID: FeatureID,
        tolerance: ModelingTolerance
    ) throws -> [VertexID: Vector3D] {
        let normal = try neutralNormal.normalized(tolerance: tolerance.distance)
        let helper = abs(normal.z) < 0.9 ? Vector3D.unitZ : Vector3D.unitY
        let u = try helper.cross(normal).normalized(tolerance: tolerance.distance)
        let v = normal.cross(u)
        var result: [VertexID: Vector3D] = [:]
        for vertexID in constraints.keys.sorted() {
            guard let vertexConstraints = constraints[vertexID],
                  vertexConstraints.isEmpty == false else {
                continue
            }
            let displacement = try solve(
                vertexConstraints,
                u: u,
                v: v,
                featureID: featureID,
                tolerance: tolerance
            )
            result[vertexID] = displacement
        }
        return result
    }

    private func solve(
        _ constraints: [PlanarDraftConstraint],
        u: Vector3D,
        v: Vector3D,
        featureID: FeatureID,
        tolerance: ModelingTolerance
    ) throws -> Vector3D {
        let rows = try constraints.map { constraint -> DraftConstraintRow in
            let direction = try constraint.direction.normalized(tolerance: tolerance.distance)
            guard constraint.value.isFinite else {
                throw error(
                    .invalidInput,
                    featureID: featureID,
                    residual: constraint.value,
                    tolerance: tolerance,
                    "Planar draft constraint value must be finite."
                )
            }
            return DraftConstraintRow(
                x: direction.dot(u),
                y: direction.dot(v),
                value: constraint.value
            )
        }
        var xx = 0.0
        var xy = 0.0
        var yy = 0.0
        var xb = 0.0
        var yb = 0.0
        for row in rows {
            xx += row.x * row.x
            xy += row.x * row.y
            yy += row.y * row.y
            xb += row.x * row.value
            yb += row.y * row.value
        }
        let determinant = xx * yy - xy * xy
        let x: Double
        let y: Double
        if abs(determinant) > max(tolerance.angle * tolerance.angle, 1.0e-24) {
            x = (xb * yy - yb * xy) / determinant
            y = (yb * xx - xb * xy) / determinant
        } else {
            let reference = try constraints[0].direction.normalized(tolerance: tolerance.distance)
            let candidates = try constraints.map { constraint -> Double in
                let direction = try constraint.direction.normalized(tolerance: tolerance.distance)
                let coefficient = direction.dot(reference)
                guard abs(coefficient) > tolerance.angle else {
                    throw error(
                        .singularSystem,
                        featureID: featureID,
                        tolerance: tolerance,
                        "Planar draft constraints do not determine a stable displacement."
                    )
                }
                return constraint.value / coefficient
            }
            let scalar = candidates.reduce(0.0, +) / Double(candidates.count)
            let residual = candidates.map { abs($0 - scalar) }.max() ?? 0.0
            guard residual <= tolerance.distance else {
                throw error(
                    .conflictingConstraints,
                    featureID: featureID,
                    residual: residual,
                    tolerance: tolerance,
                    "Parallel planar draft constraints require conflicting displacements."
                )
            }
            x = reference.dot(u) * scalar
            y = reference.dot(v) * scalar
        }
        let displacement = u * x + v * y
        let residual = rows.map { row in
            abs(row.x * x + row.y * y - row.value)
        }.max() ?? 0.0
        guard residual <= tolerance.distance else {
            throw error(
                .conflictingConstraints,
                featureID: featureID,
                residual: residual,
                tolerance: tolerance,
                "Planar draft constraints have no common displacement within tolerance."
            )
        }
        return displacement
    }

    private func error(
        _ code: KernelErrorCode,
        featureID: FeatureID,
        residual: Double? = nil,
        tolerance: ModelingTolerance,
        _ message: String
    ) -> KernelError {
        KernelError(
            phase: .geometry,
            code: code,
            featureID: featureID,
            residual: residual,
            tolerance: tolerance,
            message: message
        )
    }
}

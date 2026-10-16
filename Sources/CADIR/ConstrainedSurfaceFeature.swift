import CADCore
import CADGeometry

public struct ConstrainedSurfaceFeature: Hashable, Sendable {
    public struct PointConstraint: Hashable, Sendable {
        public var position: Point3D

        public init(position: Point3D) {
            self.position = position
        }

#if !hasFeature(Embedded)
        private enum CodingKeys: String, CodingKey { case position }
#endif

#if !hasFeature(Embedded)
        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            try container.validateOnlyExpectedKeys([.position], in: decoder)
            position = try container.decode(Point3D.self, forKey: .position)
        }
#endif
    }

    public enum Optimization: String, CaseIterable, Sendable {
        case performance
        case smoothness
    }

    public var points: [PointConstraint]
    public var positionTolerance: Double
    public var angularTolerance: Double
    public var optimization: Optimization

    public init(points: [PointConstraint], positionTolerance: Double,
                angularTolerance: Double, optimization: Optimization = .smoothness) {
        self.points = points
        self.positionTolerance = positionTolerance
        self.angularTolerance = angularTolerance
        self.optimization = optimization
    }

    public func validate(tolerance: ModelingTolerance) throws {
        var execution = try OriginalQueryExecution.independentGeometry()
        try validate(tolerance: tolerance, using: &execution)
    }

    public func validate(tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution) throws {
        try execution.consumeWork(1)
        try execution.consumeWork(1); try tolerance.validate()
        guard points.count >= 3, positionTolerance.isFinite, positionTolerance > 0,
              angularTolerance.isFinite, angularTolerance > 0, angularTolerance <= Double.pi else {
            throw FeatureEvaluationError.invalidGraph("Constrained Surface requires at least three points and positive position/angular tolerances.")
        }
        for point in points {
            try execution.consumeWork(1)
            try execution.consumeWork(1); try point.position.validate()
        }

        try execution.checkpoint()
    }

#if !hasFeature(Embedded)
    private enum CodingKeys: String, CodingKey {
        case points, positionTolerance, angularTolerance, optimization
    }
#endif

#if !hasFeature(Embedded)
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try container.validateOnlyExpectedKeys([.points, .positionTolerance, .angularTolerance, .optimization], in: decoder)
        points = try container.decode([PointConstraint].self, forKey: .points)
        positionTolerance = try container.decode(Double.self, forKey: .positionTolerance)
        angularTolerance = try container.decode(Double.self, forKey: .angularTolerance)
        optimization = try container.decode(Optimization.self, forKey: .optimization)
        try validate(tolerance: CADIRPersistenceValidation.tolerance)
    }
#endif
}

#if !hasFeature(Embedded)
extension ConstrainedSurfaceFeature: Codable {}
extension ConstrainedSurfaceFeature.PointConstraint: Codable {}
extension ConstrainedSurfaceFeature.Optimization: Codable {}
#endif

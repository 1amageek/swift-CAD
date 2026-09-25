import CADCore

public struct ConstrainedSurfaceFeature: Codable, Hashable, Sendable {
    public struct PointConstraint: Codable, Hashable, Sendable {
        public var position: Point3D

        public init(position: Point3D) {
            self.position = position
        }

        private enum CodingKeys: String, CodingKey { case position }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            try container.validateOnlyExpectedKeys([.position], in: decoder)
            position = try container.decode(Point3D.self, forKey: .position)
        }
    }

    public enum Optimization: String, Codable, CaseIterable, Sendable {
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
        try tolerance.validate()
        guard points.count >= 3, positionTolerance.isFinite, positionTolerance > 0,
              angularTolerance.isFinite, angularTolerance > 0, angularTolerance <= Double.pi else {
            throw FeatureEvaluationError.invalidGraph("Constrained Surface requires at least three points and positive position/angular tolerances.")
        }
        for point in points {
            try point.position.validate()
        }
    }

    private enum CodingKeys: String, CodingKey {
        case points, positionTolerance, angularTolerance, optimization
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try container.validateOnlyExpectedKeys([.points, .positionTolerance, .angularTolerance, .optimization], in: decoder)
        points = try container.decode([PointConstraint].self, forKey: .points)
        positionTolerance = try container.decode(Double.self, forKey: .positionTolerance)
        angularTolerance = try container.decode(Double.self, forKey: .angularTolerance)
        optimization = try container.decode(Optimization.self, forKey: .optimization)
        try validate(tolerance: CADIRPersistenceValidation.tolerance)
    }
}

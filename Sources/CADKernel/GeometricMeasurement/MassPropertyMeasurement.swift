import CADCore
import CADGeometry
import CADIR
import CADTopology

public struct MassPropertyMeasurement: Sendable, Hashable {
    /// Canonical SI: kilograms, metres, kilograms times metres squared.
    /// Units of published fields, including the error-enclosure endpoints.
    public var units: (mass: String, length: String, firstMoment: String, inertia: String) {
        ("kg", "m", "kg*m", "kg*m^2")
    }
    /// Original integration accuracy before density, placement and SI conversion.
    public let requestedIntegrationAccuracy: BRepVolumeMomentOptions
    public let modelLengthUnit: LengthUnit
    public let consumedWork: Int
    public let mass: ScalarInterval
    public let firstMoments: [ScalarInterval]
    public let secondMoments: [[ScalarInterval]]
    public let centroid: Point3D
    public let centroidBounds: [ScalarInterval]
    public let inertiaAtReference: [[ScalarInterval]]
    public let inertiaReference: Point3D
    public let principalMoments: [ScalarInterval]
    public let principalAxes: [Vector3D]
    /// Upper bound on the Frobenius norm of the frame Gram matrix minus identity.
    public let principalFrameOrthogonalityError: Double
    /// Original interval tensor residual norms for the published principal axes.
    public let principalAxisResidualBounds: [ScalarInterval]

    public func validate() throws {
        var execution = try OriginalQueryExecution.independentGeometry()
        try validate(using: &execution)
    }

    public func validate(using execution: inout OriginalQueryExecution) throws {
        try execution.checkpoint()
        try requestedIntegrationAccuracy.validate()
        try centroid.validate(); try inertiaReference.validate()
        guard consumedWork > 0, consumedWork <= requestedIntegrationAccuracy.maximumWork,
            mass.lower > 0, firstMoments.count == 3, centroidBounds.count == 3,
            secondMoments.count == 3, try OriginalParameterQueryStorage.allSatisfy(secondMoments, using: &execution, predicate: { row, execution in row.count == 3 }),
            inertiaAtReference.count == 3, try OriginalParameterQueryStorage.allSatisfy(inertiaAtReference, using: &execution, predicate: { row, execution in row.count == 3 }),
            principalMoments.count == 3, principalAxes.count == 3, principalAxisResidualBounds.count == 3,
            principalFrameOrthogonalityError.isFinite, principalFrameOrthogonalityError >= 0,
            principalFrameOrthogonalityError < 1 else { throw invalid() }
        func finiteOrdered(_ value: ScalarInterval, using execution: inout OriginalQueryExecution) throws -> Bool {
            try execution.consumeWork(1)
            return value.lower.isFinite && value.upper.isFinite && value.lower <= value.upper
        }
        // Scan the original fields in concatenation order without allocating their duplicate payload.
        guard try finiteOrdered(mass, using: &execution),
            try OriginalParameterQueryStorage.allSatisfy(firstMoments, using: &execution, predicate: finiteOrdered),
            try OriginalParameterQueryStorage.allSatisfy(centroidBounds, using: &execution, predicate: finiteOrdered),
            try OriginalParameterQueryStorage.allSatisfy(secondMoments, using: &execution, predicate: { row, execution in
                try OriginalParameterQueryStorage.allSatisfy(row, using: &execution, predicate: finiteOrdered)
            }),
            try OriginalParameterQueryStorage.allSatisfy(inertiaAtReference, using: &execution, predicate: { row, execution in
                try OriginalParameterQueryStorage.allSatisfy(row, using: &execution, predicate: finiteOrdered)
            }),
            try OriginalParameterQueryStorage.allSatisfy(principalMoments, using: &execution, predicate: finiteOrdered),
            try OriginalParameterQueryStorage.allSatisfy(principalAxisResidualBounds, using: &execution, predicate: finiteOrdered),
            try OriginalParameterQueryStorage.allSatisfy(principalAxisResidualBounds, using: &execution, predicate: { value, execution in value.lower >= 0 }) else { throw invalid() }
        let centers = try OriginalParameterQueryStorage.values(count: 3, using: &execution) { execution in
            try execution.consumeWork(3); return [centroid.x, centroid.y, centroid.z]
        }
        func interval(_ value: ScalarInterval) -> OutwardScalarInterval {
            OutwardScalarInterval(lower: value.lower, upper: value.upper)
        }
        func absoluteLower(_ value: OutwardScalarInterval) -> Double {
            value.lower > 0 ? value.lower : value.upper < 0 ? -value.upper : 0
        }
        for i in 0..<3 {
            try execution.consumeWork(1)
            guard centroidBounds[i].contains(centers[i]), centers[i] == centroidBounds[i].midpoint,
                principalMoments[i].upper >= 0 else { throw invalid() }
            guard let quotient = interval(firstMoments[i]).divided(by: interval(mass)),
                quotient.lower <= centroidBounds[i].upper, quotient.upper >= centroidBounds[i].lower else {
                throw invalid()
            }
            try principalAxes[i].validate()
            guard principalAxes[i].length.isFinite, principalAxes[i].length > 0 else { throw invalid() }
            if i > 0, principalMoments[i-1].midpoint > principalMoments[i].midpoint { throw invalid() }
            for j in 0..<3 {
                try execution.consumeWork(1)
                guard secondMoments[i][j].intersects(secondMoments[j][i]),
                    inertiaAtReference[i][j].intersects(inertiaAtReference[j][i]) else { throw invalid() }
            }
        }
        let axes = try OriginalParameterQueryStorage.map(principalAxes, using: &execution) { axis, execution in
            try OriginalParameterQueryStorage.values(count: 3, using: &execution) { execution in
                try execution.consumeWork(3); return [axis.x, axis.y, axis.z]
            }
        }
        let reference = try OriginalParameterQueryStorage.values(count: 3, using: &execution) { execution in
            try execution.consumeWork(3); return [inertiaReference.x, inertiaReference.y, inertiaReference.z]
        }
        var centered = try OriginalParameterQueryStorage.map(secondMoments, using: &execution) { row, execution in
            try OriginalParameterQueryStorage.map(row, using: &execution) { value, execution in interval(value) }
        }
        for i in 0..<3 { for j in 0..<3 {
            try execution.consumeWork(1)
            centered[i][j] = centered[i][j] - .exact(reference[i]) * interval(firstMoments[j])
                - .exact(reference[j]) * interval(firstMoments[i])
                + .exact(reference[i]) * .exact(reference[j]) * interval(mass)
        } }
        let trace = centered[0][0] + centered[1][1] + centered[2][2]
        for i in 0..<3 { for j in 0..<3 {
            try execution.consumeWork(1)
            let expected = i == j ? trace - centered[i][j] : -centered[i][j]
            guard expected.lower <= inertiaAtReference[i][j].upper,
                expected.upper >= inertiaAtReference[i][j].lower else { throw invalid() }
        } }
        var gramSquared = OutwardScalarInterval.exact(0)
        for i in 0..<3 { for j in 0..<3 {
            try execution.consumeWork(1)
            var defect = OutwardScalarInterval.exact(i == j ? -1 : 0)
            for k in 0..<3 { try execution.consumeWork(1); defect = defect + .exact(axes[i][k]) * .exact(axes[j][k]) }
            let lower = absoluteLower(defect)
            gramSquared = gramSquared + .exact(lower) * .exact(lower)
        } }
        guard max(0, gramSquared.lower).squareRoot().nextDown <= principalFrameOrthogonalityError else {
            throw invalid()
        }
        for k in 0..<3 {
            try execution.consumeWork(1)
            var squared = OutwardScalarInterval.exact(0)
            for i in 0..<3 {
                try execution.consumeWork(1)
                var residual = -interval(principalMoments[k]) * .exact(axes[k][i])
                for j in 0..<3 { try execution.consumeWork(1); residual = residual + interval(inertiaAtReference[i][j]) * .exact(axes[k][j]) }
                let lower = absoluteLower(residual)
                squared = squared + .exact(lower) * .exact(lower)
            }
            guard max(0, squared.lower).squareRoot().nextDown <= principalAxisResidualBounds[k].upper else {
                throw invalid()
            }
        }
        try execution.checkpoint()
    }

    private func invalid() -> KernelError {
        KernelError(phase: .geometry, code: .invalidInput, tolerance: nil,
            message: "Mass property dimensions, enclosures or retained numeric authority are incoherent.")
    }

}

#if !hasFeature(Embedded)
extension MassPropertyMeasurement: Codable {
    private enum CodingKeys: String, CodingKey {
        case requestedIntegrationAccuracy, modelLengthUnit, consumedWork, mass, firstMoments, secondMoments, centroid, centroidBounds, inertiaAtReference, inertiaReference, principalMoments, principalAxes, principalFrameOrthogonalityError, principalAxisResidualBounds
    }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        try c.validateOnlyExpectedKeys([.requestedIntegrationAccuracy, .modelLengthUnit, .consumedWork, .mass, .firstMoments, .secondMoments, .centroid, .centroidBounds, .inertiaAtReference, .inertiaReference, .principalMoments, .principalAxes, .principalFrameOrthogonalityError, .principalAxisResidualBounds], in: decoder)
        requestedIntegrationAccuracy = try c.decode(BRepVolumeMomentOptions.self, forKey: .requestedIntegrationAccuracy)
        modelLengthUnit = try c.decode(LengthUnit.self, forKey: .modelLengthUnit)
        consumedWork = try c.decode(Int.self, forKey: .consumedWork)
        mass = try c.decode(ScalarInterval.self, forKey: .mass)
        firstMoments = try c.decode([ScalarInterval].self, forKey: .firstMoments)
        secondMoments = try c.decode([[ScalarInterval]].self, forKey: .secondMoments)
        centroid = try c.decode(Point3D.self, forKey: .centroid)
        centroidBounds = try c.decode([ScalarInterval].self, forKey: .centroidBounds)
        inertiaAtReference = try c.decode([[ScalarInterval]].self, forKey: .inertiaAtReference)
        inertiaReference = try c.decode(Point3D.self, forKey: .inertiaReference)
        principalMoments = try c.decode([ScalarInterval].self, forKey: .principalMoments)
        principalAxes = try c.decode([Vector3D].self, forKey: .principalAxes)
        principalFrameOrthogonalityError = try c.decode(Double.self, forKey: .principalFrameOrthogonalityError)
        principalAxisResidualBounds = try c.decode([ScalarInterval].self, forKey: .principalAxisResidualBounds)
        try validate()
    }
    public func encode(to encoder: Encoder) throws {
        try validate()
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(requestedIntegrationAccuracy, forKey: .requestedIntegrationAccuracy)
        try c.encode(modelLengthUnit, forKey: .modelLengthUnit)
        try c.encode(consumedWork, forKey: .consumedWork)
        try c.encode(mass, forKey: .mass)
        try c.encode(firstMoments, forKey: .firstMoments)
        try c.encode(secondMoments, forKey: .secondMoments)
        try c.encode(centroid, forKey: .centroid)
        try c.encode(centroidBounds, forKey: .centroidBounds)
        try c.encode(inertiaAtReference, forKey: .inertiaAtReference)
        try c.encode(inertiaReference, forKey: .inertiaReference)
        try c.encode(principalMoments, forKey: .principalMoments)
        try c.encode(principalAxes, forKey: .principalAxes)
        try c.encode(principalFrameOrthogonalityError, forKey: .principalFrameOrthogonalityError)
        try c.encode(principalAxisResidualBounds, forKey: .principalAxisResidualBounds)
    }
}
#endif

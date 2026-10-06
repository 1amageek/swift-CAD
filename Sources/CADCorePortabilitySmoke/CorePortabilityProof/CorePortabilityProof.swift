import CADCore
import HashTreeCollections

enum CorePortabilityProof {
    static func run() throws {
        try valuesAndMath()
        print("CORE_VALUES_MATH_OK")
        try typedFailures()
        print("CORE_TYPED_FAILURE_OK")
        try diagnosticPresentation()
        print("CORE_DIAGNOSTIC_PRESENTATION_OK")
        try ownershipAndReferences()
        print("CORE_COW_REFERENCES_OK")
    }

    static func checkCancellationWitness() async throws {
        let task = Task {
            try withUnsafeCurrentTask { current in
                guard let current else { throw CorePortabilityProofFailure.missingCurrentTask }
                current.cancel()
            }
            let checker: any CurrentTaskCancellationChecking = CurrentTaskCancellationChecker()
            do {
                try checker.checkCancellation()
                throw CorePortabilityProofFailure.expectedFailure("current task cancellation")
            } catch let error as CancellationError {
                let normalized = KernelError.wrapping(error, phase: .evaluation, tolerance: .standard)
                guard normalized.code == .cancelled else {
                    throw CorePortabilityProofFailure.unexpectedValue("cancellation classification")
                }
            }
        }
        try await task.value
        print("CORE_CANCELLATION_WITNESS_OK")
    }

    private static func valuesAndMath() throws {
        let point = Point3D(x: 1, y: 2, z: 3)
        try point.validate()
        let vector = Vector3D(x: 3, y: 4, z: 12)
        guard vector.length == 13, point + vector == Point3D(x: 4, y: 6, z: 15),
              point - .origin == Vector3D(x: 1, y: 2, z: 3) else {
            throw CorePortabilityProofFailure.unexpectedValue("point and vector arithmetic")
        }
        let large = try Vector3D(x: Double.greatestFiniteMagnitude, y: 0, z: 0)
            .normalized(tolerance: 1e-9)
        guard large == .unitX else {
            throw CorePortabilityProofFailure.unexpectedValue("overflow-safe hypot")
        }
        try Transform3D.identity.validate()
        try SchemaVersion.current.validate()
        try ModelingTolerance.standard.validate()
        try UnitSystem.meters.validate()
        guard Quantity.length(2, unit: .kilometer).value == 2_000,
              Quantity.angle(180, unit: .degree).value == .pi else {
            throw CorePortabilityProofFailure.unexpectedValue("unit conversion")
        }
        let original = [Point2D(x: 0, y: 0), Point2D(x: 1, y: 0)]
        let continuation = try NaturalBezierContinuation(tolerance: .standard)
            .naturalSpan(ofSegment: original, at: .end, length: 2)
        guard continuation.count == 1 else {
            throw CorePortabilityProofFailure.unexpectedValue("original linear continuation count")
        }
        // The original integral/Newton producer admits floating-point quadrature error.
        // This coordinate bound is stricter than its unchanged modeling-distance postcondition.
        print("CORE_LINEAR_CONTINUATION observedX=\(continuation[0].x) deltaX=\(abs(continuation[0].x - 3)) observedY=\(continuation[0].y)")
        guard abs(continuation[0].x - 3) <= 1e-12, continuation[0].y == 0 else {
            throw CorePortabilityProofFailure.unexpectedValue("original linear continuation")
        }
        let profile = try CurvatureProfileExtension(tolerance: .standard).cubicSpans(
            from: Point2D(x: 0, y: 0), direction: Point2D(x: 1, y: 0),
            curvature: 0, length: 2, profile: .arc, spanCount: 1
        )
        let expected = [Point2D(x: 2.0 / 3, y: 0), Point2D(x: 4.0 / 3, y: 0), Point2D(x: 2, y: 0)]
        guard profile.count == expected.count else {
            throw CorePortabilityProofFailure.unexpectedValue("profile count")
        }
        for index in expected.indices {
            guard abs(profile[index].x - expected[index].x) <= 1e-12,
                  abs(profile[index].y - expected[index].y) <= 1e-12 else {
                throw CorePortabilityProofFailure.unexpectedValue("actual C trigonometry")
            }
        }
        let expression = CADExpression.hypot(.constant(.scalar(3)), .constant(.scalar(4)))
        try expression.validateLiteralQuantities()
        guard expression.referencedParameterIDs.isEmpty else {
            throw CorePortabilityProofFailure.unexpectedValue("expression dependencies")
        }
    }

    private static func typedFailures() throws {
        try expectGeometry(.invalidMatrixElementCount(3)) { _ = try Matrix4x4(values: [1, 2, 3]) }
        try expectGeometry(.invalidCoordinate(.infinity)) {
            try Point3D(x: .infinity, y: 0, z: 0).validate()
        }
        try expectGeometry(.invalidVectorLength(0)) {
            _ = try Vector3D.zero.normalized(tolerance: 1e-9)
        }
        try expectGeometry(.invalidVectorLength(.infinity)) {
            _ = try Vector3D(x: .greatestFiniteMagnitude, y: .greatestFiniteMagnitude, z: 0)
                .normalized(tolerance: 1e-9)
        }
        do {
            try DocumentRevision(-1).validate()
            throw CorePortabilityProofFailure.expectedFailure("invalid revision")
        } catch SchemaError.invalidRevision(-1) {}
        let invalid = KernelError.wrapping(GeometryError.invalidRadius(-1), phase: .geometry, tolerance: .standard)
        let resource = KernelError.wrapping(
            TessellationError.resourceExhausted(.triangleCount, requested: 2, limit: 1),
            phase: .evaluation, tolerance: .standard
        )
        guard invalid.code == .invalidInput, resource.code == .resourceLimitExceeded,
              invalid.description == invalid.message, !invalid.debugDescription.isEmpty else {
            throw CorePortabilityProofFailure.unexpectedValue("typed failure preservation")
        }
    }

    private static func diagnosticPresentation() throws {
        let first = PortableIdentity128(high: 0x0011_2233_4455_4677, low: 0x8899_AABB_CCDD_EEFF)
        let second = PortableIdentity128(high: 0x0011_2233_4455_4677, low: 0x8899_AABB_CCDD_EEF0)
        let parameter = ParameterID(first)
        let otherParameter = ParameterID(second)
        let feature = FeatureID(first)
        let context = ModelingTolerance(distance: 0.125, angle: 0.25, relative: 0.5)
        let cases: [(Error, KernelErrorCode, String, [String])] = [
            (GeometryError.invalidModelingTolerance(distance: 0.125, angle: 0.25, relative: 0.5),
             .invalidInput,
             "GeometryError.invalidModelingTolerance(distance: 0.125, angle: 0.25, relative: 0.5)",
             ["0.125", "0.25", "0.5"]),
            (SchemaError.unsupportedVersion(SchemaVersion(major: 2, minor: 3, patch: 4)),
             .unsupportedCapability,
             "SchemaError.unsupportedVersion(major: 2, minor: 3, patch: 4)",
             ["major: 2", "minor: 3", "patch: 4"]),
            (ParameterError.kindMismatch(parameterID: parameter, expected: .length, actual: .angle),
             .invalidInput,
             "ParameterError.kindMismatch(parameterID: 00112233-4455-4677-8899-AABBCCDDEEFF, expected: length, actual: angle)",
             ["00112233-4455-4677-8899-AABBCCDDEEFF", "length", "angle"]),
            (ParameterError.cycleDetected([parameter, otherParameter, parameter]),
             .invalidInput,
             "ParameterError.cycleDetected([00112233-4455-4677-8899-AABBCCDDEEFF, 00112233-4455-4677-8899-AABBCCDDEEF0, 00112233-4455-4677-8899-AABBCCDDEEFF])",
             ["00112233-4455-4677-8899-AABBCCDDEEFF, 00112233-4455-4677-8899-AABBCCDDEEF0, 00112233-4455-4677-8899-AABBCCDDEEFF"]),
            (FeatureEvaluationError.invalidDirection(Vector3D(x: 3, y: 4, z: 12)),
             .invalidInput, "FeatureEvaluationError.invalidDirection(x: 3.0, y: 4.0, z: 12.0)",
             ["x: 3.0", "y: 4.0", "z: 12.0"]),
            (CacheValidationError.meshCacheExceedsLimits(bodyID: BodyID(first), .triangleCount, recorded: 3, limit: 2),
             .resourceLimitExceeded,
             "CacheValidationError.meshCacheExceedsLimits(bodyID: 00112233-4455-4677-8899-AABBCCDDEEFF, triangleCount, recorded: 3, limit: 2)",
             ["00112233-4455-4677-8899-AABBCCDDEEFF", "triangleCount", "recorded: 3", "limit: 2"]),
            (ImportError.compositionFailure(kind: "literal-kind", message: "source-note"),
             .invalidInput,
             "ImportError.compositionFailure(kind: \"literal-kind\", message: \"source-note\")",
             ["literal-kind", "source-note"])
        ]
        for (source, code, structuralMessage, nativePayloads) in cases {
            let normalized = KernelError.wrapping(source, phase: .geometry, featureID: feature, tolerance: context)
            guard normalized.code == code, normalized.phase == .geometry,
                  normalized.featureID == feature, normalized.tolerance == context else {
                throw CorePortabilityProofFailure.unexpectedValue("domain diagnostic context")
            }
            #if hasFeature(Embedded)
            guard normalized.message == structuralMessage else {
                throw CorePortabilityProofFailure.unexpectedValue("structural associated-value diagnostic")
            }
            #else
            for payload in nativePayloads {
                guard normalized.message.contains(payload) else {
                    throw CorePortabilityProofFailure.unexpectedValue("reflected associated-value diagnostic")
                }
            }
            #endif
        }
        let foreign = KernelError.wrapping(
            CorePortabilityProofFailure.unexpectedValue("foreign-associated-value"),
            phase: .evaluation, tolerance: .standard
        )
        guard foreign.code == .unclassifiedFailure else {
            throw CorePortabilityProofFailure.unexpectedValue("foreign error classification")
        }
        #if hasFeature(Embedded)
        guard foreign.message == "Unclassified source error; reflective diagnostic payload is unavailable on Embedded Swift." else {
            throw CorePortabilityProofFailure.unexpectedValue("explicit reflection capability boundary")
        }
        #else
        guard foreign.message.contains("foreign-associated-value") else {
            throw CorePortabilityProofFailure.unexpectedValue("original foreign diagnostic payload")
        }
        #endif
        let original = KernelError(
            phase: .geometry, code: .singularGeometry, featureID: feature,
            subshapeID: SubshapeID(featureID: feature, role: "source", ordinal: 2),
            residual: 0.5, tolerance: context, message: "original-diagnostic"
        )
        let preserved = KernelError.wrapping(
            original, phase: .evaluation, featureID: FeatureID(second), tolerance: .standard
        )
        guard preserved == original, preserved.category == .singularity else {
            throw CorePortabilityProofFailure.unexpectedValue("complete original KernelError context")
        }
    }

    private static func ownershipAndReferences() throws {
        let feature = FeatureID(PortableIdentity128(high: 0x0011_2233_4455_4677, low: 0x8899_AABB_CCDD_EEFF))
        let parent = SubshapeID(featureID: feature, role: "source", ordinal: 0)
        let output = SubshapeID(featureID: feature, role: "result", ordinal: 0)
        let lineage = TopologyLineage(output: output, parents: [parent, parent], relation: .preserved)
        guard lineage.isStructurallyValid, lineage.parents == [parent],
              lineage.output.featureID == feature else {
            throw CorePortabilityProofFailure.unexpectedValue("exact lineage references")
        }
        var current: PersistentMap<String, Point3D> = ["point": .origin]
        let before = current
        current["point"] = Point3D(x: 1, y: 2, z: 3)
        var matrix = Matrix4x4.identity
        let matrixBefore = matrix
        matrix.values[0] = 2
        guard before["point"] == .origin, current["point"] == Point3D(x: 1, y: 2, z: 3),
              matrixBefore == .identity, matrix.values[0] == 2 else {
            throw CorePortabilityProofFailure.unexpectedValue("original COW owner")
        }
        requireSendable(current)
        requireSendable(lineage)
        requireSendable(matrix)
    }

    private static func expectGeometry(_ expected: GeometryError, _ body: () throws -> Void) throws {
        do {
            try body()
            throw CorePortabilityProofFailure.expectedFailure("geometry refusal")
        } catch let error as GeometryError {
            guard error == expected else {
                throw CorePortabilityProofFailure.unexpectedValue("geometry failure reason")
            }
        }
    }

    private static func requireSendable<Value: Sendable>(_ value: Value) {}
}

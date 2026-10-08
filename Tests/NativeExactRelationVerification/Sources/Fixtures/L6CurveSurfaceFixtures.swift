import CADCore
import CADGeometry

public enum L6CurveSurfaceFixtures {
    private static func limits() throws -> ExactGeometricRelationLimits {
        try .init(cells: NativeExactFixtures.cells(), topology: NativeExactFixtures.topology(),
            maximumStrata: 20_000, maximumProjectionSpans: 1_000)
    }

    private static func query(_ curve: BSplineCurve3D, _ surface: BSplineSurface3D,
        options: CurveSurfaceIntersectionOptions = .init()) throws -> CurveSurfaceIntersectionResult {
        var admission = try NativeExactFixtures.ledger()
        return try DefaultCurveSurfaceIntersector().intersectionResult(curve: curve, surface: surface,
            options: options, tolerance: .standard, maximumExtensionLevel: 10,
            limits: limits(), using: &admission)
    }

    public static func verify() throws {
        let resolver = DefaultCurveSurfaceIntersector()
        for mode in 0..<5 {
            var source = NativeExactFixtures.curve(mode == 1 ? [1, -1, 1] :
                mode == 2 ? [-0.125, 0.125, -0.125, 0.125] : mode == 3 ? [0, 0] : [-1, 1])
            if mode == 1 {
                source.controlPoints[0].x = 0
                source.controlPoints[1].x = 0.5
                source.controlPoints[2].x = 1
            }
            let surface = NativeExactFixtures.plane(z: mode == 4 ? 2 : 0)
            let result = try query(source, surface)
            guard let receipt = result.originalExactGeometricRelation else {
                throw NativeExactFixtures.Failure.invalidEvidence
            }
            try NativeExactFixtures.require(receipt.geometry.original.selection.cells.count ==
                receipt.parameterRelation.relation.selection.cells.count)
            if mode == 3 {
                try NativeExactFixtures.require(result.points.isEmpty && result.hasPositiveDimensionalSolutions)
                try NativeExactFixtures.require(!receipt.hasPositiveDimensionalImage)
            } else if mode == 4 {
                try NativeExactFixtures.require(result.points.isEmpty && receipt.geometry.isEmpty)
            } else {
                try NativeExactFixtures.require(result.points.count == 1)
                let expected: CurveSurfaceIntersectionKind = mode == 0 ? .transverse : mode == 1 ? .tangent : .mixed
                try NativeExactFixtures.require(result.points[0].kind == expected)
                try NativeExactFixtures.require(result.points[0].residual <= ModelingTolerance.standard.distance)
                try NativeExactFixtures.require(abs(result.points[0].curveParameter - 0.5) <= ModelingTolerance.standard.distance)
            }
            print("PASS L6 public CS point/classification/coverage case \(mode)")
        }
        // Distinct exact UV tuples at a common XYZ remain distinct public representatives.
        let folded = BSplineSurface3D(uDegree: 2, vDegree: 1,
            uKnots: [0, 0, 0, 1, 1, 1], vKnots: [0, 0, 1, 1], controlPoints: [
                [.init(x: 1, y: 0, z: 0), .init(x: -1, y: 0, z: 0), .init(x: 1, y: 0, z: 0)],
                [.init(x: 1, y: 1, z: 0), .init(x: -1, y: 1, z: 0), .init(x: 1, y: 1, z: 0)]])
        let duplicateXYZ = try query(NativeExactFixtures.curve([-1, 1]), folded)
        try NativeExactFixtures.require(duplicateXYZ.points.count == 2)
        try NativeExactFixtures.require(duplicateXYZ.points[0].surfaceU != duplicateXYZ.points[1].surfaceU)
        try NativeExactFixtures.require(duplicateXYZ.points.allSatisfy { $0.point.x == 0.25 && $0.point.y == 0.5 })
        print("PASS L6 public CS distinct UV tuples")

        for weighted in [false, true] {
            print("START L6 public CS representative refinement weighted=\(weighted)")
            let source = NativeExactFixtures.curve(weighted ? [-1, 1] : [-0.5, -0.5, 0.5],
                weights: weighted ? [1, 2] : nil)
            let result = try query(source, NativeExactFixtures.plane())
            let parameter = weighted ? 1.0 / 3.0 : 0.7071067811865476
            try NativeExactFixtures.require(result.points.count == 1)
            try NativeExactFixtures.require(abs(result.points[0].curveParameter - parameter) <= ModelingTolerance.standard.distance)
            try NativeExactFixtures.require(result.points[0].kind == .transverse)
            print("PASS L6 public CS representative refinement weighted=\(weighted)")
        }
        print("PASS L6 public CS rational and algebraic representative refinement")

        let smallest = Double.leastNonzeroMagnitude
        var subnormalCurve = NativeExactFixtures.curve([-1, 1])
        subnormalCurve.controlPoints[0].x = smallest
        subnormalCurve.controlPoints[1].x = smallest
        let subnormal = try query(subnormalCurve, NativeExactFixtures.plane(),
            options: .init(surfaceURange: .init(lower: smallest, upper: smallest)))
        try NativeExactFixtures.require(subnormal.points.count == 1)
        try NativeExactFixtures.require(subnormal.points[0].point.x == smallest)
        try NativeExactFixtures.require(subnormal.points[0].surfaceU == smallest)
        print("PASS L6 public CS smallest-subnormal singleton representatives")

        // One isolated tuple and one continuous tuple component share their XYZ image.
        let (planarCurve, mixedSurface) = mixedSources()
        let mixed = try query(planarCurve, mixedSurface)
        try NativeExactFixtures.require(mixed.points.count == 1 && mixed.hasPositiveDimensionalSolutions)
        try NativeExactFixtures.require(mixed.originalExactGeometricRelation?.hasPositiveDimensionalImage == true)
        try NativeExactFixtures.require(mixed.points[0].surfaceV == 0.5)
        do {
            var admission = try NativeExactFixtures.ledger()
            _ = try resolver.intersections(curve: planarCurve, surface: mixedSurface,
                options: .init(), tolerance: .standard, maximumExtensionLevel: 10,
                limits: limits(), using: &admission)
            throw NativeExactFixtures.Failure.invalidEvidence
        } catch let error as KernelError {
            try NativeExactFixtures.require(error.code == .nonDiscreteIntersection)
        }
        print("PASS L6 public CS mixed components and point-only failure")

        for mode in 0..<3 {
            var admission = try NativeExactFixtures.ledger(work: mode == 0 ? 0 : 8_388_608,
                bytes: mode == 1 ? 0 : 1_073_741_824)
            if mode == 2 { admission.cancel() }
            do {
                _ = try resolver.exactGeometricRelation(curve: NativeExactFixtures.curve([-1, 1]),
                    surface: NativeExactFixtures.plane(), tolerance: .standard, maximumPolynomialDegree: 3,
                    maximumExtensionLevel: 10, limits: limits(), using: &admission)
                throw NativeExactFixtures.Failure.invalidEvidence
            } catch is NativeExactGeometricRelationFailure { }
        }
        print("PASS L6 public CS caller admission work/storage/cancellation")

        for empty in [false, true] {
            let source = NativeExactFixtures.curve(empty ? [1, 2] : [-1, 1])
            var measured = try FinalPublicationAdmission()
            _ = try resolver.intersectionResult(curve: source, surface: NativeExactFixtures.plane(),
                options: .init(), tolerance: .standard, maximumExtensionLevel: 10,
                limits: limits(), using: &measured)
            var cancelled = try FinalPublicationAdmission(cancellingCall: measured.storageCalls)
            do {
                _ = try resolver.intersectionResult(curve: source, surface: NativeExactFixtures.plane(),
                    options: .init(), tolerance: .standard, maximumExtensionLevel: 10,
                    limits: limits(), using: &cancelled)
                throw NativeExactFixtures.Failure.invalidEvidence
            } catch is CancellationError { }
            try NativeExactFixtures.require(cancelled.storageCalls == measured.storageCalls)
        }
        print("PASS L6 public CS final point/empty cancellation")
    }
    private static func mixedSources() -> (BSplineCurve3D, BSplineSurface3D) {
        let mixedSurface = BSplineSurface3D(uDegree: 1, vDegree: 2,
            uKnots: [0, 0, 1, 1], vKnots: [0, 0, 0, 1, 1, 1], controlPoints: [
                [.init(x: 0, y: 0, z: 0), .init(x: 1, y: 0, z: 0)],
                [.init(x: 0, y: -0.25, z: -0.25), .init(x: 1, y: 0.25, z: -0.25)],
                [.init(x: 0, y: -0.5, z: 0.5), .init(x: 1, y: 0.5, z: 0.5)]])
        let planarCurve = BSplineCurve3D(degree: 1, knots: [0, 0, 1, 1], controlPoints: [
            .init(x: 0, y: 0, z: 0), .init(x: 1, y: 0, z: 0)])
        return (planarCurve, mixedSurface)
    }

    public static func verifyMixedRelation() throws {
        let (curve, surface) = mixedSources()
        var admission = try NativeExactFixtures.ledger()
        do {
            let parameters = try DefaultNativeExactRelationResolver().exactParameterRelation(
                curve: curve, surface: surface, tolerance: .standard, maximumPolynomialDegree: 3,
                maximumExtensionLevel: 10, cellLimits: limits().cells,
                topologyLimits: limits().topology, using: &admission)
            print("PASS mixed original L5 relation work=\(admission.work)")
            _ = try DefaultNativeExactGeometricRelationResolver().resolve(parameters,
                limits: limits(), using: &admission)
            print("PASS mixed original L6 relation work=\(admission.work)")
        } catch let error as NativeExactRelationFailure {
            print("FAILED mixed relation work=\(admission.work), depth=\(admission.valueDepth)/\(admission.coefficientDepth): \(error)")
            throw error
        }
    }
}

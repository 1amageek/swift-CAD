import CADCore
import CADGeometry
import CADTopology

/// Original transverse finite-face interiors prove an open material wedge.
package struct OriginalTransverseMaterialOverlap: OriginalMaterialOverlapProving {
    private struct VectorBounds {
        let x: OutwardScalarInterval
        let y: OutwardScalarInterval
        let z: OutwardScalarInterval

        func cross(_ other: Self) -> Self {
            Self(x: y * other.z - z * other.y,
                y: z * other.x - x * other.z, z: x * other.y - y * other.x)
        }

        var excludesZero: Bool {
            x.isFinite && y.isFinite && z.isFinite
                && (x.lower > 0 || x.upper < 0 || y.lower > 0 || y.upper < 0
                    || z.lower > 0 || z.upper < 0)
        }
    }

    private enum Evidence {
        case inconclusive
        case transverse
        case interior(Point3D)

        var provesOverlap: Bool {
            switch self {
            case .inconclusive: return false
            case .transverse, .interior: return true
            }
        }
    }

    private let containment: any OriginalFaceTrimBoxContaining

    package init(containment: any OriginalFaceTrimBoxContaining = OriginalFaceTrimBoxContainment()) {
        self.containment = containment
    }

    package func provesOverlap(in prepared: PreparedBooleanIntersectionGraph,
        firstBodyID: BodyID, secondBodyID: BodyID,
        maximumSpanCount: Int, maximumSubdivisionDepth: Int, remainingSourceDepth: Int,
        consumeWork: @escaping @Sendable (Int) throws -> Void,
        consumeStorage: (@Sendable (Int) throws -> Void)?, maximumAlgebraicDepth: Int = 32) throws -> Bool {
        var selectedPair = prepared.toolBodyID == nil
        for target in prepared.targetBodyIDs {
            try Task.checkCancellation()
            try consumeWork(0)
            if (target == firstBodyID && prepared.toolBodyID == secondBodyID)
                || (target == secondBodyID && prepared.toolBodyID == firstBodyID) { selectedPair = true }
        }
        guard selectedPair else {
            throw KernelError(phase: .classification, code: .invalidInput,
                tolerance: prepared.validatedModel.tolerance,
                message: "Original overlap bodies are foreign to the producer-bound operand graph.")
        }
        return try prove(graph: prepared.intersectionGraph, firstBodyID: firstBodyID,
            secondBodyID: secondBodyID, validatedModel: prepared.validatedModel, producerBound: true, classifications: nil,
            maximumSpanCount: maximumSpanCount, maximumSubdivisionDepth: maximumSubdivisionDepth,
            remainingSourceDepth: remainingSourceDepth, consumeWork: consumeWork,
            consumeStorage: consumeStorage, maximumAlgebraicDepth: maximumAlgebraicDepth).provesOverlap
    }

    package func provesOverlap(inAdmitted graph: BooleanIntersectionGraph,
        firstBodyID: BodyID, secondBodyID: BodyID, validatedModel: ValidatedBRepModel,
        maximumSpanCount: Int, maximumSubdivisionDepth: Int, remainingSourceDepth: Int,
        consumeWork: @escaping @Sendable (Int) throws -> Void,
        consumeStorage: (@Sendable (Int) throws -> Void)?, maximumAlgebraicDepth: Int = 32) throws -> Bool {
        try prove(graph: graph, firstBodyID: firstBodyID, secondBodyID: secondBodyID,
            validatedModel: validatedModel, producerBound: false, classifications: nil, maximumSpanCount: maximumSpanCount,
            maximumSubdivisionDepth: maximumSubdivisionDepth, remainingSourceDepth: remainingSourceDepth,
            consumeWork: consumeWork, consumeStorage: consumeStorage, maximumAlgebraicDepth: maximumAlgebraicDepth).provesOverlap
    }

    package func interiorWitness(in classifications: PreparedSolidClassificationPair,
        maximumSubdivisionDepth: Int,
        consumeWork: @escaping @Sendable (Int) throws -> Void,
        consumeStorage: (@Sendable (Int) throws -> Void)?) throws -> Point3D? {
        try OriginalContainmentMaterialWitness().witness(in: classifications,
            maximumSubdivisionDepth: maximumSubdivisionDepth,
            consumeWork: consumeWork, consumeStorage: consumeStorage)
    }

    // FIXME(INCOMPLETE_IMPLEMENTATION): This Q1/Q2 positive witness route handles
    // original implicit transverse cells lying wholly inside both finite trims.
    // Tangent/coincident/analytic witnesses and straddling-cell refinement remain
    // required for full relationship classification; nil never proves absence.
    // Retained classifier lower storage and combined candidate/source depth are
    // separate accounting dependencies before whole-query bounded completion.
    package func interiorWitness(in prepared: PreparedBooleanIntersectionGraph,
        maximumSpanCount: Int, maximumSubdivisionDepth: Int, remainingSourceDepth: Int,
        consumeWork: @escaping @Sendable (Int) throws -> Void,
        consumeStorage: (@Sendable (Int) throws -> Void)?, maximumAlgebraicDepth: Int = 32) throws -> Point3D? {
        try Task.checkCancellation()
        try consumeWork(0)
        guard let classifications = prepared.classifications else {
            throw KernelError(phase: .classification, code: .invalidInput,
                tolerance: prepared.validatedModel.tolerance,
                message: "An original interior witness requires the graph's retained classification-pair owner.")
        }
        let evidence = try prove(graph: prepared.intersectionGraph,
            firstBodyID: classifications.firstBodyID, secondBodyID: classifications.secondBodyID,
            validatedModel: classifications.validatedModel, producerBound: true,
            classifications: classifications, maximumSpanCount: maximumSpanCount,
            maximumSubdivisionDepth: maximumSubdivisionDepth, remainingSourceDepth: remainingSourceDepth,
            consumeWork: consumeWork, consumeStorage: consumeStorage, maximumAlgebraicDepth: maximumAlgebraicDepth)
        if case .interior(let point) = evidence { return point }
        return nil
    }

    private func prove(graph: BooleanIntersectionGraph, firstBodyID: BodyID, secondBodyID: BodyID,
        validatedModel: ValidatedBRepModel, producerBound: Bool,
        classifications: PreparedSolidClassificationPair?, maximumSpanCount: Int, maximumSubdivisionDepth: Int, remainingSourceDepth: Int,
        consumeWork: @escaping @Sendable (Int) throws -> Void,
        consumeStorage: (@Sendable (Int) throws -> Void)?, maximumAlgebraicDepth: Int) throws -> Evidence {
        let tolerance = validatedModel.tolerance
        let admission = try BooleanGraphAdmission(maximumSpanCount: maximumSpanCount,
            maximumSubdivisionDepth: maximumSubdivisionDepth, remainingSourceDepth: remainingSourceDepth,
            consumeWork: consumeWork, consumeStorage: consumeStorage, tolerance: tolerance, maximumAlgebraicDepth: maximumAlgebraicDepth)
        try admission.step()
        let model = validatedModel.model
        guard firstBodyID != secondBodyID, validatedModel.validationLevel != .modeling,
              model.bodies[firstBodyID]?.kind == .solid, model.bodies[secondBodyID]?.kind == .solid else {
            throw KernelError(phase: .classification, code: .invalidInput, tolerance: tolerance,
                message: "Original material overlap requires two distinct exact solid bodies.")
        }
        let firstFaces = try faceIDs(firstBodyID, model: model, admission: admission)
        let secondFaces = try faceIDs(secondBodyID, model: model, admission: admission)
        var supports: [FaceID: PreparedSurfaceDifferentialEncloser] = [:]
        for intersection in graph.faceIntersections {
            try admission.step()
            let pair = intersection.facePair
            guard (firstFaces.contains(pair.targetFaceID) && secondFaces.contains(pair.toolFaceID))
                || (secondFaces.contains(pair.targetFaceID) && firstFaces.contains(pair.toolFaceID)) else { continue }
            guard case .curve(let curve) = intersection.geometry,
                  case .implicit(let original) = curve.truth else { continue }
            try admission.step()
            try original.validateCertificationContract(tolerance: tolerance)
            guard let firstFace = model.faces[pair.targetFaceID], let secondFace = model.faces[pair.toolFaceID],
                  let firstSurface = model.geometry.surfaces[firstFace.surfaceID],
                  let secondSurface = model.geometry.surfaces[secondFace.surfaceID] else {
                throw TopologyError.missingReference("Original overlap faces have missing supports.")
            }
            if !producerBound {
                // FIXME(INCOMPLETE_IMPLEMENTATION): Raw same-source graph
                // compatibility checks require original supporting-value equality.
                // Its inner comparison has no callback; use the producer-bound
                // receipt entry before declaring whole query work accounting.
                guard original.firstSurface == firstSurface, original.secondSurface == secondSurface else {
                    throw KernelError(phase: .classification, code: .invalidInput, tolerance: tolerance,
                        message: "The original overlap graph belongs to different supporting surfaces.")
                }
            }
            for side in 0..<2 {
                let faceID = side == 0 ? pair.targetFaceID : pair.toolFaceID
                guard supports[faceID] == nil else { continue }
                try admission.reserve(count: 1, stride: MemoryLayout<FaceID>.stride
                    + MemoryLayout<PreparedSurfaceDifferentialEncloser>.stride)
                guard let face = model.faces[faceID], let surface = model.geometry.surfaces[face.surfaceID] else {
                    throw TopologyError.missingReference("An original overlap support disappeared.")
                }
                supports[faceID] = try PreparedSurfaceDifferentialEncloser(surface: surface,
                    tolerance: tolerance, remainingSourceDepth: remainingSourceDepth,
                    maximumSubdivisionDepth: maximumSubdivisionDepth,
                    consumeWork: { try admission.step() }, consumeStorage: consumeStorage,
                    maximumAlgebraicDepth: maximumAlgebraicDepth)
            }
            guard let firstPrepared = supports[pair.targetFaceID], let secondPrepared = supports[pair.toolFaceID] else {
                throw KernelError(phase: .classification, code: .classificationFailure, tolerance: tolerance,
                    message: "Original overlap preparation is missing its retained supports.")
            }
            for (cellIndex, cell) in original.cells.enumerated() {
                try admission.step()
                let firstBox = SurfaceParameterBox(u: cell.parameterBox.firstU, v: cell.parameterBox.firstV)
                let secondBox = SurfaceParameterBox(u: cell.parameterBox.secondU, v: cell.parameterBox.secondV)
                guard try containment.classify(firstBox, in: pair.targetFaceID,
                    validatedModel: validatedModel, maximumSubdivisionDepth: maximumSubdivisionDepth,
                    remainingSourceDepth: remainingSourceDepth, maximumAlgebraicDepth: maximumAlgebraicDepth,
                    consumeWork: consumeWork, consumeStorage: consumeStorage) == .inside else { continue }
                guard try containment.classify(secondBox, in: pair.toolFaceID,
                    validatedModel: validatedModel, maximumSubdivisionDepth: maximumSubdivisionDepth,
                    remainingSourceDepth: remainingSourceDepth, maximumAlgebraicDepth: maximumAlgebraicDepth,
                    consumeWork: consumeWork, consumeStorage: consumeStorage) == .inside else { continue }
                let firstJet = try firstPrepared.intervalJet(overClosedBox: firstBox,
                    tolerance: tolerance, maximumSpanCount: maximumSpanCount,
                    maximumSubdivisionDepth: maximumSubdivisionDepth, remainingSourceDepth: remainingSourceDepth,
                    consumeWork: { try admission.step() }, consumeStorage: consumeStorage)
                let secondJet = try secondPrepared.intervalJet(overClosedBox: secondBox,
                    tolerance: tolerance, maximumSpanCount: maximumSpanCount,
                    maximumSubdivisionDepth: maximumSubdivisionDepth, remainingSourceDepth: remainingSourceDepth,
                    consumeWork: { try admission.step() }, consumeStorage: consumeStorage)
                try admission.step()
                let firstNormal = VectorBounds(x: firstJet.x.derivativeU, y: firstJet.y.derivativeU,
                    z: firstJet.z.derivativeU).cross(VectorBounds(x: firstJet.x.derivativeV,
                        y: firstJet.y.derivativeV, z: firstJet.z.derivativeV))
                let secondNormal = VectorBounds(x: secondJet.x.derivativeU, y: secondJet.y.derivativeU,
                    z: secondJet.z.derivativeU).cross(VectorBounds(x: secondJet.x.derivativeV,
                        y: secondJet.y.derivativeV, z: secondJet.z.derivativeV))
                guard firstNormal.cross(secondNormal).excludesZero else { continue }
                guard let classifications else { return .transverse }
                if let point = try interiorStation(original: original, cellIndex: cellIndex,
                    firstPrepared: firstPrepared, secondPrepared: secondPrepared,
                    firstFace: firstFace, secondFace: secondFace,
                    firstBox: firstBox, secondBox: secondBox, jet: firstJet,
                    classifications: classifications, tolerance: tolerance, admission: admission) {
                    return .interior(point)
                }
            }
        }
        return .inconclusive
    }

    private func interiorStation(original: CertifiedImplicitIntersectionCurve, cellIndex: Int,
        firstPrepared: PreparedSurfaceDifferentialEncloser,
        secondPrepared: PreparedSurfaceDifferentialEncloser,
        firstFace: Face, secondFace: Face, firstBox: SurfaceParameterBox,
        secondBox: SurfaceParameterBox, jet: SurfaceIntervalVectorJet,
        classifications: PreparedSolidClassificationPair,
        tolerance: ModelingTolerance, admission: BooleanGraphAdmission) throws -> Point3D? {
        let sourceAdmission = try SurfaceSurfaceQueryAdmission(
            maximumSpanCount: admission.maximumSpanCount,
            maximumSubdivisionDepth: admission.maximumSubdivisionDepth,
            remainingSourceDepth: admission.remainingSourceDepth,
            consumeWork: { try admission.step() }, consumeStorage: admission.consumeStorage,
            maximumAlgebraicDepth: admission.maximumAlgebraicDepth)
        try admission.step()
        let fraction = (Double(cellIndex) + 0.5) / Double(original.cells.count)
        let parameters = try original.parameterPair(atNormalizedFraction: fraction,
            firstSurface: firstPrepared, secondSurface: secondPrepared,
            tolerance: tolerance, admission: sourceAdmission)
        guard firstBox.u.contains(parameters.first.u), firstBox.v.contains(parameters.first.v),
              secondBox.u.contains(parameters.second.u), secondBox.v.contains(parameters.second.v) else { return nil }
        let anchor = try original.point(atNormalizedFraction: fraction,
            firstSurface: firstPrepared, secondSurface: secondPrepared,
            tolerance: tolerance, admission: sourceAdmission)
        let first = try firstPrepared.numericalSample(at: parameters.first, tolerance: tolerance,
            maximumSpanCount: admission.maximumSpanCount,
            maximumSubdivisionDepth: admission.maximumSubdivisionDepth,
            remainingSourceDepth: admission.remainingSourceDepth,
            consumeWork: { try admission.step() }, consumeStorage: admission.consumeStorage)
        let second = try secondPrepared.numericalSample(at: parameters.second, tolerance: tolerance,
            maximumSpanCount: admission.maximumSpanCount,
            maximumSubdivisionDepth: admission.maximumSubdivisionDepth,
            remainingSourceDepth: admission.remainingSourceDepth,
            consumeWork: { try admission.step() }, consumeStorage: admission.consumeStorage)
        let firstNormal = first.derivativeU.cross(first.derivativeV)
        let secondNormal = second.derivativeU.cross(second.derivativeV)
        let firstLength = firstNormal.length, secondLength = secondNormal.length
        guard firstLength.isFinite, secondLength.isFinite, firstLength > 0, secondLength > 0 else { return nil }
        let firstInward = firstNormal / firstLength * (firstFace.orientation == .forward ? -1 : 1)
        let secondInward = secondNormal / secondLength * (secondFace.orientation == .forward ? -1 : 1)
        let bisector = firstInward + secondInward
        let length = bisector.length
        guard length.isFinite, length > 0 else { return nil }
        let direction = bisector / length
        var reach = max(jet.x.value.upper - jet.x.value.lower,
            max(jet.y.value.upper - jet.y.value.lower, jet.z.value.upper - jet.z.value.lower))
        reach = max(reach, tolerance.distance)
        guard reach.isFinite, reach > 0 else { return nil }
        // Numerical source anchors and normals only propose stations. Both complete
        // original material sessions must accept the identical point before publication.
        for depth in 0...admission.maximumSubdivisionDepth {
            try Task.checkCancellation()
            try admission.consumeWork(depth)
            let candidate = anchor + direction * reach
            try candidate.validate()
            if try classifications.firstClassification.classify(candidate) == .inside,
               try classifications.secondClassification.classify(candidate) == .inside {
                try Task.checkCancellation()
                return candidate
            }
            let smaller = reach * 0.5
            guard smaller > 0, smaller < reach else { return nil }
            reach = smaller
        }
        return nil
    }

    private func faceIDs(_ bodyID: BodyID, model: BRepModel,
        admission: BooleanGraphAdmission) throws -> Set<FaceID> {
        guard let body = model.bodies[bodyID] else { throw TopologyError.missingReference("An original overlap body is missing.") }
        var result: Set<FaceID> = []
        for shellID in body.shellIDs {
            try admission.step()
            guard let shell = model.shells[shellID] else { throw TopologyError.missingReference("An original overlap shell is missing.") }
            for faceID in shell.faceIDs {
                try admission.reserve(count: 1, stride: MemoryLayout<FaceID>.stride)
                result.insert(faceID)
            }
        }
        return result
    }
}

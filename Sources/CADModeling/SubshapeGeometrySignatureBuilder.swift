import HashTreeCollections
import CADCore
import CADIR
import CADGeometry
import CADTopology

package struct SubshapeGeometrySignatureBuilder {
    package let model: BRepModel
    package let tolerance: ModelingTolerance

    package init(model: BRepModel, tolerance: ModelingTolerance) {
        self.model = model
        self.tolerance = tolerance
    }

    package func signature(
        for reference: TopologyReference
    ) throws -> SubshapeGeometrySignature {
        try tolerance.validate()
        switch reference {
        case let .body(bodyID):
            return .body(try bodySignature(bodyID))
        case let .vertex(vertexID):
            guard let vertex = model.vertices[vertexID] else {
                throw missingTopology("vertex")
            }
            return .vertex(point: vertex.point)
        case let .edge(edgeID):
            return .edge(try edgeSignature(edgeID))
        case let .face(faceID):
            return .face(try faceSignature(faceID))
        }
    }

    package func matches(
        _ lhs: SubshapeGeometrySignature,
        _ rhs: SubshapeGeometrySignature
    ) -> Bool {
        switch (lhs, rhs) {
        case let (.body(first), .body(second)):
            return first == second
        case let (.face(first), .face(second)):
            return first == second
        case let (.vertex(first), .vertex(second)):
            return first.isApproximatelyEqual(to: second, tolerance: tolerance.distance)
        case let (.edge(first), .edge(second)):
            return first == second
        default:
            return false
        }
    }

    private func bodySignature(_ bodyID: BodyID) throws -> BodyGeometrySignature {
        guard let body = model.bodies[bodyID] else {
            throw missingTopology("body")
        }
        let shells = try body.shellIDs.map { shellID -> ShellGeometrySignature in
            guard let shell = model.shells[shellID] else {
                throw missingTopology("shell")
            }
            return ShellGeometrySignature(
                orientation: shell.orientation,
                faces: try shell.faceIDs.map(faceSignature)
            )
        }
        return BodyGeometrySignature(kind: body.kind, shells: shells)
    }

    private func faceSignature(_ faceID: FaceID) throws -> FaceGeometrySignature {
        guard let face = model.faces[faceID],
              let surface = model.geometry.surfaces[face.surfaceID] else {
            throw missingTopology("face")
        }
        let loops = try face.loops.map { loopID -> LoopGeometrySignature in
            guard let loop = model.loops[loopID] else {
                throw missingTopology("loop")
            }
            return LoopGeometrySignature(
                role: loop.role,
                coedges: try loop.coedges.map { coedge in
                    guard let parameterCurve = coedge.surfaceParameterCurve else {
                        throw KernelError(
                            phase: .topology,
                            code: .topologyFailure,
                            tolerance: tolerance,
                            message: "Stable face geometry requires every coedge to carry a pcurve."
                        )
                    }
                    return CoedgeGeometrySignature(
                        edge: try edgeSignature(coedge.edgeID),
                        orientation: coedge.orientation,
                        surfaceParameterCurve: parameterCurve
                    )
                }
            )
        }
        return FaceGeometrySignature(
            surface: surface,
            orientation: face.orientation,
            loops: loops
        )
    }

    private func edgeSignature(_ edgeID: EdgeID) throws -> CurveSpanGeometrySignature {
        guard let edge = model.edges[edgeID],
              let curve = model.geometry.curves[edge.curveID],
              let start = model.vertices[edge.startVertexID]?.point,
              let end = model.vertices[edge.endVertexID]?.point else {
            throw missingTopology("edge")
        }
        return CurveSpanGeometrySignature(
            curve: curve,
            startParameter: edge.trim?.startParameter,
            endParameter: edge.trim?.endParameter,
            startPoint: start,
            endPoint: end
        )
    }

    private func missingTopology(_ kind: String) -> KernelError {
        KernelError(
            phase: .evaluation,
            code: .missingReference,
            tolerance: tolerance,
            message: "Stable selection geometry signature references a missing \(kind)."
        )
    }
}


extension SubshapeGeometrySignatureBuilder {
    package func validateOriginal(_ signature: SubshapeGeometrySignature,
        maximumSubdivisionDepth: Int, remainingSourceDepth: Int,
        consumeWork: @escaping @Sendable (Int) throws -> Void,
        consumeStorage: (@Sendable (Int) throws -> Void)?,
        maximumAlgebraicDepth: Int?) throws {
        try consumeWork(0); try CurrentTaskCancellationChecker().checkCancellation()
        let structuralTolerance = GeometrySignatureValidation.tolerance
        func edge(_ value: CurveSpanGeometrySignature) throws {
            try consumeWork(0)
            try value.curve.validate(tolerance: structuralTolerance,
                remainingSourceDepth: remainingSourceDepth, maximumSubdivisionDepth: maximumSubdivisionDepth,
                consumeWork: consumeWork, consumeStorage: consumeStorage,
                maximumAlgebraicDepth: maximumAlgebraicDepth)
            try value.startPoint.validate(); try value.endPoint.validate()
            guard value.startPoint != value.endPoint,
                (value.startParameter == nil) == (value.endParameter == nil) else {
                throw missingTopology("valid original curve-span signature")
            }
            if let first = value.startParameter, let last = value.endParameter {
                guard first.isFinite, last.isFinite, first != last else {
                    throw missingTopology("finite original curve-span trim")
                }
            }
        }
        func face(_ value: FaceGeometrySignature) throws {
            try consumeWork(0)
            try value.surface.validate(tolerance: structuralTolerance,
                remainingSourceDepth: remainingSourceDepth, maximumSubdivisionDepth: maximumSubdivisionDepth,
                consumeWork: consumeWork, consumeStorage: consumeStorage,
                maximumAlgebraicDepth: maximumAlgebraicDepth)
            for loop in value.loops {
                try consumeWork(0)
                guard !loop.coedges.isEmpty else { throw missingTopology("nonempty signature loop") }
                for coedge in loop.coedges {
                    try consumeWork(0); try CurrentTaskCancellationChecker().checkCancellation()
                    try edge(coedge.edge)
                    try coedge.surfaceParameterCurve.validate(on: value.surface,
                        tolerance: structuralTolerance, remainingSourceDepth: remainingSourceDepth,
                        maximumSubdivisionDepth: maximumSubdivisionDepth,
                        consumeWork: consumeWork, consumeStorage: consumeStorage,
                        maximumAlgebraicDepth: maximumAlgebraicDepth)
                }
            }
        }
        switch signature {
        case .vertex(let point): try point.validate()
        case .edge(let value): try edge(value)
        case .face(let value): try face(value)
        case .body(let value):
            guard !value.shells.isEmpty else { throw missingTopology("nonempty signature body") }
            for shell in value.shells {
                try consumeWork(0)
                guard !shell.faces.isEmpty else { throw missingTopology("nonempty signature shell") }
                for value in shell.faces { try face(value) }
            }
        }
    }

    package func signature(for reference: TopologyReference,
        consumeWork: @escaping @Sendable (Int) throws -> Void,
        consumeStorage: (@Sendable (Int) throws -> Void)?) throws -> SubshapeGeometrySignature {
        try consumeWork(0); try CurrentTaskCancellationChecker().checkCancellation()
        func reserve<T>(_ type: T.Type, count: Int) throws {
            let (bytes, overflow) = count.multipliedReportingOverflow(by: MemoryLayout<T>.stride)
            guard !overflow else { throw GeometryConversionError.resourceLimitExceeded("Signature storage overflow.") }
            try consumeStorage?(bytes)
        }
        func edge(_ id: EdgeID) throws -> CurveSpanGeometrySignature {
            try consumeWork(0); try CurrentTaskCancellationChecker().checkCancellation()
            return try edgeSignature(id)
        }
        func face(_ id: FaceID) throws -> FaceGeometrySignature {
            try consumeWork(0); try CurrentTaskCancellationChecker().checkCancellation()
            guard let face = model.faces[id], let surface = model.geometry.surfaces[face.surfaceID] else {
                throw missingTopology("face")
            }
            try reserve(LoopGeometrySignature.self, count: face.loops.count)
            var loops: [LoopGeometrySignature] = []; loops.reserveCapacity(face.loops.count)
            for id in face.loops {
                try consumeWork(0)
                guard let loop = model.loops[id] else { throw missingTopology("loop") }
                try reserve(CoedgeGeometrySignature.self, count: loop.coedges.count)
                var coedges: [CoedgeGeometrySignature] = []; coedges.reserveCapacity(loop.coedges.count)
                for coedge in loop.coedges {
                    try consumeWork(0); try CurrentTaskCancellationChecker().checkCancellation()
                    guard let pcurve = coedge.surfaceParameterCurve else {
                        throw KernelError(phase: .topology, code: .topologyFailure, tolerance: tolerance,
                            message: "Stable face geometry requires original coedge pcurves.")
                    }
                    coedges.append(CoedgeGeometrySignature(edge: try edge(coedge.edgeID),
                        orientation: coedge.orientation, surfaceParameterCurve: pcurve))
                }
                loops.append(LoopGeometrySignature(role: loop.role, coedges: coedges))
            }
            return FaceGeometrySignature(surface: surface, orientation: face.orientation, loops: loops)
        }
        switch reference {
        case .vertex(let id):
            guard let vertex = model.vertices[id] else { throw missingTopology("vertex") }
            return .vertex(point: vertex.point)
        case .edge(let id): return .edge(try edge(id))
        case .face(let id): return .face(try face(id))
        case .body(let id):
            guard let body = model.bodies[id] else { throw missingTopology("body") }
            try reserve(ShellGeometrySignature.self, count: body.shellIDs.count)
            var shells: [ShellGeometrySignature] = []; shells.reserveCapacity(body.shellIDs.count)
            for id in body.shellIDs {
                try consumeWork(0)
                guard let shell = model.shells[id] else { throw missingTopology("shell") }
                try reserve(FaceGeometrySignature.self, count: shell.faceIDs.count)
                var faces: [FaceGeometrySignature] = []; faces.reserveCapacity(shell.faceIDs.count)
                for id in shell.faceIDs { faces.append(try face(id)) }
                shells.append(ShellGeometrySignature(orientation: shell.orientation, faces: faces))
            }
            return .body(BodyGeometrySignature(kind: body.kind, shells: shells))
        }
    }

    package static func chargeStoredSignature(_ value: SubshapeGeometrySignature,
        consumeWork: @escaping @Sendable (Int) throws -> Void) throws {
        func visit(_ units: Int) throws {
            guard units >= 0 else { throw GeometryConversionError.invalidInput("Negative signature comparison work.") }
            for _ in 0..<units { try consumeWork(0); try CurrentTaskCancellationChecker().checkCancellation() }
        }
        func edge(_ value: CurveSpanGeometrySignature) throws {
            try visit(5); try GeometryStructuralComparisonWork.charge(curve: value.curve, using: visit)
        }
        func face(_ value: FaceGeometrySignature) throws {
            try visit(3); try GeometryStructuralComparisonWork.charge(surface: value.surface, using: visit)
            for loop in value.loops {
                try visit(2)
                for coedge in loop.coedges {
                    try visit(3); try edge(coedge.edge)
                    try GeometryStructuralComparisonWork.charge(parameterCurve: coedge.surfaceParameterCurve, using: visit)
                }
            }
        }
        func signature(_ value: SubshapeGeometrySignature) throws {
            try visit(1)
            switch value {
            case .vertex: try visit(3)
            case .edge(let value): try edge(value)
            case .face(let value): try face(value)
            case .body(let value):
                try visit(2)
                for shell in value.shells {
                    try visit(2)
                    for value in shell.faces { try face(value) }
                }
            }
        }
        try signature(value)
    }

    package func matches(_ left: SubshapeGeometrySignature, _ right: SubshapeGeometrySignature,
        consumeWork: @escaping @Sendable (Int) throws -> Void) throws -> Bool {
        try Self.chargeStoredSignature(left, consumeWork: consumeWork)
        try Self.chargeStoredSignature(right, consumeWork: consumeWork)
        return matches(left, right)
    }

}

import Foundation
import CADCore
import CADGeometry
import CADIR
import CADTopology

struct ExactIGESReader {
    let text: String
    let lengthUnit: LengthUnit
    let processingBudget: ExchangeProcessingBudget
    let tolerance: ModelingTolerance

    func read() throws -> BRepModel {
        try processingBudget.check(format: .iges)
        let entities = try EntityParser(text: text, processingBudget: processingBudget).parse()
        var builder = Builder(
            entities: entities,
            lengthUnit: lengthUnit,
            processingBudget: processingBudget,
            tolerance: tolerance
        )
        let model = try builder.build()
        try processingBudget.check(format: .iges)
        try model.validate(level: .exact, tolerance: tolerance)
        return model
    }
}

private extension ExactIGESReader {
    struct Entity: Sendable {
        let pointer: Int
        let type: Int
        let form: Int
        let transformationPointer: Int
        let label: String
        let parameters: [String]
    }

    struct EntityParser {
        let text: String
        let processingBudget: ExchangeProcessingBudget

        func parse() throws -> [Int: Entity] {
            let lines = normalizedLines()
            let directoryLines = lines.filter { Array($0)[72] == "D" }
            let parameterLines = lines.filter { Array($0)[72] == "P" }
            guard directoryLines.count.isMultiple(of: 2) else {
                throw invalid("IGES directory records are not paired.")
            }
            var parametersBySequence: [Int: String] = [:]
            var directoryPointerBySequence: [Int: Int] = [:]
            for line in parameterLines {
                try processingBudget.check(format: .iges)
                let characters = Array(line)
                let sequence = try integer(String(characters[73..<80]), label: "parameter sequence")
                parametersBySequence[sequence] = String(characters[0..<64])
                directoryPointerBySequence[sequence] = try integer(
                    String(characters[64..<72]),
                    label: "parameter directory pointer"
                )
            }
            var result: [Int: Entity] = [:]
            for index in stride(from: 0, to: directoryLines.count, by: 2) {
                try processingBudget.check(format: .iges)
                let first = Array(directoryLines[index])
                let second = Array(directoryLines[index + 1])
                let pointer = try integer(String(first[73..<80]), label: "directory pointer")
                let type = try integerField(first, index: 0)
                let parameterStart = try integerField(first, index: 1)
                let secondType = try integerField(second, index: 0)
                let transformationPointer = try integerField(first, index: 6)
                let parameterCount = try integerField(second, index: 3)
                let form = try integerField(second, index: 4)
                let label = String(second[56..<64]).trimmingCharacters(in: .whitespaces)
                guard pointer == index + 1, pointer % 2 == 1, type == secondType,
                      parameterStart > 0, parameterCount > 0 else {
                    throw invalid("IGES directory entry #\(pointer) is malformed.")
                }
                var parameterText = ""
                for sequence in parameterStart..<(parameterStart + parameterCount) {
                    try processingBudget.check(format: .iges)
                    guard let content = parametersBySequence[sequence],
                          directoryPointerBySequence[sequence] == pointer else {
                        throw missing("IGES parameter record #\(sequence)")
                    }
                    parameterText += content
                }
                let parameters = try parseParameters(parameterText)
                guard let parameterType = parameters.first.flatMap(Int.init), parameterType == type else {
                    throw invalid("IGES directory and parameter entity types disagree at #\(pointer).")
                }
                guard result[pointer] == nil else {
                    throw invalid("IGES directory pointer #\(pointer) is duplicated.")
                }
                result[pointer] = Entity(
                    pointer: pointer,
                    type: type,
                    form: form,
                    transformationPointer: transformationPointer,
                    label: label,
                    parameters: parameters
                )
            }
            return result
        }

        private func normalizedLines() -> [String] {
            text.split(separator: "\n", omittingEmptySubsequences: true).map { raw in
                raw.last == "\r" ? String(raw.dropLast()) : String(raw)
            }
        }

        private func integerField(_ characters: [Character], index: Int) throws -> Int {
            let start = index * 8
            return try integer(String(characters[start..<(start + 8)]), label: "directory field")
        }

        private func integer(_ text: String, label: String) throws -> Int {
            guard let value = Int(text.trimmingCharacters(in: .whitespacesAndNewlines)) else {
                throw invalid("IGES \(label) is not an integer.")
            }
            return value
        }

        private func parseParameters(_ text: String) throws -> [String] {
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let terminator = trimmed.firstIndex(of: ";"),
                  trimmed[trimmed.index(after: terminator)...].trimmingCharacters(in: .whitespaces).isEmpty else {
                throw invalid("IGES parameter data is not terminated exactly once.")
            }
            let content = trimmed[..<terminator]
            let values = content.split(separator: ",", omittingEmptySubsequences: false).map {
                $0.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            guard !values.isEmpty, values.allSatisfy({ !$0.isEmpty }) else {
                throw invalid("IGES parameter data contains an empty value.")
            }
            return values
        }

        private func invalid(_ message: String) -> ImportError { .invalidData(message) }
        private func missing(_ message: String) -> ImportError { .missingRequiredEntity(message) }
    }

    struct Builder {
        struct IndexedPointer: Hashable {
            let pointer: Int
            let index: Int
        }

        struct CurveSurfaceParameterAssociation: Hashable {
            let surfacePointer: Int
            let parameterCurvePointer: Int
        }

        let entities: [Int: Entity]
        let lengthUnit: LengthUnit
        let processingBudget: ExchangeProcessingBudget
        let tolerance: ModelingTolerance

        var geometry = GeometryStore()
        var bodies: [BodyID: Body] = [:]
        var shells: [ShellID: Shell] = [:]
        var faces: [FaceID: Face] = [:]
        var loops: [LoopID: Loop] = [:]
        var edges: [EdgeID: Edge] = [:]
        var vertices: [VertexID: Vertex] = [:]

        var surfaceCache: [Int: SurfaceID] = [:]
        var curveCache: [Int: CurveID] = [:]
        var curveTrimCache: [Int: CurveTrim] = [:]
        var exactTransferTrims: [CurveID: CurveTrim] = [:]
        var circularArcEndpoints: [Int: (start: Point3D, end: Point3D)] = [:]
        var curveSurfaceAssociations: [Int: [Int]] = [:]
        var curveSurfaceParameterAssociations: [Int: [CurveSurfaceParameterAssociation]] = [:]
        var intersectionPcurves: [CurveID: [Surface3D: SurfaceParameterCurve]] = [:]
        var edgeModelSameSense: [EdgeID: Bool] = [:]
        var vertexCache: [IndexedPointer: VertexID] = [:]
        var edgeCache: [IndexedPointer: EdgeID] = [:]
        var shellOwners: Set<Int> = []
        var faceOwners: Set<Int> = []
        var loopOwners: Set<Int> = []

        func curveTrim(_ pointer: Int) -> CurveTrim? {
            curveTrimCache[pointer]
        }

        mutating func build() throws -> BRepModel {
            var solidShellPointers = Set<Int>()
            for pointer in entities.keys.sorted() {
                try processingBudget.check(format: .iges)
                guard let entity = entities[pointer], entity.type == 186 else { continue }
                let values = entity.parameters
                guard values.count >= 4 else {
                    throw invalid("IGES solid #\(pointer) is malformed.")
                }
                let shellPointer = try integerAt(values, 1, label: "solid shell pointer")
                let outerOrientation = try orientation(values[2])
                let voidCount = try integerAt(values, 3, label: "solid void count")
                guard voidCount >= 0, values.count == 4 + voidCount * 2 else {
                    throw invalid("IGES solid #\(pointer) has an inconsistent void shell list.")
                }
                guard solidShellPointers.insert(shellPointer).inserted else {
                    throw unsupported("IGES shell #\(shellPointer) is shared by multiple solids.")
                }
                var shellIDs = [try buildShell(shellPointer, orientation: outerOrientation)]
                for index in 0..<voidCount {
                    try processingBudget.check(format: .iges)
                    let voidPointer = try integerAt(
                        values,
                        4 + index * 2,
                        label: "solid void shell pointer"
                    )
                    let voidOrientation = try orientation(values[5 + index * 2])
                    guard solidShellPointers.insert(voidPointer).inserted else {
                        throw unsupported("IGES shell #\(voidPointer) is shared by multiple solids.")
                    }
                    shellIDs.append(try buildShell(voidPointer, orientation: voidOrientation))
                }
                let bodyID: BodyID = taggedID(namespace: 0x494745535F424F44, pointer: pointer)
                bodies[bodyID] = Body(id: bodyID, shellIDs: shellIDs, kind: .solid)
            }
            var groupedSheetShellPointers = Set<Int>()
            for pointer in entities.keys.sorted() {
                try processingBudget.check(format: .iges)
                guard let entity = entities[pointer], entity.type == 402 else { continue }
                guard entity.form == 7 else {
                    throw unsupported(
                        "IGES associativity #\(pointer) must be a form 7 group without back pointers."
                    )
                }
                let values = entity.parameters
                let shellCount = try integerAt(values, 1, label: "sheet body shell count")
                guard shellCount > 0,
                      shellCount <= entities.count,
                      values.count == shellCount + 2 else {
                    throw invalid("IGES sheet body group #\(pointer) is malformed.")
                }
                var shellPointers: [Int] = []
                shellPointers.reserveCapacity(shellCount)
                for index in 0..<shellCount {
                    try processingBudget.check(format: .iges)
                    let shellPointer = try integerAt(
                        values,
                        index + 2,
                        label: "sheet body shell pointer"
                    )
                    _ = try required(shellPointer, type: 514, label: "sheet body shell")
                    guard !solidShellPointers.contains(shellPointer) else {
                        throw unsupported(
                            "IGES shell #\(shellPointer) cannot belong to both a solid and a sheet body group."
                        )
                    }
                    guard groupedSheetShellPointers.insert(shellPointer).inserted else {
                        throw unsupported(
                            "IGES shell #\(shellPointer) is referenced by more than one sheet body group."
                        )
                    }
                    shellPointers.append(shellPointer)
                }
                let shellIDs = try shellPointers.sorted().map {
                    try buildShell($0, orientation: .forward)
                }
                let bodyID: BodyID = taggedID(namespace: 0x494745535F424F44, pointer: pointer)
                bodies[bodyID] = Body(id: bodyID, shellIDs: shellIDs, kind: .sheet)
            }
            for pointer in entities.keys.sorted() {
                try processingBudget.check(format: .iges)
                guard let entity = entities[pointer], entity.type == 514,
                      !solidShellPointers.contains(pointer),
                      !groupedSheetShellPointers.contains(pointer) else { continue }
                let shellID = try buildShell(pointer, orientation: .forward)
                let bodyID: BodyID = taggedID(namespace: 0x494745535F424F44, pointer: pointer)
                bodies[bodyID] = Body(id: bodyID, shellIDs: [shellID], kind: .sheet)
            }
            guard !bodies.isEmpty else {
                throw unsupported("IGES input does not contain manifold B-rep shell topology.")
            }
            return BRepModel(
                geometry: try topologyOwnedGeometry(),
                bodies: bodies,
                shells: shells,
                faces: faces,
                loops: loops,
                edges: edges,
                vertices: vertices
            )
        }

        func topologyOwnedGeometry() throws -> GeometryStore {
            var result = GeometryStore()
            for curveID in Set(edges.values.map(\.curveID)) {
                guard let curve = geometry.curves[curveID] else {
                    throw missing("IGES topology-owned curve \(curveID)")
                }
                result.curves[curveID] = curve
            }
            for surfaceID in Set(faces.values.map(\.surfaceID)) {
                guard let surface = geometry.surfaces[surfaceID] else {
                    throw missing("IGES topology-owned surface \(surfaceID)")
                }
                result.surfaces[surfaceID] = surface
            }
            return result
        }

        mutating func buildShell(_ pointer: Int, orientation shellOrientation: Orientation) throws -> ShellID {
            guard shellOwners.insert(pointer).inserted else {
                throw unsupported("IGES shell #\(pointer) is referenced more than once.")
            }
            let entity = try required(pointer, type: 514, label: "shell")
            let values = entity.parameters
            let count = try integerAt(values, 1, label: "shell face count")
            guard count > 0, values.count == 2 + count * 2 else {
                throw invalid("IGES shell #\(pointer) is malformed.")
            }
            var faceIDs: [FaceID] = []
            for index in 0..<count {
                try processingBudget.check(format: .iges)
                let facePointer = try integerAt(values, 2 + index * 2, label: "shell face pointer")
                let faceOrientation = try orientation(values[3 + index * 2])
                faceIDs.append(try buildFace(facePointer, orientation: faceOrientation))
            }
            let shellID: ShellID = taggedID(namespace: 0x494745535F53484C, pointer: pointer)
            shells[shellID] = Shell(id: shellID, faceIDs: faceIDs, orientation: shellOrientation)
            return shellID
        }

        mutating func buildFace(_ pointer: Int, orientation faceOrientation: Orientation) throws -> FaceID {
            guard faceOwners.insert(pointer).inserted else {
                throw unsupported("IGES face #\(pointer) is referenced more than once.")
            }
            let entity = try required(pointer, type: 510, label: "face")
            let values = entity.parameters
            let surfacePointer = try integerAt(values, 1, label: "face surface pointer")
            let loopCount = try integerAt(values, 2, label: "face loop count")
            let hasOuterLoop = try booleanAt(values, 3, label: "face outer loop flag")
            guard loopCount > 0, hasOuterLoop, values.count == 4 + loopCount else {
                throw invalid("IGES face #\(pointer) is malformed or has no outer loop.")
            }
            let surfaceID = try buildSurface(surfacePointer)
            guard let surface = geometry.surfaces[surfaceID] else {
                throw missing("IGES face surface #\(surfacePointer)")
            }
            var loopIDs: [LoopID] = []
            for index in 0..<loopCount {
                try processingBudget.check(format: .iges)
                let loopPointer = try integerAt(values, 4 + index, label: "face loop pointer")
                loopIDs.append(try buildLoop(
                    loopPointer,
                    role: index == 0 ? .outer : .inner,
                    surface: surface
                ))
            }
            let faceID: FaceID = taggedID(namespace: 0x494745535F464143, pointer: pointer)
            faces[faceID] = Face(
                id: faceID,
                surfaceID: surfaceID,
                loops: loopIDs,
                orientation: faceOrientation
            )
            return faceID
        }

        mutating func buildLoop(_ pointer: Int, role: LoopRole, surface: Surface3D) throws -> LoopID {
            guard loopOwners.insert(pointer).inserted else {
                throw unsupported("IGES loop #\(pointer) is referenced more than once.")
            }
            let entity = try required(pointer, type: 508, label: "loop")
            let values = entity.parameters
            let edgeCount = try integerAt(values, 1, label: "loop edge count")
            guard edgeCount > 0 else {
                throw invalid("IGES loop #\(pointer) has no edges.")
            }
            var cursor = 2
            var coedges: [Coedge] = []
            for _ in 0..<edgeCount {
                try processingBudget.check(format: .iges)
                guard cursor + 4 < values.count else {
                    throw invalid("IGES loop #\(pointer) is truncated.")
                }
                guard try integerAt(values, cursor, label: "loop edge type") == 0 else {
                    throw unsupported("IGES vertex-only loops are not supported.")
                }
                let edgeListPointer = try integerAt(values, cursor + 1, label: "loop edge list pointer")
                let edgeIndex = try integerAt(values, cursor + 2, label: "loop edge index")
                let agreesWithModelCurve = try booleanAt(values, cursor + 3, label: "loop orientation")
                let pcurveCount = try integerAt(values, cursor + 4, label: "loop p-curve count")
                cursor += 5
                guard pcurveCount == 0 || pcurveCount == 1 else {
                    throw unsupported("IGES exact coedges support zero or one parameter-space curve.")
                }
                let pcurvePointer: Int?
                if pcurveCount == 1 {
                    guard cursor + 1 < values.count else {
                        throw invalid("IGES loop #\(pointer) is missing its parameter-space curve.")
                    }
                    _ = try booleanAt(values, cursor, label: "loop isoparametric flag")
                    pcurvePointer = try integerAt(
                        values,
                        cursor + 1,
                        label: "loop p-curve pointer"
                    )
                    cursor += 2
                } else {
                    pcurvePointer = nil
                }

                let edgeKey = IndexedPointer(pointer: edgeListPointer, index: edgeIndex)
                let edgeID = try buildEdge(edgeKey)
                guard let edge = edges[edgeID],
                      let startVertex = vertices[edge.startVertexID],
                      let endVertex = vertices[edge.endVertexID] else {
                    throw missing("IGES loop edge geometry")
                }
                guard let sameSense = edgeModelSameSense[edgeID] else {
                    throw missing("IGES edge model-curve orientation")
                }
                let coedgeOrientation: Orientation = agreesWithModelCurve == sameSense ? .forward : .reversed
                let modelStart = sameSense ? startVertex.point : endVertex.point
                let modelEnd = sameSense ? endVertex.point : startVertex.point
                let modelParameterCurve: SurfaceParameterCurve
                if let pcurvePointer {
                    modelParameterCurve = try parameterCurve(
                        pcurvePointer,
                        modelStart: modelStart,
                        modelEnd: modelEnd,
                        surface: surface
                    )
                } else {
                    guard let modelCurve = geometry.curves[edge.curveID] else {
                        throw missing("IGES model-curve-only coedge geometry")
                    }
                    if case let .surfaceLift(lift) = modelCurve {
                        guard lift.surface == surface else {
                            throw invalid(
                                "IGES surface-lift coedge surface differs from its exact source surface."
                            )
                        }
                        modelParameterCurve = lift.parameterCurve
                    } else if case let .analytic(.planeTorus(planeTorus)) = modelCurve {
                        let role: SurfaceIntersectionSurfaceRole
                        if surface == planeTorus.planeSurface {
                            role = .first
                        } else if surface == planeTorus.torusSurface {
                            role = .second
                        } else {
                            throw invalid(
                                "IGES plane-torus coedge surface is not one of its exact source surfaces."
                            )
                        }
                        let exactIntersection = try CertifiedAnalyticAnalyticIntersectionCurve(
                            planeTorusCurve: planeTorus,
                            firstSurface: planeTorus.planeSurface,
                            secondSurface: planeTorus.torusSurface,
                            tolerance: tolerance
                        )
                        let period = 2.0 * Double.pi
                        guard let exactTransferTrim = exactTransferTrims[edge.curveID] else {
                            throw missing("IGES plane-torus exact transfer trim")
                        }
                        let startParameter = exactTransferTrim.startParameter
                        let endParameter = exactTransferTrim.endParameter
                        guard endParameter - startParameter <= period + tolerance.angle else {
                            throw invalid("IGES plane-torus coedge trim exceeds one period.")
                        }
                        modelParameterCurve = .certifiedAnalyticPair(
                            try CertifiedAnalyticPairSurfaceParameterCurve(
                                intersection: exactIntersection,
                                role: role,
                                startFraction: startParameter / period,
                                endFraction: endParameter / period,
                                tolerance: tolerance
                            )
                        )
                    } else if let sourceParameterCurve = intersectionPcurves[edge.curveID]?[surface] {
                        guard let exactTransferTrim = exactTransferTrims[edge.curveID] else {
                            throw missing("IGES implicit-intersection exact transfer trim")
                        }
                        let startParameter = exactTransferTrim.startParameter
                        let endParameter = exactTransferTrim.endParameter
                        let increasingParameterCurve = try sourceParameterCurve.trimmed(
                            from: min(startParameter, endParameter),
                            to: max(startParameter, endParameter),
                            curveDomain: modelCurve.parameterDomain,
                            tolerance: tolerance
                        )
                        modelParameterCurve = endParameter > startParameter
                            ? increasingParameterCurve
                            : try increasingParameterCurve.reversed(tolerance: tolerance)
                    } else {
                        modelParameterCurve = try ExactAssociatedSurfacePcurveBuilder().build(
                            curve: modelCurve,
                            modelStart: modelStart,
                            modelEnd: modelEnd,
                            surface: surface,
                            tolerance: tolerance
                        )
                    }
                }
                let edgeParameterCurve = sameSense
                    ? modelParameterCurve
                    : try modelParameterCurve.reversed(tolerance: tolerance)
                let orientedParameterCurve = coedgeOrientation == .forward
                    ? edgeParameterCurve
                    : try edgeParameterCurve.reversed(tolerance: tolerance)
                coedges.append(Coedge(
                    edgeID: edgeID,
                    orientation: coedgeOrientation,
                    surfaceParameterCurve: orientedParameterCurve
                ))
            }
            guard cursor == values.count else {
                throw invalid("IGES loop #\(pointer) contains trailing parameters.")
            }
            let loopID: LoopID = taggedID(namespace: 0x494745535F4C4F50, pointer: pointer)
            loops[loopID] = Loop(id: loopID, role: role, coedges: coedges)
            return loopID
        }

        mutating func buildEdge(_ key: IndexedPointer) throws -> EdgeID {
            if let cached = edgeCache[key] { return cached }
            let entity = try required(key.pointer, type: 504, label: "edge list")
            let values = entity.parameters
            let count = try integerAt(values, 1, label: "edge list count")
            guard key.index > 0, key.index <= count, values.count == 2 + count * 5 else {
                throw invalid("IGES edge list #\(key.pointer) is malformed.")
            }
            let start = 2 + (key.index - 1) * 5
            let curvePointer = try integerAt(values, start, label: "edge curve pointer")
            let startVertexKey = IndexedPointer(
                pointer: try integerAt(values, start + 1, label: "start vertex list pointer"),
                index: try integerAt(values, start + 2, label: "start vertex index")
            )
            let endVertexKey = IndexedPointer(
                pointer: try integerAt(values, start + 3, label: "end vertex list pointer"),
                index: try integerAt(values, start + 4, label: "end vertex index")
            )
            let startVertexID = try buildVertex(startVertexKey)
            let endVertexID = try buildVertex(endVertexKey)
            let curve = try buildCurve(curvePointer)
            let edgeID: EdgeID = indexedID(namespace: 0x494745535F454447, key: key)
            var reconstructedSurfaceLiftSense: Bool?
            if let reconstructed = try associatedPlaneTorusCurve(
                curvePointer: curvePointer,
                startPoint: vertices[startVertexID]?.point,
                endPoint: vertices[endVertexID]?.point
            ) {
                guard let transferCurve = geometry.curves[curve.id],
                      case .bSpline = transferCurve,
                      let transferTrim = curve.trim else {
                    throw invalid("IGES plane-torus intersection has incomplete transfer geometry.")
                }
                let exactCurve = Curve3D.analytic(.planeTorus(reconstructed))
                exactTransferTrims[curve.id] = try ExactTransferTrimResolver(
                    tolerance: tolerance
                ).resolve(
                    transferCurve: transferCurve,
                    transferTrim: transferTrim,
                    exactCurve: exactCurve,
                    convention: "IGES"
                )
                geometry.curves[curve.id] = exactCurve
            } else if let reconstructed = try associatedImplicitIntersection(
                curvePointer: curvePointer,
                startPoint: vertices[startVertexID]?.point,
                endPoint: vertices[endVertexID]?.point
            ) {
                guard let transferCurve = geometry.curves[curve.id],
                      case .bSpline = transferCurve,
                      let transferTrim = curve.trim else {
                    throw invalid("IGES implicit intersection has incomplete transfer geometry.")
                }
                exactTransferTrims[curve.id] = try ExactTransferTrimResolver(
                    tolerance: tolerance
                ).resolve(
                    transferCurve: transferCurve,
                    transferTrim: transferTrim,
                    exactCurve: reconstructed.curve,
                    convention: "IGES"
                )
                geometry.curves[curve.id] = reconstructed.curve
                intersectionPcurves[curve.id] = [
                    reconstructed.firstSurface: reconstructed.firstSurfaceParameterCurve,
                    reconstructed.secondSurface: reconstructed.secondSurfaceParameterCurve,
                ]
            } else if let reconstructed = try associatedSurfaceLift(
                curvePointer: curvePointer,
                curveID: curve.id,
                derivedTrim: curve.trim,
                startPoint: vertices[startVertexID]?.point,
                endPoint: vertices[endVertexID]?.point
            ) {
                geometry.curves[curve.id] = .surfaceLift(reconstructed.lift)
                reconstructedSurfaceLiftSense = reconstructed.sameSense
            }
            guard let curveGeometry = geometry.curves[curve.id],
                  let startVertex = vertices[startVertexID],
                  let endVertex = vertices[endVertexID] else {
                throw missing("IGES edge geometry")
            }
            let trim: CurveTrim?
            let sameSense: Bool
            switch curveGeometry {
            case let .line(line):
                trim = nil
                sameSense = (endVertex.point - startVertex.point).dot(line.direction) > 0.0
            case .bSpline:
                guard let declaredTrim = curve.trim else {
                    throw invalid("IGES B-spline edge has no explicit parameter interval.")
                }
                try declaredTrim.validate(
                    on: curveGeometry,
                    edgeID: edgeID,
                    tolerance: tolerance
                )
                let expectedStart = try curveGeometry.point(
                    at: declaredTrim.startParameter,
                    tolerance: tolerance
                )
                let expectedEnd = try curveGeometry.point(
                    at: declaredTrim.endParameter,
                    tolerance: tolerance
                )
                guard startVertex.point.isApproximatelyEqual(
                    to: expectedStart,
                    tolerance: tolerance.distance
                ), endVertex.point.isApproximatelyEqual(
                    to: expectedEnd,
                    tolerance: tolerance.distance
                ) else {
                    throw invalid("IGES B-spline edge vertices disagree with its parameter interval.")
                }
                trim = declaredTrim
                sameSense = true
            case .circle:
                guard let arcEndpoints = circularArcEndpoints[curvePointer] else {
                    throw invalid("IGES circular edge has no defining arc endpoints.")
                }
                let result = try periodicConicEdgeTrim(
                    curve: curveGeometry,
                    startPoint: startVertex.point,
                    endPoint: endVertex.point,
                    arcStart: arcEndpoints.start,
                    arcEnd: arcEndpoints.end,
                    label: "IGES circular edge"
                )
                trim = result.trim
                sameSense = result.sameSense
            case let .analytic(analytic):
                switch analytic {
                case let .line(_, direction):
                    trim = curve.trim
                    sameSense = (endVertex.point - startVertex.point).dot(direction) > 0.0
                case .circle, .arc, .ellipse:
                    guard let conicEndpoints = circularArcEndpoints[curvePointer] else {
                        throw invalid("IGES analytic conic has no defining arc endpoints.")
                    }
                    let result = try periodicConicEdgeTrim(
                        curve: curveGeometry,
                        startPoint: startVertex.point,
                        endPoint: endVertex.point,
                        arcStart: conicEndpoints.start,
                        arcEnd: conicEndpoints.end,
                        label: "IGES analytic conic"
                    )
                    trim = result.trim
                    sameSense = result.sameSense
                case .hyperbola, .parabola:
                    guard let declaredTrim = curve.trim else {
                        throw invalid("IGES analytic open conic has no finite parameter interval.")
                    }
                    let declaredStart = try curveGeometry.point(
                        at: declaredTrim.startParameter,
                        tolerance: tolerance
                    )
                    let declaredEnd = try curveGeometry.point(
                        at: declaredTrim.endParameter,
                        tolerance: tolerance
                    )
                    if startVertex.point.isApproximatelyEqual(
                        to: declaredStart,
                        tolerance: tolerance.distance
                    ), endVertex.point.isApproximatelyEqual(
                        to: declaredEnd,
                        tolerance: tolerance.distance
                    ) {
                        trim = declaredTrim
                        sameSense = true
                    } else if startVertex.point.isApproximatelyEqual(
                        to: declaredEnd,
                        tolerance: tolerance.distance
                    ), endVertex.point.isApproximatelyEqual(
                        to: declaredStart,
                        tolerance: tolerance.distance
                    ) {
                        trim = CurveTrim(
                            startParameter: declaredTrim.endParameter,
                            endParameter: declaredTrim.startParameter
                        )
                        sameSense = false
                    } else {
                        throw invalid("IGES analytic open-conic endpoints disagree with its parameter interval.")
                    }
                case .planeTorus:
                    guard let declaredTrim = exactTransferTrims[curve.id] else {
                        throw invalid("IGES plane-torus edge has no derived transfer interval.")
                    }
                    let expectedStart = try curveGeometry.point(
                        at: declaredTrim.startParameter,
                        tolerance: tolerance
                    )
                    let expectedEnd = try curveGeometry.point(
                        at: declaredTrim.endParameter,
                        tolerance: tolerance
                    )
                    if startVertex.point.isApproximatelyEqual(
                        to: expectedStart,
                        tolerance: tolerance.distance
                    ), endVertex.point.isApproximatelyEqual(
                        to: expectedEnd,
                        tolerance: tolerance.distance
                    ) {
                        trim = declaredTrim
                        sameSense = true
                    } else if startVertex.point.isApproximatelyEqual(
                        to: expectedEnd,
                        tolerance: tolerance.distance
                    ), endVertex.point.isApproximatelyEqual(
                        to: expectedStart,
                        tolerance: tolerance.distance
                    ) {
                        trim = CurveTrim(
                            startParameter: declaredTrim.endParameter,
                            endParameter: declaredTrim.startParameter
                        )
                        sameSense = false
                    } else {
                        throw invalid(
                            "IGES plane-torus edge vertices disagree with its derived transfer interval."
                        )
                    }
                }
            case .implicit:
                guard let declaredTrim = exactTransferTrims[curve.id] else {
                    throw invalid("IGES implicit intersection edge has no derived transfer interval.")
                }
                let expectedStart = try curveGeometry.point(
                    at: declaredTrim.startParameter,
                    tolerance: tolerance
                )
                let expectedEnd = try curveGeometry.point(
                    at: declaredTrim.endParameter,
                    tolerance: tolerance
                )
                if startVertex.point.isApproximatelyEqual(
                    to: expectedStart,
                    tolerance: tolerance.distance
                ), endVertex.point.isApproximatelyEqual(
                    to: expectedEnd,
                    tolerance: tolerance.distance
                ) {
                    trim = declaredTrim
                    sameSense = true
                } else if startVertex.point.isApproximatelyEqual(
                    to: expectedEnd,
                    tolerance: tolerance.distance
                ), endVertex.point.isApproximatelyEqual(
                    to: expectedStart,
                    tolerance: tolerance.distance
                ) {
                    trim = CurveTrim(
                        startParameter: declaredTrim.endParameter,
                        endParameter: declaredTrim.startParameter
                    )
                    sameSense = false
                } else {
                    throw invalid(
                        "IGES implicit intersection edge vertices disagree with its derived transfer interval."
                    )
                }
            case .surfaceLift:
                guard let reconstructedSurfaceLiftSense else {
                    throw invalid(
                        "IGES curve entity decoding produced a surface lift without a curve-on-surface source entity."
                    )
                }
                trim = reconstructedSurfaceLiftSense
                    ? CurveTrim(startParameter: 0.0, endParameter: 1.0)
                    : CurveTrim(startParameter: 1.0, endParameter: 0.0)
                sameSense = reconstructedSurfaceLiftSense
            case .certifiedIntersection:
                throw invalid("IGES curve decoding produced an unsupported certified intersection runtime curve.")
            }
            edges[edgeID] = Edge(
                id: edgeID,
                curveID: curve.id,
                startVertexID: startVertexID,
                endVertexID: endVertexID,
                trim: trim
            )
            edgeModelSameSense[edgeID] = sameSense
            edgeCache[key] = edgeID
            return edgeID
        }

        mutating func associatedPlaneTorusCurve(
            curvePointer: Int,
            startPoint: Point3D?,
            endPoint: Point3D?
        ) throws -> CertifiedPlaneTorusIntersectionCurve? {
            guard let startPoint,
                  let endPoint,
                  let surfacePointers = curveSurfaceAssociations[curvePointer],
                  surfacePointers.count == 2 else {
                return nil
            }
            var surfaces: [Surface3D] = []
            for pointer in surfacePointers {
                let surfaceID = try buildSurface(pointer)
                guard let surface = geometry.surfaces[surfaceID] else {
                    throw missing("IGES associated intersection surface")
                }
                surfaces.append(surface)
            }
            let plane = surfaces.first(where: { surface in
                switch surface {
                case .plane, .analytic(.plane): return true
                case .cylinder, .analytic, .bSpline: return false
                }
            })
            let torus = surfaces.first(where: { surface in
                if case .analytic(.torus) = surface { return true }
                return false
            })
            guard let plane, let torus else { return nil }
            let candidates = try CertifiedPlaneTorusIntersectionCurve.regularComponents(
                planeSurface: plane,
                torusSurface: torus,
                options: SurfaceSurfaceIntersectionOptions(),
                tolerance: tolerance
            )
            var matches: [CertifiedPlaneTorusIntersectionCurve] = []
            for candidate in candidates {
                let exactCurve = Curve3D.analytic(.planeTorus(candidate))
                do {
                    _ = try exactCurve.parameterProjection(
                        of: startPoint,
                        tolerance: tolerance
                    )
                    _ = try exactCurve.parameterProjection(
                        of: endPoint,
                        tolerance: tolerance
                    )
                    matches.append(candidate)
                } catch let error as KernelError where
                    error.code == .intersectionFailure || error.code == .invalidInput {
                    continue
                }
            }
            guard matches.count <= 1 else {
                throw invalid(
                    "IGES plane-torus curve-on-surface chain matches multiple exact components."
                )
            }
            guard let match = matches.first else {
                throw invalid(
                    "IGES plane-torus curve-on-surface chain does not match its edge endpoints."
                )
            }
            return match
        }

        mutating func associatedImplicitIntersection(
            curvePointer: Int,
            startPoint: Point3D?,
            endPoint: Point3D?
        ) throws -> (
            curve: Curve3D,
            firstSurface: Surface3D,
            secondSurface: Surface3D,
            firstSurfaceParameterCurve: SurfaceParameterCurve,
            secondSurfaceParameterCurve: SurfaceParameterCurve
        )? {
            guard let startPoint,
                  let endPoint,
                  let surfacePointers = curveSurfaceAssociations[curvePointer],
                  surfacePointers.count == 2 else {
                return nil
            }
            var surfaces: [Surface3D] = []
            for pointer in surfacePointers {
                let surfaceID = try buildSurface(pointer)
                guard let surface = geometry.surfaces[surfaceID] else {
                    throw missing("IGES associated implicit-intersection surface")
                }
                surfaces.append(surface)
            }
            guard surfaces.contains(where: { surface in
                if case .bSpline = surface { return true }
                return false
            }) else {
                return nil
            }
            let intersections = try DefaultSurfaceSurfaceIntersector().intersections(
                first: surfaces[0],
                second: surfaces[1],
                tolerance: tolerance
            )
            var matches: [SurfaceSurfaceIntersectionCurve] = []
            for intersection in intersections {
                guard case let .curve(candidate) = intersection else { continue }
                switch candidate.truth {
                case .implicit, .analyticBSpline:
                    break
                case .parametric, .analyticAnalytic, .quadraticTangency,
                     .analyticBSplineTangency:
                    continue
                }
                do {
                    _ = try candidate.curve.parameterProjection(
                        of: startPoint,
                        tolerance: tolerance
                    )
                    _ = try candidate.curve.parameterProjection(
                        of: endPoint,
                        tolerance: tolerance
                    )
                    matches.append(candidate)
                } catch let error as KernelError where
                    error.code == .intersectionFailure || error.code == .invalidInput {
                    continue
                }
            }
            guard matches.count <= 1 else {
                throw invalid(
                    "IGES implicit curve-on-surface chain matches multiple exact components."
                )
            }
            guard let match = matches.first else {
                throw invalid(
                    "IGES implicit curve-on-surface chain does not match its edge endpoints."
                )
            }
            return (
                match.curve,
                surfaces[0],
                surfaces[1],
                match.firstSurfaceParameterCurve,
                match.secondSurfaceParameterCurve
            )
        }

        mutating func associatedSurfaceLift(
            curvePointer: Int,
            curveID: CurveID,
            derivedTrim: CurveTrim?,
            startPoint: Point3D?,
            endPoint: Point3D?
        ) throws -> (lift: SurfaceLiftCurve3D, sameSense: Bool)? {
            guard let entity = entities[curvePointer], entity.label == "SURFLIFT" else {
                return nil
            }
            guard let startPoint,
                  let endPoint,
                  let derivedTrim,
                  case let .bSpline(derivedCurve) = geometry.curves[curveID],
                  let associations = curveSurfaceParameterAssociations[curvePointer],
                  associations.count == 1,
                  let association = associations.first else {
                throw invalid("IGES surface-lift curve-on-surface metadata is incomplete.")
            }
            let surfaceID = try buildSurface(association.surfacePointer)
            guard let surface = geometry.surfaces[surfaceID] else {
                throw missing("IGES surface-lift source surface")
            }
            let derivedStart = try Curve3D.bSpline(derivedCurve).point(
                at: derivedTrim.startParameter,
                tolerance: tolerance
            )
            let derivedEnd = try Curve3D.bSpline(derivedCurve).point(
                at: derivedTrim.endParameter,
                tolerance: tolerance
            )
            let sameSense: Bool
            if startPoint.isApproximatelyEqual(
                to: derivedStart,
                tolerance: tolerance.distance
            ), endPoint.isApproximatelyEqual(
                to: derivedEnd,
                tolerance: tolerance.distance
            ) {
                sameSense = true
            } else if startPoint.isApproximatelyEqual(
                to: derivedEnd,
                tolerance: tolerance.distance
            ), endPoint.isApproximatelyEqual(
                to: derivedStart,
                tolerance: tolerance.distance
            ) {
                sameSense = false
            } else {
                throw invalid(
                    "IGES surface-lift edge vertices disagree with its derived transfer interval."
                )
            }
            let sourceParameterCurve = try parameterCurve(
                association.parameterCurvePointer,
                modelStart: derivedStart,
                modelEnd: derivedEnd,
                surface: surface
            )
            try DefaultCurveSurfaceCorrespondenceValidator().validate(
                curve: .bSpline(derivedCurve),
                from: derivedTrim.startParameter,
                to: derivedTrim.endParameter,
                surface: surface,
                parameterCurve: sourceParameterCurve,
                options: CurveSurfaceCorrespondenceValidationOptions(
                    maximumSubdivisionDepth: 24,
                    maximumCellCount: 65_536
                ),
                tolerance: tolerance
            )
            let lift = SurfaceLiftCurve3D(
                surface: surface,
                parameterCurve: sourceParameterCurve
            )
            try lift.validate(tolerance: tolerance)
            return (lift, sameSense)
        }

        func periodicConicEdgeTrim(
            curve: Curve3D,
            startPoint: Point3D,
            endPoint: Point3D,
            arcStart: Point3D,
            arcEnd: Point3D,
            label: String
        ) throws -> (trim: CurveTrim, sameSense: Bool) {
            let followsCurve = arcStart.isApproximatelyEqual(
                to: startPoint,
                tolerance: tolerance.distance
            ) && arcEnd.isApproximatelyEqual(
                to: endPoint,
                tolerance: tolerance.distance
            )
            let opposesCurve = arcStart.isApproximatelyEqual(
                to: endPoint,
                tolerance: tolerance.distance
            ) && arcEnd.isApproximatelyEqual(
                to: startPoint,
                tolerance: tolerance.distance
            )
            guard followsCurve != opposesCurve else {
                throw invalid("\(label) endpoints disagree with its edge vertices.")
            }
            let period = 2.0 * Double.pi
            let startParameter = try curve.parameterProjection(
                of: startPoint,
                tolerance: tolerance
            ).parameter
            var endParameter = try curve.parameterProjection(
                of: endPoint,
                tolerance: tolerance
            ).parameter
            if followsCurve {
                while endParameter <= startParameter + tolerance.angle {
                    endParameter += period
                }
            } else {
                while endParameter >= startParameter - tolerance.angle {
                    endParameter -= period
                }
            }
            let span = abs(endParameter - startParameter)
            guard span > tolerance.angle,
                  span < period - tolerance.angle else {
                throw unsupported("\(label) has a degenerate or full-period trim interval.")
            }
            return (
                CurveTrim(
                    startParameter: startParameter,
                    endParameter: endParameter
                ),
                followsCurve
            )
        }

        mutating func buildVertex(_ key: IndexedPointer) throws -> VertexID {
            if let cached = vertexCache[key] { return cached }
            let entity = try required(key.pointer, type: 502, label: "vertex list")
            let values = entity.parameters
            let count = try integerAt(values, 1, label: "vertex list count")
            guard key.index > 0, key.index <= count, values.count == 2 + count * 3 else {
                throw invalid("IGES vertex list #\(key.pointer) is malformed.")
            }
            let start = 2 + (key.index - 1) * 3
            let point = try point(values, start: start, label: "vertex")
            let vertexID: VertexID = indexedID(namespace: 0x494745535F565458, key: key)
            vertices[vertexID] = Vertex(id: vertexID, point: point)
            vertexCache[key] = vertexID
            return vertexID
        }

        mutating func buildCurve(_ pointer: Int) throws -> (id: CurveID, trim: CurveTrim?) {
            if let cached = curveCache[pointer] {
                return (cached, curveTrim(pointer))
            }
            let curveID: CurveID = taggedID(namespace: 0x494745535F435256, pointer: pointer)
            guard let entity = entities[pointer] else {
                throw missing("IGES curve #\(pointer)")
            }
            if entity.type == 142 {
                guard entity.form == 0, entity.parameters.count == 6 else {
                    throw invalid("IGES curve-on-surface #\(pointer) is malformed.")
                }
                _ = try integerAt(
                    entity.parameters,
                    1,
                    label: "curve-on-surface creation flag"
                )
                let surfacePointer = try integerAt(
                    entity.parameters,
                    2,
                    label: "curve-on-surface surface pointer"
                )
                let parameterCurvePointer = try integerAt(
                    entity.parameters,
                    3,
                    label: "curve-on-surface parameter curve pointer"
                )
                let modelCurvePointer = try integerAt(
                    entity.parameters,
                    4,
                    label: "curve-on-surface model curve pointer"
                )
                let preferredRepresentation = try integerAt(
                    entity.parameters,
                    5,
                    label: "curve-on-surface preferred representation"
                )
                guard preferredRepresentation == 3 else {
                    throw unsupported(
                        "IGES exact curve-on-surface #\(pointer) must declare equal model and parameter representations."
                    )
                }
                let modelCurve = try buildCurve(modelCurvePointer)
                var associations = curveSurfaceAssociations[modelCurvePointer] ?? []
                if associations.contains(surfacePointer) == false {
                    associations.append(surfacePointer)
                }
                guard associations.count <= 2 else {
                    throw unsupported(
                        "IGES exact intersection curves support at most two associated surfaces."
                    )
                }
                curveSurfaceAssociations[pointer] = associations
                var parameterAssociations = curveSurfaceParameterAssociations[modelCurvePointer] ?? []
                let parameterAssociation = CurveSurfaceParameterAssociation(
                    surfacePointer: surfacePointer,
                    parameterCurvePointer: parameterCurvePointer
                )
                if parameterAssociations.contains(parameterAssociation) == false {
                    parameterAssociations.append(parameterAssociation)
                }
                guard parameterAssociations.count <= 2 else {
                    throw unsupported(
                        "IGES exact intersection curves support at most two parameter-space associations."
                    )
                }
                curveSurfaceParameterAssociations[pointer] = parameterAssociations
                curveCache[pointer] = modelCurve.id
                if let trim = modelCurve.trim {
                    curveTrimCache[pointer] = trim
                }
                return modelCurve
            }
            let trim: CurveTrim?
            switch entity.type {
            case 100:
                let values = entity.parameters
                guard values.count == 8 else {
                    throw invalid("IGES circular arc #\(pointer) is malformed.")
                }
                let z = lengthUnit.toInternal(try numberAt(values, 1, label: "circular arc Z"))
                let localCenter = Point3D(
                    x: lengthUnit.toInternal(try numberAt(values, 2, label: "circular arc center X")),
                    y: lengthUnit.toInternal(try numberAt(values, 3, label: "circular arc center Y")),
                    z: z
                )
                let localStart = Point3D(
                    x: lengthUnit.toInternal(try numberAt(values, 4, label: "circular arc start X")),
                    y: lengthUnit.toInternal(try numberAt(values, 5, label: "circular arc start Y")),
                    z: z
                )
                let localEnd = Point3D(
                    x: lengthUnit.toInternal(try numberAt(values, 6, label: "circular arc end X")),
                    y: lengthUnit.toInternal(try numberAt(values, 7, label: "circular arc end Y")),
                    z: z
                )
                let transformation = try transformation(for: entity)
                let center = transformation?.apply(to: localCenter) ?? localCenter
                let start = transformation?.apply(to: localStart) ?? localStart
                let end = transformation?.apply(to: localEnd) ?? localEnd
                let normal = try (transformation?.apply(to: .unitZ) ?? .unitZ).normalized(
                    tolerance: tolerance.distance
                )
                let radius = (start - center).length
                guard abs((end - center).length - radius) <= tolerance.distance else {
                    throw invalid("IGES circular arc #\(pointer) has inconsistent endpoint radii.")
                }
                if entity.label == "ANAARC" {
                    let basis = AnalyticCurve3D.circle(
                        center: center,
                        normal: normal,
                        radius: radius
                    )
                    try basis.validate(tolerance: tolerance)
                    let basisCurve = Curve3D.analytic(basis)
                    let startParameter = try basisCurve.parameterProjection(
                        of: start,
                        tolerance: tolerance
                    ).parameter
                    var endParameter = try basisCurve.parameterProjection(
                        of: end,
                        tolerance: tolerance
                    ).parameter
                    while endParameter <= startParameter + tolerance.angle {
                        endParameter += 2.0 * Double.pi
                    }
                    guard endParameter - startParameter
                            < 2.0 * Double.pi - tolerance.angle else {
                        throw unsupported(
                            "IGES analytic arc #\(pointer) has a degenerate or full-period domain."
                        )
                    }
                    let arc = AnalyticCurve3D.arc(
                        center: center,
                        normal: normal,
                        radius: radius,
                        startAngle: startParameter,
                        endAngle: endParameter
                    )
                    try arc.validate(tolerance: tolerance)
                    geometry.curves[curveID] = .analytic(arc)
                } else if entity.label == "ANACIRCL" {
                    let circle = AnalyticCurve3D.circle(center: center, normal: normal, radius: radius)
                    try circle.validate(tolerance: tolerance)
                    geometry.curves[curveID] = .analytic(circle)
                } else {
                    let circle = Circle3D(center: center, normal: normal, radius: radius)
                    try circle.validate(tolerance: tolerance)
                    geometry.curves[curveID] = .circle(circle)
                }
                circularArcEndpoints[pointer] = (start, end)
                trim = nil
            case 104:
                let values = entity.parameters
                guard values.count == 12 else {
                    throw invalid("IGES conic #\(pointer) is malformed.")
                }
                let a = try numberAt(values, 1, label: "ellipse A")
                let b = try numberAt(values, 2, label: "ellipse B")
                let c = try numberAt(values, 3, label: "ellipse C")
                let d = try numberAt(values, 4, label: "ellipse D")
                let e = try numberAt(values, 5, label: "ellipse E")
                let f = try numberAt(values, 6, label: "ellipse F")
                let transformation = try transformation(for: entity)
                guard let transformation else {
                    throw unsupported("IGES conic #\(pointer) requires a defining transformation.")
                }
                let localStart = Point3D(
                    x: lengthUnit.toInternal(try numberAt(values, 8, label: "conic start X")),
                    y: lengthUnit.toInternal(try numberAt(values, 9, label: "conic start Y")),
                    z: lengthUnit.toInternal(try numberAt(values, 7, label: "conic Z"))
                )
                let localEnd = Point3D(
                    x: lengthUnit.toInternal(try numberAt(values, 10, label: "conic end X")),
                    y: lengthUnit.toInternal(try numberAt(values, 11, label: "conic end Y")),
                    z: localStart.z
                )
                switch entity.form {
                case 1:
                    guard a > 0.0, c > 0.0, f < 0.0,
                          abs(b) <= tolerance.angle,
                          abs(d) <= tolerance.angle,
                          abs(e) <= tolerance.angle else {
                        throw unsupported("IGES conic #\(pointer) is outside the canonical ellipse contract.")
                    }
                    let firstRadius = lengthUnit.toInternal(sqrt(-f / a))
                    let secondRadius = lengthUnit.toInternal(sqrt(-f / c))
                    guard firstRadius >= secondRadius else {
                        throw unsupported("IGES ellipse #\(pointer) must place its major axis on local X.")
                    }
                    let ellipse = AnalyticCurve3D.ellipse(
                        center: transformation.translation,
                        normal: transformation.zAxis,
                        majorAxis: transformation.xAxis,
                        majorRadius: firstRadius,
                        minorRadius: secondRadius
                    )
                    try ellipse.validate(tolerance: tolerance)
                    geometry.curves[curveID] = .analytic(ellipse)
                    circularArcEndpoints[pointer] = (
                        transformation.apply(to: localStart),
                        transformation.apply(to: localEnd)
                    )
                    trim = nil
                case 2:
                    guard a > 0.0, c < 0.0, f < 0.0,
                          abs(b) <= tolerance.relative,
                          abs(d) <= tolerance.relative,
                          abs(e) <= tolerance.relative else {
                        throw unsupported("IGES conic #\(pointer) is outside the canonical hyperbola contract.")
                    }
                    let hyperbola = Hyperbola3D(
                        center: transformation.translation,
                        normal: transformation.zAxis,
                        transverseAxis: transformation.xAxis,
                        transverseRadius: lengthUnit.toInternal(sqrt(-f / a)),
                        conjugateRadius: lengthUnit.toInternal(sqrt(f / c))
                    )
                    try hyperbola.validate(tolerance: tolerance)
                    let exactCurve = Curve3D.analytic(.hyperbola(hyperbola))
                    geometry.curves[curveID] = exactCurve
                    trim = CurveTrim(
                        startParameter: try exactCurve.parameterProjection(
                            of: transformation.apply(to: localStart),
                            tolerance: tolerance
                        ).parameter,
                        endParameter: try exactCurve.parameterProjection(
                            of: transformation.apply(to: localEnd),
                            tolerance: tolerance
                        ).parameter
                    )
                case 3:
                    guard abs(a) <= tolerance.relative,
                          abs(b) <= tolerance.relative,
                          c > 0.0,
                          d < 0.0,
                          abs(e) <= tolerance.relative,
                          abs(f) <= tolerance.relative else {
                        throw unsupported("IGES conic #\(pointer) is outside the canonical parabola contract.")
                    }
                    let parabola = Parabola3D(
                        vertex: transformation.translation,
                        normal: transformation.zAxis,
                        axis: transformation.xAxis,
                        focalLength: lengthUnit.toInternal(-d / (4.0 * c))
                    )
                    try parabola.validate(tolerance: tolerance)
                    geometry.curves[curveID] = .analytic(.parabola(parabola))
                    trim = CurveTrim(
                        startParameter: localStart.y,
                        endParameter: localEnd.y
                    )
                default:
                    throw unsupported("IGES conic #\(pointer) has unsupported form \(entity.form).")
                }
            case 110:
                let segment = try line(pointer, parameterSpace: false)
                let delta = segment.end - segment.start
                let curve = Line3D(
                    origin: segment.start,
                    direction: try delta.normalized(tolerance: tolerance.distance)
                )
                if entity.label == "ANALINE" {
                    geometry.curves[curveID] = .analytic(.line(
                        origin: segment.start,
                        direction: curve.direction
                    ))
                    trim = CurveTrim(startParameter: 0.0, endParameter: delta.length)
                } else {
                    geometry.curves[curveID] = .line(curve)
                    trim = nil
                }
            case 126:
                let result = try bSplineCurve(entity)
                geometry.curves[curveID] = .bSpline(result.curve)
                trim = CurveTrim(startParameter: result.startParameter, endParameter: result.endParameter)
            default:
                throw unsupported("IGES curve #\(pointer) has unsupported type \(entity.type).")
            }
            curveCache[pointer] = curveID
            if let trim {
                curveTrimCache[pointer] = trim
            }
            return (curveID, trim)
        }

        mutating func buildSurface(_ pointer: Int) throws -> SurfaceID {
            if let cached = surfaceCache[pointer] { return cached }
            guard let entity = entities[pointer] else {
                throw missing("IGES surface #\(pointer)")
            }
            let surface: Surface3D
            switch entity.type {
            case 190:
                guard entity.form == 1, entity.parameters.count == 4 else {
                    throw unsupported("IGES plane surface #\(pointer) must use form 1.")
                }
                let origin = try pointEntity(integerAt(entity.parameters, 1, label: "plane origin pointer"))
                let normal = try directionEntity(integerAt(entity.parameters, 2, label: "plane normal pointer"))
                let reference = try directionEntity(integerAt(entity.parameters, 3, label: "plane reference pointer"))
                guard abs(normal.dot(reference)) <= tolerance.angle else {
                    throw invalid("IGES plane surface #\(pointer) has non-orthogonal axes.")
                }
                let plane = Plane3D(origin: origin, normal: normal)
                try plane.validate(tolerance: tolerance)
                if entity.label == "ANAPLANE" {
                    let expectedReference = try ExactAnalyticFrame.analyticBasis(for: normal, tolerance: tolerance).u
                    guard reference.dot(expectedReference) >= 1.0 - tolerance.angle else {
                        throw unsupported("IGES analytic plane #\(pointer) uses an unsupported parameter frame.")
                    }
                    surface = .analytic(.plane(origin: origin, normal: normal))
                } else {
                    let expectedReference = try ExactAnalyticFrame.directBasis(for: normal, tolerance: tolerance).u
                    guard reference.dot(expectedReference) >= 1.0 - tolerance.angle else {
                        throw unsupported("IGES plane #\(pointer) uses an unsupported parameter frame.")
                    }
                    surface = .plane(plane)
                }
            case 192:
                guard entity.form == 1, entity.parameters.count == 5 else {
                    throw invalid("IGES cylindrical surface #\(pointer) is malformed.")
                }
                let origin = try pointEntity(integerAt(entity.parameters, 1, label: "cylinder origin pointer"))
                let axis = try directionEntity(integerAt(entity.parameters, 2, label: "cylinder axis pointer"))
                let reference = try directionEntity(
                    integerAt(entity.parameters, 4, label: "cylinder reference pointer")
                )
                let isAnalytic = entity.label == "ANACYL"
                let expectedReference = try isAnalytic
                    ? ExactAnalyticFrame.analyticBasis(for: axis, tolerance: tolerance).u
                    : ExactAnalyticFrame.directBasis(for: axis, tolerance: tolerance).u
                guard reference.dot(expectedReference) >= 1.0 - tolerance.angle else {
                    throw unsupported("IGES cylinder #\(pointer) uses an unsupported parameter frame.")
                }
                let radius = lengthUnit.toInternal(
                    try numberAt(entity.parameters, 3, label: "cylinder radius")
                )
                if isAnalytic {
                    let cylinder = AnalyticSurface3D.cylinder(
                        origin: origin,
                        axis: axis,
                        radius: radius
                    )
                    try cylinder.validate(tolerance: tolerance)
                    surface = .analytic(cylinder)
                } else {
                    let cylinder = Cylinder3D(origin: origin, axis: axis, radius: radius)
                    try cylinder.validate(tolerance: tolerance)
                    surface = .cylinder(cylinder)
                }
            case 194:
                guard entity.form == 1, entity.parameters.count == 6 else {
                    throw invalid("IGES conical surface #\(pointer) is malformed.")
                }
                let apex = try pointEntity(integerAt(entity.parameters, 1, label: "cone origin pointer"))
                let axis = try directionEntity(integerAt(entity.parameters, 2, label: "cone axis pointer"))
                let radius = lengthUnit.toInternal(
                    try numberAt(entity.parameters, 3, label: "cone radius")
                )
                let halfAngle = try numberAt(entity.parameters, 4, label: "cone semi-angle")
                let reference = try directionEntity(
                    integerAt(entity.parameters, 5, label: "cone reference pointer")
                )
                let expectedReference = try ExactAnalyticFrame.analyticBasis(for: axis, tolerance: tolerance).u
                guard entity.label == "ANACONE",
                      abs(radius) <= tolerance.distance,
                      reference.dot(expectedReference) >= 1.0 - tolerance.angle else {
                    throw unsupported("IGES cone #\(pointer) is outside the analytic apex contract.")
                }
                let cone = AnalyticSurface3D.cone(apex: apex, axis: axis, halfAngle: halfAngle)
                try cone.validate(tolerance: tolerance)
                surface = .analytic(cone)
            case 196:
                guard entity.form == 1, entity.parameters.count == 5 else {
                    throw invalid("IGES spherical surface #\(pointer) is malformed.")
                }
                let center = try pointEntity(integerAt(entity.parameters, 1, label: "sphere center pointer"))
                let radius = lengthUnit.toInternal(
                    try numberAt(entity.parameters, 2, label: "sphere radius")
                )
                let axis = try directionEntity(integerAt(entity.parameters, 3, label: "sphere axis pointer"))
                let reference = try directionEntity(
                    integerAt(entity.parameters, 4, label: "sphere reference pointer")
                )
                let expectedReference = try ExactAnalyticFrame.analyticBasis(for: .unitZ, tolerance: tolerance).u
                guard entity.label == "ANASPHER",
                      axis.dot(.unitZ) >= 1.0 - tolerance.angle,
                      reference.dot(expectedReference) >= 1.0 - tolerance.angle else {
                    throw unsupported("IGES sphere #\(pointer) uses an unsupported parameter frame.")
                }
                let sphere = AnalyticSurface3D.sphere(center: center, radius: radius)
                try sphere.validate(tolerance: tolerance)
                surface = .analytic(sphere)
            case 198:
                guard entity.form == 1, entity.parameters.count == 6 else {
                    throw invalid("IGES toroidal surface #\(pointer) is malformed.")
                }
                let center = try pointEntity(integerAt(entity.parameters, 1, label: "torus center pointer"))
                let axis = try directionEntity(integerAt(entity.parameters, 2, label: "torus axis pointer"))
                let majorRadius = lengthUnit.toInternal(
                    try numberAt(entity.parameters, 3, label: "torus major radius")
                )
                let minorRadius = lengthUnit.toInternal(
                    try numberAt(entity.parameters, 4, label: "torus minor radius")
                )
                let reference = try directionEntity(
                    integerAt(entity.parameters, 5, label: "torus reference pointer")
                )
                let expectedReference = try ExactAnalyticFrame.analyticBasis(for: axis, tolerance: tolerance).u
                guard entity.label == "ANATORUS",
                      reference.dot(expectedReference) >= 1.0 - tolerance.angle else {
                    throw unsupported("IGES torus #\(pointer) uses an unsupported parameter frame.")
                }
                let torus = AnalyticSurface3D.torus(
                    center: center,
                    axis: axis,
                    majorRadius: majorRadius,
                    minorRadius: minorRadius
                )
                try torus.validate(tolerance: tolerance)
                surface = .analytic(torus)
            case 128:
                surface = .bSpline(try bSplineSurface(entity))
            default:
                throw unsupported("IGES surface #\(pointer) has unsupported type \(entity.type).")
            }
            let surfaceID: SurfaceID = taggedID(namespace: 0x494745535F535246, pointer: pointer)
            geometry.surfaces[surfaceID] = surface
            surfaceCache[pointer] = surfaceID
            return surfaceID
        }

        func bSplineCurve(
            _ entity: Entity
        ) throws -> (curve: BSplineCurve3D, startParameter: Double, endParameter: Double) {
            let values = entity.parameters
            guard values.count >= 12 else {
                throw invalid("IGES B-spline curve #\(entity.pointer) is truncated.")
            }
            let upperIndex = try integerAt(values, 1, label: "B-spline curve upper index")
            let degree = try integerAt(values, 2, label: "B-spline curve degree")
            let controlPointCount = upperIndex + 1
            let knotCount = controlPointCount + degree + 1
            guard upperIndex >= degree,
                  try booleanAt(values, 4, label: "B-spline curve closed flag") == false,
                  try booleanAt(values, 6, label: "B-spline curve periodic flag") == false,
                  values.count == 7 + knotCount + controlPointCount + controlPointCount * 3 + 5 else {
                throw unsupported("IGES B-spline curve #\(entity.pointer) must be open and non-periodic.")
            }
            var cursor = 7
            let knots = try numbers(values, cursor: &cursor, count: knotCount, label: "B-spline curve knot")
            let weights = try numbers(values, cursor: &cursor, count: controlPointCount, label: "B-spline curve weight")
            var controlPoints: [Point3D] = []
            controlPoints.reserveCapacity(controlPointCount)
            for _ in 0..<controlPointCount {
                controlPoints.append(try point(values, start: cursor, label: "B-spline curve control point"))
                cursor += 3
            }
            let startParameter = try numberAt(values, cursor, label: "B-spline curve start parameter")
            let endParameter = try numberAt(values, cursor + 1, label: "B-spline curve end parameter")
            let curve = BSplineCurve3D(
                degree: degree,
                knots: knots,
                controlPoints: controlPoints,
                weights: weights
            )
            try curve.validate(tolerance: tolerance)
            guard startParameter.isFinite,
                  endParameter.isFinite,
                  abs(endParameter - startParameter) > tolerance.distance,
                  try curve.domain.containsSpan(
                    from: startParameter,
                    to: endParameter,
                    tolerance: tolerance
                  ) else {
                throw invalid("IGES B-spline curve #\(entity.pointer) has an invalid parameter interval.")
            }
            let polynomial = try booleanAt(values, 5, label: "B-spline curve polynomial flag")
            guard polynomial == !curve.isRational else {
                throw invalid("IGES B-spline curve #\(entity.pointer) has an inconsistent polynomial flag.")
            }
            return (curve, startParameter, endParameter)
        }

        func bSplineSurface(_ entity: Entity) throws -> BSplineSurface3D {
            let values = entity.parameters
            guard values.count >= 14 else {
                throw invalid("IGES B-spline surface #\(entity.pointer) is truncated.")
            }
            let uUpperIndex = try integerAt(values, 1, label: "B-spline surface U upper index")
            let vUpperIndex = try integerAt(values, 2, label: "B-spline surface V upper index")
            let uDegree = try integerAt(values, 3, label: "B-spline surface U degree")
            let vDegree = try integerAt(values, 4, label: "B-spline surface V degree")
            let uCount = uUpperIndex + 1
            let vCount = vUpperIndex + 1
            let uKnotCount = uCount + uDegree + 1
            let vKnotCount = vCount + vDegree + 1
            let controlPointCount = uCount * vCount
            let expectedCount = 10 + uKnotCount + vKnotCount + controlPointCount + controlPointCount * 3 + 4
            guard uUpperIndex >= uDegree,
                  vUpperIndex >= vDegree,
                  try booleanAt(values, 5, label: "B-spline surface U closed flag") == false,
                  try booleanAt(values, 6, label: "B-spline surface V closed flag") == false,
                  try booleanAt(values, 8, label: "B-spline surface U periodic flag") == false,
                  try booleanAt(values, 9, label: "B-spline surface V periodic flag") == false,
                  values.count == expectedCount else {
                throw unsupported("IGES B-spline surface #\(entity.pointer) must be open and non-periodic.")
            }
            var cursor = 10
            let uKnots = try numbers(values, cursor: &cursor, count: uKnotCount, label: "B-spline surface U knot")
            let vKnots = try numbers(values, cursor: &cursor, count: vKnotCount, label: "B-spline surface V knot")
            let flatWeights = try numbers(
                values,
                cursor: &cursor,
                count: controlPointCount,
                label: "B-spline surface weight"
            )
            var flatPoints: [Point3D] = []
            flatPoints.reserveCapacity(controlPointCount)
            for _ in 0..<controlPointCount {
                flatPoints.append(try point(values, start: cursor, label: "B-spline surface control point"))
                cursor += 3
            }
            let uLower = try numberAt(values, cursor, label: "B-spline surface U lower bound")
            let uUpper = try numberAt(values, cursor + 1, label: "B-spline surface U upper bound")
            let vLower = try numberAt(values, cursor + 2, label: "B-spline surface V lower bound")
            let vUpper = try numberAt(values, cursor + 3, label: "B-spline surface V upper bound")
            var controlPoints: [[Point3D]] = []
            var weights: [[Double]] = []
            for vIndex in 0..<vCount {
                let range = (vIndex * uCount)..<((vIndex + 1) * uCount)
                controlPoints.append(Array(flatPoints[range]))
                weights.append(Array(flatWeights[range]))
            }
            let surface = BSplineSurface3D(
                uDegree: uDegree,
                vDegree: vDegree,
                uKnots: uKnots,
                vKnots: vKnots,
                controlPoints: controlPoints,
                weights: weights
            )
            try surface.validate(tolerance: tolerance)
            guard case let .closed(expectedULower, expectedUUpper) = surface.uDomain,
                  case let .closed(expectedVLower, expectedVUpper) = surface.vDomain,
                  abs(uLower - expectedULower) <= tolerance.distance,
                  abs(uUpper - expectedUUpper) <= tolerance.distance,
                  abs(vLower - expectedVLower) <= tolerance.distance,
                  abs(vUpper - expectedVUpper) <= tolerance.distance else {
                throw invalid("IGES B-spline surface #\(entity.pointer) parameter bounds disagree with its knots.")
            }
            let polynomial = try booleanAt(values, 7, label: "B-spline surface polynomial flag")
            guard polynomial == !surface.isRational else {
                throw invalid("IGES B-spline surface #\(entity.pointer) has an inconsistent polynomial flag.")
            }
            return surface
        }

        func parameterCurve(
            _ pointer: Int,
            modelStart: Point3D,
            modelEnd: Point3D,
            surface: Surface3D
        ) throws -> SurfaceParameterCurve {
            guard let entity = entities[pointer] else {
                throw missing("IGES p-curve #\(pointer)")
            }
            let curve: SurfaceParameterCurve
            switch entity.type {
            case 110:
                let segment = try line(pointer, parameterSpace: true)
                let start = try ExactSurfaceParameterCodec.decode(
                    SurfaceParameter(u: segment.start.x, v: segment.start.y),
                    on: surface,
                    unit: lengthUnit,
                    tolerance: tolerance,
                    convention: .iges
                )
                let end = try ExactSurfaceParameterCodec.decode(
                    SurfaceParameter(u: segment.end.x, v: segment.end.y),
                    on: surface,
                    unit: lengthUnit,
                    tolerance: tolerance,
                    convention: .iges
                )
                curve = .polyline([start, end])
            case 104:
                let parsed = try parameterEllipse(entity)
                let decodedCenter = try ExactSurfaceParameterCodec.decode(
                    SurfaceParameter(u: parsed.ellipse.center.x, v: parsed.ellipse.center.y),
                    on: surface,
                    unit: lengthUnit,
                    tolerance: tolerance,
                    convention: .iges
                )
                let major = parsed.ellipse.majorVector
                let minor = parsed.ellipse.minorVector
                let decodedMajor = try ExactSurfaceParameterCodec.decode(
                    SurfaceParameter(
                        u: parsed.ellipse.center.x + major.x,
                        v: parsed.ellipse.center.y + major.y
                    ),
                    on: surface,
                    unit: lengthUnit,
                    tolerance: tolerance,
                    convention: .iges
                )
                let decodedMinor = try ExactSurfaceParameterCodec.decode(
                    SurfaceParameter(
                        u: parsed.ellipse.center.x + minor.x,
                        v: parsed.ellipse.center.y + minor.y
                    ),
                    on: surface,
                    unit: lengthUnit,
                    tolerance: tolerance,
                    convention: .iges
                )
                let startParameter = parsed.ellipse.parameter(of: parsed.start)
                var endParameter = parsed.ellipse.parameter(of: parsed.end)
                while endParameter <= startParameter + tolerance.angle {
                    endParameter += 2.0 * Double.pi
                }
                curve = .harmonic(
                    center: Point2D(x: decodedCenter.u, y: decodedCenter.v),
                    cosine: Point2D(
                        x: decodedMajor.u - decodedCenter.u,
                        y: decodedMajor.v - decodedCenter.v
                    ),
                    sine: Point2D(
                        x: decodedMinor.u - decodedCenter.u,
                        y: decodedMinor.v - decodedCenter.v
                    ),
                    startParameter: startParameter,
                    endParameter: endParameter
                )
            case 126:
                curve = .bSpline(try parameterBSpline(entity, surface: surface))
            default:
                throw unsupported("IGES p-curve #\(pointer) has unsupported type \(entity.type).")
            }
            let start = try curve.startParameter(tolerance: tolerance)
            let end = try curve.endParameter(tolerance: tolerance)
            let reconstructedStart = try surface.point(
                u: start.u,
                v: start.v,
                tolerance: tolerance
            )
            let reconstructedEnd = try surface.point(
                u: end.u,
                v: end.v,
                tolerance: tolerance
            )
            guard reconstructedStart.isApproximatelyEqual(
                to: modelStart,
                tolerance: tolerance.distance
            ), reconstructedEnd.isApproximatelyEqual(
                to: modelEnd,
                tolerance: tolerance.distance
            ) else {
                throw invalid("IGES p-curve #\(pointer) disagrees with its model-space curve.")
            }
            return curve
        }

        func parameterBSpline(_ entity: Entity, surface: Surface3D) throws -> BSplineCurve2D {
            let values = entity.parameters
            guard values.count >= 12 else {
                throw invalid("IGES p-curve B-spline #\(entity.pointer) is truncated.")
            }
            let upperIndex = try integerAt(values, 1, label: "p-curve B-spline upper index")
            let degree = try integerAt(values, 2, label: "p-curve B-spline degree")
            let controlPointCount = upperIndex + 1
            let knotCount = controlPointCount + degree + 1
            guard upperIndex >= degree,
                  try booleanAt(values, 4, label: "p-curve B-spline closed flag") == false,
                  try booleanAt(values, 6, label: "p-curve B-spline periodic flag") == false,
                  values.count == 7 + knotCount + controlPointCount + controlPointCount * 3 + 5 else {
                throw unsupported("IGES p-curve B-spline #\(entity.pointer) must be open and non-periodic.")
            }
            var cursor = 7
            let knots = try numbers(
                values,
                cursor: &cursor,
                count: knotCount,
                label: "p-curve B-spline knot"
            )
            let weights = try numbers(
                values,
                cursor: &cursor,
                count: controlPointCount,
                label: "p-curve B-spline weight"
            )
            var controlPoints: [Point2D] = []
            for _ in 0..<controlPointCount {
                let encoded = SurfaceParameter(
                    u: try numberAt(values, cursor, label: "p-curve control U"),
                    v: try numberAt(values, cursor + 1, label: "p-curve control V")
                )
                guard abs(try numberAt(values, cursor + 2, label: "p-curve control Z"))
                        <= tolerance.distance else {
                    throw invalid("IGES p-curve B-spline #\(entity.pointer) has nonzero Z coordinates.")
                }
                let decoded = try ExactSurfaceParameterCodec.decode(
                    encoded,
                    on: surface,
                    unit: lengthUnit,
                    tolerance: tolerance,
                    convention: .iges
                )
                controlPoints.append(Point2D(x: decoded.u, y: decoded.v))
                cursor += 3
            }
            let startParameter = try numberAt(values, cursor, label: "p-curve start parameter")
            let endParameter = try numberAt(values, cursor + 1, label: "p-curve end parameter")
            let curve = BSplineCurve2D(
                degree: degree,
                knots: knots,
                controlPoints: controlPoints,
                weights: weights
            )
            try curve.validate(tolerance: tolerance)
            guard case let .closed(lower, upper) = curve.domain,
                  abs(startParameter - lower) <= tolerance.distance,
                  abs(endParameter - upper) <= tolerance.distance else {
                throw unsupported("IGES p-curve B-spline #\(entity.pointer) requires its complete domain.")
            }
            let polynomial = try booleanAt(values, 5, label: "p-curve polynomial flag")
            guard polynomial == !curve.isRational else {
                throw invalid("IGES p-curve B-spline #\(entity.pointer) has an inconsistent polynomial flag.")
            }
            return curve
        }

        func parameterEllipse(
            _ entity: Entity
        ) throws -> (ellipse: STEPParameterEllipse, start: Point2D, end: Point2D) {
            let values = entity.parameters
            guard entity.form == 1, values.count == 12, entity.transformationPointer == 0 else {
                throw unsupported("IGES p-curve conic #\(entity.pointer) is not a direct ellipse.")
            }
            let a = try numberAt(values, 1, label: "p-curve ellipse A")
            let halfB = 0.5 * (try numberAt(values, 2, label: "p-curve ellipse B"))
            let c = try numberAt(values, 3, label: "p-curve ellipse C")
            let d = try numberAt(values, 4, label: "p-curve ellipse D")
            let e = try numberAt(values, 5, label: "p-curve ellipse E")
            let f = try numberAt(values, 6, label: "p-curve ellipse F")
            let determinant = a * c - halfB * halfB
            guard a > 0.0, determinant > 0.0 else {
                throw unsupported("IGES p-curve conic #\(entity.pointer) is not an ellipse.")
            }
            let center = Point2D(
                x: -0.5 * (c * d - halfB * e) / determinant,
                y: -0.5 * (a * e - halfB * d) / determinant
            )
            let centeredValue = a * center.x * center.x
                + 2.0 * halfB * center.x * center.y
                + c * center.y * center.y
                + d * center.x
                + e * center.y
                + f
            let discriminant = hypot(a - c, 2.0 * halfB)
            let minimumEigenvalue = 0.5 * (a + c - discriminant)
            let maximumEigenvalue = 0.5 * (a + c + discriminant)
            guard centeredValue < 0.0, minimumEigenvalue > 0.0 else {
                throw invalid("IGES p-curve ellipse #\(entity.pointer) is degenerate.")
            }
            let majorDirection: Point2D
            if abs(halfB) > tolerance.angle {
                majorDirection = Point2D(x: halfB, y: minimumEigenvalue - a)
            } else if a <= c {
                majorDirection = Point2D(x: 1.0, y: 0.0)
            } else {
                majorDirection = Point2D(x: 0.0, y: 1.0)
            }
            let ellipse = try STEPParameterEllipse(
                center: center,
                majorDirection: majorDirection,
                majorRadius: sqrt(-centeredValue / minimumEigenvalue),
                minorRadius: sqrt(-centeredValue / maximumEigenvalue),
                tolerance: tolerance.distance
            )
            let start = Point2D(
                x: try numberAt(values, 8, label: "p-curve ellipse start X"),
                y: try numberAt(values, 9, label: "p-curve ellipse start Y")
            )
            let end = Point2D(
                x: try numberAt(values, 10, label: "p-curve ellipse end X"),
                y: try numberAt(values, 11, label: "p-curve ellipse end Y")
            )
            let tolerance = tolerance.distance
            guard ellipse.residual(of: start) <= tolerance,
                  ellipse.residual(of: end) <= tolerance else {
                throw invalid("IGES p-curve ellipse #\(entity.pointer) endpoints are off-conic.")
            }
            return (ellipse, start, end)
        }

        func line(_ pointer: Int, parameterSpace: Bool) throws -> (start: Point3D, end: Point3D) {
            let entity = try required(pointer, type: 110, label: parameterSpace ? "p-curve" : "line")
            guard entity.parameters.count == 7 else {
                throw invalid("IGES line #\(pointer) is malformed.")
            }
            if parameterSpace {
                return (
                    try rawPoint(entity.parameters, start: 1, label: "p-curve start"),
                    try rawPoint(entity.parameters, start: 4, label: "p-curve end")
                )
            }
            return (
                try point(entity.parameters, start: 1, label: "line start"),
                try point(entity.parameters, start: 4, label: "line end")
            )
        }

        func pointEntity(_ pointer: Int) throws -> Point3D {
            let entity = try required(pointer, type: 116, label: "point")
            guard entity.parameters.count == 5,
                  try integerAt(entity.parameters, 4, label: "point display pointer") == 0 else {
                throw invalid("IGES point #\(pointer) is malformed.")
            }
            return try point(entity.parameters, start: 1, label: "point")
        }

        func directionEntity(_ pointer: Int) throws -> Vector3D {
            let entity = try required(pointer, type: 123, label: "direction")
            guard entity.parameters.count == 4 else {
                throw invalid("IGES direction #\(pointer) is malformed.")
            }
            return try Vector3D(
                x: numberAt(entity.parameters, 1, label: "direction x"),
                y: numberAt(entity.parameters, 2, label: "direction y"),
                z: numberAt(entity.parameters, 3, label: "direction z")
            ).normalized(tolerance: tolerance.distance)
        }

        func transformation(for entity: Entity) throws -> IGESTransformation? {
            guard entity.transformationPointer != 0 else {
                return nil
            }
            let transformationEntity = try required(
                entity.transformationPointer,
                type: 124,
                label: "transformation matrix"
            )
            guard transformationEntity.form == 0,
                  transformationEntity.transformationPointer == 0,
                  transformationEntity.parameters.count == 13 else {
                throw unsupported(
                    "IGES transformation #\(entity.transformationPointer) must be a non-nested form 0 matrix."
                )
            }
            let values = transformationEntity.parameters
            return try IGESTransformation(
                xAxis: Vector3D(
                    x: numberAt(values, 1, label: "transformation R11"),
                    y: numberAt(values, 5, label: "transformation R21"),
                    z: numberAt(values, 9, label: "transformation R31")
                ),
                yAxis: Vector3D(
                    x: numberAt(values, 2, label: "transformation R12"),
                    y: numberAt(values, 6, label: "transformation R22"),
                    z: numberAt(values, 10, label: "transformation R32")
                ),
                zAxis: Vector3D(
                    x: numberAt(values, 3, label: "transformation R13"),
                    y: numberAt(values, 7, label: "transformation R23"),
                    z: numberAt(values, 11, label: "transformation R33")
                ),
                translation: Point3D(
                    x: lengthUnit.toInternal(try numberAt(values, 4, label: "transformation T1")),
                    y: lengthUnit.toInternal(try numberAt(values, 8, label: "transformation T2")),
                    z: lengthUnit.toInternal(try numberAt(values, 12, label: "transformation T3"))
                ),
                tolerance: tolerance
            )
        }

        func point(_ values: [String], start: Int, label: String) throws -> Point3D {
            guard start >= 0, start + 2 < values.count else {
                throw invalid("IGES \(label) coordinates are missing.")
            }
            return Point3D(
                x: lengthUnit.toInternal(try numberAt(values, start, label: "\(label) x")),
                y: lengthUnit.toInternal(try numberAt(values, start + 1, label: "\(label) y")),
                z: lengthUnit.toInternal(try numberAt(values, start + 2, label: "\(label) z"))
            )
        }

        func rawPoint(_ values: [String], start: Int, label: String) throws -> Point3D {
            guard start >= 0, start + 2 < values.count else {
                throw invalid("IGES \(label) coordinates are missing.")
            }
            return Point3D(
                x: try numberAt(values, start, label: "\(label) x"),
                y: try numberAt(values, start + 1, label: "\(label) y"),
                z: try numberAt(values, start + 2, label: "\(label) z")
            )
        }

        func numbers(
            _ values: [String],
            cursor: inout Int,
            count: Int,
            label: String
        ) throws -> [Double] {
            guard count > 0, cursor >= 0, cursor + count <= values.count else {
                throw invalid("IGES \(label) data is truncated.")
            }
            var result: [Double] = []
            result.reserveCapacity(count)
            for offset in 0..<count {
                result.append(try numberAt(values, cursor + offset, label: label))
            }
            cursor += count
            return result
        }

        func required(_ pointer: Int, type: Int, label: String) throws -> Entity {
            guard let entity = entities[pointer] else { throw missing("IGES \(label) #\(pointer)") }
            guard entity.type == type else {
                throw invalid("IGES \(label) #\(pointer) has type \(entity.type), expected \(type).")
            }
            return entity
        }

        func integerAt(_ values: [String], _ index: Int, label: String) throws -> Int {
            guard values.indices.contains(index), let value = Int(values[index]) else {
                throw invalid("IGES \(label) is not an integer.")
            }
            return value
        }

        func numberAt(_ values: [String], _ index: Int, label: String) throws -> Double {
            guard values.indices.contains(index) else { throw invalid("IGES \(label) is missing.") }
            let normalized = values[index].replacingOccurrences(of: "D", with: "E")
                .replacingOccurrences(of: "d", with: "E")
            guard let value = Double(normalized), value.isFinite else {
                throw invalid("IGES \(label) is not finite.")
            }
            return value
        }

        func booleanAt(_ values: [String], _ index: Int, label: String) throws -> Bool {
            guard values.indices.contains(index) else { throw invalid("IGES \(label) is missing.") }
            return try boolean(values[index])
        }

        func boolean(_ value: String) throws -> Bool {
            switch value {
            case "0": false
            case "1": true
            default: throw invalid("IGES Boolean value is not 0 or 1.")
            }
        }

        func orientation(_ value: String) throws -> Orientation {
            try boolean(value) ? .forward : .reversed
        }

        func taggedID<Tag>(namespace: UInt64, pointer: Int) -> TaggedID<Tag> {
            TaggedID<Tag>(highBits: namespace, lowBits: UInt64(pointer))
        }

        func indexedID<Tag>(namespace: UInt64, key: IndexedPointer) -> TaggedID<Tag> {
            TaggedID<Tag>(
                highBits: namespace,
                lowBits: (UInt64(key.pointer) << 32) | UInt64(key.index)
            )
        }

        func invalid(_ message: String) -> ImportError { .invalidData(message) }
        func missing(_ message: String) -> ImportError { .missingRequiredEntity(message) }
        func unsupported(_ message: String) -> KernelError {
            KernelError(
                phase: .exchange,
                code: .unsupportedCapability,
                tolerance: tolerance,
                message: message
            )
        }
    }
}

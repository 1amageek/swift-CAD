import HashTreeCollections
import CADCore
import CADGeometry
import CADTopology

/// Solves a whole sheet shell's offset jointly, rather than moving shared topology face by face.
package struct SharedSheetSurfaceOffsetter {
    package func offset(shell: Shell, bodyID: BodyID, by distance: Double, featureID: FeatureID,
                        model: inout BRepModel, tolerance: ModelingTolerance) throws {
        let original = model
        var replacements: [FaceID: FaceSurfaceReplacementRebuilder.Replacement] = [:]
        var transportedVertices: [VertexID: [Point3D]] = [:]
        for faceID in shell.faceIDs.sorted() {
            guard let face = original.faces[faceID], let source = original.geometry.surfaces[face.surfaceID] else {
                throw TopologyError.missingReference("Shared offset face support is missing.")
            }
            let offset = OffsetSurface3D(source: source, distance: face.orientation == .forward ? distance : -distance)
            let target = try offset.exactChartPreservingSurface(tolerance: tolerance) ?? .procedural(.offset(offset))
            var charts: [SurfaceParameterCurve] = []
            var boundaryCharts: [EdgeID: SurfaceParameterCurve] = [:]
            var displacement = Vector3D.zero
            var vertexCount = 0
            for loopID in face.loops {
                guard let loop = original.loops[loopID] else {
                    throw TopologyError.missingReference("Shared offset source loop is missing.")
                }
                for coedge in loop.edges {
                    guard let edge = original.edges[coedge.edgeID], let chart = coedge.surfaceParameterCurve else {
                        throw TopologyError.missingReference("Shared offset requires exact boundary pcurves.")
                    }
                    charts.append(chart)
                    let canonical = coedge.orientation == .forward ? chart : try chart.reversed(tolerance: tolerance)
                    let mapped = SurfaceParameterCurve.offsetSurfaceImage(try offset.parameterCurveImage(
                        transporting: canonical, tolerance: tolerance))
                    boundaryCharts[edge.id] = mapped
                    let startUV = try mapped.startParameter(tolerance: tolerance)
                    let endUV = try mapped.endParameter(tolerance: tolerance)
                    for (vertexID, uv) in [(edge.startVertexID, startUV), (edge.endVertexID, endUV)] {
                        guard let old = original.vertices[vertexID]?.point else {
                            throw TopologyError.missingReference("Shared offset source vertex is missing.")
                        }
                        let point = try target.point(u: uv.u, v: uv.v, tolerance: tolerance)
                        transportedVertices[vertexID, default: []].append(point)
                        displacement = displacement + (point - old)
                        vertexCount += 1
                    }
                }
            }
            let bounds = try ExactSurfaceParameterBoundsResolver().resolve(parameterCurves: charts,
                                                                          on: source, tolerance: tolerance)
            try DefaultSurfaceRegularityValidator().validate(target, over: bounds, tolerance: tolerance)
            var replacement = FaceSurfaceReplacementRebuilder.Replacement(surface: target,
                orientation: face.orientation, landing: vertexCount == 0 ? .zero : displacement / Double(vertexCount))
            replacement.boundaryParameterCurves = boundaryCharts
            replacements[faceID] = replacement
        }
        var known: [VertexID: Point3D] = [:]
        for (id, points) in transportedVertices {
            guard let first = points.first else { continue }
            if points.allSatisfy({ ($0 - first).length <= tolerance.distance }) { known[id] = first }
        }
        try FaceSurfaceReplacementRebuilder().replace(replacements, bodyID: bodyID, featureID: featureID,
            model: &model, tolerance: tolerance, knownPoints: known)
        try ExactFacePcurveBuilder().populateMissingPcurves(in: &model, tolerance: tolerance)
    }
}

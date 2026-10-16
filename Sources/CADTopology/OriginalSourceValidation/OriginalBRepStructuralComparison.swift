import CADCore
import CADGeometry
import HashTreeCollections

/// Accounts the authored variable-length payloads consumed by structural equality.
package enum OriginalBRepStructuralComparison {
    package static func models(_ first: BRepModel, _ second: BRepModel,
        using execution: inout OriginalQueryExecution) throws -> Bool {
        try charge(first, using: &execution)
        try charge(second, using: &execution)
        return first == second
    }

    package static func charge(_ model: BRepModel,
        using execution: inout OriginalQueryExecution) throws {
        for body in model.bodies.values {
            try execution.consumeWork(1)
            if let name = body.name { try execution.consumeWork(name.utf8.count) }
            switch body.topology {
            case .sheet(let ids): try execution.consumeWork(ids.count)
            case .solid(let components):
                for component in components {
                    try execution.consumeWork(1)
                    try execution.consumeWork(component.voidShellIDs.count)
                }
            }
        }
        for shell in model.shells.values {
            try execution.consumeWork(1); try execution.consumeWork(shell.faceIDs.count)
        }
        for face in model.faces.values {
            try execution.consumeWork(1); try execution.consumeWork(face.loops.count)
        }
        for loop in model.loops.values {
            try execution.consumeWork(1)
            for use in loop.coedges {
                try execution.consumeWork(1)
                if let curve = use.surfaceParameterCurve {
                    try GeometryStructuralComparisonWork.charge(parameterCurve: curve, using: &execution)
                }
            }
        }
        for _ in model.edges { try execution.consumeWork(1) }
        for vertex in model.vertices.values {
            try execution.consumeWork(1)
            if let point = vertex.originalPoint {
                try GeometryStructuralComparisonWork.charge(word: point.word, using: &execution)
            }
        }
        for curve in model.geometry.curves.values {
            try GeometryStructuralComparisonWork.charge(curve: curve, using: &execution)
        }
        for surface in model.geometry.surfaces.values {
            try GeometryStructuralComparisonWork.charge(surface: surface, using: &execution)
        }
    }
}

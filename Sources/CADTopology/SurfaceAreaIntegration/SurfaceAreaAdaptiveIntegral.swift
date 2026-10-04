import CADCore
import CADGeometry

/// Combines every leaf uncertainty before accepting one original fan integral.
/// Native pieces share the caller's one target and query-wide processed-cell counter.
struct SurfaceAreaAdaptiveIntegral {
    struct Cell {
        let t: ScalarInterval
        let r: ScalarInterval
        let depth: Int
        let rectangle: SurfaceParameterBox?
        let domain: SurfaceAreaNativeSpanDomain?
    }

    struct Evaluation {
        let contribution: [OutwardScalarInterval]?
        let splitT: Bool
    }

    private struct Node {
        var parent: Int?
        var children: (Int,Int)?
        let cell: Cell?
        var evaluation: Evaluation
        let score: Double
    }

    func integrate(cells: [Cell], goals: [Double], options: FaceAreaIntegrationOptions,
                   work: inout Int, tolerance: ModelingTolerance,
                   evaluate: (Cell, inout Int) throws -> Evaluation) throws -> [OutwardScalarInterval] {
        guard !cells.isEmpty,goals.count == 4,goals.allSatisfy({ $0.isFinite && $0 > 0 }) else {
            throw failure(.classificationFailure,tolerance,"Native integration requires complete coverage and four finite positive uncertainty targets.")
        }
        var nodes: [Node] = []
        var heap: [Int] = []
        var level: [Int] = []
        func score(_ evaluation: Evaluation) -> Double {
            guard let values = evaluation.contribution else { return .infinity }
            return zip(values,goals).map { $0.0.width*0.5/$0.1 }.max() ?? .infinity
        }
        func process(_ cell: Cell) throws -> Evaluation {
            guard !Task.isCancelled else { throw failure(.cancelled,tolerance,"Native area integration was cancelled.") }
            work += 1
            guard work <= options.maximumCellCount else {
                throw KernelError(phase:.topology,code:.resourceLimitExceeded,residual:Double(work),tolerance:tolerance,
                    message:"Certified face area exceeded its shared cell budget.")
            }
            let evaluation = try evaluate(cell,&work)
            if let values = evaluation.contribution {
                guard values.count == 4,values.allSatisfy(\.isFinite) else {
                    throw failure(.classificationFailure,tolerance,"Native integration has incomplete or nonfinite moment coverage.")
                }
            }
            return evaluation
        }
        func push(_ index: Int) {
            heap.append(index)
            var position = heap.count-1
            while position > 0 {
                let parent = (position-1)/2
                guard nodes[heap[position]].score > nodes[heap[parent]].score else { break }
                heap.swapAt(position,parent); position = parent
            }
        }
        func pop() -> Int? {
            guard !heap.isEmpty else { return nil }
            let first = heap[0], last = heap.removeLast()
            if !heap.isEmpty {
                heap[0] = last
                var position = 0
                while position*2+1 < heap.count {
                    var child = position*2+1
                    if child+1 < heap.count, nodes[heap[child+1]].score > nodes[heap[child]].score { child += 1 }
                    guard nodes[heap[child]].score > nodes[heap[position]].score else { break }
                    heap.swapAt(position,child); position = child
                }
            }
            return first
        }
        func combined(_ left: Evaluation, _ right: Evaluation) -> Evaluation {
            guard let a = left.contribution, let b = right.contribution else {
                return Evaluation(contribution:nil,splitT:true)
            }
            return Evaluation(contribution:zip(a,b).map { $0.0+$0.1 },splitT:true)
        }
        for cell in cells {
            let value = try process(cell)
            let index = nodes.count
            nodes.append(Node(parent:nil,children:nil,cell:cell,evaluation:value,score:score(value)))
            level.append(index); push(index)
        }
        // Balanced aggregation avoids repeatedly summing all leaves and retains
        // outward rounding through every mutation. At most 2*processedCells-1
        // records exist; the heap contains at most processedCells live leaves.
        while level.count > 1 {
            var next: [Int] = []
            var offset = 0
            while offset < level.count {
                guard offset+1 < level.count else { next.append(level[offset]); break }
                let left = level[offset], right = level[offset+1], parent = nodes.count
                let value = combined(nodes[left].evaluation,nodes[right].evaluation)
                nodes.append(Node(parent:nil,children:(left,right),cell:nil,evaluation:value,score:0))
                nodes[left].parent = parent; nodes[right].parent = parent
                next.append(parent); offset += 2
            }
            level = next
        }
        let root = level[0]
        while true {
            if let total = nodes[root].evaluation.contribution,
               zip(total,goals).allSatisfy({ ($0.0.width*0.5).nextUp <= $0.1 }) {
                return total
            }
            guard let index = pop(), let cell = nodes[index].cell else {
                throw failure(.classificationFailure,tolerance,"Native area uncertainty has no refinable leaf.")
            }
            guard cell.depth < options.maximumSubdivisionDepth else {
                throw failure(.resourceLimitExceeded,tolerance,"Native area integration reached its shared subdivision depth limit.")
            }
            let splitT = nodes[index].evaluation.splitT
            let interval = splitT ? cell.t : cell.r
            let middle = interval.midpoint
            guard middle > interval.lower, middle < interval.upper else {
                throw failure(.classificationFailure,tolerance,"Native area integration reached floating-point resolution.")
            }
            let first = try ScalarInterval(lower:interval.lower,upper:middle)
            let last = try ScalarInterval(lower:middle,upper:interval.upper)
            let leftCell = Cell(t:splitT ? first : cell.t,r:splitT ? cell.r : first,depth:cell.depth+1,
                rectangle:cell.rectangle,domain:cell.domain)
            let rightCell = Cell(t:splitT ? last : cell.t,r:splitT ? cell.r : last,depth:cell.depth+1,
                rectangle:cell.rectangle,domain:cell.domain)
            let leftValue = try process(leftCell), rightValue = try process(rightCell)
            let left = nodes.count, right = left+1
            nodes.append(Node(parent:index,children:nil,cell:leftCell,evaluation:leftValue,score:score(leftValue)))
            nodes.append(Node(parent:index,children:nil,cell:rightCell,evaluation:rightValue,score:score(rightValue)))
            nodes[index].children = (left,right)
            nodes[index].evaluation = combined(leftValue,rightValue)
            push(left); push(right)
            var parent = nodes[index].parent
            while let current = parent {
                guard let children = nodes[current].children else {
                    throw failure(.classificationFailure,tolerance,"Native integral aggregation lost its owned child records.")
                }
                nodes[current].evaluation = combined(nodes[children.0].evaluation,nodes[children.1].evaluation)
                parent = nodes[current].parent
            }
        }
    }

    private func failure(_ code: KernelErrorCode, _ tolerance: ModelingTolerance, _ message: String) -> KernelError {
        KernelError(phase:.topology,code:code,tolerance:tolerance,message:message)
    }
}

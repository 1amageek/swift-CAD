/// One connected regular component produced by pseudo-arclength continuation.
/// Closure is continuation topology, not a property that downstream consumers
/// may infer from spatially coincident endpoints.
struct ParametricSurfaceIntersectionTracedComponent: Sendable {
  let samples: [ParametricSurfaceIntersectionSample]
  let isClosed: Bool
}

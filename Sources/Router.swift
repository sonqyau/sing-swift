import Foundation

struct Router: Sendable {
    private let routes: [String: RouteConfiguration]
    private let fallback: String?

    init(routes: [RouteConfiguration], fallback: String?) {
        var storage: [String: RouteConfiguration] = [:]
        storage.reserveCapacity(routes.count)

        for route in routes {
            precondition(!route.key.isEmpty, "route key must not be empty")
            precondition(!route.outbound.isEmpty, "route outbound must not be empty")
            storage[route.key] = route
        }

        self.routes = storage
        self.fallback = fallback
    }

    func resolve(pipeline: PipelineConfiguration) throws -> String {
        if let outbound = pipeline.outboundTag, !outbound.isEmpty {
            return outbound
        }

        if let key = pipeline.routeKey, let route = routes[key] {
            return route.outbound
        }

        if let fallback {
            return fallback
        }

        throw Error.routeMissing(pipeline.routeKey ?? "default")
    }
}

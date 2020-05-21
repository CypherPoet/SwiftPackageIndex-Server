import Fluent
import Foundation
import Vapor


extension PackageShow.Model {
    static func query(database: Database, packageId: Package.Id) -> EventLoopFuture<Self> {
        Package.query(on: database)
            .with(\.$repositories)
            .with(\.$versions) { $0.with(\.$products) }
            .filter(\.$id == packageId)
            .first()
            .unwrap(or: Abort(.notFound))
            .map { p -> Self? in
                // we consider certain attributes as essential and return nil (raising .notFound)
                guard let title = p.name else { return nil }
                return Self.init(title: title,
                                 url: p.url,
                                 license: p.repository?.license ?? .none,
                                 summary: p.repository?.summary ?? "–",
                                 authors: [],      // TODO: fill in
                                 history: nil,     // TODO: fill in
                                 activity: nil,    // TODO: fill in
                                 products: p.productCounts,
                                 releases: .init(stable: nil, beta: nil, latest: nil),  // TODO: fill in
                                 languagePlatforms: .init(
                                    stable: .init(
                                        link: .init(name: "stable", url: "stable"),  // TODO: fill in
                                        swiftVersions: [],                           // TODO: fill in
                                        platforms: []),                              // TODO: fill in
                                    beta: .init(
                                        link: .init(name: "beta", url: "beta"),      // TODO: fill in
                                        swiftVersions: [],                           // TODO: fill in
                                        platforms: []),                              // TODO: fill in
                                    latest: .init(
                                        link: .init(name: "latest", url: "latest"),  // TODO: fill in
                                        swiftVersions: [],                           // TODO: fill in
                                        platforms: [])))                             // TODO: fill in
            }
            .unwrap(or: Abort(.notFound))
    }
}


private extension Package {
    // keep this private, because it requires relationships to be eagerly loaded
    // we do this above but in order to ensure this not being called from elsewhere
    // where this isn't guaranteed, we keep this extension off limits
    var defaultVersion: Version? {
        versions.first(where: { $0.reference?.isBranch ?? false })
    }

    var name: String? { defaultVersion?.packageName }

    var productCounts: PackageShow.Model.ProductCounts? {
        guard let version = defaultVersion else { return nil }
        return .init(
            libraries: version.products.filter(\.isLibrary).count,
            executables: version.products.filter(\.isExecutable).count
        )
    }
}

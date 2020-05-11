import Fluent

struct CreateVersion: Migration {
    func prepare(on database: Database) -> EventLoopFuture<Void> {
        return database.schema("versions")
            .id()
            .field("created_at", .datetime)
            .field("updated_at", .datetime)
            .field("package_id", .uuid, .references("packages", "id", onDelete: .cascade))
            .field("reference", .json)
            .field("package_name", .string)
            .field("commit", .string)
            .field("supported_platforms", .array(of: .json))
            .field("swift_versions", .array(of: .string))
            .create()
    }

    func revert(on database: Database) -> EventLoopFuture<Void> {
        return database.schema("versions").delete()
    }
}
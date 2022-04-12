import SQLKit
import Vapor


actor TestSchema {
    var isMigrated = false
    var tableNamesCache: [String]?

    func autoMigrate(on app: Application) async throws {
        guard !isMigrated else { return }
        try await app.autoMigrate()
        isMigrated = true
    }

    func resetDB(on app: Application) async throws {
        guard let db = app.db as? SQLDatabase else {
            fatalError("Database must be an SQLDatabase ('as? SQLDatabase' must succeed)")
        }

        guard let tables = tableNamesCache else {
            struct Row: Decodable { var table_name: String }
            tableNamesCache = try await db.raw("""
                    SELECT table_name FROM
                    information_schema.tables
                    WHERE
                      table_schema NOT IN ('pg_catalog', 'information_schema', 'public._fluent_migrations')
                      AND table_schema NOT LIKE 'pg_toast%'
                      AND table_name NOT LIKE '_fluent_%'
                    """)
                .all(decoding: Row.self)
                .map(\.table_name)
            if tableNamesCache != nil {
                try await resetDB(on: app)
            }
            return
        }

        for table in tables {
            try await db.raw("TRUNCATE TABLE \(raw: table) CASCADE").run()
        }
    }
}


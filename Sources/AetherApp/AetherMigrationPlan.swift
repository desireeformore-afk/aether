import SwiftData
import AetherCore

enum AetherMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [AetherSchemaV1.self]
    }
    static var stages: [MigrationStage] {
        []
    }
}

enum AetherSchemaV1: VersionedSchema {
    static var versionIdentifier: Schema.Version {
        Schema.Version(1, 0, 0)
    }

    static var models: [any PersistentModel.Type] {
        [PlaylistRecord.self, FavoriteRecord.self, WatchHistoryRecord.self]
    }
}

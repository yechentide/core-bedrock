//
// Created by yechentide on 2025/09/04
//

import Foundation

enum NetEasePlayerDataProcessor {
    static func processPlayerData(
        worldDir: String,
        transform: (Data) throws -> Data?
    ) throws {
        let dbDirPath = (worldDir as NSString).appendingPathComponent("db")
        let database = try LevelDB(dbPath: dbDirPath, createIfMissing: false)
        defer { database.close() }

        do {
            let localPlayerKey = LvDBStringKeyType.localPlayer.rawValue.data(using: .utf8)!
            let localPlayerData = try database.data(forKey: localPlayerKey)
            try autoreleasepool {
                try Task.checkCancellation()
                if let fixedData = try transform(localPlayerData) {
                    try database.putData(fixedData, forKey: localPlayerKey)
                }
            }
        } catch {
            let lvdbError = LvDBError(nsError: error as NSError)
            guard case LvDBError.notFound = lvdbError else {
                throw error
            }
        }

        let iter = try database.makeIterator()
        defer { iter.close() }
        let playerPrefix = Data(NetEaseConstants.playerKeyPrefix.utf8)
        iter.move(to: playerPrefix)
        while iter.isValid {
            try Task.checkCancellation()
            defer { iter.moveToNext() }
            // NetEase also stores player_uid_ records and ID mappings under player_.
            // Scan the entire prefix; valid mappings require no transformation.
            guard
                let key = iter.currentKey,
                key.starts(with: playerPrefix),
                let serverPlayerData = iter.currentValue
            else {
                break
            }

            try autoreleasepool {
                if let fixedData = try transform(serverPlayerData) {
                    try Task.checkCancellation()
                    try database.putData(fixedData, forKey: key)
                }
            }
        }
    }
}

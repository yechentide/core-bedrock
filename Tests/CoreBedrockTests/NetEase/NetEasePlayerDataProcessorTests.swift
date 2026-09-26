@testable import CoreBedrock
import Foundation
import Testing

struct NetEasePlayerDataProcessorTests {
    @Test(.withEmptyDirectory, arguments: [true, false])
    func convertsAllPlayerRecordsAndPreservesMappings(includeLocalPlayer: Bool) throws {
        let worldPath = EmptyDirectoryTrait.Context.directoryPath
        let dbPath = "\(worldPath)/db"
        let bedrockData = try CompoundTag([
            ByteArrayTag(name: "scriptData", [0x11, 0x22, 0x33]),
        ]).toData()
        let encoded = try NetEaseNBTTransform.patchEncodedPlayerData(bedrockData)
        let neteaseData = try #require(encoded)
        var playerKeys = [
            "player_server_00000000-0000-4000-8000-000000000001",
            "player_uid_2855639031",
            "player_uid_2924597660",
        ]
        if includeLocalPlayer {
            playerKeys.append("~local_player")
        }
        let mapping = try CompoundTag([
            StringTag(name: "NeteaseUUID", "2855639031"),
            StringTag(name: "ServerId", playerKeys[0]),
        ]).toData()
        let untouched = [
            "player_00000000-0000-4000-8000-000024bc74db": mapping,
            "player_2855639031": mapping,
            "player_t_mapping": mapping,
            "player": neteaseData,
            "playerX_unrelated": neteaseData,
            "player`_unrelated": neteaseData,
        ]
        do {
            let db = try LevelDB(dbPath: dbPath, createIfMissing: true)
            defer { db.close() }
            for key in playerKeys {
                try db.putData(neteaseData, forKey: Data(key.utf8))
            }
            for (key, value) in untouched {
                try db.putData(value, forKey: Data(key.utf8))
            }
        }

        try NetEaseWorldTransform.decryptPlayerData(at: worldPath)
        try NetEaseWorldTransform.decryptPlayerData(at: worldPath)
        try self.verifyRecords(at: dbPath, playerKeys: playerKeys, expected: bedrockData, untouched: untouched)

        try NetEaseWorldTransform.encryptPlayerData(at: worldPath)
        try self.verifyRecords(at: dbPath, playerKeys: playerKeys, expected: neteaseData, untouched: untouched)
    }

    private func verifyRecords(
        at dbPath: String,
        playerKeys: [String],
        expected: Data,
        untouched: [String: Data]
    ) throws {
        let db = try LevelDB(dbPath: dbPath, createIfMissing: false)
        defer { db.close() }
        for key in playerKeys {
            #expect(try db.data(forKey: Data(key.utf8)) == expected)
        }
        for (key, value) in untouched {
            #expect(try db.data(forKey: Data(key.utf8)) == value)
        }
    }
}

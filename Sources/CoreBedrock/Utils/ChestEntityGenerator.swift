//
// Created by yechentide on 2025/11/20
//

public enum ChestEntityGenerator {
    static let capacity = 27

    static func place(database: LevelKeyValueStore, x: Int32, y: Int32, z: Int32, items: [CompoundTag]) throws {
        try self.addBlockPalette(database: database, x: x, y: y, z: z)
        try self.addBlockEntityData(database: database, x: x, y: y, z: z, items: items)
    }

    private static func addBlockPalette(database: LevelKeyValueStore, x: Int32, y: Int32, z: Int32) throws {
        let chunkX = convertPos(from: x, .blockToChunk)
        let chunkZ = convertPos(from: z, .blockToChunk)
        let chunkY = Int8(truncatingIfNeeded: convertPos(from: y, .blockToChunk))
        let subchunkKey = LvDBKey.subChunk(chunkX, chunkZ, .overworld, .subChunkPrefix, chunkY).data
        let subchunkData = try database.data(forKey: subchunkKey)
        var subchunk = try ExpandedSubChunk(data: subchunkData, chunkY: chunkY)
        let chestPalette = try CompoundTag([
            StringTag(name: "name", "minecraft:chest"),
            CompoundTag(name: "states", [
                StringTag(name: "minecraft:cardinal_direction", "south"),
            ]),
            IntTag(name: "version", ItemGenerator.BlockMeta.defaultVersion),
        ])
        subchunk.blockLayer.place(localX: Int(x) % 16, localY: Int(y) % 16, localZ: Int(z) % 16, block: chestPalette)
        let newData = try subchunk.toData()
        try database.putData(newData, forKey: subchunkKey)
    }

    private static func addBlockEntityData(
        database: LevelKeyValueStore, x: Int32, y: Int32, z: Int32, items: [CompoundTag]
    ) throws {
        let packedItems: [CompoundTag]
        if items.count > Self.capacity {
            let shulkerBox = try ShulkerNestingPacker.pack(items: items)
            packedItems = [shulkerBox]
        } else {
            packedItems = items
        }
        let itemsTag = try ListTag(name: "Items", packedItems)
        let blockEntity = try CompoundTag([
            StringTag(name: "id", "Chest"),
            IntTag(name: "x", x),
            IntTag(name: "y", y),
            IntTag(name: "z", z),
            ByteTag(name: "Findable", 0),
            ByteTag(name: "isMovable", 0),
            // Large Chest Only
            // ByteTag(name: "pairlead", 0),
            // IntTag(name: "pairx", 0),
            // IntTag(name: "pairz", 0),
            itemsTag,
        ])
        let blockEntityData = try blockEntity.toData()

        let chunkX = convertPos(from: x, .blockToChunk)
        let chunkZ = convertPos(from: z, .blockToChunk)
        let blockEntityKey = LvDBKey.subChunk(chunkX, chunkZ, .overworld, .blockEntity, nil).data
        if database.containsKey(blockEntityKey) {
            let existingData = try database.data(forKey: blockEntityKey)
            let reader = CBTagReader(data: existingData)
            var existingEntities = try reader.readAll()
            existingEntities = existingEntities.filter { entity in
                guard let compoundTag = entity as? CompoundTag,
                      compoundTag["x"]?.intValue == x,
                      compoundTag["y"]?.intValue == y,
                      compoundTag["z"]?.intValue == z
                else {
                    return true
                }

                return false
            }
            let writer = CBTagWriter()
            try writer.write(tags: existingEntities)
            let fixedExistingData = writer.toData()
            try database.putData(fixedExistingData + blockEntityData, forKey: blockEntityKey)
        } else {
            try database.putData(blockEntityData, forKey: blockEntityKey)
        }
    }
}

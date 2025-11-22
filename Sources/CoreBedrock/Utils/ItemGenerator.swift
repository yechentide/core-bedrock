//
// Created by yechentide on 2025/11/20
//

public enum ItemGenerator {
    public struct BlockMeta {
        static let defaultVersion: Int32 = 18_168_865
        let states: [NBT]
        let version: Int32
    }

    public struct ItemMeta {
        let slot: UInt8
        let type: String
        let name: String?
        let count: UInt8
        let damage: Int16
        let wasPickedUp: Bool
        var tags: [NBT]
        var blockMeta: BlockMeta?

        public static func map(
            slot: UInt8,
            mapID: Int64,
            type: String = "minecraft:filled_map",
            name: String? = nil
        ) -> Self {
            Self(slot: slot, type: type, name: name, count: 1, damage: 0, wasPickedUp: false, tags: [
                ByteTag(name: "map_display_players", 1),
                IntTag(name: "map_name_index", 1),
                LongTag(name: "map_uuid", mapID),
            ])
        }

        public static func shulkerBox(
            slot: UInt8,
            type: String = "minecraft:undyed_shulker_box",
            name: String? = nil,
            items: [CompoundTag]
        ) throws -> Self {
            let innerItemsTag = try ListTag(name: "Items", items)
            return Self(
                slot: slot,
                type: type,
                name: name,
                count: 1,
                damage: 0,
                wasPickedUp: false,
                tags: [innerItemsTag],
                blockMeta: .init(states: [], version: BlockMeta.defaultVersion)
            )
        }
    }

    public static func generate(_ meta: ItemMeta) throws -> CompoundTag {
        let itemTag = try CompoundTag([
            ByteTag(name: "Slot", meta.slot),
            StringTag(name: "Name", meta.type),
            ByteTag(name: "Count", meta.count),
            ShortTag(name: "Damage", meta.damage),
            ByteTag(name: "WasPickedUp", meta.wasPickedUp ? 1 : 0),
        ])

        let tags = try CompoundTag(name: "tag", meta.tags)
        if let name = meta.name {
            let displayTag = try CompoundTag(name: "display", [
                StringTag(name: "Name", name),
            ])
            try tags.append(displayTag)
        }
        if !tags.isEmpty {
            try itemTag.append(tags)
        }

        if let blockMeta = meta.blockMeta {
            let blockMetaTag = try CompoundTag([
                StringTag(name: "name", meta.type),
                IntTag(name: "version", blockMeta.version),
                CompoundTag(name: "states", blockMeta.states),
            ])
            try itemTag.append(blockMetaTag)
        }

        return itemTag
    }
}

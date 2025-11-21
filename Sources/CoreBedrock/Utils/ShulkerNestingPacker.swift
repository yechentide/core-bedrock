//
// Created by yechentide on 2025/11/21
//

public enum ShulkerNestingPacker {
    private static let capacity = 27

    /// Packs items into shulker boxes with automatic nesting when count exceeds capacity.
    /// - Parameters:
    ///   - items: Array of CompoundTag items to pack
    ///   - rootSlot: Slot number for the outermost shulker box (default: 0). Nested shulkers always use slot 0.
    ///   - rootName: Optional name for the outermost shulker box (default: nil). Nested shulkers have no name.
    /// - Returns: A CompoundTag representing a shulker box containing the packed items
    /// - Throws: If item generation or tag operations fail
    public static func pack(items: [CompoundTag], rootSlot: UInt8 = 0, rootName: String? = nil) throws -> CompoundTag {
        try self.pack(items: items, slot: rootSlot, name: rootName, isRoot: true)
    }

    /// Private helper for recursive packing with slot/name control.
    /// - Parameters:
    ///   - items: Array of CompoundTag items to pack
    ///   - slot: Slot number for this shulker box
    ///   - name: Optional name for this shulker box
    ///   - isRoot: Whether this is the root/outermost shulker box
    /// - Returns: A CompoundTag representing a shulker box containing the packed items
    /// - Throws: If item generation or tag operations fail
    private static func pack(items: [CompoundTag], slot: UInt8, name: String?, isRoot: Bool) throws -> CompoundTag {
        if items.count <= self.capacity {
            // Base case: items fit in a single shulker box
            let slottedItems = try assignSlots(to: items)
            return try ItemGenerator.generate(.shulkerBox(slot: slot, name: name, items: slottedItems))
        } else {
            // Recursive case: split into chunks and nest
            let chunks = self.chunk(array: items, size: self.capacity)
            let nestedShulkers = try chunks.map { chunk in
                try self.pack(items: chunk, slot: 0, name: nil, isRoot: false)
            }
            // Recursively pack the shulker boxes with original root parameters
            return try self.pack(items: nestedShulkers, slot: slot, name: name, isRoot: isRoot)
        }
    }

    /// Clones items and assigns sequential Slot tags starting from 0.
    /// - Parameter items: Original items to process
    /// - Returns: New array with cloned items having sequential Slot tags
    /// - Throws: If cloning or tag operations fail
    private static func assignSlots(to items: [CompoundTag]) throws -> [CompoundTag] {
        try items.enumerated().map { index, item in
            let cloned = try CompoundTag(from: item)
            _ = cloned.remove(forKey: "Slot")
            try cloned.append(ByteTag(name: "Slot", UInt8(index)))
            return cloned
        }
    }

    /// Splits an array into chunks of specified size.
    /// - Parameters:
    ///   - array: Array to split
    ///   - size: Maximum size of each chunk
    /// - Returns: Array of chunks
    private static func chunk<T>(array: [T], size: Int) -> [[T]] {
        stride(from: 0, to: array.count, by: size).map {
            Array(array[$0..<min($0 + size, array.count)])
        }
    }
}

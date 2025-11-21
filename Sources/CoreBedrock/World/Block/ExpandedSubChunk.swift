//
// Created by yechentide on 2025/11/20
//

import Foundation

public struct ExpandedSubChunk {
    public let version: Int
    public let chunkY: Int8

    public var blockLayer: ExpandedBlockLayer
    public var liquidLayer: ExpandedBlockLayer?

    public init(version: Int, chunkY: Int8, blockLayer: ExpandedBlockLayer, liquidLayer: ExpandedBlockLayer? = nil) {
        self.version = version
        self.chunkY = chunkY
        self.blockLayer = blockLayer
        self.liquidLayer = liquidLayer
    }

    public init(data: Data, chunkY: Int8) throws {
        let subchunkParser = SubChunkParser(data: data, chunkY: chunkY)
        guard let packed = try subchunkParser.parsePackedLayer() else {
            throw CBError.failedParseSubchunk
        }

        self.init(packed: packed)
    }

    public init(packed: PackedSubChunk) {
        self.version = packed.version
        self.chunkY = packed.chunkY
        self.blockLayer = ExpandedBlockLayer(packedLayer: packed.blockLayer)

        guard let packedLiquidLayer = packed.liquidLayer,
              !packedLiquidLayer.palette.isEmpty,
              !packedLiquidLayer.indicesBytes.isEmpty
        else {
            self.liquidLayer = nil
            return
        }

        self.liquidLayer = ExpandedBlockLayer(packedLayer: packedLiquidLayer)
    }

    public func toData() throws -> Data {
        let writer = CBBinaryWriter()

        // Determine layer count
        let hasLiquid = self.liquidLayer != nil
            && !(self.liquidLayer?.palette.isEmpty ?? true)
            && !(self.liquidLayer?.indices.isEmpty ?? true)
        let layerCount: UInt8 = hasLiquid ? 2 : 1

        // Write header
        try writer.write(UInt8(self.version))
        try writer.write(layerCount)
        try writer.write(self.chunkY)

        // Write block layer
        try Self.writeLayer(self.blockLayer, to: writer)

        // Write liquid layer if present
        if hasLiquid, let liquid = liquidLayer {
            try Self.writeLayer(liquid, to: writer)
        }

        return writer.data
    }

    private static func writeLayer(_ layer: ExpandedBlockLayer, to writer: CBBinaryWriter) throws {
        // Compute bitWidth from max palette index
        let maxIndex = layer.indices.max() ?? 0
        let bitWidth = max(1, min(CBBinaryReader.wordBitSize, maxIndex.bitWidth))

        guard bitWidth >= 1, bitWidth <= CBBinaryReader.wordBitSize else {
            throw CBStreamError.invalidFormat("Invalid bitWidth: \(bitWidth)")
        }

        // Pack indices into bytes
        let indicesBytes = try Self.packIndices(layer.indices, bitWidth: bitWidth, palette: layer.palette)

        // Write type byte
        let typeByte = UInt8((bitWidth << 1) | 0x01)
        try writer.write(typeByte)

        // Write packed indices
        try writer.write(indicesBytes)

        // Write palette count
        try writer.write(UInt32(layer.palette.count))

        // Write each block tag inline (CBTagReader expects inline tags, not separate buffers)
        let tagWriter = CBTagWriter()
        for block in layer.palette {
            try tagWriter.write(tag: block)
        }
        let tagData = tagWriter.toData()
        try writer.write([UInt8](tagData))
    }

    private static func packIndices(
        _ indices: [UInt16],
        bitWidth: Int,
        palette: [CompoundTag]
    ) throws -> [UInt8] {
        guard indices.count == MCSubChunk.totalBlockCount else {
            throw CBStreamError.argumentError("Indices count must be \(MCSubChunk.totalBlockCount)")
        }

        let valuesPerWord = CBBinaryReader.wordBitSize / bitWidth
        let wordCount = (MCSubChunk.totalBlockCount + valuesPerWord - 1) / valuesPerWord
        var indicesBytes = [UInt8](repeating: 0, count: wordCount * 4)

        let mask: UInt32 = (1 << bitWidth) - 1

        for linear in 0..<MCSubChunk.totalBlockCount {
            let paletteIndex = Int(indices[linear])

            // Validate palette index
            guard paletteIndex < palette.count else {
                throw CBStreamError.argumentOutOfRange(
                    "paletteIndex",
                    "Index \(paletteIndex) out of bounds for palette of size \(palette.count)"
                )
            }

            let wordIndex = linear / valuesPerWord
            let indexInWord = linear % valuesPerWord
            let bitOffset = indexInWord * bitWidth
            let byteOffset = wordIndex * 4

            // Read existing word (little-endian)
            var word: UInt32 = 0
            for i in 0..<4 {
                word |= UInt32(indicesBytes[byteOffset + i]) << (i * 8)
            }

            // Clear and set bits
            let clearMask = ~(mask << bitOffset)
            word = (word & clearMask) | (UInt32(paletteIndex) << bitOffset)

            // Write word back (little-endian)
            for i in 0..<4 {
                indicesBytes[byteOffset + i] = UInt8((word >> (i * 8)) & 0xFF)
            }
        }

        return indicesBytes
    }
}

public struct ExpandedBlockLayer {
    public private(set) var palette: [CompoundTag]
    public private(set) var indices: [UInt16]
    private var nameCache: [String: [Int]]

    public init(packedLayer: PackedBlockLayer) {
        self.palette = packedLayer.palette
        self.nameCache = [:]

        if let indices = packedLayer.unpackPaletteIndices() {
            self.indices = indices
        } else {
            self.indices = [UInt16](repeating: 0, count: MCSubChunk.totalBlockCount)
        }
    }

    public func block(localX: Int, localY: Int, localZ: Int) -> CompoundTag? {
        guard let linearIndex = MCSubChunk.linearIndex(localX, localY, localZ) else {
            return nil
        }

        let paletteIndex = Int(indices[linearIndex])
        guard paletteIndex < self.palette.count else {
            return nil
        }

        return self.palette[paletteIndex]
    }

    public mutating func place(localX: Int, localY: Int, localZ: Int, block: CompoundTag) {
        guard let linearIndex = MCSubChunk.linearIndex(localX, localY, localZ) else { return }

        let paletteIndex = self.ensurePaletteIndex(for: block)
        guard paletteIndex <= UInt16.max else { return }

        self.indices[linearIndex] = UInt16(paletteIndex)
    }

    // MARK: - Private Helpers

    private mutating func rebuildCacheIfNeeded() {
        guard self.nameCache.isEmpty else { return }

        var cache: [String: [Int]] = [:]
        for (index, block) in self.palette.enumerated() {
            guard let nameTag = block["name"] as? StringTag else { continue }

            let name = nameTag.value
            cache[name, default: []].append(index)
        }
        self.nameCache = cache
    }

    private mutating func ensurePaletteIndex(for block: CompoundTag) -> Int {
        self.rebuildCacheIfNeeded()

        // Try to find existing block by name first
        if let nameTag = block["name"] as? StringTag {
            let name = nameTag.value
            if let candidateIndices = nameCache[name] {
                // Only iterate the cached indices for this name
                for paletteIndex in candidateIndices where self.palette[paletteIndex] == block {
                    return paletteIndex
                }
            }

            // Not found, add to palette
            let newIndex = self.palette.count
            self.palette.append(block)
            self.nameCache[name, default: []].append(newIndex)
            return newIndex
        }

        // No name, just append
        let newIndex = self.palette.count
        self.palette.append(block)
        return newIndex
    }
}

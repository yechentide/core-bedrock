//
// Created by yechentide on 2025/09/19
//

import Foundation

struct PackedBiomeHeightColumn {
    let heightBytes: [UInt8] // 1 block = 2 bytes
    let biomeSections: [PackedBiomeSection]

    @inline(__always)
    func highestBlockY(atLocalX localX: Int, localZ: Int) -> UInt16? {
        guard MCSubChunk.localPosRange ~= localX, MCSubChunk.localPosRange ~= localZ else {
            return nil
        }

        let byteOffset = ((localX << 4) + localZ) << 1
        guard byteOffset + 1 < self.heightBytes.count else { return nil }

        return UInt16(self.heightBytes[byteOffset]) | (UInt16(self.heightBytes[byteOffset + 1]) << 8)
    }

    func biomeValue(atLocalX localX: Int, y: Int, localZ: Int) -> Int32? {
        let chunkY = Int8(truncatingIfNeeded: y >> 4)
        guard let subChunkBiome = biomeSections.first(where: { $0.chunkY == chunkY }) else {
            return nil
        }

        let localY = y % MCChunk.sideLength
        return subChunkBiome.paletteValue(localX: localX, localY: localY, localZ: localZ)
    }

    struct PackedBiomeSection: PackedPaletteReadable {
        let chunkY: Int8
        let bitWidth: Int
        let palette: [Int32]
        let indicesBytes: [UInt8]
    }
}

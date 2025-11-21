//
// Created by yechentide on 2025/09/19
//

public struct PackedSubChunk {
    public let version: Int
    public let chunkY: Int8

    public let blockLayer: PackedBlockLayer
    public let liquidLayer: PackedBlockLayer?
}

public struct PackedBlockLayer: PackedPaletteReadable {
    public let bitWidth: Int
    public let palette: [CompoundTag]
    public let indicesBytes: [UInt8]

    public func paletteValue(at linearIndex: Int) -> CompoundTag? {
        guard 0..<MCSubChunk.totalBlockCount ~= linearIndex else {
            return nil
        }

        let localX = (linearIndex >> 8) & 0xF
        let localZ = (linearIndex >> 4) & 0xF
        let localY = linearIndex & 0xF
        return self.paletteValue(localX: localX, localY: localY, localZ: localZ)
    }

    @inline(__always)
    func unsafeEnumerateColumnDescendingY(
        atLocalX localX: Int, localZ: Int, _ perform: (Int, CompoundTag) -> Bool
    ) {
        guard let baseIndex = MCSubChunk.linearIndex(localX, 0, localZ) else {
            return
        }

        let valuesPerWord = self.valuesPerWord
        let mask = self.indexBitMask

        self.indicesBytes.withUnsafeBytes { rawBuffer in
            guard let base = rawBuffer.baseAddress else { return }

            let words = base.assumingMemoryBound(to: UInt32.self)

            var currentWordIndex = -1
            var currentWord: UInt32 = 0

            for localY in stride(from: MCChunk.sideLength - 1, through: 0, by: -1) {
                let index = baseIndex + localY
                let wordIndex = index / valuesPerWord
                let indexInWord = index % valuesPerWord

                if wordIndex != currentWordIndex {
                    currentWord = words[wordIndex]
                    currentWordIndex = wordIndex
                }

                let paletteIndex = Int(mask & (currentWord >> (indexInWord * self.bitWidth)))
                guard paletteIndex < self.palette.count else { return }

                if perform(localY, self.palette[paletteIndex]) {
                    return
                }
            }
        }
    }
}

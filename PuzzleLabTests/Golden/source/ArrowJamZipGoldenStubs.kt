// Minimal stand-ins so ArrowModel.kt and ZipModel.kt compile unmodified on a plain JVM.
@file:Suppress("unused")

package com.ngstudio.puzzlelab.braingames.core

/** Copied from core/LevelPack.kt. */
enum class DifficultyTier(val title: String, val patchIndex: Int) {
    Easy("Easy", 3), Medium("Medium", 5), Hard("Hard", 1), Expert("Expert", 7), Master("Master", 6);

    companion object {
        fun parse(raw: String): DifficultyTier = entries.firstOrNull { it.name.equals(raw, ignoreCase = true) } ?: Easy
    }
}

/** Copied from core/LevelPack.kt. */
interface PackLevel {
    val id: Int
    val tier: DifficultyTier
    val sizeLabel: String
}

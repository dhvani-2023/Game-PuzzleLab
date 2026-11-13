@file:Suppress("unused")

package com.ngstudio.puzzlelab.braingames.features.play

/** Copied from features/play/GameShell.kt. */
interface PuzzleSession {
    val levelID: Int
    var elapsed: Int
    val hintsUsed: Int
    val isSolved: Boolean
    val canUndo: Boolean
    val canClear: Boolean
    val progress: Float
    val progressText: String
    val statusText: String
    val feedbackMessage: String?
    val errorCount: Int
    val actionCount: Int
    val revision: Int

    fun undo()
    fun clear()
    fun hint()
    fun clearFeedback()
    fun encodeState(): String?
}

package com.ngstudio.puzzlelab.braingames.games.boxbattle

import java.io.File
import kotlin.math.PI
import kotlin.math.cos
import kotlin.math.exp
import kotlin.math.sin
import kotlin.math.sqrt
import kotlin.random.Random

// Copied verbatim from BoxFx.kt.
fun springStep(t: Float, response: Float = 0.34f, damping: Float = 0.42f): Float {
    if (t <= 0f) return 0f
    val w = 2.0 * PI / response
    val z = damping.toDouble()
    val wd = w * sqrt(1 - z * z)
    return (1 - exp(-z * w * t) * (cos(wd * t) + z * w / wd * sin(wd * t))).toFloat()
}

// The point loop of BoxArt.kt `scribblePath`, verbatim except Rect/Offset are plain floats.
fun scribblePoints(left: Float, top: Float, right: Float, bottom: Float, seed: Int): List<Pair<Float, Float>> {
    val width = right - left
    val height = bottom - top
    val rnd = Random(seed)
    val n = 6
    val pts = ArrayList<Pair<Float, Float>>(n + 1)
    for (i in 0..n) {
        val k = i / 2
        val up = i % 2 == 1
        val u = (if (up) 0.27f * k + 0.25f else 0.27f * k - if (k > 0) 0.03f else 0f) / 0.79f
        val x = left + width * u + (rnd.nextFloat() - 0.5f) * width * 0.04f
        val y = if (up) top + height * rnd.nextFloat() * 0.16f else bottom - height * rnd.nextFloat() * 0.12f
        pts.add(x to y)
    }
    return pts
}

fun playGame(rows: Int, cols: Int, botYou: Int, botRival: Int, seed: Int): String {
    val m = BoxModel(rows, cols)
    val rng = Random(seed)
    var turn = Player.You
    val sb = StringBuilder()
    while (!m.isComplete) {
        val d = if (turn == Player.You) botYou else botRival
        val e = BoxBot.move(m, d, rng)
        sb.append(if (e.horizontal) 'h' else 'v').append(e.r).append('.').append(e.c).append(' ')
        val closed = m.draw(e, turn)
        if (closed == 0) turn = if (turn == Player.You) Player.Rival else Player.You
    }
    return sb.toString().trim() + "|" + m.scoreYou + "-" + m.scoreRival
}

/** Probes on a half-played board: safe count after and chain size for every legal edge. */
fun probes(rows: Int, cols: Int, seed: Int, plies: Int): String {
    val m = BoxModel(rows, cols)
    val rng = Random(seed)
    var turn = Player.You
    var n = 0
    while (!m.isComplete && n < plies) {
        val e = BoxBot.move(m, 1, rng)
        val closed = m.draw(e, turn)
        if (closed == 0) turn = if (turn == Player.You) Player.Rival else Player.You
        n++
    }
    val sb = StringBuilder()
    for (e in m.legalEdges()) {
        sb.append(if (e.horizontal) 'h' else 'v').append(e.r).append('.').append(e.c)
            .append('=').append(m.boxesClosedBy(e)).append(',').append(if (m.createsThreeSided(e)) 1 else 0)
            .append(',').append(m.safeCountAfter(e)).append(',').append(m.chainSizeOpenedBy(e)).append(' ')
    }
    return sb.toString().trim()
}

fun main(args: Array<String>) {
    val out = StringBuilder()
    out.append("{\n\"games\":[\n")
    val sizes = listOf(2 to 2, 2 to 3, 3 to 3, 3 to 4, 4 to 4, 5 to 5, 5 to 6, 6 to 6, 7 to 6, 7 to 7, 8 to 7, 8 to 8)
    var first = true
    for (d in -3..3) for ((r, c) in sizes) for (seed in listOf(1, 7, 2026, -5, 123456789)) {
        val rival = ((d + 3 + 4) % 7) - 3
        val trace = playGame(r, c, d, rival, seed)
        if (!first) out.append(",\n")
        first = false
        out.append("{\"rows\":$r,\"cols\":$c,\"you\":$d,\"rival\":$rival,\"seed\":$seed,\"trace\":\"$trace\"}")
    }
    out.append("\n],\n\"probes\":[\n")
    first = true
    for ((r, c) in sizes) for (seed in listOf(3, 99)) for (plies in listOf(4, 10, 20)) {
        if (!first) out.append(",\n")
        first = false
        out.append("{\"rows\":$r,\"cols\":$c,\"seed\":$seed,\"plies\":$plies,\"edges\":\"${probes(r, c, seed, plies)}\"}")
    }
    out.append("\n],\n\"scribbles\":[\n")
    first = true
    val rects = listOf(floatArrayOf(10f, 10.5f, 50f, 50f), floatArrayOf(113.27f, 87.1f, 158.9f, 131.4f), floatArrayOf(0f, 0f, 1f, 1f))
    for (rect in rects) for (r in 0 until 8) for (c in 0 until 8) {
        val seed = 31 * r + 7 * c + 11
        val pts = scribblePoints(rect[0], rect[1], rect[2], rect[3], seed)
        if (!first) out.append(",\n")
        first = false
        out.append("{\"seed\":$seed,\"rect\":[${rect.joinToString(",") { java.lang.Float.floatToRawIntBits(it).toString() }}],\"pts\":[")
        out.append(pts.joinToString(",") { "${java.lang.Float.floatToRawIntBits(it.first)},${java.lang.Float.floatToRawIntBits(it.second)}" })
        out.append("]}")
    }
    out.append("\n],\n\"springs\":[\n")
    first = true
    val params = listOf(0.34f to 0.42f, 0.3f to 0.5f, 0.32f to 0.38f, 0.3f to 0.35f, 0.36f to 0.32f, 0.22f to 0.5f)
    for ((resp, damp) in params) for (i in -2..60) {
        val t = i * 0.0173f
        val v = springStep(t, resp, damp)
        if (!first) out.append(",\n")
        first = false
        out.append("{\"t\":${java.lang.Float.floatToRawIntBits(t)},\"response\":${java.lang.Float.floatToRawIntBits(resp)},\"damping\":${java.lang.Float.floatToRawIntBits(damp)},\"v\":${java.lang.Float.floatToRawIntBits(v)}}")
    }
    out.append("\n]\n}\n")
    File(args[0]).writeText(out.toString())
}

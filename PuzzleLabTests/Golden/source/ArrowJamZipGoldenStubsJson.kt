@file:Suppress("unused")

package org.json

/**
 * A small org.json look-alike (the API surface ArrowModel.kt / ZipModel.kt use), with a
 * recursive-descent parser. Objects keep insertion order like Android's org.json.
 */
class JSONObject() {
    internal val map = LinkedHashMap<String, Any?>()

    constructor(text: String) : this() {
        val p = Parser(text)
        val v = p.value()
        if (v !is JSONObject) throw JSONException("not an object")
        map.putAll(v.map)
    }

    fun has(key: String) = map.containsKey(key)
    fun keys(): Iterator<String> = map.keys.iterator()
    fun getInt(key: String): Int = (map[key] as? Number)?.toInt() ?: (map[key] as? String)?.toInt() ?: throw JSONException("no int $key")
    fun optInt(key: String, fallback: Int = 0): Int = (map[key] as? Number)?.toInt() ?: (map[key] as? String)?.toIntOrNull() ?: fallback
    fun getString(key: String): String = map[key]?.let { if (it is String) it else it.toString() } ?: throw JSONException("no string $key")
    fun optString(key: String, fallback: String = ""): String = map[key]?.let { if (it is String) it else it.toString() } ?: fallback
    fun getJSONArray(key: String): JSONArray = map[key] as? JSONArray ?: throw JSONException("no array $key")
    fun optJSONArray(key: String): JSONArray? = map[key] as? JSONArray
    fun getJSONObject(key: String): JSONObject = map[key] as? JSONObject ?: throw JSONException("no object $key")
    fun put(key: String, value: Any?): JSONObject { map[key] = value; return this }
    override fun toString(): String = map.entries.joinToString(",", "{", "}") { (k, v) -> "\"$k\":${write(v)}" }
}

class JSONArray() {
    internal val list = ArrayList<Any?>()

    constructor(items: Collection<*>) : this() { list.addAll(items) }

    fun length() = list.size
    fun getInt(i: Int): Int = (list[i] as Number).toInt()
    fun getString(i: Int): String = list[i].let { if (it is String) it else it.toString() }
    fun getJSONArray(i: Int): JSONArray = list[i] as JSONArray
    fun getJSONObject(i: Int): JSONObject = list[i] as JSONObject
    override fun toString(): String = list.joinToString(",", "[", "]") { write(it) }
}

class JSONException(message: String) : RuntimeException(message)

private fun write(v: Any?): String = when (v) {
    null -> "null"
    is String -> "\"" + v.replace("\\", "\\\\").replace("\"", "\\\"") + "\""
    else -> v.toString()
}

private class Parser(val s: String) {
    var i = 0

    fun ws() { while (i < s.length && s[i].isWhitespace()) i++ }

    fun value(): Any? {
        ws()
        return when (val c = s[i]) {
            '{' -> obj()
            '[' -> arr()
            '"' -> str()
            't' -> { i += 4; true }
            'f' -> { i += 5; false }
            'n' -> { i += 4; null }
            else -> if (c == '-' || c.isDigit()) num() else throw JSONException("bad char $c at $i")
        }
    }

    fun obj(): JSONObject {
        val o = JSONObject()
        i++
        ws()
        if (s[i] == '}') { i++; return o }
        while (true) {
            ws()
            val k = str()
            ws()
            if (s[i] != ':') throw JSONException("expected : at $i")
            i++
            o.map[k] = value()
            ws()
            if (s[i] == ',') { i++; continue }
            if (s[i] == '}') { i++; return o }
            throw JSONException("bad object at $i")
        }
    }

    fun arr(): JSONArray {
        val a = JSONArray()
        i++
        ws()
        if (s[i] == ']') { i++; return a }
        while (true) {
            a.list.add(value())
            ws()
            if (s[i] == ',') { i++; continue }
            if (s[i] == ']') { i++; return a }
            throw JSONException("bad array at $i")
        }
    }

    fun str(): String {
        if (s[i] != '"') throw JSONException("expected string at $i")
        i++
        val b = StringBuilder()
        while (s[i] != '"') {
            val c = s[i]
            if (c == '\\') {
                val e = s[i + 1]
                i += 2
                when (e) {
                    'n' -> b.append('\n'); 't' -> b.append('\t'); 'r' -> b.append('\r'); 'b' -> b.append('\b'); 'f' -> b.append('\u000C')
                    'u' -> { b.append(s.substring(i, i + 4).toInt(16).toChar()); i += 4 }
                    else -> b.append(e)
                }
            } else { b.append(c); i++ }
        }
        i++
        return b.toString()
    }

    fun num(): Number {
        val start = i
        while (i < s.length && (s[i].isDigit() || s[i] in "+-.eE")) i++
        val t = s.substring(start, i)
        return if (t.any { it in ".eE" }) t.toDouble() else t.toLong().let { if (it in Int.MIN_VALUE..Int.MAX_VALUE) it.toInt() else it }
    }
}

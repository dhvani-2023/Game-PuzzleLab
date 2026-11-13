@file:Suppress("unused")

package androidx.compose.runtime

import kotlin.reflect.KProperty

/** Plain holders standing in for Compose snapshot state (no recomposition on a JVM). */
class MutableState<T>(var value: T)
class MutableIntState(var value: Int)

fun <T> mutableStateOf(value: T): MutableState<T> = MutableState(value)
fun mutableIntStateOf(value: Int): MutableIntState = MutableIntState(value)

operator fun <T> MutableState<T>.getValue(thisRef: Any?, property: KProperty<*>): T = value
operator fun <T> MutableState<T>.setValue(thisRef: Any?, property: KProperty<*>, v: T) { value = v }
operator fun MutableIntState.getValue(thisRef: Any?, property: KProperty<*>): Int = value
operator fun MutableIntState.setValue(thisRef: Any?, property: KProperty<*>, v: Int) { value = v }

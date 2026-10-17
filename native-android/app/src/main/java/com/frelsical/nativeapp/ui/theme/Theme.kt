package com.frelsical.nativeapp.ui.theme

import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Typography
import androidx.compose.material3.darkColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.toArgb

private val FrelsiColorScheme = darkColorScheme(
    primary = Color(0xFF6C63FF),
    onPrimary = Color.White,
    primaryContainer = Color(0xFF3A356F),
    onPrimaryContainer = Color(0xFFEDEBFF),
    secondary = Color(0xFF03DAC6),
    onSecondary = Color(0xFF00201C),
    background = Color(0xFF12121D),
    onBackground = Color.White,
    surface = Color(0xFF1E1E2C),
    onSurface = Color.White,
    surfaceVariant = Color(0xFF2A2A3C),
    onSurfaceVariant = Color(0xFFB9B9C9),
    outline = Color(0xFF4A4A5E),
    error = Color(0xFFFF4B4B),
)

@Composable
fun FrelsiTheme(content: @Composable () -> Unit) {
    MaterialTheme(
        colorScheme = FrelsiColorScheme,
        typography = Typography(),
        content = content,
    )
}

/** Accepts #RRGGBB and Apple's #RRGGBBAA calendar colors. */
fun parseCalendarColor(value: String?): Color {
    if (value.isNullOrBlank()) return FrelsiColorScheme.primary
    val hex = value.removePrefix("#").trim()
    return runCatching {
        when (hex.length) {
            6 -> Color(0xFF000000 or hex.toLong(16))
            8 -> {
                val red = hex.substring(0, 2).toInt(16)
                val green = hex.substring(2, 4).toInt(16)
                val blue = hex.substring(4, 6).toInt(16)
                val alpha = hex.substring(6, 8).toInt(16)
                Color(android.graphics.Color.argb(alpha, red, green, blue))
            }

            else -> FrelsiColorScheme.primary
        }
    }.getOrDefault(FrelsiColorScheme.primary)
}

/** CalDAV stores colors as #RRGGBBAA. */
fun calendarColorHex(color: Color): String {
    val argb = color.toArgb()
    return "#%02X%02X%02X%02X".format(
        android.graphics.Color.red(argb),
        android.graphics.Color.green(argb),
        android.graphics.Color.blue(argb),
        android.graphics.Color.alpha(argb),
    )
}

package com.portfolioassistant.app.widget

import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.DashPathEffect
import android.graphics.Paint
import android.graphics.Path

/**
 * Dibuja el gráfico del día (`v2.chart`, ya normalizado a 0..1) en un Bitmap
 * chico para `setImageViewBitmap` (RemoteViews no admite vistas custom).
 * Tamaños acotados (<= 600x160 px) por el límite de memoria de RemoteViews.
 * Es una forma, no un valor: no hay ejes ni números.
 */
object PortyChartBitmap {
    private fun dims(size: WidgetSize): Pair<Int, Int> = when (size) {
        WidgetSize.SMALL -> 240 to 56
        WidgetSize.MEDIUM -> 360 to 96
        WidgetSize.LARGE -> 600 to 120
    }

    fun render(chart: PortyFeedPicker.Chart, size: WidgetSize, lineColor: Int, baselineColor: Int): Bitmap {
        val (w, h) = dims(size)
        val bmp = Bitmap.createBitmap(w, h, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(bmp)
        val stroke = h / 28f + 2f
        val padX = stroke * 1.5f
        val padY = stroke * 1.5f
        fun x(i: Int) = padX + (w - 2 * padX) * i / (chart.points.size - 1).coerceAtLeast(1)
        // 1.0 arriba: el eje Y de Canvas crece hacia abajo.
        fun y(v: Double) = padY + (h - 2 * padY) * (1f - v.coerceIn(0.0, 1.0).toFloat())

        chart.baseline?.let { b ->
            val p = Paint(Paint.ANTI_ALIAS_FLAG).apply {
                color = baselineColor
                style = Paint.Style.STROKE
                strokeWidth = stroke * 0.5f
                pathEffect = DashPathEffect(floatArrayOf(stroke * 2, stroke * 2), 0f)
            }
            canvas.drawLine(padX, y(b), w - padX, y(b), p)
        }
        val path = Path()
        chart.points.forEachIndexed { i, v ->
            if (i == 0) path.moveTo(x(i), y(v)) else path.lineTo(x(i), y(v))
        }
        val line = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = lineColor
            style = Paint.Style.STROKE
            strokeWidth = stroke
            strokeCap = Paint.Cap.ROUND
            strokeJoin = Paint.Join.ROUND
        }
        canvas.drawPath(path, line)
        // El último punto es "ahora".
        val dot = Paint(Paint.ANTI_ALIAS_FLAG).apply { color = lineColor; style = Paint.Style.FILL }
        canvas.drawCircle(x(chart.points.size - 1), y(chart.points.last()), stroke * 1.4f, dot)
        return bmp
    }
}

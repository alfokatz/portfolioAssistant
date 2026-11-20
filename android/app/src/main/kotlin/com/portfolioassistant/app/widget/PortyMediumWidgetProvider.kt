package com.portfolioassistant.app.widget

import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import es.antonborri.home_widget.HomeWidgetProvider

/** Widget 4x2: cara + % + gráfico, una novedad con "siguiente" y una pregunta. */
class PortyMediumWidgetProvider : HomeWidgetProvider() {
    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        widgetData: SharedPreferences,
    ) {
        PortyWidgetRenderer.update(
            context, appWidgetManager, appWidgetIds, widgetData,
            size = WidgetSize.MEDIUM, provider = javaClass,
        )
    }

    /**
     * "Siguiente novedad" (§3.5): el PendingIntent es un broadcast explícito a
     * este receiver. Solo reacciona a la acción propia y no lee extras: un
     * broadcast ajeno a lo sumo avanza el índice. Todo lo demás, al padre.
     */
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action == PortyWidgetRenderer.ACTION_NEXT_NOVELTY) {
            val prefs = context.getSharedPreferences("HomeWidgetPreferences", Context.MODE_PRIVATE)
            PortyWidgetRenderer.advanceAndUpdate(context, prefs)
            return
        }
        super.onReceive(context, intent)
    }

    override fun onDisabled(context: Context) {
        super.onDisabled(context)
        PortyWidgetRenderer.cancelNext(context, javaClass)
    }
}

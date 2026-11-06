package com.portfolioassistant.app.widget

import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.SharedPreferences
import es.antonborri.home_widget.HomeWidgetProvider

/** Widget 4x2: lo del chico + frase + 2 preguntas rápidas. */
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

    override fun onDisabled(context: Context) {
        super.onDisabled(context)
        PortyWidgetRenderer.cancelNext(context, javaClass)
    }
}

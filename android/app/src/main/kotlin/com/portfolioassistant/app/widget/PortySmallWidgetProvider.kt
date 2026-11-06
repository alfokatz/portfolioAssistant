package com.portfolioassistant.app.widget

import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.SharedPreferences
import es.antonborri.home_widget.HomeWidgetProvider

/** Widget 2x2: valor, variación, período y "hace X". El nombre calificado lo usa la app (home_widget). */
class PortySmallWidgetProvider : HomeWidgetProvider() {
    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        widgetData: SharedPreferences,
    ) {
        PortyWidgetRenderer.update(
            context, appWidgetManager, appWidgetIds, widgetData,
            size = WidgetSize.SMALL, provider = javaClass,
        )
    }

    override fun onDisabled(context: Context) {
        super.onDisabled(context)
        PortyWidgetRenderer.cancelNext(context, javaClass)
    }
}

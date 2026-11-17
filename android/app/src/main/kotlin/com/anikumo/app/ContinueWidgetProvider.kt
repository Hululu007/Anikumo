package com.anikumo.app

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetProvider

/**
 * Batch 276 (#61): the "继续观看" home-screen widget.
 * Data is published from Dart (HomeWidgetPublisher)
 * into the plugin's shared preferences; this provider
 * only renders it. Tapping opens the app.
 */
class ContinueWidgetProvider : HomeWidgetProvider() {
    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        widgetData: SharedPreferences,
    ) {
        val title = widgetData.getString("hw_title", null) ?: "Anikumo"
        val subtitle = widgetData.getString("hw_subtitle", null) ?: ""
        val launchIntent = Intent(context, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
        }
        val pendingIntent = PendingIntent.getActivity(
            context,
            0,
            launchIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        for (id in appWidgetIds) {
            val views = RemoteViews(context.packageName, R.layout.continue_widget)
            views.setTextViewText(R.id.hw_title, title)
            views.setTextViewText(R.id.hw_subtitle, subtitle)
            views.setOnClickPendingIntent(R.id.hw_root, pendingIntent)
            appWidgetManager.updateAppWidget(id, views)
        }
    }
}

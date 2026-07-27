package com.bantaymuscles.bantaymuscles

import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.SharedPreferences
import android.net.Uri
import android.os.Bundle
import android.view.View
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetLaunchIntent
import es.antonborri.home_widget.HomeWidgetPlugin
import es.antonborri.home_widget.HomeWidgetProvider

/// Home-screen widget: today's calories, macros and steps, with a quick-add tap.
/// Data is written from Flutter (see lib/widget_service.dart); this only binds
/// it to the layout and adapts to the widget's size.
class BmWidgetProvider : HomeWidgetProvider() {

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        widgetData: SharedPreferences
    ) {
        for (id in appWidgetIds) {
            render(context, appWidgetManager, id, widgetData)
        }
    }

    // Re-render when the user resizes the widget, so sections show/hide.
    override fun onAppWidgetOptionsChanged(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetId: Int,
        newOptions: Bundle
    ) {
        render(context, appWidgetManager, appWidgetId, HomeWidgetPlugin.getData(context))
    }

    private fun render(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetId: Int,
        data: SharedPreferences
    ) {
        val views = RemoteViews(context.packageName, R.layout.bm_widget)

        views.setTextViewText(R.id.cal_left, data.getString("cal_left", "0"))
        views.setTextViewText(R.id.cal_label, data.getString("cal_label", "kcal left"))
        views.setTextViewText(R.id.cal_sub, data.getString("cal_sub", "0 / 0 kcal"))
        views.setProgressBar(R.id.cal_bar, 100, data.getInt("cal_progress", 0), false)

        views.setTextViewText(R.id.p_text, data.getString("p_text", "P 0/0g"))
        views.setProgressBar(R.id.p_bar, 100, data.getInt("p_progress", 0), false)
        views.setTextViewText(R.id.c_text, data.getString("c_text", "C 0/0g"))
        views.setProgressBar(R.id.c_bar, 100, data.getInt("c_progress", 0), false)
        views.setTextViewText(R.id.f_text, data.getString("f_text", "F 0/0g"))
        views.setProgressBar(R.id.f_bar, 100, data.getInt("f_progress", 0), false)

        views.setTextViewText(R.id.steps_text, data.getString("steps_text", "0 steps"))

        // Size-responsive: on a short widget, show only the calorie summary.
        val minHeight = appWidgetManager.getAppWidgetOptions(appWidgetId)
            .getInt(AppWidgetManager.OPTION_APPWIDGET_MIN_HEIGHT, 110)
        val compact = minHeight < 140
        views.setViewVisibility(R.id.macros_section, if (compact) View.GONE else View.VISIBLE)
        views.setViewVisibility(R.id.steps_text, if (compact) View.GONE else View.VISIBLE)

        // Tapping the widget (or the pill) opens the app to the Add screen.
        val pending = HomeWidgetLaunchIntent.getActivity(
            context,
            MainActivity::class.java,
            Uri.parse("bantaymuscles://add")
        )
        views.setOnClickPendingIntent(R.id.widget_root, pending)
        views.setOnClickPendingIntent(R.id.add_button, pending)

        appWidgetManager.updateAppWidget(appWidgetId, views)
    }
}

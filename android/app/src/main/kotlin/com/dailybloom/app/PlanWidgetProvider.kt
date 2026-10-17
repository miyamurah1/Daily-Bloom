package com.dailybloom.app

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.net.Uri
import android.os.Build
import android.view.View
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetLaunchIntent
import es.antonborri.home_widget.HomeWidgetProvider

/**
 * "Today's plan" home-screen widget: the top-3 plan rows Flutter pushes
 * via [PlanWidgetBridge.pushPlan]. Each row deep-links to its task
 * (`dailybloom://task/<id>`); the header opens today's plan.
 *
 * Distinct PendingIntent request codes per row: the plugin helper reuses
 * requestCode 0, which would collapse all three rows onto one task.
 */
class PlanWidgetProvider : HomeWidgetProvider() {

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        widgetData: SharedPreferences,
    ) {
        appWidgetIds.forEach { widgetId ->
            val views =
                RemoteViews(context.packageName, R.layout.plan_widget).apply {
                    setOnClickPendingIntent(
                        R.id.widget_container,
                        launchIntent(context, 100, Uri.parse("dailybloom://plan")),
                    )

                    // Streak + progress line; hidden until Dart pushes one.
                    val stats = widgetData.getString("widget_stats", "") ?: ""
                    if (stats.isEmpty()) {
                        setViewVisibility(R.id.plan_stats, View.GONE)
                    } else {
                        setViewVisibility(R.id.plan_stats, View.VISIBLE)
                        setTextViewText(R.id.plan_stats, stats)
                    }

                    val count = widgetData.getInt("plan_count", 0)
                    val rows = listOf(
                        RowViews(R.id.plan_row_0, R.id.plan_title_0, R.id.plan_reason_0, R.id.plan_check_0),
                        RowViews(R.id.plan_row_1, R.id.plan_title_1, R.id.plan_reason_1, R.id.plan_check_1),
                        RowViews(R.id.plan_row_2, R.id.plan_title_2, R.id.plan_reason_2, R.id.plan_check_2),
                    )
                    if (count <= 0) {
                        setViewVisibility(R.id.plan_empty, View.VISIBLE)
                        rows.forEach { setViewVisibility(it.row, View.GONE) }
                    } else {
                        setViewVisibility(R.id.plan_empty, View.GONE)
                        rows.forEachIndexed { i, row ->
                            if (i < count) {
                                setViewVisibility(row.row, View.VISIBLE)
                                val done =
                                    widgetData.getBoolean("plan_${i}_done", false)
                                val title =
                                    widgetData.getString("plan_${i}_title", "")
                                        ?: ""
                                val reason =
                                    widgetData.getString("plan_${i}_reason", "")
                                        ?: ""
                                val id =
                                    widgetData.getString("plan_${i}_id", "")
                                        ?: ""
                                setTextViewText(
                                    row.title,
                                    (if (done) "✓ " else "${i + 1}. ") + title,
                                )
                                setTextViewText(row.reason, reason)
                                setOnClickPendingIntent(
                                    row.row,
                                    launchIntent(
                                        context,
                                        i,
                                        Uri.parse("dailybloom://task/$id"),
                                    ),
                                )
                                // One-tap completion from the launcher.
                                // Done rows drop the button (the ✓ prefix
                                // already says it); its PendingIntent uses
                                // a 200+i request code so it never collapses
                                // onto the row's own tap intent.
                                if (done || id.isEmpty()) {
                                    setViewVisibility(row.check, View.GONE)
                                } else {
                                    setViewVisibility(row.check, View.VISIBLE)
                                    setOnClickPendingIntent(
                                        row.check,
                                        launchIntent(
                                            context,
                                            200 + i,
                                            Uri.parse("dailybloom://complete/$id"),
                                        ),
                                    )
                                }
                            } else {
                                setViewVisibility(row.row, View.GONE)
                            }
                        }
                    }
                }

            appWidgetManager.updateAppWidget(widgetId, views)
        }
    }

    /**
     * Same semantics as the plugin's launch helper, but with a caller
     * request code so per-row task taps don't collapse onto each other.
     */
    private fun launchIntent(context: Context, requestCode: Int, uri: Uri): PendingIntent {
        val intent = Intent(context, MainActivity::class.java)
        intent.data = uri
        intent.action = HomeWidgetLaunchIntent.HOME_WIDGET_LAUNCH_ACTION
        var flags = PendingIntent.FLAG_UPDATE_CURRENT
        if (Build.VERSION.SDK_INT >= 23) {
            flags = flags or PendingIntent.FLAG_IMMUTABLE
        }
        return PendingIntent.getActivity(context, requestCode, intent, flags)
    }

    private data class RowViews(val row: Int, val title: Int, val reason: Int, val check: Int)
}

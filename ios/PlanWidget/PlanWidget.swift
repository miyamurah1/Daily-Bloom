//
//  PlanWidget.swift
//  PlanWidget
//
//  "Today's plan" home-screen widget: the top-3 plan rows Flutter pushes
//  via PlanWidgetBridge into the shared App Group defaults. Each row
//  links to its task (`dailybloom://task/<id>`); the header opens the plan.
//

import SwiftUI
import WidgetKit

private let widgetGroupId = "group.com.dailybloom.app.plan"

struct PlanRow: Identifiable {
  let id: String
  let title: String
  let reason: String
  let done: Bool
}

struct PlanEntry: TimelineEntry {
  let date: Date
  let rows: [PlanRow]
  /// Streak + progress line ("Day 12 · 2 done · 3 open"). Empty = hidden.
  let stats: String
}

private func readStats() -> String {
  UserDefaults(suiteName: widgetGroupId)?.string(forKey: "widget_stats") ?? ""
}

private func readPlan() -> [PlanRow] {
  let data = UserDefaults(suiteName: widgetGroupId)
  let count = data?.integer(forKey: "plan_count") ?? 0
  guard count > 0 else { return [] }
  return (0..<min(count, 3)).compactMap { i in
    let title = data?.string(forKey: "plan_\(i)_title") ?? ""
    guard !title.isEmpty else { return nil }
    return PlanRow(
      id: data?.string(forKey: "plan_\(i)_id") ?? "",
      title: title,
      reason: data?.string(forKey: "plan_\(i)_reason") ?? "",
      done: data?.bool(forKey: "plan_\(i)_done") ?? false
    )
  }
}

struct PlanProvider: TimelineProvider {
  func placeholder(in context: Context) -> PlanEntry {
    PlanEntry(date: Date(), stats: "Day 12 · 2 done · 3 open", rows: [
      PlanRow(id: "", title: "Prepare demo slides", reason: "due soon", done: false),
      PlanRow(id: "", title: "Grocery run", reason: "small win", done: false),
    ])
  }

  func getSnapshot(in context: Context, completion: @escaping (PlanEntry) -> Void) {
    let rows = readPlan()
    let stats = readStats()
    if rows.isEmpty && context.isPreview {
      completion(placeholder(in: context))
    } else {
      completion(PlanEntry(date: Date(), rows: rows, stats: stats))
    }
  }

  func getTimeline(in context: Context, completion: @escaping (Timeline<PlanEntry>) -> Void) {
    getSnapshot(in: context) { entry in
      completion(Timeline(entries: [entry], policy: .atEnd))
    }
  }
}

struct PlanWidgetEntryView: View {
  var entry: PlanProvider.Entry

  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      Link(destination: URL(string: "dailybloom://plan")!) {
        Text("TODAY'S PLAN")
          .font(.system(size: 10, weight: .semibold))
          .tracking(1.6)
          .foregroundColor(Color(red: 0.91, green: 0.29, blue: 0.42))
      }
      if !entry.stats.isEmpty {
        Text(entry.stats)
          .font(.system(size: 11))
          .foregroundColor(Color(red: 0.65, green: 0.62, blue: 0.77))
          .lineLimit(1)
      }
      if entry.rows.isEmpty {
        Text("No plan yet — open Bloom to plan.")
          .font(.system(size: 13))
          .foregroundColor(Color(red: 0.65, green: 0.62, blue: 0.77))
      } else {
        ForEach(entry.rows) { row in
          Link(destination: URL(string: "dailybloom://task/\(row.id)")!) {
            VStack(alignment: .leading, spacing: 1) {
              Text("\(row.done ? "✓ " : "")\(row.title)")
                .font(.system(size: 13.5, weight: .bold))
                .foregroundColor(.white)
                .lineLimit(1)
              Text(row.reason)
                .font(.system(size: 11))
                .foregroundColor(Color(red: 0.65, green: 0.62, blue: 0.77))
                .lineLimit(1)
            }
          }
        }
      }
    }
    .padding(14)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    .background(Color(red: 0.12, green: 0.10, blue: 0.18))
  }
}

@main
struct PlanWidget: Widget {
  let kind: String = "PlanWidget"

  var body: some WidgetConfiguration {
    StaticConfiguration(kind: kind, provider: PlanProvider()) { entry in
      PlanWidgetEntryView(entry: entry)
    }
    .configurationDisplayName("Today's plan")
    .description("Your top-3 from Daily Bloom. Tap a task to open it.")
    .supportedFamilies([.systemSmall, .systemMedium])
  }
}

// Copyright 2020 The Brave Authors. All rights reserved.
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import WidgetKit
import SwiftUI
import Shared
import BraveShared

struct StatsEntry: TimelineEntry {
    var date: Date
    var statData: [StatData]
}

struct StatsProvider: TimelineProvider {
    typealias Entry = StatsEntry
    
    var stats: [StatData] {
        let kinds: [StatKind] = [.adsBlocked, .httpsUpgrades, .timeSaved]
        return kinds.map { StatData(name: $0.name, value: $0.displayString, color: $0.valueColor) }
    }
    
    func placeholder(in context: Context) -> Entry {
        Entry(date: Date(), statData: [])
    }
    func getSnapshot(in context: Context, completion: @escaping (Entry) -> Void) {
        let entry = Entry(date: Date(), statData: stats)
        completion(entry)
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<Entry>) -> Void) {
        let entry = Entry(date: Date(), statData: stats)
        let timeline = Timeline(entries: [entry], policy: .never)
        completion(timeline)
    }
}

struct PlaceholderStatsView: View {
    var entry: StatsEntry
    
    var body: some View {
        StatsView(entry: entry)
            .redacted(reason: .placeholder)
    }
}

struct StatsView: View {
    var entry: StatsEntry
    @ScaledMetric private var fontSize: CGFloat = 32
    
    var body: some View {
        HStack(alignment: .top) {
            ForEach(entry.statData, id: \.name) { data in
                VStack(spacing: 4) {
                    Text(verbatim: data.value)
                        .font(.system(size: fontSize))
                        .foregroundColor(Color(data.color))
                        .multilineTextAlignment(.center)
                    Text(verbatim: data.name)
                        .font(.footnote)
                        .fontWeight(.semibold)
                        .foregroundColor(.white)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(6)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(10)
        .background(Color(white: 0.25))
    }
}

struct StatsWidget: Widget {
    let kind: String = "StatsWidget"
    
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: StatsProvider()) { entry in
            StatsView(entry: entry)
        }
        .supportedFamilies([.systemMedium])
        .configurationDisplayName("Shields Stats")
        .description("Displays all shields stats")
    }
}

struct StatsWidget_Previews: PreviewProvider {
    static var stats: [StatData] {
        let kinds: [StatKind] = [.adsBlocked, .httpsUpgrades, .timeSaved]
        return kinds.map { StatData(name: $0.name, value: $0.displayString, color: $0.valueColor) }
    }
    
    static var previews: some View {
        StatsView(entry: StatsEntry(date: Date(), statData: stats))
            .previewContext(WidgetPreviewContext(family: .systemMedium))
        StatsView(entry: StatsEntry(date: Date(), statData: stats))
            .redacted(reason: .placeholder)
            .previewContext(WidgetPreviewContext(family: .systemMedium))
    }
}

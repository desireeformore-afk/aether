import WidgetKit
import SwiftUI

struct AetherWidget: Widget {
    let kind: String = "AetherWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: Provider()) { entry in
            AetherWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("Now Playing")
        .description("Shows the currently playing channel")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct Provider: TimelineProvider {
    func placeholder(in context: Context) -> SimpleEntry {
        SimpleEntry(date: Date(), channelName: "BBC News", channelLogo: nil)
    }

    func getSnapshot(in context: Context, completion: @escaping (SimpleEntry) -> ()) {
        let entry = SimpleEntry(date: Date(), channelName: "BBC News", channelLogo: nil)
        completion(entry)
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<Entry>) -> ()) {
        let currentChannel = UserDefaults(suiteName: "group.com.aether.app")?.string(forKey: "currentChannel") ?? "No channel"
        let entry = SimpleEntry(date: Date(), channelName: currentChannel, channelLogo: nil)
        let timeline = Timeline(entries: [entry], policy: .after(Date().addingTimeInterval(60)))
        completion(timeline)
    }
}

struct SimpleEntry: TimelineEntry {
    let date: Date
    let channelName: String
    let channelLogo: String?
}

struct AetherWidgetEntryView : View {
    var entry: Provider.Entry

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(red: 0.1, green: 0.1, blue: 0.2), Color(red: 0.2, green: 0.1, blue: 0.3)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: "play.tv.fill")
                        .font(.title2)
                        .foregroundStyle(.white)
                    Spacer()
                }
                
                Spacer()
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("NOW PLAYING")
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.7))
                    
                    Text(entry.channelName)
                        .font(.headline)
                        .foregroundStyle(.white)
                        .lineLimit(2)
                }
            }
            .padding()
        }
    }
}

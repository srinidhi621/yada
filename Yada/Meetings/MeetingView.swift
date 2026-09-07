import SwiftUI

struct MeetingView: View {
    @Bindable var meeting: MeetingController
    let dictation: SessionController
    let language: LanguageSetup
    @State private var confirmDelete = false
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Meetings").font(.largeTitle.bold())
                Text("Record locally, then transcribe. Meeting audio is saved until you delete it; ordinary dictation still saves no audio.")
                Label(meeting.state.rawValue, systemImage: meeting.capturing ? "record.circle.fill" : "waveform")
                    .foregroundStyle(meeting.capturing ? .red : .secondary)
                Picker("Audio process", selection: $meeting.selectedID) {
                    Text("Choose a process").tag(UInt32(0))
                    ForEach(meeting.applications, id: \.id) { app in
                        Text("\(app.name) (PID \(app.pid))").tag(app.id)
                    }
                }.disabled(meeting.busy)
                Button("Refresh audio processes") { meeting.refreshApplications() }.disabled(meeting.busy || UIValidation.isEnabled)
                Text("Select the process playing your meeting audio. Some apps use helper processes. Browser capture may include other tabs in that process. Use headphones to avoid recording the same speech twice.").font(.caption)
                Toggle("I have permission from the participants to record", isOn: $meeting.consent).disabled(meeting.busy)
                HStack {
                    Button("Record meeting") { meeting.start(dictationBusy: dictation.busy) }
                        .disabled(meeting.busy || dictation.busy || !meeting.consent || meeting.selectedID == 0 || UIValidation.isEnabled)
                    if meeting.state == .recording { Button("Pause") { meeting.pause() } }
                    if meeting.state == .paused { Button("Resume") { meeting.resume() } }
                    if meeting.state == .recording || meeting.state == .paused { Button("Stop and save") { meeting.stop() } }
                }
                if meeting.busy {
                    Text("Elapsed timeline: \(Int(meeting.elapsed)) seconds").monospacedDigit()
                    Text("Local microphone").font(.caption)
                    ProgressView(value: Double(meeting.microphoneLevel))
                    Text("Selected app audio").font(.caption)
                    ProgressView(value: Double(meeting.remoteLevel))
                    Text("Silence in the selected-app meter can mean the wrong process was chosen. Muting in your meeting app does not mute Yada; use Pause here.").font(.caption)
                }
                Text(meeting.message).textSelection(.enabled)
                if meeting.directory != nil {
                    HStack {
                        Button("Transcribe saved audio") { meeting.transcribe(locale: language.locale) }.disabled(meeting.busy || UIValidation.isEnabled)
                        if meeting.state == .transcribing { Button("Cancel transcription") { meeting.cancelTranscription() } }
                        Button("Show files / export") { if let directory = meeting.directory { NSWorkspace.shared.open(directory) } }.disabled(meeting.busy)
                        Button("Delete meeting", role: .destructive) { confirmDelete = true }.disabled(meeting.busy)
                    }
                    if !meeting.transcript.isEmpty { Text(meeting.transcript).textSelection(.enabled) }
                }
                Divider()
                Text("Saved meetings").font(.headline)
                ForEach(meeting.savedDirectories(), id: \.self) { directory in
                    Button((try? directory.resourceValues(forKeys: [.creationDateKey]).creationDate)?.formatted(date: .abbreviated, time: .shortened) ?? "Saved meeting") { meeting.openSaved(directory) }.disabled(meeting.busy)
                }
                Text("This first version transcribes short chunks independently. Review words near chunk boundaries. Labels identify audio tracks, not people. Speaker recognition and meeting summaries come later.").font(.caption).foregroundStyle(.secondary)
            }.padding(24)
        }
        .confirmationDialog("Delete this meeting's audio and transcript?", isPresented: $confirmDelete) {
            Button("Delete permanently", role: .destructive) { meeting.deleteCurrent() }
        }
    }
}

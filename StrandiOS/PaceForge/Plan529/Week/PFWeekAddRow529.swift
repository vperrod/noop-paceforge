import SwiftUI
import StrandDesign

/// The two buttons at the top of Plan > Week: "+ Add workout" (the Add form: day, sport, name, minutes and a large description, optionally every
/// week) and, next to it, "Log a workout I did". The bottom buttons of the page stay as they were.
struct PFWeekAddRow529: View {
    /// The day a new workout starts on; empty falls back to today inside the form.
    let addDate: String

    @State private var form: PFOwnForm529?

    var body: some View {
        LookFlowLayout(spacing: 6, lineSpacing: 6) {
            PFWeekButton529(title: "+ Add workout", isProminent: true, identifier: "plan529-add-workout") { form = .addSession }
            PFWeekButton529(title: "Log a workout I did", identifier: "plan529-log-did") { form = .logWorkout }
        }
        .sheet(item: $form) { form in
            switch form {
            case .addSession: PFAddSessionSheet529(startDate: addDate) { NotificationCenter.default.post(name: .pfPlan529Changed, object: nil) }
            case .logWorkout: PFLogWorkoutSheet529 { NotificationCenter.default.post(name: .pfPlan529Changed, object: nil) }
            }
        }
        .containerIdentifier("plan529-top-buttons")
    }
}

/// The small "+" on a day's header: the Add form with that day filled in.
struct PFDayAddButton529: View {
    let date: String

    @State private var isOpen = false

    var body: some View {
        Button { isOpen = true } label: {
            Image(systemName: "plus")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(PFWeekColor529.teal)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Add a workout on this day")
        .accessibilityIdentifier("plan529-day-add-\(date)")
        .sheet(isPresented: $isOpen) {
            PFAddSessionSheet529(startDate: date) { NotificationCenter.default.post(name: .pfPlan529Changed, object: nil) }
        }
    }
}

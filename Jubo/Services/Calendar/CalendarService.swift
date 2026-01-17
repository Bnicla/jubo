//
//  CalendarService.swift
//  Jubo
//
//  Service for accessing calendar events and reminders via EventKit.
//  All data stays on-device - no cloud sync required.
//
//  Permissions:
//  - NSCalendarsUsageDescription in Info.plist
//  - NSRemindersUsageDescription in Info.plist
//

import Foundation
import EventKit

/// Service for accessing user's calendar and reminders.
///
/// Usage:
/// ```swift
/// let service = CalendarService()
/// if await service.requestAccess() {
///     let events = await service.fetchTodayEvents()
///     let context = service.formatForLLM(events: events, query: "What's on my schedule?")
/// }
/// ```
@MainActor
class CalendarService: ObservableObject {

    // MARK: - Types

    /// Simplified event data for LLM context.
    struct CalendarEvent: Identifiable {
        let id: String
        let title: String
        let startDate: Date
        let endDate: Date
        let isAllDay: Bool
        let location: String?
        let notes: String?
        let calendarName: String
    }

    /// Simplified reminder data for LLM context.
    struct ReminderItem: Identifiable {
        let id: String
        let title: String
        let dueDate: Date?
        let isCompleted: Bool
        let priority: Int  // 0 = none, 1 = high, 5 = medium, 9 = low
        let notes: String?
        let listName: String
    }

    /// Authorization status for calendar/reminders.
    enum AuthorizationStatus {
        case notDetermined
        case authorized
        case denied
        case restricted
    }

    // MARK: - Properties

    private let eventStore = EKEventStore()

    @Published private(set) var calendarAuthStatus: AuthorizationStatus = .notDetermined
    @Published private(set) var reminderAuthStatus: AuthorizationStatus = .notDetermined

    // Date formatters
    private let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        return formatter
    }()

    private let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE, MMM d"
        return formatter
    }()

    private let relativeDateFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter
    }()

    // MARK: - Initialization

    init() {
        updateAuthorizationStatus()
    }

    // MARK: - Authorization

    /// Request access to calendars.
    /// Returns true if access was granted.
    func requestCalendarAccess() async -> Bool {
        do {
            let granted = try await eventStore.requestFullAccessToEvents()
            updateAuthorizationStatus()
            return granted
        } catch {
            print("[Calendar] Access request failed: \(error)")
            return false
        }
    }

    /// Request access to reminders.
    /// Returns true if access was granted.
    func requestReminderAccess() async -> Bool {
        do {
            let granted = try await eventStore.requestFullAccessToReminders()
            updateAuthorizationStatus()
            return granted
        } catch {
            print("[Calendar] Reminder access request failed: \(error)")
            return false
        }
    }

    /// Request access to both calendars and reminders.
    func requestFullAccess() async -> (calendar: Bool, reminders: Bool) {
        async let calendarAccess = requestCalendarAccess()
        async let reminderAccess = requestReminderAccess()
        return await (calendarAccess, reminderAccess)
    }

    /// Check if calendar access is authorized.
    var hasCalendarAccess: Bool {
        calendarAuthStatus == .authorized
    }

    /// Check if reminder access is authorized.
    var hasReminderAccess: Bool {
        reminderAuthStatus == .authorized
    }

    private func updateAuthorizationStatus() {
        // Calendar status
        switch EKEventStore.authorizationStatus(for: .event) {
        case .notDetermined:
            calendarAuthStatus = .notDetermined
        case .fullAccess, .writeOnly:
            calendarAuthStatus = .authorized
        case .denied:
            calendarAuthStatus = .denied
        case .restricted:
            calendarAuthStatus = .restricted
        @unknown default:
            calendarAuthStatus = .denied
        }

        // Reminder status
        switch EKEventStore.authorizationStatus(for: .reminder) {
        case .notDetermined:
            reminderAuthStatus = .notDetermined
        case .fullAccess, .writeOnly:
            reminderAuthStatus = .authorized
        case .denied:
            reminderAuthStatus = .denied
        case .restricted:
            reminderAuthStatus = .restricted
        @unknown default:
            reminderAuthStatus = .denied
        }
    }

    // MARK: - Fetch Events

    /// Fetch events for today.
    func fetchTodayEvents() async -> [CalendarEvent] {
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: Date())
        let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay)!

        return await fetchEvents(from: startOfDay, to: endOfDay)
    }

    /// Fetch events for tomorrow.
    func fetchTomorrowEvents() async -> [CalendarEvent] {
        let calendar = Calendar.current
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: Date())!
        let startOfDay = calendar.startOfDay(for: tomorrow)
        let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay)!

        return await fetchEvents(from: startOfDay, to: endOfDay)
    }

    /// Fetch events for this week.
    func fetchThisWeekEvents() async -> [CalendarEvent] {
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: Date())
        let endOfWeek = calendar.date(byAdding: .day, value: 7, to: startOfDay)!

        return await fetchEvents(from: startOfDay, to: endOfWeek)
    }

    /// Fetch events for a specific date range.
    func fetchEvents(from startDate: Date, to endDate: Date) async -> [CalendarEvent] {
        guard hasCalendarAccess else {
            print("[Calendar] No calendar access")
            return []
        }

        let calendars = eventStore.calendars(for: .event)
        let predicate = eventStore.predicateForEvents(withStart: startDate, end: endDate, calendars: calendars)
        let ekEvents = eventStore.events(matching: predicate)

        return ekEvents.map { event in
            CalendarEvent(
                id: event.eventIdentifier,
                title: event.title ?? "Untitled",
                startDate: event.startDate,
                endDate: event.endDate,
                isAllDay: event.isAllDay,
                location: event.location,
                notes: event.notes,
                calendarName: event.calendar.title
            )
        }.sorted { $0.startDate < $1.startDate }
    }

    // MARK: - Fetch Reminders

    /// Fetch incomplete reminders due today or overdue.
    func fetchTodayReminders() async -> [ReminderItem] {
        guard hasReminderAccess else {
            print("[Calendar] No reminder access")
            return []
        }

        let calendars = eventStore.calendars(for: .reminder)
        let predicate = eventStore.predicateForIncompleteReminders(
            withDueDateStarting: nil,
            ending: Calendar.current.date(byAdding: .day, value: 1, to: Date()),
            calendars: calendars
        )

        return await withCheckedContinuation { continuation in
            eventStore.fetchReminders(matching: predicate) { reminders in
                let items = (reminders ?? []).map { reminder in
                    ReminderItem(
                        id: reminder.calendarItemIdentifier,
                        title: reminder.title ?? "Untitled",
                        dueDate: reminder.dueDateComponents?.date,
                        isCompleted: reminder.isCompleted,
                        priority: reminder.priority,
                        notes: reminder.notes,
                        listName: reminder.calendar.title
                    )
                }
                continuation.resume(returning: items)
            }
        }
    }

    /// Fetch all incomplete reminders.
    func fetchAllIncompleteReminders() async -> [ReminderItem] {
        guard hasReminderAccess else { return [] }

        let calendars = eventStore.calendars(for: .reminder)
        let predicate = eventStore.predicateForIncompleteReminders(
            withDueDateStarting: nil,
            ending: nil,
            calendars: calendars
        )

        return await withCheckedContinuation { continuation in
            eventStore.fetchReminders(matching: predicate) { reminders in
                let items = (reminders ?? []).map { reminder in
                    ReminderItem(
                        id: reminder.calendarItemIdentifier,
                        title: reminder.title ?? "Untitled",
                        dueDate: reminder.dueDateComponents?.date,
                        isCompleted: reminder.isCompleted,
                        priority: reminder.priority,
                        notes: reminder.notes,
                        listName: reminder.calendar.title
                    )
                }
                continuation.resume(returning: items)
            }
        }
    }

    // MARK: - Create Reminder

    /// Create a new reminder.
    /// - Parameters:
    ///   - title: The reminder title
    ///   - dueDate: Optional due date
    ///   - notes: Optional notes
    /// - Returns: True if created successfully
    func createReminder(title: String, dueDate: Date? = nil, notes: String? = nil) async -> Bool {
        guard hasReminderAccess else {
            print("[Calendar] No reminder access for creating")
            return false
        }

        let reminder = EKReminder(eventStore: eventStore)
        reminder.title = title
        reminder.notes = notes

        if let dueDate = dueDate {
            reminder.dueDateComponents = Calendar.current.dateComponents(
                [.year, .month, .day, .hour, .minute],
                from: dueDate
            )
        }

        // Use default reminders calendar
        reminder.calendar = eventStore.defaultCalendarForNewReminders()

        do {
            try eventStore.save(reminder, commit: true)
            print("[Calendar] Created reminder: \(title)")
            return true
        } catch {
            print("[Calendar] Failed to create reminder: \(error)")
            return false
        }
    }

    // MARK: - LLM Context Formatting

    /// Format events for LLM context injection.
    func formatEventsForLLM(events: [CalendarEvent], query: String, dateDescription: String) -> String {
        var parts: [String] = []

        if events.isEmpty {
            parts.append("[CALENDAR - \(dateDescription.uppercased())]")
            parts.append("No events scheduled.")
        } else {
            parts.append("[CALENDAR - \(dateDescription.uppercased())]")

            for event in events {
                var eventLine = "• "
                if event.isAllDay {
                    eventLine += "[All Day] "
                } else {
                    eventLine += "[\(timeFormatter.string(from: event.startDate))] "
                }
                eventLine += event.title

                if let location = event.location, !location.isEmpty {
                    eventLine += " @ \(location)"
                }

                parts.append(eventLine)
            }
        }

        parts.append("")
        parts.append("Based on this calendar data, answer: \(query)")

        return parts.joined(separator: "\n")
    }

    /// Format reminders for LLM context injection.
    func formatRemindersForLLM(reminders: [ReminderItem], query: String) -> String {
        var parts: [String] = []

        if reminders.isEmpty {
            parts.append("[REMINDERS]")
            parts.append("No pending reminders.")
        } else {
            parts.append("[REMINDERS - \(reminders.count) pending]")

            for reminder in reminders.prefix(10) {  // Limit to 10 for context size
                var line = "• \(reminder.title)"

                if let dueDate = reminder.dueDate {
                    let relative = relativeDateFormatter.localizedString(for: dueDate, relativeTo: Date())
                    line += " (due \(relative))"
                }

                if reminder.priority == 1 {
                    line += " ⚠️ High priority"
                }

                parts.append(line)
            }

            if reminders.count > 10 {
                parts.append("... and \(reminders.count - 10) more")
            }
        }

        parts.append("")
        parts.append("Based on these reminders, answer: \(query)")

        return parts.joined(separator: "\n")
    }

    /// Format combined calendar and reminders for a daily summary.
    func formatDailySummaryForLLM(events: [CalendarEvent], reminders: [ReminderItem], query: String) -> String {
        var parts: [String] = []

        // Events section
        parts.append("[TODAY'S SCHEDULE]")
        if events.isEmpty {
            parts.append("No events scheduled today.")
        } else {
            for event in events {
                var eventLine = "• "
                if event.isAllDay {
                    eventLine += "[All Day] "
                } else {
                    eventLine += "[\(timeFormatter.string(from: event.startDate))] "
                }
                eventLine += event.title
                if let location = event.location, !location.isEmpty {
                    eventLine += " @ \(location)"
                }
                parts.append(eventLine)
            }
        }

        // Reminders section
        parts.append("")
        parts.append("[PENDING REMINDERS]")
        if reminders.isEmpty {
            parts.append("No pending reminders.")
        } else {
            for reminder in reminders.prefix(5) {
                var line = "• \(reminder.title)"
                if let dueDate = reminder.dueDate {
                    line += " (due: \(dateFormatter.string(from: dueDate)))"
                }
                parts.append(line)
            }
        }

        parts.append("")
        parts.append("Based on this schedule, answer: \(query)")

        return parts.joined(separator: "\n")
    }
}

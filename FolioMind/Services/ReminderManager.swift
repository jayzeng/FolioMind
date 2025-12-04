//
//  ReminderManager.swift
//  FolioMind
//
//  Manages reminders and calendar events using EventKit for document-related actions.
//

import Foundation
import EventKit

@MainActor
final class ReminderManager {
    private let eventStore = EKEventStore()

    enum ReminderError: LocalizedError {
        case permissionDenied
        case creationFailed(String)
        case notFound

        var errorDescription: String? {
            switch self {
            case .permissionDenied:
                return "Permission to access reminders was denied. Please enable in Settings."
            case .creationFailed(let reason):
                return "Failed to create reminder: \(reason)"
            case .notFound:
                return "Reminder not found in system."
            }
        }
    }

    // MARK: - Permission Management

    func requestPermission() async -> Bool {
        if #available(iOS 17.0, *) {
            do {
                return try await eventStore.requestFullAccessToReminders()
            } catch {
                print("Error requesting reminders permission: \(error)")
                return false
            }
        } else {
            return await withCheckedContinuation { continuation in
                eventStore.requestAccess(to: .reminder) { granted, error in
                    if let error = error {
                        print("Error requesting reminders access: \(error)")
                    }
                    continuation.resume(returning: granted)
                }
            }
        }
    }

    func checkPermission() -> Bool {
        let status = EKEventStore.authorizationStatus(for: .reminder)
        if #available(iOS 17.0, *) {
            return status == .fullAccess || status == .writeOnly || status == .authorized
        } else {
            return status == .authorized
        }
    }

    // MARK: - Reminder Creation

    func createReminder(
        title: String,
        notes: String?,
        dueDate: Date,
        priority: Int = 0
    ) async throws -> String {
        guard checkPermission() else {
            throw ReminderError.permissionDenied
        }

        let reminder = EKReminder(eventStore: eventStore)
        reminder.title = title
        reminder.notes = notes
        reminder.calendar = eventStore.defaultCalendarForNewReminders()

        // Set due date
        let dateComponents = Calendar.current.dateComponents(
            [.year, .month, .day, .hour, .minute],
            from: dueDate
        )
        reminder.dueDateComponents = dateComponents

        // Set priority (0 = None, 1 = High, 5 = Medium, 9 = Low)
        reminder.priority = priority

        do {
            try eventStore.save(reminder, commit: true)
            return reminder.calendarItemIdentifier
        } catch {
            throw ReminderError.creationFailed(error.localizedDescription)
        }
    }

    func updateReminder(
        eventKitID: String,
        title: String,
        notes: String?,
        dueDate: Date,
        priority: Int = 0
    ) async throws {
        guard checkPermission() else {
            throw ReminderError.permissionDenied
        }

        guard let reminder = eventStore.calendarItem(withIdentifier: eventKitID) as? EKReminder else {
            throw ReminderError.notFound
        }

        reminder.title = title
        reminder.notes = notes
        reminder.calendar = eventStore.defaultCalendarForNewReminders()

        let dateComponents = Calendar.current.dateComponents(
            [.year, .month, .day, .hour, .minute],
            from: dueDate
        )
        reminder.dueDateComponents = dateComponents
        reminder.priority = priority

        do {
            try eventStore.save(reminder, commit: true)
        } catch {
            throw ReminderError.creationFailed(error.localizedDescription)
        }
    }

    func createCalendarEvent(
        title: String,
        notes: String?,
        startDate: Date,
        duration: TimeInterval = 3600 // 1 hour default
    ) async throws -> String {
        guard checkPermission() else {
            throw ReminderError.permissionDenied
        }

        let event = EKEvent(eventStore: eventStore)
        event.title = title
        event.notes = notes
        event.startDate = startDate
        event.endDate = startDate.addingTimeInterval(duration)
        event.calendar = eventStore.defaultCalendarForNewEvents

        do {
            try eventStore.save(event, span: .thisEvent, commit: true)
            return event.calendarItemIdentifier
        } catch {
            throw ReminderError.creationFailed(error.localizedDescription)
        }
    }

    // MARK: - Reminder Management

    func deleteReminder(eventKitID: String) async throws {
        guard checkPermission() else {
            throw ReminderError.permissionDenied
        }

        guard let reminder = eventStore.calendarItem(withIdentifier: eventKitID) as? EKReminder else {
            throw ReminderError.notFound
        }

        do {
            try eventStore.remove(reminder, commit: true)
        } catch {
            throw ReminderError.creationFailed(error.localizedDescription)
        }
    }

    func completeReminder(eventKitID: String) async throws {
        guard checkPermission() else {
            throw ReminderError.permissionDenied
        }

        guard let reminder = eventStore.calendarItem(withIdentifier: eventKitID) as? EKReminder else {
            throw ReminderError.notFound
        }

        reminder.isCompleted = true

        do {
            try eventStore.save(reminder, commit: true)
        } catch {
            throw ReminderError.creationFailed(error.localizedDescription)
        }
    }

    // MARK: - Smart Reminder Suggestions

    func suggestReminders(for document: Document) -> [ReminderSuggestion] {
        var suggestions: [ReminderSuggestion] = []

        switch document.docType {
        case .creditCard:
            // Suggest payment reminder
            if let expiryField = document.fields.first(where: { $0.key.lowercased().contains("expiry") }) {
                if let expiryDate = parseDate(from: expiryField.value) {
                    let renewalDate = Calendar.current.date(byAdding: .month, value: -1, to: expiryDate) ?? expiryDate
                    suggestions.append(ReminderSuggestion(
                        title: "Renew \(document.title)",
                        notes: "Credit card expires on \(formatDate(expiryDate))",
                        dueDate: renewalDate,
                        type: .renewal,
                        priority: 1
                    ))
                }
            }

        case .insuranceCard:
            suggestions.append(ReminderSuggestion(
                title: "Call insurance provider",
                notes: "Regarding \(document.title)",
                dueDate: Calendar.current.date(byAdding: .day, value: 7, to: Date()) ?? Date(),
                type: .call,
                priority: 5
            ))

            suggestions.append(ReminderSuggestion(
                title: "Schedule appointment",
                notes: "Use insurance: \(document.title)",
                dueDate: Calendar.current.date(byAdding: .day, value: 14, to: Date()) ?? Date(),
                type: .appointment,
                priority: 5
            ))

        case .billStatement:
            if let dueField = document.fields.first(where: { $0.key.lowercased().contains("due") }) {
                if let dueDate = parseDate(from: dueField.value) {
                    let reminderDate = Calendar.current.date(byAdding: .day, value: -3, to: dueDate) ?? dueDate

                    let amountField = document.fields.first(where: { $0.key.lowercased().contains("amount") || $0.key.lowercased().contains("balance") })
                    let amount = amountField?.value ?? "amount due"

                    suggestions.append(ReminderSuggestion(
                        title: "Pay \(document.title)",
                        notes: "\(amount) is due on \(formatDate(dueDate))",
                        dueDate: reminderDate,
                        type: .payment,
                        priority: 1
                    ))
                }
            }

        case .idCard:
            // Suggest renewal reminder if expiry date is found
            if let expiryField = document.fields.first(where: { $0.key.lowercased().contains("expir") }) {
                if let expiryDate = parseDate(from: expiryField.value) {
                    let renewalDate = Calendar.current.date(byAdding: .month, value: -2, to: expiryDate) ?? expiryDate
                    suggestions.append(ReminderSuggestion(
                        title: "Renew \(document.title)",
                        notes: "ID expires on \(formatDate(expiryDate))",
                        dueDate: renewalDate,
                        type: .renewal,
                        priority: 1
                    ))
                }
            }

        case .letter:
            suggestions.append(ReminderSuggestion(
                title: "Follow up on \(document.title)",
                notes: "Review and respond if needed",
                dueDate: Calendar.current.date(byAdding: .day, value: 7, to: Date()) ?? Date(),
                type: .followUp,
                priority: 5
            ))

        case .promotional:
            // Extract offer expiration if present
            if let expiryField = document.fields.first(where: { $0.key.lowercased().contains("expir") || $0.key.lowercased().contains("offer") }) {
                if let expiryDate = parseDate(from: expiryField.value) {
                    let reminderDate = Calendar.current.date(byAdding: .day, value: -3, to: expiryDate) ?? expiryDate
                    suggestions.append(ReminderSuggestion(
                        title: "Use offer: \(document.title)",
                        notes: "Promotional offer expires on \(formatDate(expiryDate))",
                        dueDate: reminderDate,
                        type: .followUp,
                        priority: 3
                    ))
                }
            }

        case .receipt, .generic:
            break
        }

        return suggestions
    }

    // MARK: - Helper Methods

    private func parseDate(from string: String) -> Date? {
        let formatters: [DateFormatter] = [
            {
                let f = DateFormatter()
                f.dateFormat = "MM/dd/yyyy"
                return f
            }(),
            {
                let f = DateFormatter()
                f.dateFormat = "MM/dd/yy"
                return f
            }(),
            {
                let f = DateFormatter()
                f.dateFormat = "MMM dd, yyyy"
                return f
            }(),
            {
                let f = DateFormatter()
                f.dateFormat = "MMMM dd, yyyy"
                return f
            }()
        ]

        for formatter in formatters {
            if let date = formatter.date(from: string) {
                return date
            }
        }

        return nil
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }
}

// MARK: - Supporting Types

struct ReminderSuggestion: Identifiable {
    let id = UUID()
    let title: String
    let notes: String
    let dueDate: Date
    let type: ReminderType
    let priority: Int

    var priorityLabel: String {
        switch priority {
        case 1: return "High"
        case 5: return "Medium"
        case 9: return "Low"
        default: return "None"
        }
    }

    var typeIcon: String {
        switch type {
        case .call: return "phone.fill"
        case .appointment: return "calendar"
        case .payment: return "creditcard.fill"
        case .renewal: return "arrow.clockwise"
        case .followUp: return "checkmark.circle"
        case .custom: return "bell.fill"
        }
    }

    var typeColor: String {
        switch type {
        case .call: return "blue"
        case .appointment: return "green"
        case .payment: return "red"
        case .renewal: return "orange"
        case .followUp: return "purple"
        case .custom: return "gray"
        }
    }
}

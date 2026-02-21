//
//  PlanCSV.swift
//  Klettrack
//  Created by Shahar Noy on 17.02.26.
//

import Foundation
import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct PlanCSVImportSummary: Sendable {
    let createdPlanName: String
    let importedDays: Int
    let linkedExercises: Int
    let skippedRows: Int
    let warnings: [String]
    let placeholderPlanKinds: Int
    let placeholderDayTypes: Int
    let placeholderActivities: Int
    let placeholderTrainingTypes: Int
    let placeholderExercises: Int

    var totalPlaceholders: Int {
        placeholderPlanKinds + placeholderDayTypes + placeholderActivities + placeholderTrainingTypes + placeholderExercises
    }
}

struct PlanCSVDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.commaSeparatedText] }
    static var writableContentTypes: [UTType] { [.commaSeparatedText] }

    var csv: String

    init(csv: String = "") {
        self.csv = csv
    }

    init(configuration: ReadConfiguration) throws {
        guard
            let data = configuration.file.regularFileContents,
            let string = String(data: data, encoding: .utf8)
        else {
            throw CocoaError(.fileReadCorruptFile)
        }
        self.csv = string
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: Data(csv.utf8))
    }
}

enum PlanCSV {
    fileprivate static let requiredHeaders: [String] = [
        "plan_name",
        "plan_kind",
        "plan_start_date",
        "day_date",
        "weekday",
        "day_type",
        "day_notes",
        "exercise_order",
        "exercise_name",
        "activity_name",
        "training_type_name",
        "exercise_id"
    ]

    private static let placeholderActivityName = "Imported Activity"
    private static let placeholderTrainingTypeName = "Imported Training Type"

    @MainActor
    static func makeExportCSV(for plan: Plan, in context: ModelContext) -> PlanCSVDocument {
        let dateFormatter = DateFormatter()
        dateFormatter.calendar = Calendar(identifier: .gregorian)
        dateFormatter.locale = Locale(identifier: "en_US_POSIX")
        dateFormatter.timeZone = TimeZone.current
        dateFormatter.dateFormat = "yyyy-MM-dd"

        let exercises = (try? context.fetch(FetchDescriptor<Exercise>()))?.filter { !$0.isSoftDeleted } ?? []
        var exerciseByID = makeDictionaryKeepingFirstValue(exercises.map { ($0.id, $0) })
        var exerciseByName = makeDictionaryKeepingFirstValue(exercises.map { (normalizeName($0.name), $0) })
        var exerciseContextByID: [UUID: (activityName: String, trainingTypeName: String)] = [:]

        let activeActivities = (try? context.fetch(FetchDescriptor<Activity>()))?.filter { !$0.isSoftDeleted } ?? []
        for activity in activeActivities {
            for trainingType in activity.types where !trainingType.isSoftDeleted {
                for exercise in trainingType.exercises where !exercise.isSoftDeleted {
                    exerciseContextByID[exercise.id] = (activity.name, trainingType.name)
                    exerciseByID[exercise.id] = exercise
                    exerciseByName[normalizeName(exercise.name)] = exercise
                }
            }
        }

        var rows: [String] = [requiredHeaders.joined(separator: ",")]
        let planName = plan.name
        let planKind = plan.kind?.name ?? ""
        let planStartDate = dateFormatter.string(from: plan.startDate)
        let weekdayFormatter = Date.FormatStyle().weekday(.wide)
        let sortedDays = plan.days.sorted { $0.date < $1.date }

        for day in sortedDays {
            let dayDateText = dateFormatter.string(from: day.date)
            let weekdayText = day.date.formatted(weekdayFormatter)
            let dayType = day.type?.name ?? ""
            let dayNotes = day.dailyNotes ?? ""

            let orderedRows = orderedExerciseRows(
                for: day,
                exerciseByID: exerciseByID,
                exerciseByName: exerciseByName,
                exerciseContextByID: exerciseContextByID
            )

            if orderedRows.isEmpty {
                rows.append([
                    planCSVEscape(planName),
                    planCSVEscape(planKind),
                    planStartDate,
                    dayDateText,
                    planCSVEscape(weekdayText),
                    planCSVEscape(dayType),
                    planCSVEscape(dayNotes),
                    "",
                    "",
                    "",
                    "",
                    ""
                ].joined(separator: ","))
                continue
            }

            for row in orderedRows {
                rows.append([
                    planCSVEscape(planName),
                    planCSVEscape(planKind),
                    planStartDate,
                    dayDateText,
                    planCSVEscape(weekdayText),
                    planCSVEscape(dayType),
                    planCSVEscape(dayNotes),
                    String(row.order),
                    planCSVEscape(row.exerciseName),
                    planCSVEscape(row.activityName),
                    planCSVEscape(row.trainingTypeName),
                    row.exerciseID
                ].joined(separator: ","))
            }
        }

        return PlanCSVDocument(csv: rows.joined(separator: "\n"))
    }

    @MainActor
    static func importPlanCSVAsync(
        from url: URL,
        into context: ModelContext,
        progress: ((Double) -> Void)? = nil,
        importedPlanName: String? = nil,
        importedPlanKind: PlanKindModel? = nil,
        importedPlanStartDate: Date? = nil
    ) async throws -> PlanCSVImportSummary {
        let didAccess = url.startAccessingSecurityScopedResource()
        defer {
            if didAccess {
                url.stopAccessingSecurityScopedResource()
            }
        }

        let data = try Data(contentsOf: url)
        guard let text = String(data: data, encoding: .utf8) else {
            throw NSError(domain: "PlanCSV", code: 1, userInfo: [NSLocalizedDescriptionKey: "Unable to decode CSV file as UTF-8."])
        }

        let parsed = try parseCSV(text)
        guard let group = parsed.groups.first else {
            throw NSError(domain: "PlanCSV", code: 2, userInfo: [NSLocalizedDescriptionKey: "No valid plan rows found in CSV."])
        }

        progress?(0.2)

        let activePlans = (try? context.fetch(FetchDescriptor<Plan>()))?.filter { !$0.isSoftDeleted } ?? []
        let activePlanKinds = (try? context.fetch(FetchDescriptor<PlanKindModel>()))?.filter { !$0.isSoftDeleted } ?? []
        let activeDayTypes = (try? context.fetch(FetchDescriptor<DayTypeModel>()))?.filter { !$0.isSoftDeleted } ?? []
        let activeActivities = (try? context.fetch(FetchDescriptor<Activity>()))?.filter { !$0.isSoftDeleted } ?? []
        let activeTrainingTypes = (try? context.fetch(FetchDescriptor<TrainingType>()))?.filter { !$0.isSoftDeleted } ?? []
        let activeExercises = (try? context.fetch(FetchDescriptor<Exercise>()))?.filter { !$0.isSoftDeleted } ?? []

        var planKindByName = makeDictionaryKeepingFirstValue(activePlanKinds.map { (normalizeName($0.name), $0) })
        var dayTypeByName = makeDictionaryKeepingFirstValue(activeDayTypes.map { (normalizeName($0.name), $0) })
        var activityByName = makeDictionaryKeepingFirstValue(activeActivities.map { (normalizeName($0.name), $0) })
        var exerciseByID = makeDictionaryKeepingFirstValue(activeExercises.map { ($0.id, $0) })
        var exerciseByName = makeDictionaryKeepingFirstValue(activeExercises.map { (normalizeName($0.name), $0) })

        var createdTrainingTypesByKey: [String: TrainingType] = [:]
        var createdExercisesByKey: [String: Exercise] = [:]

        var placeholderPlanKinds = 0
        var placeholderDayTypes = 0
        var placeholderActivities = 0
        var placeholderTrainingTypes = 0
        var placeholderExercises = 0

        func ensurePlanKind(name: String) -> PlanKindModel? {
            let normalized = normalizeName(name)
            guard !normalized.isEmpty else { return nil }
            if let existing = planKindByName[normalized] {
                return existing
            }

            let nextOrder = (activePlanKinds.map(\.order).max() ?? 0) + placeholderPlanKinds + 1
            let created = PlanKindModel(
                key: "imported-\(slugify(name))",
                name: name,
                totalWeeks: nil,
                isRepeating: false,
                order: nextOrder
            )
            SyncLocalMutation.touch(created)
            context.insert(created)
            planKindByName[normalized] = created
            placeholderPlanKinds += 1
            return created
        }

        func ensureDayType(name: String) -> DayTypeModel? {
            let normalized = normalizeName(name)
            guard !normalized.isEmpty else { return nil }
            if let existing = dayTypeByName[normalized] {
                return existing
            }

            let nextOrder = (activeDayTypes.map(\.order).max() ?? 0) + placeholderDayTypes + 1
            let created = DayTypeModel(
                key: "imported-\(slugify(name))",
                name: name,
                order: nextOrder,
                colorKey: "gray",
                isdefault: false,
                isHidden: false
            )
            SyncLocalMutation.touch(created)
            context.insert(created)
            dayTypeByName[normalized] = created
            placeholderDayTypes += 1
            return created
        }

        func ensureActivity(name: String) -> Activity {
            let resolvedName = name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? placeholderActivityName : name
            let normalized = normalizeName(resolvedName)
            if let existing = activityByName[normalized] {
                return existing
            }

            let created = Activity(name: resolvedName)
            SyncLocalMutation.touch(created)
            context.insert(created)
            activityByName[normalized] = created
            placeholderActivities += 1
            return created
        }

        func ensureTrainingType(activity: Activity, name: String) -> TrainingType {
            let resolvedName = name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? placeholderTrainingTypeName : name
            let key = "\(activity.id.uuidString)|\(normalizeName(resolvedName))"
            if let created = createdTrainingTypesByKey[key] {
                return created
            }

            if let existing = activeTrainingTypes.first(where: { trainingType in
                normalizeName(trainingType.name) == normalizeName(resolvedName) && activity.types.contains(where: { $0.id == trainingType.id })
            }) {
                return existing
            }

            let created = TrainingType(name: resolvedName, area: nil, typeDescription: "Imported placeholder")
            SyncLocalMutation.touch(created)
            activity.types.append(created)
            SyncLocalMutation.touch(activity)
            createdTrainingTypesByKey[key] = created
            placeholderTrainingTypes += 1
            return created
        }

        func ensureExercise(
            rawExerciseID: String,
            exerciseName: String,
            trainingTypeName: String,
            activityName: String,
            fallbackCounter: Int
        ) -> Exercise {
            let trimmedID = rawExerciseID.trimmingCharacters(in: .whitespacesAndNewlines)
            if let uuid = UUID(uuidString: trimmedID), let existing = exerciseByID[uuid] {
                return existing
            }

            let normalizedName = normalizeName(exerciseName)
            if !normalizedName.isEmpty, let existing = exerciseByName[normalizedName] {
                return existing
            }

            let resolvedExerciseName = exerciseName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? "Imported Exercise \(fallbackCounter)"
                : exerciseName
            let activity = ensureActivity(name: activityName)
            let trainingType = ensureTrainingType(activity: activity, name: trainingTypeName)
            let key = "\(trainingType.id.uuidString)|\(normalizeName(resolvedExerciseName))"
            if let created = createdExercisesByKey[key] {
                return created
            }

            let created = Exercise(
                name: resolvedExerciseName,
                area: nil,
                order: 0,
                exerciseDescription: "Imported placeholder",
                repsText: nil,
                durationText: nil,
                setsText: nil,
                restText: nil,
                notes: "Imported placeholder"
            )
            SyncLocalMutation.touch(created)
            trainingType.exercises.append(created)
            SyncLocalMutation.touch(trainingType)
            createdExercisesByKey[key] = created
            exerciseByID[created.id] = created
            exerciseByName[normalizeName(created.name)] = created
            placeholderExercises += 1
            return created
        }

        let requestedPlanName = importedPlanName?.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedPlanName = (requestedPlanName?.isEmpty == false) ? requestedPlanName! : group.planName
        let importStartDate = importedPlanStartDate.map { Calendar.current.startOfDay(for: $0) }
        let startDate = importStartDate ?? group.planStartDate ?? group.days.first?.dayDate
        guard let startDate else {
            throw NSError(domain: "PlanCSV", code: 3, userInfo: [NSLocalizedDescriptionKey: "No valid day rows found in CSV."])
        }

        let existingPlanNames = Set(activePlans.map { normalizeName($0.name) })
        let createdPlanName = uniqueImportedPlanName(baseName: resolvedPlanName, existing: existingPlanNames)
        let planKind = importedPlanKind.flatMap { $0.isSoftDeleted ? nil : $0 } ?? ensurePlanKind(name: group.planKind)
        let plan = Plan(name: createdPlanName, kind: planKind, startDate: startDate)
        SyncLocalMutation.touch(plan)
        context.insert(plan)

        progress?(0.55)

        var linkedExercises = 0
        var fallbackExerciseCounter = 1
        for day in group.days {
            let planDay = PlanDay(date: day.dayDate, type: ensureDayType(name: day.dayType))
            planDay.dailyNotes = day.dayNotes.isEmpty ? nil : day.dayNotes

            let sortedRows = day.exerciseRows.sorted { left, right in
                let leftOrder = left.exerciseOrder ?? Int.max
                let rightOrder = right.exerciseOrder ?? Int.max
                if leftOrder != rightOrder {
                    return leftOrder < rightOrder
                }
                return left.lineNumber < right.lineNumber
            }

            var chosenIDs: [UUID] = []
            var chosenNames: [String] = []
            var orderByID: [String: Int] = [:]
            var orderByName: [String: Int] = [:]

            for row in sortedRows {
                if row.isExerciseEmpty {
                    continue
                }

                let exercise = ensureExercise(
                    rawExerciseID: row.exerciseID,
                    exerciseName: row.exerciseName,
                    trainingTypeName: row.trainingTypeName,
                    activityName: row.activityName,
                    fallbackCounter: fallbackExerciseCounter
                )
                fallbackExerciseCounter += 1
                chosenIDs.append(exercise.id)
                chosenNames.append(exercise.name)
                let order = chosenIDs.count - 1
                orderByID[exercise.id.uuidString] = order
                orderByName[exercise.name] = order
                linkedExercises += 1
            }

            planDay.chosenExerciseIDs = chosenIDs
            planDay.exerciseOrderByID = orderByID
            planDay.chosenExercises = chosenNames
            planDay.exerciseOrder = orderByName
            SyncLocalMutation.touch(planDay)
            plan.days.append(planDay)
        }

        try context.save()
        progress?(1.0)

        return PlanCSVImportSummary(
            createdPlanName: createdPlanName,
            importedDays: group.days.count,
            linkedExercises: linkedExercises,
            skippedRows: parsed.skippedRows,
            warnings: parsed.warnings,
            placeholderPlanKinds: placeholderPlanKinds,
            placeholderDayTypes: placeholderDayTypes,
            placeholderActivities: placeholderActivities,
            placeholderTrainingTypes: placeholderTrainingTypes,
            placeholderExercises: placeholderExercises
        )
    }
}

private struct PlanCSVExportExerciseRow {
    let order: Int
    let exerciseName: String
    let exerciseID: String
    let activityName: String
    let trainingTypeName: String
}

private func orderedExerciseRows(
    for day: PlanDay,
    exerciseByID: [UUID: Exercise],
    exerciseByName: [String: Exercise],
    exerciseContextByID: [UUID: (activityName: String, trainingTypeName: String)]
) -> [PlanCSVExportExerciseRow] {
    var resolvedRows: [PlanCSVExportExerciseRow] = []

    if !day.chosenExerciseIDs.isEmpty {
        let sortedIDs = day.chosenExerciseIDs.enumerated().sorted { left, right in
            let leftOrder = day.exerciseOrderByID[left.element.uuidString] ?? left.offset
            let rightOrder = day.exerciseOrderByID[right.element.uuidString] ?? right.offset
            if leftOrder != rightOrder {
                return leftOrder < rightOrder
            }
            return left.offset < right.offset
        }.map(\.element)

        for (index, id) in sortedIDs.enumerated() {
            let exercise = exerciseByID[id]
            let context = exerciseContextByID[id]
            let fallbackName = index < day.chosenExercises.count ? day.chosenExercises[index] : ""
            let name = exercise?.name ?? fallbackName
            resolvedRows.append(
                PlanCSVExportExerciseRow(
                    order: index + 1,
                    exerciseName: name,
                    exerciseID: id.uuidString,
                    activityName: context?.activityName ?? "",
                    trainingTypeName: context?.trainingTypeName ?? ""
                )
            )
        }
        return resolvedRows
    }

    if !day.chosenExercises.isEmpty {
        let sortedNames = day.chosenExercises.enumerated().sorted { left, right in
            let leftOrder = day.exerciseOrder[left.element] ?? left.offset
            let rightOrder = day.exerciseOrder[right.element] ?? right.offset
            if leftOrder != rightOrder {
                return leftOrder < rightOrder
            }
            return left.offset < right.offset
        }.map(\.element)

        for (index, name) in sortedNames.enumerated() {
            let exercise = exerciseByName[normalizeName(name)]
            let context = exercise.flatMap { exerciseContextByID[$0.id] }
            resolvedRows.append(
                PlanCSVExportExerciseRow(
                    order: index + 1,
                    exerciseName: exercise?.name ?? name,
                    exerciseID: exercise?.id.uuidString ?? "",
                    activityName: context?.activityName ?? "",
                    trainingTypeName: context?.trainingTypeName ?? ""
                )
            )
        }
    }

    return resolvedRows
}

private struct PlanCSVParseResult {
    let groups: [PlanCSVGroup]
    let skippedRows: Int
    let warnings: [String]
}

private struct PlanCSVGroup {
    let key: String
    let planName: String
    let planKind: String
    let planStartDate: Date?
    let days: [PlanCSVDay]
}

private struct PlanCSVDay {
    let dayDate: Date
    let dayType: String
    let dayNotes: String
    let exerciseRows: [PlanCSVExerciseRow]
}

private struct PlanCSVExerciseRow {
    let lineNumber: Int
    let exerciseOrder: Int?
    let exerciseName: String
    let exerciseID: String
    let activityName: String
    let trainingTypeName: String

    var isExerciseEmpty: Bool {
        exerciseName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && exerciseID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && activityName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && trainingTypeName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

private func parseCSV(_ text: String) throws -> PlanCSVParseResult {
    let rows = parseCSVRows(text)
    guard !rows.isEmpty else {
        throw NSError(domain: "PlanCSV", code: 4, userInfo: [NSLocalizedDescriptionKey: "CSV file is empty."])
    }

    let normalizedHeaders = rows[0].map { normalizeHeader($0) }
    var headerIndex: [String: Int] = [:]
    for (index, header) in normalizedHeaders.enumerated() {
        headerIndex[header] = index
    }

    let missing = PlanCSV.requiredHeaders.filter { headerIndex[$0] == nil }
    if !missing.isEmpty {
        throw NSError(
            domain: "PlanCSV",
            code: 5,
            userInfo: [NSLocalizedDescriptionKey: "Missing required headers: \(missing.joined(separator: ", "))"]
        )
    }

    func cell(_ row: [String], _ key: String) -> String {
        guard let index = headerIndex[key], row.indices.contains(index) else {
            return ""
        }
        return row[index].trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var warnings: [String] = []
    var skippedRows = 0
    var grouped: [String: [RowEntry]] = [:]

    for rawIndex in 1..<rows.count {
        let row = rows[rawIndex]
        let lineNumber = rawIndex + 1

        if row.allSatisfy({ $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) {
            continue
        }

        let dayDateText = cell(row, "day_date")
        guard let dayDate = parseDateOnly(dayDateText) else {
            skippedRows += 1
            warnings.append("Line \(lineNumber): invalid day_date \"\(dayDateText)\" (expected YYYY-MM-DD), row skipped.")
            continue
        }

        let startDateText = cell(row, "plan_start_date")
        let planStartDate = parseDateOnly(startDateText)
        if !startDateText.isEmpty && planStartDate == nil {
            warnings.append("Line \(lineNumber): invalid plan_start_date \"\(startDateText)\" (using earliest day date).")
        }

        let exerciseOrderRaw = cell(row, "exercise_order")
        let exerciseOrder = parsePositiveInt(exerciseOrderRaw)
        if !exerciseOrderRaw.isEmpty && exerciseOrder == nil {
            warnings.append("Line \(lineNumber): invalid exercise_order \"\(exerciseOrderRaw)\" (using row order).")
        }

        let planName = cell(row, "plan_name").isEmpty ? "Imported Plan" : cell(row, "plan_name")
        let planKind = cell(row, "plan_kind")
        let groupKey = "\(planName)::\(startDateText)"

        grouped[groupKey, default: []].append(
            RowEntry(
                lineNumber: lineNumber,
                planName: planName,
                planKind: planKind,
                planStartDate: planStartDate,
                dayDate: dayDate,
                dayType: cell(row, "day_type"),
                dayNotes: cell(row, "day_notes"),
                exerciseOrder: exerciseOrder,
                exerciseName: cell(row, "exercise_name"),
                exerciseID: cell(row, "exercise_id"),
                activityName: cell(row, "activity_name"),
                trainingTypeName: cell(row, "training_type_name")
            )
        )
    }

    let groups = grouped.keys.sorted().compactMap { key -> PlanCSVGroup? in
        guard let entries = grouped[key], let first = entries.first else { return nil }

        var daysByDate: [Date: [RowEntry]] = [:]
        for entry in entries {
            daysByDate[entry.dayDate, default: []].append(entry)
        }

        let sortedDates = daysByDate.keys.sorted()
        let days: [PlanCSVDay] = sortedDates.compactMap { date in
            guard let dayRows = daysByDate[date], let firstDayRow = dayRows.first else { return nil }
            let exerciseRows = dayRows.map {
                PlanCSVExerciseRow(
                    lineNumber: $0.lineNumber,
                    exerciseOrder: $0.exerciseOrder,
                    exerciseName: $0.exerciseName,
                    exerciseID: $0.exerciseID,
                    activityName: $0.activityName,
                    trainingTypeName: $0.trainingTypeName
                )
            }
            return PlanCSVDay(dayDate: date, dayType: firstDayRow.dayType, dayNotes: firstDayRow.dayNotes, exerciseRows: exerciseRows)
        }

        guard !days.isEmpty else { return nil }
        return PlanCSVGroup(
            key: key,
            planName: first.planName,
            planKind: first.planKind,
            planStartDate: first.planStartDate,
            days: days
        )
    }

    if groups.isEmpty {
        throw NSError(domain: "PlanCSV", code: 6, userInfo: [NSLocalizedDescriptionKey: "No valid day rows found in CSV."])
    }

    return PlanCSVParseResult(groups: groups, skippedRows: skippedRows, warnings: warnings)
}

private struct RowEntry {
    let lineNumber: Int
    let planName: String
    let planKind: String
    let planStartDate: Date?
    let dayDate: Date
    let dayType: String
    let dayNotes: String
    let exerciseOrder: Int?
    let exerciseName: String
    let exerciseID: String
    let activityName: String
    let trainingTypeName: String
}

private func parseCSVRows(_ text: String) -> [[String]] {
    var rows: [[String]] = []
    var row: [String] = []
    var current = ""
    var inQuotes = false
    let chars = Array(text)
    var index = 0

    while index < chars.count {
        let char = chars[index]
        let nextChar: Character? = (index + 1 < chars.count) ? chars[index + 1] : nil

        if char == "\"" {
            if inQuotes && nextChar == "\"" {
                current.append("\"")
                index += 1
            } else {
                inQuotes.toggle()
            }
            index += 1
            continue
        }

        if !inQuotes && char == "," {
            row.append(current)
            current = ""
            index += 1
            continue
        }

        if !inQuotes && (char == "\n" || char == "\r") {
            if char == "\r" && nextChar == "\n" {
                index += 1
            }
            row.append(current)
            rows.append(row)
            row = []
            current = ""
            index += 1
            continue
        }

        current.append(char)
        index += 1
    }

    if !current.isEmpty || !row.isEmpty {
        row.append(current)
        rows.append(row)
    }

    return rows
}

private func normalizeHeader(_ value: String) -> String {
    value
        .trimmingCharacters(in: .whitespacesAndNewlines)
        .lowercased()
        .replacing(" ", with: "_")
}

private func normalizeName(_ value: String) -> String {
    value
        .trimmingCharacters(in: .whitespacesAndNewlines)
        .lowercased()
        .split(whereSeparator: \ .isWhitespace)
        .joined(separator: " ")
}

private func parseDateOnly(_ value: String) -> Date? {
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    guard trimmed.count == 10 else { return nil }
    let formatter = DateFormatter()
    formatter.calendar = Calendar(identifier: .gregorian)
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = TimeZone.current
    formatter.dateFormat = "yyyy-MM-dd"
    return formatter.date(from: trimmed)
}

private func parsePositiveInt(_ value: String) -> Int? {
    guard let parsed = Int(value.trimmingCharacters(in: .whitespacesAndNewlines)), parsed > 0 else {
        return nil
    }
    return parsed
}

private func uniqueImportedPlanName(baseName: String, existing: Set<String>) -> String {
    let base = "\(baseName) (Imported)"
    if !existing.contains(normalizeName(base)) {
        return base
    }

    var counter = 2
    while counter < 5000 {
        let candidate = "\(base) \(counter)"
        if !existing.contains(normalizeName(candidate)) {
            return candidate
        }
        counter += 1
    }
    return "\(base) \(Int(Date.now.timeIntervalSince1970))"
}

private func slugify(_ value: String) -> String {
    let lowered = value.lowercased()
    let allowed = lowered.map { ch -> Character in
        if ch.isLetter || ch.isNumber {
            return ch
        }
        return "-"
    }
    let raw = String(allowed)
    let collapsed = raw.replacing("--", with: "-")
    let trimmed = collapsed.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
    return trimmed.isEmpty ? "imported" : trimmed
}

private func makeDictionaryKeepingFirstValue<Key: Hashable, Value>(_ items: [(Key, Value)]) -> [Key: Value] {
    var result: [Key: Value] = [:]
    for (key, value) in items where result[key] == nil {
        result[key] = value
    }
    return result
}

private func planCSVEscape(_ value: String) -> String {
    if value.contains(",") || value.contains("\"") || value.contains("\n") {
        let escaped = value.replacingOccurrences(of: "\"", with: "\"\"")
        return "\"\(escaped)\""
    }
    return value
}

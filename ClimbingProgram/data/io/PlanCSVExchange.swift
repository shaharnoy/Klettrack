import Foundation
import SwiftUI
import SwiftData
import UniformTypeIdentifiers
import CryptoKit

struct PlanCSVDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.commaSeparatedText] }
    static var writableContentTypes: [UTType] { [.commaSeparatedText] }

    var csv: String

    init(csv: String = "") {
        self.csv = csv
    }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents,
              let csv = String(data: data, encoding: .utf8) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        self.csv = csv
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: Data(csv.utf8))
    }
}

@MainActor
enum PlanCSVExchange {
    enum ImportMode {
        case newPlan
        case existing(Plan)
    }

    struct Summary: Sendable {
        let planName: String
        let dayCount: Int
        let exerciseCount: Int
        let logCount: Int
        let climbCount: Int
        let warnings: [String]

        var message: String {
            var result = "Imported \(planName): \(dayCount) day(s), \(exerciseCount) exercise definition(s), \(logCount) log(s), \(climbCount) climb(s)."
            if !warnings.isEmpty {
                result += " \(warnings.count) row warning(s)."
            }
            return result
        }
    }

    struct ParsedExchange: Sendable {
        struct PlanRow: Sendable {
            var id: UUID
            var name: String
            var startDate: Date
            var kindKey: String?
            var kindName: String?
            var totalWeeks: Int?
            var isRepeating: Bool
        }

        struct ExerciseRow: Sendable {
            var id: UUID
            var catalogID: UUID?
            var name: String
            var area: String?
            var description: String?
            var reps: String?
            var sets: String?
            var duration: String?
            var rest: String?
            var notes: String?
        }

        struct DayRow: Sendable {
            var id: UUID
            var date: Date
            var dayTypeKey: String?
            var dayTypeName: String?
            var dayTypeColor: String?
            var exerciseRefs: [(UUID, Int)]
            var dailyNotes: String?
        }

        struct ContextRow: Sendable {
            var date: Date
            var note: String?
            var tags: [PlanCSVTag]
        }

        struct LogRow: Sendable {
            var id: UUID
            var date: Date
            var dayID: UUID?
            var planExerciseID: UUID?
            var name: String
            var reps: Double?
            var sets: Double?
            var duration: Double?
            var weight: Double?
            var grade: String?
            var notes: String?
        }

        struct ClimbRow: Sendable {
            var id: UUID
            var date: Date
            var dayID: UUID?
            var type: ClimbType
            var grade: String
            var feelsLikeGrade: String?
            var angle: Int?
            var holdColor: HoldColor?
            var ropeType: RopeClimbType?
            var style: String
            var attempts: String?
            var isWIP: Bool
            var isPreviouslyClimbed: Bool
            var gym: String
            var notes: String?
            var tb2UUID: String?
        }

        var plan: PlanRow
        var exercises: [ExerciseRow]
        var days: [DayRow]
        var contexts: [ContextRow]
        var logs: [LogRow]
        var climbs: [ClimbRow]
        var warnings: [String]
    }

    struct PlanCSVTag: Codable, Equatable, Sendable {
        let name: String
        let colorKey: String
    }

    static func exportFilename(for plan: Plan, exportedAt: Date = .now) -> String {
        let safeName = plan.name
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .map { character in
                character.isLetter || character.isNumber ? String(character) : "_"
            }
            .joined()
            .split(separator: "_", omittingEmptySubsequences: true)
            .joined(separator: "_")

        let calendar = Calendar.current
        let components = calendar.dateComponents([.year, .month, .day], from: exportedAt)
        let year = components.year ?? 0
        let month = twoDigit(components.month ?? 0)
        let day = twoDigit(components.day ?? 0)
        let date = "\(year)-\(month)-\(day)"

        return "klettrack_\(safeName.isEmpty ? "plan" : safeName)_\(date)"
    }

    private static let headers = [
        "row_type", "plan_id", "plan_name", "start_date", "kind_key", "kind_name",
        "kind_total_weeks", "kind_repeating", "plan_exercise_id", "catalog_exercise_id", "exercise_name",
        "area", "exercise_description", "reps", "sets", "duration", "rest", "exercise_notes", "day_id",
        "day_date", "day_type_key", "day_type_name", "day_type_color", "exercise_refs", "day_note",
        "context_note", "day_tags", "session_item_id", "log_date", "log_day_id", "log_plan_exercise_id",
        "log_exercise_name", "log_reps", "log_sets", "log_duration", "log_weight", "log_grade", "log_notes",
        "climb_id", "climb_date", "climb_day_id", "climb_type", "climb_grade", "climb_feels_like_grade",
        "climb_angle", "climb_hold_color", "climb_rope_type", "climb_style", "climb_attempts", "climb_wip",
        "climb_previously_climbed", "climb_gym", "climb_notes", "tb2_uuid"
    ]

    static func export(plan: Plan, in context: ModelContext) -> PlanCSVDocument {
        let allExercises = catalogExercises(in: context)
        var definitions: [UUID: ParsedExchange.ExerciseRow] = [:]

        for definition in plan.exerciseDefinitions {
            definitions[definition.id] = ParsedExchange.ExerciseRow(
                id: definition.id,
                catalogID: definition.catalogExerciseID,
                name: definition.name,
                area: definition.area,
                description: definition.exerciseDescription,
                reps: definition.repsText,
                sets: definition.setsText,
                duration: definition.durationText,
                rest: definition.restText,
                notes: definition.notes
            )
        }

        for day in plan.days {
            for (index, name) in day.chosenExercises.enumerated() {
                let existingID = day.planExerciseIDs[safe: index]
                let catalog = allExercises.first { $0.id == day.chosenExerciseIDs[safe: index] }
                    ?? allExercises.first { normalized($0.name) == normalized(name) }
                let id = existingID ?? catalog?.id ?? stableID("plan-exercise|\(plan.id.uuidString)|\(name)")
                if definitions[id] == nil {
                    definitions[id] = ParsedExchange.ExerciseRow(
                        id: id,
                        catalogID: catalog?.id,
                        name: name,
                        area: catalog?.area,
                        description: catalog?.exerciseDescription,
                        reps: catalog?.repsText,
                        sets: catalog?.setsText,
                        duration: catalog?.durationText,
                        rest: catalog?.restText,
                        notes: catalog?.notes
                    )
                }
            }
        }

        var rows = [headers.joined(separator: ",")]

        rows.append(row(type: "plan", values: [
            "plan_id": plan.id.uuidString,
            "plan_name": plan.name,
            "start_date": encodeDate(plan.startDate),
            "kind_key": plan.kind?.key ?? "",
            "kind_name": plan.kind?.name ?? "",
            "kind_total_weeks": plan.kind?.totalWeeks.map(String.init) ?? "",
            "kind_repeating": plan.kind?.isRepeating == true ? "true" : "false"
        ]))

        for definition in definitions.values.sorted(by: { $0.name.localizedStandardCompare($1.name) == .orderedAscending }) {
            rows.append(row(type: "exercise", values: [
                "plan_exercise_id": definition.id.uuidString,
                "catalog_exercise_id": definition.catalogID?.uuidString ?? "",
                "exercise_name": definition.name,
                "area": definition.area ?? "",
                "exercise_description": definition.description ?? "",
                "reps": definition.reps ?? "",
                "sets": definition.sets ?? "",
                "duration": definition.duration ?? "",
                "rest": definition.rest ?? "",
                "exercise_notes": definition.notes ?? ""
            ]))
        }

        let calendar = Calendar.current
        for day in plan.days.sorted(by: { $0.date < $1.date }) {
            var refs: [(UUID, Int)] = []
            for (index, name) in day.chosenExercises.enumerated() {
                let catalog = allExercises.first { $0.id == day.chosenExerciseIDs[safe: index] }
                    ?? allExercises.first { normalized($0.name) == normalized(name) }
                let id = day.planExerciseIDs[safe: index] ?? catalog?.id ?? stableID("plan-exercise|\(plan.id.uuidString)|\(name)")
                refs.append((id, day.exerciseOrder[name] ?? index))
            }
            let encodedRefs = refs.map { "\($0.0.uuidString):\($0.1)" }.joined(separator: ";")
            rows.append(row(type: "day", values: [
                "day_id": day.id.uuidString,
                "day_date": encodeDate(day.date),
                "day_type_key": day.type?.key ?? "",
                "day_type_name": day.type?.name ?? "",
                "day_type_color": day.type?.colorKey ?? "gray",
                "exercise_refs": encodedRefs,
                "day_note": day.dailyNotes ?? ""
            ]))

            if let dayLog = DayLogStore.fetchDayLog(for: day.date, in: context), DayLogStore.hasContext(dayLog) {
                let tags = DayLogStore.activeTags(from: dayLog).map { PlanCSVTag(name: $0.name, colorKey: $0.colorKey) }
                rows.append(row(type: "context", values: [
                    "day_date": encodeDate(calendar.startOfDay(for: day.date)),
                    "context_note": dayLog.note ?? "",
                    "day_tags": encodeTags(tags)
                ]))
            }
        }

        let sessions = (try? context.fetch(FetchDescriptor<Session>())) ?? []
        for session in sessions.sorted(by: { $0.date < $1.date }) {
            for item in session.items where item.planSourceId == plan.id {
                rows.append(row(type: "exercise_log", values: [
                    "session_item_id": item.id.uuidString,
                    "log_date": encodeDate(session.date),
                    "log_day_id": item.planDayId?.uuidString ?? "",
                    "log_plan_exercise_id": item.planExerciseID?.uuidString ?? "",
                    "log_exercise_name": item.exerciseName,
                    "log_reps": item.reps.map(csvNumber) ?? "",
                    "log_sets": item.sets.map(csvNumber) ?? "",
                    "log_duration": item.duration.map(csvNumber) ?? "",
                    "log_weight": item.weightKg.map(csvNumber) ?? "",
                    "log_grade": item.grade ?? "",
                    "log_notes": item.notes ?? ""
                ]))
            }
        }

        let climbs = (try? context.fetch(FetchDescriptor<ClimbEntry>())) ?? []
        let linkedClimbIDs = Set(sessions.flatMap(\.items).filter { $0.planSourceId == plan.id }.compactMap(\.climbEntryId))
        for climb in climbs where climb.planSourceId == plan.id || linkedClimbIDs.contains(climb.id) {
            rows.append(row(type: "climb", values: [
                "climb_id": climb.id.uuidString,
                "climb_date": encodeDate(climb.dateLogged),
                "climb_day_id": climb.planDayId?.uuidString ?? "",
                "climb_type": climb.climbType.rawValue,
                "climb_grade": climb.grade,
                "climb_feels_like_grade": climb.feelsLikeGrade ?? "",
                "climb_angle": climb.angleDegrees.map(String.init) ?? "",
                "climb_hold_color": climb.holdColor?.rawValue ?? "",
                "climb_rope_type": climb.ropeClimbType?.rawValue ?? "",
                "climb_style": climb.style,
                "climb_attempts": climb.attempts ?? "",
                "climb_wip": climb.isWorkInProgress ? "true" : "false",
                "climb_previously_climbed": climb.isPreviouslyClimbed == true ? "true" : "false",
                "climb_gym": climb.gym,
                "climb_notes": climb.notes ?? "",
                "tb2_uuid": climb.tb2ClimbUUID ?? ""
            ]))
        }

        return PlanCSVDocument(csv: rows.joined(separator: "\n"))
    }

    static func parse(_ csv: String) throws -> ParsedExchange {
        let records = PlanCSVCodec.records(csv)
        guard let headerRecord = records.first else { throw Error.emptyFile }
        let header = PlanCSVCodec.line(headerRecord).map(normalizedHeader)
        guard header.contains("row_type") else { throw Error.invalidHeader }

        var rows: [[String: String]] = []
        for record in records.dropFirst() {
            let values = PlanCSVCodec.line(record)
            var row: [String: String] = [:]
            for (index, key) in header.enumerated() where index < values.count {
                row[key] = values[index]
            }
            rows.append(row)
        }

        guard let planRaw = rows.first(where: { $0["row_type"] == "plan" }),
              let planID = UUID(uuidString: planRaw["plan_id"] ?? ""),
              let planName = nonEmpty(planRaw["plan_name"]),
              let startDate = parseDate(planRaw["start_date"] ?? "") else {
            throw Error.missingPlanRow
        }

        var warnings: [String] = []
        let plan = ParsedExchange.PlanRow(
            id: planID,
            name: planName,
            startDate: startDate,
            kindKey: nonEmpty(planRaw["kind_key"]),
            kindName: nonEmpty(planRaw["kind_name"]),
            totalWeeks: Int(planRaw["kind_total_weeks"] ?? ""),
            isRepeating: (planRaw["kind_repeating"] ?? "").lowercased() == "true"
        )

        var exercises: [ParsedExchange.ExerciseRow] = []
        var days: [ParsedExchange.DayRow] = []
        var contexts: [ParsedExchange.ContextRow] = []
        var logs: [ParsedExchange.LogRow] = []
        var climbs: [ParsedExchange.ClimbRow] = []

        for row in rows where row["row_type"] != "plan" {
            switch row["row_type"] {
            case "exercise":
                guard let id = UUID(uuidString: row["plan_exercise_id"] ?? ""), let name = nonEmpty(row["exercise_name"]) else {
                    warnings.append("Skipped exercise row without an ID or name.")
                    continue
                }
                exercises.append(.init(
                    id: id,
                    catalogID: UUID(uuidString: row["catalog_exercise_id"] ?? ""),
                    name: name,
                    area: nonEmpty(row["area"]),
                    description: nonEmpty(row["exercise_description"]),
                    reps: nonEmpty(row["reps"]),
                    sets: nonEmpty(row["sets"]),
                    duration: nonEmpty(row["duration"]),
                    rest: nonEmpty(row["rest"]),
                    notes: nonEmpty(row["exercise_notes"])
                ))
            case "day":
                guard let id = UUID(uuidString: row["day_id"] ?? ""), let date = parseDate(row["day_date"] ?? "") else {
                    warnings.append("Skipped day row without an ID or date.")
                    continue
                }
                days.append(.init(
                    id: id,
                    date: date,
                    dayTypeKey: nonEmpty(row["day_type_key"]),
                    dayTypeName: nonEmpty(row["day_type_name"]),
                    dayTypeColor: nonEmpty(row["day_type_color"]),
                    exerciseRefs: parseExerciseRefs(row["exercise_refs"] ?? ""),
                    dailyNotes: nonEmpty(row["day_note"])
                ))
            case "context":
                guard let date = parseDate(row["day_date"] ?? "") else {
                    warnings.append("Skipped context row without a date.")
                    continue
                }
                contexts.append(.init(date: date, note: nonEmpty(row["context_note"]), tags: decodeTags(row["day_tags"] ?? "")))
            case "exercise_log":
                guard let id = UUID(uuidString: row["session_item_id"] ?? ""), let date = parseDate(row["log_date"] ?? ""), let name = nonEmpty(row["log_exercise_name"]) else {
                    warnings.append("Skipped exercise log row without an ID, date, or name.")
                    continue
                }
                logs.append(.init(
                    id: id,
                    date: date,
                    dayID: UUID(uuidString: row["log_day_id"] ?? ""),
                    planExerciseID: UUID(uuidString: row["log_plan_exercise_id"] ?? ""),
                    name: name,
                    reps: Double(row["log_reps"] ?? ""),
                    sets: Double(row["log_sets"] ?? ""),
                    duration: Double(row["log_duration"] ?? ""),
                    weight: Double(row["log_weight"] ?? ""),
                    grade: nonEmpty(row["log_grade"]),
                    notes: nonEmpty(row["log_notes"])
                ))
            case "climb":
                guard let id = UUID(uuidString: row["climb_id"] ?? ""), let date = parseDate(row["climb_date"] ?? ""), let grade = nonEmpty(row["climb_grade"]) else {
                    warnings.append("Skipped climb row without an ID, date, or grade.")
                    continue
                }
                climbs.append(.init(
                    id: id,
                    date: date,
                    dayID: UUID(uuidString: row["climb_day_id"] ?? ""),
                    type: ClimbType(rawValue: row["climb_type"] ?? "") ?? .boulder,
                    grade: grade,
                    feelsLikeGrade: nonEmpty(row["climb_feels_like_grade"]),
                    angle: Int(row["climb_angle"] ?? ""),
                    holdColor: HoldColor(rawValue: row["climb_hold_color"] ?? ""),
                    ropeType: RopeClimbType(rawValue: row["climb_rope_type"] ?? ""),
                    style: nonEmpty(row["climb_style"]) ?? "Unknown",
                    attempts: nonEmpty(row["climb_attempts"]),
                    isWIP: (row["climb_wip"] ?? "").lowercased() == "true",
                    isPreviouslyClimbed: (row["climb_previously_climbed"] ?? "").lowercased() == "true",
                    gym: nonEmpty(row["climb_gym"]) ?? "Unknown",
                    notes: nonEmpty(row["climb_notes"]),
                    tb2UUID: nonEmpty(row["tb2_uuid"])
                ))
            default:
                warnings.append("Ignored unknown row type '\(row["row_type"] ?? "")'.")
            }
        }

        return ParsedExchange(plan: plan, exercises: exercises, days: days, contexts: contexts, logs: logs, climbs: climbs, warnings: warnings)
    }

    static func apply(_ exchange: ParsedExchange, mode: ImportMode, in context: ModelContext) throws -> Summary {
        let targetPlan: Plan
        let isNew: Bool
        switch mode {
        case .newPlan:
            isNew = true
            let existingIDs = Set(((try? context.fetch(FetchDescriptor<Plan>())) ?? []).map(\.id))
            let id = existingIDs.contains(exchange.plan.id) ? UUID() : exchange.plan.id
            let kind = resolvePlanKind(exchange.plan, in: context)
            targetPlan = Plan(id: id, name: exchange.plan.name, kind: kind, startDate: exchange.plan.startDate)
            context.insert(targetPlan)
        case .existing(let plan):
            isNew = false
            targetPlan = plan
        }

        if isNew == false {
            targetPlan.name = exchange.plan.name
            targetPlan.startDate = exchange.plan.startDate
            if targetPlan.kind == nil { targetPlan.kind = resolvePlanKind(exchange.plan, in: context) }
        }

        let persistedExercises = (try? context.fetch(FetchDescriptor<Exercise>())) ?? []
        let existingDefinitionIDs = Set(((try? context.fetch(FetchDescriptor<PlanExerciseDefinition>())) ?? []).map(\.id))
        var definitionsBySourceID: [UUID: PlanExerciseDefinition] = [:]
        var definitionsByName: [String: PlanExerciseDefinition] = [:]

        for row in exchange.exercises {
            let matched = row.catalogID.flatMap { catalogID in persistedExercises.first(where: { $0.id == catalogID }) }
                ?? persistedExercises.first { normalized($0.name) == normalized(row.name) }
            let catalogExercise = matched ?? createImportedExercise(from: row, in: context)
            let existingDefinition = targetPlan.exerciseDefinitions.first { $0.id == row.id }
                ?? targetPlan.exerciseDefinitions.first { normalized($0.name) == normalized(row.name) }
            let definition = existingDefinition ?? PlanExerciseDefinition(
                id: existingDefinitionIDs.contains(row.id) ? UUID() : row.id,
                catalogExerciseID: catalogExercise.id,
                name: row.name
            )
            definition.catalogExerciseID = catalogExercise.id
            definition.name = row.name
            definition.area = row.area
            definition.exerciseDescription = row.description
            definition.repsText = row.reps
            definition.setsText = row.sets
            definition.durationText = row.duration
            definition.restText = row.rest
            definition.notes = row.notes
            if definition.modelContext == nil {
                targetPlan.exerciseDefinitions.append(definition)
                context.insert(definition)
            }
            definitionsBySourceID[row.id] = definition
            definitionsByName[normalized(row.name)] = definition
        }

        let calendar = Calendar.current
        let existingDayIDs = Set(((try? context.fetch(FetchDescriptor<PlanDay>())) ?? []).map(\.id))
        var existingDaysByDate: [Date: PlanDay] = [:]
        for day in targetPlan.days {
            existingDaysByDate[calendar.startOfDay(for: day.date)] = day
        }
        let currentSessions = (try? context.fetch(FetchDescriptor<Session>())) ?? []
        let currentItems = currentSessions.flatMap(\.items).filter { $0.planSourceId == targetPlan.id }
        let currentClimbs = ((try? context.fetch(FetchDescriptor<ClimbEntry>())) ?? []).filter { $0.planSourceId == targetPlan.id }
        let importedDates = Set(exchange.days.map { calendar.startOfDay(for: $0.date) })

        for dayRow in exchange.days {
            let dayDate = calendar.startOfDay(for: dayRow.date)
            let day = existingDaysByDate[dayDate] ?? {
                let created = PlanDay(id: existingDayIDs.contains(dayRow.id) ? UUID() : dayRow.id, date: dayDate)
                targetPlan.days.append(created)
                return created
            }()
            let dayItems = currentItems.filter { item in
                if let planDayId = item.planDayId { return planDayId == day.id }
                return sessionsDate(for: item, in: currentSessions, calendar: calendar) == dayDate
            }
            let dayClimbs = currentClimbs.filter { calendar.startOfDay(for: $0.dateLogged) == dayDate }
            let hasProtectedRecords = !dayItems.isEmpty || !dayClimbs.isEmpty

            if !hasProtectedRecords || isNew {
                day.type = resolveDayType(key: dayRow.dayTypeKey, name: dayRow.dayTypeName, color: dayRow.dayTypeColor, in: context)
                day.dailyNotes = dayRow.dailyNotes
            }

            let incomingDefinitions = dayRow.exerciseRefs.compactMap { sourceID, order in
                if let definition = definitionsBySourceID[sourceID] {
                    return (definition, order)
                }
                return nil
            }
            if !hasProtectedRecords || isNew {
                day.planExerciseIDs = incomingDefinitions.map { $0.0.id }
                day.chosenExercises = incomingDefinitions.map { $0.0.name }
                day.exerciseOrder = Dictionary(uniqueKeysWithValues: incomingDefinitions.map { ($0.0.name, $0.1) })
                day.chosenExerciseIDs = incomingDefinitions.compactMap { $0.0.catalogExerciseID }
                day.exerciseOrderByID = Dictionary(uniqueKeysWithValues: incomingDefinitions.compactMap { definition, order in
                    guard let catalogID = definition.catalogExerciseID else { return nil }
                    return (catalogID.uuidString, order)
                })
            } else {
                var names = incomingDefinitions.map { $0.0.name }
                var planIDs = incomingDefinitions.map { $0.0.id }
                for item in dayItems where !names.contains(item.exerciseName) {
                    names.append(item.exerciseName)
                    if let id = item.planExerciseID {
                        planIDs.append(id)
                    } else if let definition = definitionsByName[normalized(item.exerciseName)] {
                        planIDs.append(definition.id)
                    }
                }
                day.chosenExercises = names
                day.planExerciseIDs = planIDs
            }
        }

        if !isNew {
            targetPlan.days.removeAll { day in
                let date = calendar.startOfDay(for: day.date)
                guard !importedDates.contains(date) else { return false }
                let hasItems = currentItems.contains { item in
                    if let planDayId = item.planDayId { return planDayId == day.id }
                    return sessionsDate(for: item, in: currentSessions, calendar: calendar) == date
                }
                let hasClimbs = currentClimbs.contains { calendar.startOfDay(for: $0.dateLogged) == date }
                return !hasItems && !hasClimbs && !DayLogStore.hasContext(DayLogStore.fetchDayLog(for: date, in: context))
            }
        }

        applyContexts(exchange.contexts, in: context)
        let insertedLogs = importLogs(exchange.logs, into: targetPlan, definitions: definitionsBySourceID, isNew: isNew, in: context, calendar: calendar)
        let insertedClimbs = importClimbs(exchange.climbs, into: targetPlan, isNew: isNew, in: context, calendar: calendar)
        try context.save()

        return Summary(
            planName: targetPlan.name,
            dayCount: exchange.days.count,
            exerciseCount: exchange.exercises.count,
            logCount: insertedLogs,
            climbCount: insertedClimbs,
            warnings: exchange.warnings
        )
    }

    enum Error: Swift.Error, LocalizedError {
        case emptyFile
        case invalidHeader
        case missingPlanRow

        var errorDescription: String? {
            switch self {
            case .emptyFile: return "The plan CSV is empty."
            case .invalidHeader: return "This is not a supported plan CSV file."
            case .missingPlanRow: return "The plan CSV does not contain a valid plan row."
            }
        }
    }

    private static func importLogs(_ rows: [ParsedExchange.LogRow], into plan: Plan, definitions: [UUID: PlanExerciseDefinition], isNew: Bool, in context: ModelContext, calendar: Calendar) -> Int {
        var sessions = (try? context.fetch(FetchDescriptor<Session>())) ?? []
        let existingItems = (try? context.fetch(FetchDescriptor<SessionItem>())) ?? []
        var existingItemIDs = Set(existingItems.map(\.id))
        var inserted = 0
        for row in rows {
            let itemID: UUID
            if existingItemIDs.contains(row.id) {
                guard isNew else { continue }
                itemID = UUID()
            } else {
                itemID = row.id
            }
            let start = calendar.startOfDay(for: row.date)
            let session = sessions.first { calendar.startOfDay(for: $0.date) == start } ?? {
                let created = Session(id: UUID(), date: start)
                context.insert(created)
                sessions.append(created)
                return created
            }()
            let targetDayID = plan.days.first(where: { calendar.isDate($0.date, inSameDayAs: row.date) })?.id
            let item = SessionItem(id: itemID, exerciseName: row.name, planSourceId: plan.id, planName: plan.name, planDayId: targetDayID, planExerciseID: row.planExerciseID.flatMap { definitions[$0]?.id } ?? definitions.values.first(where: { normalized($0.name) == normalized(row.name) })?.id, reps: row.reps, sets: row.sets, weightKg: row.weight, grade: row.grade, notes: row.notes, duration: row.duration)
            session.items.append(item)
            existingItemIDs.insert(itemID)
            inserted += 1
        }
        return inserted
    }

    private static func importClimbs(_ rows: [ParsedExchange.ClimbRow], into plan: Plan, isNew: Bool, in context: ModelContext, calendar: Calendar) -> Int {
        let existing = (try? context.fetch(FetchDescriptor<ClimbEntry>())) ?? []
        var existingIDs = Set(existing.map(\.id))
        var inserted = 0
        for row in rows {
            let climbID: UUID
            if existingIDs.contains(row.id) {
                guard isNew else { continue }
                climbID = UUID()
            } else {
                climbID = row.id
            }
            let targetDayID = plan.days.first(where: { calendar.isDate($0.date, inSameDayAs: row.date) })?.id
            context.insert(ClimbEntry(id: climbID, climbType: row.type, ropeClimbType: row.ropeType, grade: row.grade, feelsLikeGrade: row.feelsLikeGrade, angleDegrees: row.angle, style: row.style, attempts: row.attempts, isWorkInProgress: row.isWIP, isPreviouslyClimbed: row.isPreviouslyClimbed, holdColor: row.holdColor, gym: row.gym, notes: row.notes, dateLogged: row.date, planSourceId: plan.id, planDayId: targetDayID, tb2ClimbUUID: row.tb2UUID))
            existingIDs.insert(climbID)
            inserted += 1
        }
        return inserted
    }

    private static func applyContexts(_ rows: [ParsedExchange.ContextRow], in context: ModelContext) {
        for row in rows {
            let existing = DayLogStore.fetchDayLog(for: row.date, in: context)
            if let existing, DayLogStore.hasContext(existing) { continue }
            let dayLog = existing ?? DayLogStore.dayLog(for: row.date, in: context)
            guard let dayLog else { continue }
            DayLogStore.setNote(row.note ?? "", for: dayLog)
            dayLog.tags = row.tags.compactMap { tag in
                DayLogStore.createTag(name: tag.name, colorKey: tag.colorKey, in: context)
            }
        }
    }

    private static func resolvePlanKind(_ row: ParsedExchange.PlanRow, in context: ModelContext) -> PlanKindModel? {
        guard let key = row.kindKey, !key.isEmpty else { return nil }
        if let existing = ((try? context.fetch(FetchDescriptor<PlanKindModel>())) ?? []).first(where: { $0.key == key }) { return existing }
        let kind = PlanKindModel(key: key, name: row.kindName ?? key.capitalized, totalWeeks: row.totalWeeks, isRepeating: row.isRepeating)
        context.insert(kind)
        return kind
    }

    private static func resolveDayType(key: String?, name: String?, color: String?, in context: ModelContext) -> DayTypeModel? {
        let types = (try? context.fetch(FetchDescriptor<DayTypeModel>())) ?? []
        if let key, let found = types.first(where: { $0.key == key }) { return found }
        if let name, let found = types.first(where: { $0.name == name }) { return found }
        guard let key = nonEmpty(key), let name = nonEmpty(name) else { return nil }
        let type = DayTypeModel(key: key, name: name, colorKey: color ?? "gray")
        context.insert(type)
        return type
    }

    private static func createImportedExercise(from row: ParsedExchange.ExerciseRow, in context: ModelContext) -> Exercise {
        let activities = (try? context.fetch(FetchDescriptor<Activity>())) ?? []
        let activity = activities.first(where: { normalized($0.name) == normalized("Imported") }) ?? {
            let created = Activity(name: "Imported")
            context.insert(created)
            return created
        }()
        let type = activity.types.first(where: { normalized($0.name) == normalized("Imported Plans") }) ?? {
            let created = TrainingType(name: "Imported Plans")
            activity.types.append(created)
            return created
        }()
        if let existing = type.exercises.first(where: { normalized($0.name) == normalized(row.name) }) { return existing }
        let existingExercises = (try? context.fetch(FetchDescriptor<Exercise>())) ?? []
        let importedID = if let catalogID = row.catalogID, !existingExercises.contains(where: { $0.id == catalogID }) {
            catalogID
        } else {
            UUID()
        }
        let exercise = Exercise(id: importedID, name: row.name, area: row.area, exerciseDescription: row.description, repsText: row.reps, durationText: row.duration, setsText: row.sets, restText: row.rest, notes: row.notes)
        type.exercises.append(exercise)
        context.insert(exercise)
        return exercise
    }

    private static func catalogExercises(in context: ModelContext) -> [Exercise] {
        let activities = (try? context.fetch(FetchDescriptor<Activity>())) ?? []
        var result: [Exercise] = []
        var seen: Set<UUID> = []
        for activity in activities {
            for type in activity.types {
                for exercise in type.exercises where seen.insert(exercise.id).inserted { result.append(exercise) }
                for combination in type.combinations {
                    for exercise in combination.exercises where seen.insert(exercise.id).inserted { result.append(exercise) }
                }
            }
        }
        return result
    }

    private static func sessionsDate(for item: SessionItem, in sessions: [Session], calendar: Calendar) -> Date? {
        sessions.first(where: { $0.items.contains(where: { $0.id == item.id }) }).map { calendar.startOfDay(for: $0.date) }
    }

    private static func row(type: String, values: [String: String]) -> String {
        var all = Array(repeating: "", count: headers.count)
        if let index = headers.firstIndex(of: "row_type") { all[index] = type }
        for (key, value) in values {
            if let index = headers.firstIndex(of: key) { all[index] = PlanCSVCodec.escape(value) }
        }
        return all.joined(separator: ",")
    }

    private static func normalizedHeader(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\u{FEFF}", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }

    private static func normalized(_ value: String) -> String { value.trimmingCharacters(in: .whitespacesAndNewlines).folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current) }
    private static func twoDigit(_ value: Int) -> String { value < 10 ? "0\(value)" : String(value) }
    private static func nonEmpty(_ value: String?) -> String? { guard let value else { return nil }; let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines); return trimmed.isEmpty ? nil : trimmed }
    private static func encodeDate(_ date: Date) -> String { ISO8601DateFormatter.planExchange.string(from: date) }
    private static func parseDate(_ raw: String) -> Date? { ISO8601DateFormatter.planExchange.date(from: raw) ?? DateFormatter.planExchange.date(from: raw) }
    private static func encodeTags(_ tags: [PlanCSVTag]) -> String { guard let data = try? JSONEncoder().encode(tags) else { return "[]" }; return String(decoding: data, as: UTF8.self) }
    private static func decodeTags(_ raw: String) -> [PlanCSVTag] { guard let data = raw.data(using: .utf8), let tags = try? JSONDecoder().decode([PlanCSVTag].self, from: data) else { return [] }; return tags }
    private static func parseExerciseRefs(_ raw: String) -> [(UUID, Int)] { raw.split(separator: ";").compactMap { part in let values = part.split(separator: ":"); guard values.count >= 1, let id = UUID(uuidString: String(values[0])) else { return nil }; return (id, Int(values[safe: 1].map(String.init) ?? "") ?? 0) } }
    private static func csvNumber(_ value: Double) -> String { value.formatted(.number.locale(Locale(identifier: "en_US_POSIX")).precision(.fractionLength(3))) }
    private static func stableID(_ value: String) -> UUID {
        let bytes = Array(SHA256.hash(data: Data(value.utf8)).prefix(16))
        let tuple: uuid_t = (
            bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7],
            bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]
        )
        return UUID(uuid: tuple)
    }
}

private enum PlanCSVCodec {
    static func escape(_ value: String) -> String {
        guard value.contains(",") || value.contains("\"") || value.contains("\n") || value.contains("\r") else { return value }
        return "\"\(value.replacingOccurrences(of: "\"", with: "\"\""))\""
    }

    static func line(_ record: String) -> [String] {
        var result: [String] = []
        var value = ""
        var quoted = false
        let chars = Array(record)
        var index = 0
        while index < chars.count {
            let character = chars[index]
            if character == "\"" {
                if quoted, index + 1 < chars.count, chars[index + 1] == "\"" { value.append("\""); index += 1 } else { quoted.toggle() }
            } else if character == "," && !quoted { result.append(value); value = "" } else { value.append(character) }
            index += 1
        }
        result.append(value)
        return result
    }

    static func records(_ csv: String) -> [String] {
        var result: [String] = []
        var current = ""
        var quoted = false
        let chars = Array(csv)
        var index = 0
        while index < chars.count {
            let character = chars[index]
            if character == "\"" {
                current.append(character)
                if quoted, index + 1 < chars.count, chars[index + 1] == "\"" { current.append(chars[index + 1]); index += 1 } else { quoted.toggle() }
            } else if character.isNewline && !quoted {
                if !current.isEmpty { result.append(current); current = "" }
                if character == "\r", index + 1 < chars.count, chars[index + 1] == "\n" { index += 1 }
            } else { current.append(character) }
            index += 1
        }
        if !current.isEmpty { result.append(current) }
        return result
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? { indices.contains(index) ? self[index] : nil }
}

private extension ISO8601DateFormatter {
    static var planExchange: ISO8601DateFormatter {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }
}

private extension DateFormatter {
    static var planExchange: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        return formatter
    }
}

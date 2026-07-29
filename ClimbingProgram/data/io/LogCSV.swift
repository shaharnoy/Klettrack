//
//  LogCSV.swift
//  Klettrack
//  Created by Shahar Noy on 02.09.25.
//

import Foundation
import SwiftUI
import SwiftData
import UniformTypeIdentifiers
import CryptoKit
import Photos
import UIKit

// MARK: - CSV FileDocument for export/share

struct LogCSVDocument: FileDocument {
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

// MARK: - CSV utilities (export + import)

enum LogCSV {

    /// Build a CSV snapshot from all Sessions + SessionItems + ClimbEntries in the store.
    static func makeExportCSV(context: ModelContext) -> LogCSVDocument {
        // Fetch sessions oldest → newest for nice reading
        let sessions: [Session] = (try? context.fetch(
            FetchDescriptor<Session>(sortBy: [SortDescriptor(\.date, order: .forward)])
        )) ?? []

        // Fetch climb entries oldest → newest
        let climbEntries: [ClimbEntry] = (try? context.fetch(
            FetchDescriptor<ClimbEntry>(sortBy: [SortDescriptor(\.dateLogged, order: .forward)])
        )) ?? []

        // Fetch all plans to look up day types
        let plans: [Plan] = (try? context.fetch(FetchDescriptor<Plan>())) ?? []
        
        // Header extended with climb_id, tb2_uuid and the timer columns at the end
        // (backward compatible: the importer resolves columns by name)
        var rows: [String] = ["date,type,exercise_name,climb_type,grade,feelsLikeGrade,angle,holdColor,rope_type,style,attempts,wip,ispreviouslyClimbed,gym,reps,sets,duration,weight_kg,plan_id,plan_name,day_type,notes,climb_id,tb2_uuid,media_refs,rest,timer_name,timer_spec,sets_detail,activity,training_type,shape"]

        // Catalog lookups by exercise name, built once — export walks SessionItems,
        // not catalog exercises, so a per-row fetch would be O(rows).
        // Rest lives only on the catalog Exercise (SessionItem has no rest field),
        // which is why it is sourced here rather than from the logged item.
        let allTemplates: [TimerTemplate] = (try? context.fetch(FetchDescriptor<TimerTemplate>())) ?? []
        let templatesById = Dictionary(allTemplates.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var timerByExerciseName: [String: TimerTemplate] = [:]
        var restByExerciseName: [String: String] = [:]
        // Plan rows have no logged item to read metrics from, so they source reps/sets/
        // duration/notes from the catalog guidance instead.
        var exerciseByName: [String: Exercise] = [:]
        for exercise in (try? context.fetch(FetchDescriptor<Exercise>())) ?? [] {
            if exerciseByName[exercise.name] == nil { exerciseByName[exercise.name] = exercise }
            if let rest = exercise.restText, !rest.isEmpty, restByExerciseName[exercise.name] == nil {
                restByExerciseName[exercise.name] = rest
            }
            guard let templateId = exercise.timerTemplateId,
                  let template = templatesById[templateId],
                  timerByExerciseName[exercise.name] == nil
            else { continue }
            timerByExerciseName[exercise.name] = template
        }

        // Where each exercise sits in the catalog. Exercise has no back-reference to its
        // TrainingType, so this walks down from Activity instead. Without it the path is
        // lost on export and has to be guessed on import, which is why re-imported
        // exercises all piled up under "Imported".
        //
        // ponytail: exercises filed under a combination export their parent training
        // type; the combination name isn't carried. Re-import puts them in the type,
        // which is the right node, one level up.
        var catalogPathByName: [String: (activity: String, type: String)] = [:]
        for activity in (try? context.fetch(FetchDescriptor<Activity>())) ?? [] {
            for type in activity.types {
                for exercise in type.exercises + type.combinations.flatMap(\.exercises)
                where catalogPathByName[exercise.name] == nil {
                    catalogPathByName[exercise.name] = (activity.name, type.name)
                }
            }
        }

        /// The three catalog columns for an exercise, blank when it isn't in the catalog.
        func catalogColumns(for exerciseName: String) -> [String] {
            let path = catalogPathByName[exerciseName]
            return [
                csvEscape(path?.activity ?? ""),
                csvEscape(path?.type ?? ""),
                exerciseByName[exerciseName]?.shapeKey ?? ""
            ]
        }

        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd HH:mm:ss"
        df.timeZone = TimeZone.current
        df.locale = Locale(identifier: "en_US_POSIX")

        var calendar = Calendar.current
        calendar.timeZone = TimeZone.current

        // Export exercises
        for s in sessions {
            let d = df.string(from: s.date)
            for i in s.items {
                // Find the day type for this session item (prefer DayType key)
                var dayType = ""
                if let planId = i.planSourceId {
                    if let plan = plans.first(where: { $0.id == planId }) {
                        let sessionStartOfDay = calendar.startOfDay(for: s.date)
                        if let planDay = plan.days.first(where: { calendar.startOfDay(for: $0.date) == sessionStartOfDay }) {
                            let key = planDay.type?.key.trimmingCharacters(in: .whitespacesAndNewlines)
                            let name = planDay.type?.name.trimmingCharacters(in: .whitespacesAndNewlines)
                            if let k = key, !k.isEmpty {
                                dayType = k
                            } else if let n = name, !n.isEmpty {
                                dayType = n
                            } else {
                                dayType = ""
                            }
                        }
                    }
                }
                
                let attachedTimer = timerByExerciseName[i.exerciseName]

                rows.append([
                    d,
                    "exercise", // type
                    csvEscape(i.exerciseName), // exercise_name
                    "", // climb_type
                    csvEscape(i.grade ?? ""), // grade
                    "", //feels like grade
                    "", // angle
                    "", // holdColor
                    "", // rope_type
                    "", // style
                    "", // attempts
                    "", // wip
                    "", //ispreviouslyClimbed
                    "", // gym
                    csvDecimal(i.reps),
                    csvDecimal(i.sets),
                    csvDecimal(i.duration),
                    csvDecimal(i.weightKg),
                    i.planSourceId?.uuidString ?? "",
                    csvEscape(i.planName ?? ""),
                    csvEscape(dayType),
                    csvEscape(i.notes ?? ""),
                    "", // climb_id (exercises don't use this)
                    "",  // tb2_uuid (exercises don't use this)
                    "",  // media_ref (exercises don't use this)
                    csvEscape(restByExerciseName[i.exerciseName] ?? ""),
                    csvEscape(attachedTimer?.name ?? ""),
                    csvEscape(attachedTimer.map { TimerSpec.encode($0) } ?? ""),
                    // The rollup above is lossy; without this a re-import would drop
                    // per-set weight, effort and notes.
                    csvEscape(i.loggedSets.csvEncoded)
                ].appending(catalogColumns(for: i.exerciseName)).joined(separator: ","))
            }
        }
        
        // Export climb entries
        for climb in climbEntries {
            let d = df.string(from: climb.dateLogged)

            // Encode all media refs as: assetId|type|createdAtISO;assetId2|type2|createdAt2;...
            let iso = ISO8601DateFormatter()
            let mediaRefs = climb.media.map { m in
                let created = iso.string(from: m.createdAt)
                return "\(m.assetLocalIdentifier)|\(m.type.rawValue)|\(created)"
            }.joined(separator: ";")

            rows.append([
                d,
                "climb",
                "", // exercise_name
                csvEscape(climb.climbType.rawValue),
                csvEscape(climb.grade),
                csvEscape(climb.feelsLikeGrade ?? ""),
                climb.angleDegrees.map { String($0) } ?? "",
                csvEscape(climb.holdColor?.rawValue ?? ""),
                csvEscape(climb.ropeClimbType?.rawValue ?? ""),
                csvEscape(climb.style),
                csvEscape(climb.attempts ?? ""),
                climb.isWorkInProgress ? "true" : "false",
                climb.isPreviouslyClimbed ?? false ? "true" : "false" ,
                csvEscape(climb.gym),
                "", // reps
                "", // sets
                "", // duration
                "", // weight_kg
                "", // plan_id
                "", // plan_name
                "", // day_type
                csvEscape(climb.notes ?? ""),
                climb.id.uuidString,                   // climb_id
                csvEscape(climb.tb2ClimbUUID ?? ""),   // tb2_uuid
                csvEscape(mediaRefs),                  // media_refs
                "",                                    // rest (climbs don't use this)
                "",                                    // timer_name (climbs don't use this)
                "",                                    // timer_spec (climbs don't use this)
                "",                                    // sets_detail (climbs don't use this)
                "",                                    // activity (a climb has no catalog entry)
                "",                                    // training_type
                ""                                     // shape
            ].joined(separator: ","))
        }

        // Export plan days as `type=plan` rows. Without these a plan only appears in the
        // CSV to the extent it was logged against, so a plan day nobody performed yet
        // round-trips to nothing. The importer never turns these into logged items.
        for plan in plans.sorted(by: { $0.startDate < $1.startDate }) {
            for day in plan.days.sorted(by: { $0.date < $1.date }) {
                let d = df.string(from: day.date)

                let key = day.type?.key.trimmingCharacters(in: .whitespacesAndNewlines)
                let name = day.type?.name.trimmingCharacters(in: .whitespacesAndNewlines)
                let dayType = (key?.isEmpty == false) ? key! : ((name?.isEmpty == false) ? name! : "")

                // Same order the plan day editor shows: manual order first, then by name.
                let ordered = day.chosenExercises.sorted { first, second in
                    let firstOrder = day.exerciseOrder[first] ?? .max
                    let secondOrder = day.exerciseOrder[second] ?? .max
                    if firstOrder != secondOrder { return firstOrder < secondOrder }
                    return first.localizedStandardCompare(second) == .orderedAscending
                }

                for exerciseName in ordered {
                    let catalogEntry = exerciseByName[exerciseName]
                    let attachedTimer = timerByExerciseName[exerciseName]
                    // Guidance text is hand-written ("3-5 mins", "45 sec"), so reuse the
                    // parsers the timer already relies on rather than inventing another.
                    let reps = ExerciseTimerDefaults.parseCount(catalogEntry?.repsText)
                    let sets = ExerciseTimerDefaults.parseCount(catalogEntry?.setsText)
                    let durationMinutes = ExerciseTimerDefaults
                        .parseSeconds(catalogEntry?.durationText)
                        .map { Double($0) / 60 }

                    rows.append([
                        d,
                        "plan", // type
                        csvEscape(exerciseName),
                        "", // climb_type
                        "", // grade
                        "", // feels like grade
                        "", // angle
                        "", // holdColor
                        "", // rope_type
                        "", // style
                        "", // attempts
                        "", // wip
                        "", // ispreviouslyClimbed
                        "", // gym
                        reps.map { String($0) } ?? "",
                        sets.map { String($0) } ?? "",
                        csvDecimal(durationMinutes),
                        "", // weight_kg (a plan carries no load)
                        plan.id.uuidString,
                        csvEscape(plan.name),
                        csvEscape(dayType),
                        csvEscape(catalogEntry?.notes ?? ""),
                        "", // climb_id
                        "", // tb2_uuid
                        "", // media_refs
                        csvEscape(restByExerciseName[exerciseName] ?? ""),
                        csvEscape(attachedTimer?.name ?? ""),
                        csvEscape(attachedTimer.map { TimerSpec.encode($0) } ?? ""),
                        "" // sets_detail (a plan has nothing performed yet)
                    ].appending(catalogColumns(for: exerciseName)).joined(separator: ","))
                }
            }
        }

        return LogCSVDocument(csv: rows.joined(separator: "\n"))
    }
}

// MARK: - Helpers

private extension Array {
    /// Append a run of cells to a row under construction, so the three catalog columns
    /// read as one step at each call site rather than three more literals.
    func appending(_ other: [Element]) -> [Element] { self + other }
}

/// Basic CSV escaping (quote if needed; escape inner quotes)
private func csvEscape(_ s: String) -> String {
    if s.contains(",") || s.contains("\"") || s.contains("\n") {
        let escaped = s.replacingOccurrences(of: "\"", with: "\"\"")
        return "\"\(escaped)\""
    }
    return s
}

private let csvDecimalFormat = FloatingPointFormatStyle<Double>.number
    .locale(Locale(identifier: "en_US_POSIX"))
    .precision(.fractionLength(3))

private func csvDecimal(_ value: Double?) -> String {
    value.map { $0.formatted(csvDecimalFormat) } ?? ""
}

/// Parse one CSV line (supports quoted cells with commas/quotes)
private func parseCSVLine(_ line: String) -> [String] {
    var out: [String] = []
    var cur = ""
    var inQuotes = false
    let chars = Array(line)

    var i = 0
    while i < chars.count {
        let c = chars[i]
        if c == "\"" {
            if inQuotes, i + 1 < chars.count, chars[i + 1] == "\"" {
                cur.append("\"") // escaped quote
                i += 1
            } else {
                inQuotes.toggle()
            }
        } else if c == "," && !inQuotes {
            out.append(cur)
            cur = ""
        } else {
            cur.append(c)
        }
        i += 1
    }
    out.append(cur)
    return out
}

/// Build a dedupe signature for an item row
private func itemSignature(date: Date,
                           name: String,
                           reps: Double?,
                           sets: Double?,
                           duration: Double?,
                           weight: Double?,
                           planId: UUID?,
                           planName: String?,
                           notes: String?) -> String {
    func norm(_ s: String?) -> String {
        (s ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
    let df = ISO8601DateFormatter()
    df.formatOptions = [.withFullDate]
    // Exclude notes from deduplication signature since notes can vary for the same exercise
    return [
        df.string(from: date),
        norm(name),
        csvDecimal(reps),
        csvDecimal(sets),
        csvDecimal(duration),
        csvDecimal(weight),
        planId?.uuidString ?? "",
        norm(planName)
        // Notes intentionally excluded from deduplication
    ].joined(separator: "|")
}

/// Build a dedupe signature for a climb entry
private func climbSignature(date: Date,
                            climbType: ClimbType,
                            grade: String,
                            feelsLikeGrade: String,
                            angle: Int?,
                            holdColor: String?,
                            style: String,
                            attempts: String?,
                            isWIP: Bool,
                            ispreviouslyClimbed: Bool,
                            gym: String,
                            notes: String?) -> String {
    func norm(_ s: String?) -> String {
        (s ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
    let df = ISO8601DateFormatter()
    df.formatOptions = [.withFullDate]
    
    return [
        df.string(from: date),
        climbType.rawValue,
        norm(grade),
        norm(feelsLikeGrade),
        angle?.description ?? "",
        norm(holdColor),
        norm(style),
        norm(attempts),
        isWIP ? "true" : "false",
        ispreviouslyClimbed ? "true" : "false",
        norm(gym)
        // Notes intentionally excluded from deduplication
    ].joined(separator: "|")
}

// Safe indexing helper
private extension Array {
    subscript(safe idx: Int) -> Element? {
        indices.contains(idx) ? self[idx] : nil
    }
}

extension LogCSV {
    
    struct Entry {
        let date: Date
        let type: String // "exercise" or "climb"
        let name: String
        let climbType: String?
        let grade: String?
        let feelsLikeGrade: String?
        let angle: Int?
        let holdColor: String?
        let ropeType: String?
        let style: String?
        let attempts: String?
        let isWIP: Bool
        let ispreviouslyClimbed: Bool
        let gym: String?
        let reps: Double?
        let sets: Double?
        let duration: Double?
        let weight: Double?
        let planId: UUID?
        let planName: String?
        let dayTypeKey: String?
        let notes: String?
        let climbId: UUID?
        let tb2UUID: String?
        let mediaRefs: String?
        let restText: String?
        let timerName: String?
        let timerSpec: String?
        let loggedSets: [LoggedSet]
        /// Where this exercise belongs in the catalog, when the file says.
        let activityName: String?
        let trainingTypeName: String?
        let shape: ExerciseShape?
    }

    @MainActor
    static func importCSVAsync(
        from url: URL,
        into context: ModelContext,
        tag: String? = nil,
        dedupe: Bool = true,
        progress: ((Double) -> Void)? = nil
    ) async throws -> Int {
        
        // Start security-scoped access (if needed)
        let didAccess = url.startAccessingSecurityScopedResource()
        defer { if didAccess { url.stopAccessingSecurityScopedResource() } }
        
        //Read + parse OFF-MAIN (no ModelContext captured)
        let entries: [Entry] = try await Task.detached(priority: .userInitiated) { () -> [Entry] in
            let data = try Data(contentsOf: url)
            guard let text = String(data: data, encoding: .utf8) else { return [] }
            
            let lines = text.split(whereSeparator: \.isNewline).map(String.init)
            guard !lines.isEmpty else { return [] }
            
            // --- Header-based mapping ---
            // Parse the first line as potential header
            let headerParts = parseCSVLine(lines[0]).map {
                $0.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            // Build a raw header index (lowercased, strip spaces/underscores)
            func norm(_ s: String) -> String {
                s.lowercased()
                    .replacingOccurrences(of: " ", with: "")
                    .replacingOccurrences(of: "_", with: "")
            }
            var headerIndex: [String: Int] = [:]
            for (i, h) in headerParts.enumerated() {
                headerIndex[norm(h)] = i
            }
            
            // Recognize if a header is present by looking for key columns via aliases
            func idx(_ aliases: [String]) -> Int? {
                for a in aliases { if let i = headerIndex[norm(a)] { return i } }
                return nil
            }
            
            // Column aliases (expand in case of naming changes)
            struct Cols {
                static let date       = ["date"]
                static let type       = ["type"]
                static let exercise   = ["exercise_name"]
                static let climbType  = ["climb_type"]
                static let grade      = ["grade"]
                static let feelsLikeGrade = ["feelsLikeGrade", "feelslikegrade"]
                static let angle      = ["angle"]
                static let holdColor  = ["hold_color", "holdcolor"]
                static let ropeType   = ["rope_type"]
                static let style      = ["style"]
                static let attempts   = ["attempts"]
                static let wip        = ["wip", "is_wip", "isworkinprogress"]
                static let ispreviouslyClimbed = ["ispreviouslyclimbed", "previouslyclimbed"]
                static let gym        = ["gym"]
                static let reps       = ["reps"]
                static let sets       = ["sets"]
                static let duration   = ["duration", "time"]
                static let weight     = ["weight_kg", "weight", "kg"]
                static let planId     = ["plan_id", "planid"]
                static let planName   = ["plan_name"]
                static let dayType    = ["day_type", "daytype"]
                static let notes      = ["notes", "note", "comment", "comments"]
                static let climbId    = ["climb_id", "climbid"]
                static let tb2UUID    = ["tb2_uuid", "tb2"]
                static let mediaRefs  = ["media_refs", "media"]
                static let rest       = ["rest", "rest_text"]
                static let timerName  = ["timer_name", "timer"]
                static let timerSpec  = ["timer_spec", "timer_config"]
                static let setsDetail = ["sets_detail", "setsdetail"]
                static let activity   = ["activity", "activity_name"]
                static let trainingType = ["training_type", "trainingtype", "type_name"]
                static let shape      = ["shape", "measured_in"]
            }
            
            let hasHeader = (idx(Cols.date) != nil && idx(Cols.type) != nil)
            let startIdx = hasHeader ? 1 : 0
            
            let df = DateFormatter()
            df.dateFormat = "yyyy-MM-dd HH:mm:ss"
            df.timeZone = TimeZone.current
            df.locale = Locale(identifier: "en_US_POSIX")

            
            // Helper for per-row value lookup by aliases
            func val(_ parts: [String], _ aliases: [String]) -> String {
                guard hasHeader, let i = idx(aliases), i < parts.count else { return "" }
                return parts[i]
            }
            
            var out: [Entry] = []
            out.reserveCapacity(max(0, lines.count - startIdx))
            
            for (n, rowIndex) in (startIdx..<lines.count).enumerated() {
                if n % 500 == 0 { await Task.yield() }
                
                let parts = parseCSVLine(lines[rowIndex])
                
                // Skip empty lines
                if parts.isEmpty || parts.allSatisfy({ $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) {
                    continue
                }
                
                // --- Extract values (header-based or legacy positional fallback) ---
                let dateStr, typeStr, exerciseName, climbTypeStr, gradeStr,feelsLikeGradeStr, angleStr, holdColorStr, ropeTypeStr, styleStr, attemptsStr, wipStr,ispreviouslyClimbedStr, gymStr, repsStr, setsStr, durationStr, weightStr, planIdStr, planName, dayTypeStr, notesRaw, climbIdStr, tb2UUIDStr, mediaRefsStr, restTextStr, timerNameStr, timerSpecStr, setsDetailStr, activityStr, trainingTypeStr, shapeStr: String
                
                if hasHeader {
                    dateStr      = val(parts, Cols.date)
                    typeStr      = val(parts, Cols.type)
                    exerciseName = val(parts, Cols.exercise)
                    climbTypeStr = val(parts, Cols.climbType)
                    gradeStr     = val(parts, Cols.grade)
                    feelsLikeGradeStr = val(parts, Cols.feelsLikeGrade)
                    angleStr     = val(parts, Cols.angle)
                    holdColorStr = val(parts, Cols.holdColor)
                    ropeTypeStr  = val(parts, Cols.ropeType)
                    styleStr     = val(parts, Cols.style)
                    attemptsStr  = val(parts, Cols.attempts)
                    wipStr       = val(parts, Cols.wip)
                    ispreviouslyClimbedStr = val(parts, Cols.ispreviouslyClimbed)
                    gymStr       = val(parts, Cols.gym)
                    repsStr      = val(parts, Cols.reps)
                    setsStr      = val(parts, Cols.sets)
                    durationStr  = val(parts, Cols.duration)
                    weightStr    = val(parts, Cols.weight)
                    planIdStr    = val(parts, Cols.planId)
                    planName     = val(parts, Cols.planName)
                    dayTypeStr   = val(parts, Cols.dayType)
                    notesRaw     = val(parts, Cols.notes)
                    climbIdStr   = val(parts, Cols.climbId)
                    tb2UUIDStr   = val(parts, Cols.tb2UUID)
                    mediaRefsStr = val(parts, Cols.mediaRefs)
                    // Absent in older exports — `val` returns "" and the row is unaffected.
                    restTextStr  = val(parts, Cols.rest)
                    timerNameStr = val(parts, Cols.timerName)
                    timerSpecStr = val(parts, Cols.timerSpec)
                    setsDetailStr = val(parts, Cols.setsDetail)
                    activityStr  = val(parts, Cols.activity)
                    trainingTypeStr = val(parts, Cols.trainingType)
                    shapeStr     = val(parts, Cols.shape)
                } else {
                    // Legacy positional fallback (will be removed in future)
                    func p(_ i: Int) -> String { parts.indices.contains(i) ? parts[i] : "" }
                    dateStr      = p(0)
                    typeStr      = p(1)
                    exerciseName = p(2)
                    climbTypeStr = p(3)
                    gradeStr     = p(4)
                    angleStr     = p(5)
                    holdColorStr = p(6)
                    ropeTypeStr  = p(7)
                    styleStr     = p(8)
                    attemptsStr  = p(9)
                    wipStr       = p(10)
                    ispreviouslyClimbedStr = p(11)
                    gymStr       = p(12)
                    repsStr      = p(13)
                    setsStr      = p(14)
                    durationStr  = p(15)
                    weightStr    = p(16)
                    planIdStr    = p(17)
                    planName     = p(18)
                    dayTypeStr   = p(19)
                    notesRaw     = p(20)
                    climbIdStr   = p(21)
                    tb2UUIDStr   = p(22)
                    mediaRefsStr = ""   // no media column in legacy CSV
                    feelsLikeGradeStr = "" //no alternative grade in legacy CSV
                    restTextStr  = ""   // no rest column in legacy CSV
                    timerNameStr = ""   // no timer columns in legacy CSV
                    timerSpecStr = ""
                    setsDetailStr = ""  // no per-set column in legacy CSV
                    activityStr  = ""   // no catalog-path columns in legacy CSV
                    trainingTypeStr = ""
                    shapeStr     = ""
                }
                
                // Minimal validity check
                guard
                    let dayDate = df.date(from: dateStr),
                    !typeStr.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                else { continue }
                
                // Normalize/convert
                let type = typeStr.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                let grade = gradeStr.trimmingCharacters(in: .whitespacesAndNewlines)
                let feelsLikeGrade = feelsLikeGradeStr.trimmingCharacters(in: .whitespacesAndNewlines)
                let angle = angleStr.isEmpty ? nil : Int(angleStr)
                let holdColor = holdColorStr.isEmpty ? nil : holdColorStr
                let ropeType = ropeTypeStr.isEmpty ? nil : ropeTypeStr
                let style = styleStr.trimmingCharacters(in: .whitespacesAndNewlines)
                let attempts = attemptsStr.trimmingCharacters(in: .whitespacesAndNewlines)
                let isWIP = wipStr.lowercased() == "true"
                let ispreviouslyClimbed = ispreviouslyClimbedStr.lowercased() == "true"
                let gym = gymStr.trimmingCharacters(in: .whitespacesAndNewlines)
                let name = exerciseName.trimmingCharacters(in: .whitespacesAndNewlines)
                let reps = Double(repsStr.replacingOccurrences(of: ",", with: ".")
                    .trimmingCharacters(in: .whitespacesAndNewlines))
                let sets = Double(setsStr.replacingOccurrences(of: ",", with: ".")
                    .trimmingCharacters(in: .whitespacesAndNewlines))
                let duration = Double(durationStr.replacingOccurrences(of: ",", with: ".")
                    .trimmingCharacters(in: .whitespacesAndNewlines))
                let weight = Double(weightStr
                    .replacingOccurrences(of: ",", with: ".")
                    .trimmingCharacters(in: .whitespacesAndNewlines))
                let planId = UUID(uuidString: planIdStr)
                let dayTypeKey = dayTypeStr.isEmpty ? nil : dayTypeStr
                let notes = notesRaw.trimmingCharacters(in: .whitespacesAndNewlines)
                let notesOpt = notes.isEmpty ? nil : notes
                let climbId = UUID(uuidString: climbIdStr)
                let tb2uuid = tb2UUIDStr.trimmingCharacters(in: .whitespacesAndNewlines)
                let tb2uuidOpt = tb2uuid.isEmpty ? nil : tb2uuid
                let mediaRefsValue = mediaRefsStr.trimmingCharacters(in: .whitespacesAndNewlines)
                let mediaRefsOpt = mediaRefsValue.isEmpty ? nil : mediaRefsValue
                
                out.append(Entry(
                    date: dayDate,
                    type: type,
                    name: name,
                    climbType: climbTypeStr.isEmpty ? nil : climbTypeStr,
                    grade: grade.isEmpty ? nil : grade,
                    feelsLikeGrade: feelsLikeGrade.isEmpty ? nil : feelsLikeGrade,
                    angle: angle,
                    holdColor: holdColor,
                    ropeType: ropeType,
                    style: style.isEmpty ? nil : style,
                    attempts: attempts.isEmpty ? nil : attempts,
                    isWIP: isWIP,
                    ispreviouslyClimbed: ispreviouslyClimbed,
                    gym: gym.isEmpty ? nil : gym,
                    reps: reps,
                    sets: sets,
                    duration: duration,
                    weight: weight,
                    planId: planId,
                    planName: planName.isEmpty ? nil : planName,
                    dayTypeKey: dayTypeKey,
                    notes: notesOpt,
                    climbId: climbId,
                    tb2UUID: tb2uuidOpt,
                    mediaRefs: mediaRefsOpt,
                    restText: restTextStr.isEmpty ? nil : restTextStr,
                    timerName: timerNameStr.isEmpty ? nil : timerNameStr,
                    timerSpec: timerSpecStr.isEmpty ? nil : timerSpecStr,
                    loggedSets: [LoggedSet].csvDecoded(setsDetailStr),
                    activityName: activityStr.isEmpty ? nil : activityStr,
                    trainingTypeName: trainingTypeStr.isEmpty ? nil : trainingTypeStr,
                    shape: ExerciseShape(rawValue: shapeStr)
                ))
            }
            
            return out
        }.value
        
        guard !entries.isEmpty else {
            progress?(1.0)
            return 0
        }
        
        // Optional half-way signal after parse
        progress?(0.5)
        
        //Apply ON MAIN (safe for ModelContext) + progressive progress
        let cal = Calendar.current
        var inserted = 0
        
        // Cache sessions per day to avoid repeated fetches
        var sessionCache: [Date: Session] = [:]
        sessionCache.reserveCapacity(32)
        
        // Cache plans we create/find during import
        var knownPlans: [UUID: Plan] = [:]
        
        // Cache signature sets per session for dedupe
        var sigCache: [ObjectIdentifier: Set<String>] = [:]
        
        // Track exercises by date for each plan to reconstruct plan structure.
        // Ordered, not a Set: row order in the file is the plan author's intent.
        var planExercisesByDate: [UUID: [Date: [String]]] = [:]

        // Track day types by date for each plan to preserve day type information
        var planDayTypesByDate: [UUID: [Date: String]] = [:]

        // Names contributed by `type=plan` rows, per plan and day. Two jobs: a plan with
        // an entry here is a template import, which may heal a plan that already has days
        // (log rows keep the old behaviour of only rebuilding a plan with no days at all);
        // and only these names count toward the returned total, because a log row's
        // contribution is already counted as its SessionItem.
        var planRowNames: [UUID: [Date: Set<String>]] = [:]

        // A plan row with a blank plan_id forks a fresh plan. Minted once per
        // plan_name so every such row in the file joins the same new plan.
        var mintedPlanIdsByName: [String: UUID] = [:]

        // Collect imported plan exercises (first occurrence wins) so we can
        // make sure they exist in the catalog after import
        var catalogCandidates: [String: CatalogCandidate] = [:]

        for (idx, e) in entries.enumerated() {
            // Progress from 0.5 → 1.0 during application
            if idx % 50 == 0 {
                let p = 0.5 + 0.5 * (Double(idx) / Double(entries.count))
                progress?(min(max(p, 0.5), 1.0))
            }
            
            let startOfDay = cal.startOfDay(for: e.date)
            
            if e.type == "exercise" || e.type == "plan" {
                guard !e.name.isEmpty else { continue }

                let isPlanRow = e.type == "plan"
                let rowPlanName = e.planName?.trimmingCharacters(in: .whitespacesAndNewlines)

                // ponytail: a log row naming a plan it cannot identify is history against
                // a plan that was forked by blanking plan_id. Importing it would duplicate
                // logs already in the store, because itemSignature keys on the plan id and
                // nil never matches the original. Drop it; the template rows still land.
                if !isPlanRow, e.planId == nil, rowPlanName?.isEmpty == false { continue }

                // Plan identity. A plan row with a blank (or unreadable) plan_id forks a
                // fresh plan; a known id updates that plan in place. Log rows never mint,
                // so their dedupe signature stays stable across re-imports.
                let rowPlanId: UUID?
                if let given = e.planId {
                    rowPlanId = given
                } else if isPlanRow, let name = rowPlanName, !name.isEmpty {
                    if let minted = mintedPlanIdsByName[name] {
                        rowPlanId = minted
                    } else {
                        let fresh = UUID()
                        mintedPlanIdsByName[name] = fresh
                        rowPlanId = fresh
                    }
                } else {
                    rowPlanId = nil
                }

                // Handle plan reference if present
                if let planId = rowPlanId, !knownPlans.keys.contains(planId), let planName = e.planName {
                    let planDescriptor = FetchDescriptor<Plan>(predicate: #Predicate<Plan> { $0.id == planId })
                    if let existing = try? context.fetch(planDescriptor).first {
                        knownPlans[planId] = existing
                    } else {
                        let kindFetch = FetchDescriptor<PlanKindModel>(predicate: #Predicate { $0.key == "weekly" })
                        let weeklyKind = (try? context.fetch(kindFetch))?.first
                        let plan = Plan(id: planId, name: planName, kind: weeklyKind, startDate: startOfDay)
                        context.insert(plan)
                        knownPlans[planId] = plan
                    }
                }
                
                // Track exercises for plan reconstruction
                if let planId = rowPlanId {
                    if isPlanRow { planRowNames[planId, default: [:]][startOfDay, default: []].insert(e.name) }

                    // Append-if-absent keeps the file's row order for the day.
                    var names = planExercisesByDate[planId]?[startOfDay] ?? []
                    if !names.contains(e.name) { names.append(e.name) }
                    planExercisesByDate[planId, default: [:]][startOfDay] = names

                    if let dayTypeKey = e.dayTypeKey {
                        planDayTypesByDate[planId, default: [:]][startOfDay] = dayTypeKey
                    }

                    // Remember plan exercises for catalog reconciliation
                    if catalogCandidates[e.name] == nil {
                        catalogCandidates[e.name] = CatalogCandidate(
                            reps: e.reps,
                            sets: e.sets,
                            duration: e.duration,
                            restText: e.restText,
                            notes: e.notes,
                            planName: e.planName,
                            timerName: e.timerName,
                            timerSpec: e.timerSpec,
                            activityName: e.activityName,
                            trainingTypeName: e.trainingTypeName,
                            shape: e.shape
                        )
                    }
                }

                // ponytail: a planned exercise is not a performed one. Plan rows describe
                // the template only, so they stop here — no Session, no SessionItem.
                if isPlanRow { continue }

                // Find or create session for this day
                let session: Session
                if let cached = sessionCache[startOfDay] {
                    session = cached
                } else {
                    let endOfDay = cal.date(byAdding: .day, value: 1, to: startOfDay)!
                    let fetch = FetchDescriptor<Session>(predicate: #Predicate {
                        $0.date >= startOfDay && $0.date < endOfDay
                    })
                    let matches = (try? context.fetch(fetch)) ?? []
                    if let found = matches.first {
                        session = found
                    } else {
                        let s = Session(date: startOfDay)
                        context.insert(s)
                        session = s
                    }
                    sessionCache[startOfDay] = session
                }

                // Build/get signature set for dedupe
                let sid = ObjectIdentifier(session)
                var existing = sigCache[sid]
                if existing == nil {
                    existing = Set(session.items.map {
                        itemSignature(date: session.date,
                                      name: $0.exerciseName,
                                      reps: $0.reps,
                                      sets: $0.sets,
                                      duration: $0.duration,
                                      weight: $0.weightKg,
                                      planId: $0.planSourceId,
                                      planName: $0.planName,
                                      notes: $0.notes)
                    })
                }
                
                let sig = itemSignature(date: session.date,
                                        name: e.name,
                                        reps: e.reps,
                                        sets: e.sets,
                                        duration: e.duration,
                                        weight: e.weight,
                                        planId: e.planId,
                                        planName: e.planName,
                                        notes: e.notes)
                
                if !dedupe || !(existing?.contains(sig) ?? false) {
                    let item = SessionItem(
                        exerciseName: e.name,
                        planSourceId: e.planId,
                        planName: e.planName,
                        reps: e.reps,
                        sets: e.sets,
                        weightKg: e.weight,
                        grade: e.grade,
                        notes: e.notes,
                        duration: e.duration,
                        loggedSets: e.loggedSets
                    )
                    item.sourceTag = tag
                    session.items.append(item)
                    existing?.insert(sig)
                    inserted += 1
                }
                
                sigCache[sid] = existing ?? []
                
            } else if e.type == "climb" {
                // Handle climb entries
                guard let grade = e.grade, !grade.isEmpty else { continue }
                
                let climbType: ClimbType
                if let climbTypeStr = e.climbType, let parsedType = ClimbType(rawValue: climbTypeStr) {
                    climbType = parsedType
                } else {
                    climbType = .boulder // default
                }
                let ropeClimbType = e.ropeType.flatMap { RopeClimbType(rawValue: $0) }
                
                //Upsert by explicit climb_id if provided
                if let providedId = e.climbId {
                    let fetch = FetchDescriptor<ClimbEntry>(predicate: #Predicate { $0.id == providedId })
                    if let existing = (try? context.fetch(fetch))?.first {
                        existing.climbType = climbType
                        existing.grade = grade
                        existing.feelsLikeGrade = e.feelsLikeGrade
                        existing.angleDegrees = e.angle
                        existing.style = e.style?.isEmpty == false ? e.style! : "Unknown"
                        existing.attempts = e.attempts
                        existing.isWorkInProgress = e.isWIP
                        existing.isPreviouslyClimbed = e.ispreviouslyClimbed
                        existing.holdColor = e.holdColor.flatMap { HoldColor(rawValue: $0) }
                        existing.ropeClimbType = ropeClimbType
                        existing.gym = e.gym?.isEmpty == false ? e.gym! : "Unknown"
                        existing.notes = e.notes
                        existing.dateLogged = e.date
                        if let tb2 = e.tb2UUID { existing.tb2ClimbUUID = tb2 }
                    } else {
                        let climbEntry = ClimbEntry(
                            id: providedId,
                            climbType: climbType,
                            ropeClimbType: ropeClimbType,
                            grade: grade,
                            feelsLikeGrade: e.feelsLikeGrade,
                            angleDegrees: e.angle,
                            style: e.style?.isEmpty == false ? e.style! : "Unknown",
                            attempts: e.attempts,
                            isWorkInProgress: e.isWIP,
                            isPreviouslyClimbed: e.ispreviouslyClimbed,
                            holdColor: e.holdColor.flatMap { HoldColor(rawValue: $0) },
                            gym: e.gym?.isEmpty == false ? e.gym! : "Unknown",
                            notes: e.notes,
                            dateLogged: e.date,
                            tb2ClimbUUID: e.tb2UUID
                        )
                        context.insert(climbEntry)
                        attachMedia(from: e.mediaRefs, to: climbEntry, in: context)
                        inserted += 1
                    }
                    continue
                }
                
                //Stable TB2 id upsert
                if let tb2 = e.tb2UUID {
                    let stable = stableID(
                        climbUUID: tb2,
                        day: startOfDay,
                        angle: e.angle,
                        isMirror: false,
                        isAscent: !e.isWIP
                    )
                    let fetch = FetchDescriptor<ClimbEntry>(predicate: #Predicate { $0.id == stable })
                    if let existing = (try? context.fetch(fetch))?.first {
                        existing.climbType = climbType
                        existing.grade = grade
                        existing.feelsLikeGrade = e.feelsLikeGrade
                        existing.angleDegrees = e.angle
                        existing.style = e.style?.isEmpty == false ? e.style! : "Unknown"
                        existing.attempts = e.attempts
                        existing.isWorkInProgress = e.isWIP
                        existing.isPreviouslyClimbed = e.ispreviouslyClimbed
                        existing.holdColor = e.holdColor.flatMap { HoldColor(rawValue: $0) }
                        existing.ropeClimbType = ropeClimbType
                        existing.gym = e.gym?.isEmpty == false ? e.gym! : "Unknown"
                        existing.notes = e.notes
                        existing.dateLogged = startOfDay
                        existing.tb2ClimbUUID = tb2
                    } else {
                        let climbEntry = ClimbEntry(
                            id: stable,
                            climbType: climbType,
                            ropeClimbType: ropeClimbType,
                            grade: grade,
                            feelsLikeGrade: e.feelsLikeGrade,
                            angleDegrees: e.angle,
                            style: e.style?.isEmpty == false ? e.style! : "Unknown",
                            attempts: e.attempts,
                            isWorkInProgress: e.isWIP,
                            isPreviouslyClimbed: e.ispreviouslyClimbed,
                            holdColor: e.holdColor.flatMap { HoldColor(rawValue: $0) },
                            gym: e.gym?.isEmpty == false ? e.gym! : "Unknown",
                            notes: e.notes,
                            dateLogged: e.date,
                            tb2ClimbUUID: tb2
                        )
                        context.insert(climbEntry)
                        attachMedia(from: e.mediaRefs, to: climbEntry, in: context)
                        inserted += 1
                    }
                    continue

                }
                
                //Fallback: DEDUPE by content signature (legacy CSVs)
                if dedupe {
                    let climbSig = climbSignature(
                        date: startOfDay,
                        climbType: climbType,
                        grade: grade,
                        feelsLikeGrade: e.feelsLikeGrade ?? "",
                        angle: e.angle,
                        holdColor: e.holdColor,
                        style: e.style ?? "",
                        attempts: e.attempts,
                        isWIP: e.isWIP,
                        ispreviouslyClimbed: e.ispreviouslyClimbed,
                        gym: e.gym ?? "",
                        notes: e.notes
                    )
                    
                    let endOfDay = cal.date(byAdding: .day, value: 1, to: startOfDay)!
                    let climbDescriptor = FetchDescriptor<ClimbEntry>(predicate: #Predicate<ClimbEntry> {
                        $0.dateLogged >= startOfDay && $0.dateLogged < endOfDay
                    })
                    let existingClimbs = (try? context.fetch(climbDescriptor)) ?? []
                    
                    let duplicate = existingClimbs.first { climb in
                        let existingSig = climbSignature(
                            date: Calendar.current.startOfDay(for: climb.dateLogged),
                            climbType: climb.climbType,
                            grade: climb.grade,
                            feelsLikeGrade: climb.feelsLikeGrade ?? "",
                            angle: climb.angleDegrees,
                            holdColor: climb.holdColor?.rawValue,
                            style: climb.style,
                            attempts: climb.attempts,
                            isWIP: climb.isWorkInProgress,
                            ispreviouslyClimbed: climb.isPreviouslyClimbed ?? false,
                            gym: climb.gym,
                            notes: climb.notes
                        )
                        return existingSig == climbSig
                    }
                    
                    if duplicate != nil { continue }
                }
                
                // Create climb entry (no id / no tb2 uuid path)
                let climbEntry = ClimbEntry(
                    climbType: climbType,
                    grade: grade,
                    feelsLikeGrade: e.feelsLikeGrade,
                    angleDegrees: e.angle,
                    style: e.style?.isEmpty == false ? e.style! : "Unknown",
                    attempts: e.attempts,
                    isWorkInProgress: e.isWIP,
                    isPreviouslyClimbed: e.ispreviouslyClimbed,
                    holdColor: e.holdColor.flatMap { HoldColor(rawValue: $0) },
                    gym: e.gym?.isEmpty == false ? e.gym! : "Unknown",
                    notes: e.notes,
                    dateLogged: e.date
                )
                context.insert(climbEntry)
                attachMedia(from: e.mediaRefs, to: climbEntry, in: context)
                inserted += 1

            }
        }
        
        // After processing all rows, populate the plans with their days and exercises
        for (planId, exercisesByDate) in planExercisesByDate {
            guard let plan = knownPlans[planId] else { continue }

            // A template import (`type=plan` rows) may heal a plan that already has days.
            // Log rows keep the original behaviour of only rebuilding an empty plan, so
            // re-importing a log backup never adds ad-hoc logged exercises to a template.
            guard planRowNames[planId] != nil || plan.days.isEmpty else { continue }

            for date in exercisesByDate.keys.sorted() {
                let exercises = exercisesByDate[date] ?? []
                guard !exercises.isEmpty else { continue }

                let dayTypeKey = planDayTypesByDate[planId]?[date]
                var resolvedType: DayTypeModel? = nil
                if let raw = dayTypeKey {
                    let key = raw.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !key.isEmpty {
                        let byKey = FetchDescriptor<DayTypeModel>(predicate: #Predicate { $0.key == key })
                        resolvedType = (try? context.fetch(byKey))?.first
                        if resolvedType == nil {
                            let byName = FetchDescriptor<DayTypeModel>(predicate: #Predicate { $0.name == key })
                            resolvedType = (try? context.fetch(byName))?.first
                        }
                        if resolvedType == nil {
                            let model = DayTypeModel(key: key, name: key, colorKey: "gray")
                            context.insert(model)
                            resolvedType = model
                        }
                    }
                }

                // Additive: fill in what the file adds, never remove what the app holds.
                let planDay: PlanDay
                if let found = plan.days.first(where: { cal.startOfDay(for: $0.date) == date }) {
                    planDay = found
                    if planDay.type == nil { planDay.type = resolvedType }
                } else {
                    planDay = PlanDay(date: date, type: resolvedType)
                    plan.days.append(planDay)
                }

                let fromPlanRows = planRowNames[planId]?[date] ?? []
                for name in exercises where !planDay.chosenExercises.contains(name) {
                    planDay.chosenExercises.append(name)
                    // Only a template row's contribution is new work to report; a log row
                    // was already counted when its SessionItem was inserted.
                    if fromPlanRows.contains(name) { inserted += 1 }
                }

                // PlanDayExerciseOrdering sorts by exerciseOrder and falls back to catalog
                // order then alphabetically, so row order only survives if it is written.
                planDay.exerciseOrder = Dictionary(
                    uniqueKeysWithValues: planDay.chosenExercises.enumerated().map { ($1, $0) }
                )
            }
        }
        
        // Make sure imported plan exercises exist in the catalog. Plan views
        // resolve activity grouping, guidance text, and logging affordances by
        // exercise name against the catalog, so without this step imported
        // plans render under "Unknown" with no per-exercise guidance.
        ensureCatalogEntries(for: catalogCandidates, in: context)

        try context.save()
        return inserted
    }

    /// Create catalog entries for imported plan exercises that don't exist yet.
    /// Exercises are grouped under an "Imported" activity (or "Imported Bouldering"
    /// for names containing "boulder", so the plan view offers the climb-log
    /// button via the existing activity-name heuristic), with one TrainingType
    /// per source plan. Metrics from the CSV become the exercise guidance texts.
    /// A plan exercise row's catalog-relevant fields, first occurrence wins.
    struct CatalogCandidate {
        let reps: Double?
        let sets: Double?
        let duration: Double?
        let restText: String?
        let notes: String?
        let planName: String?
        let timerName: String?
        let timerSpec: String?
        /// The exercise's own place in the catalog, when the file carried it.
        let activityName: String?
        let trainingTypeName: String?
        let shape: ExerciseShape?
    }

    @MainActor
    private static func ensureCatalogEntries(
        for candidates: [String: CatalogCandidate],
        in context: ModelContext
    ) {
        guard !candidates.isEmpty else { return }

        // Exercises already in the catalog, by trimmed name. Guidance lookup is
        // global and first-wins, so never create duplicates — but an existing
        // exercise may still be missing a timer, which we can fill in below.
        var existingByName: [String: Exercise] = [:]
        for exercise in (try? context.fetch(FetchDescriptor<Exercise>())) ?? [] {
            let key = exercise.name.trimmingCharacters(in: .whitespacesAndNewlines)
            if existingByName[key] == nil { existingByName[key] = exercise }
        }

        // Templates by name, so a CSV can reuse one instead of creating a duplicate.
        var templatesByName: [String: TimerTemplate] = [:]
        for template in (try? context.fetch(FetchDescriptor<TimerTemplate>())) ?? [] {
            let key = template.name.trimmingCharacters(in: .whitespacesAndNewlines).localizedLowercase
            if templatesByName[key] == nil { templatesByName[key] = template }
        }

        // CSV writes unset metrics as 0.000, so zero means "no guidance", not "zero reps".
        func metricText(_ value: Double?) -> String? {
            guard let value, value != 0 else { return nil }
            return value == value.rounded()
                ? String(Int(value))
                : value.formatted(.number.precision(.fractionLength(1)))
        }

        func trimmedOrNil(_ text: String?) -> String? {
            let value = text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return value.isEmpty ? nil : value
        }

        /// Reuse a template by name, else create one from the spec. nil when the row carries neither.
        func resolveTimer(for exerciseName: String, _ meta: CatalogCandidate) -> TimerTemplate? {
            let name = meta.timerName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if !name.isEmpty, let existing = templatesByName[name.localizedLowercase] {
                return existing
            }
            guard let draft = TimerSpec.decode(meta.timerSpec) else { return nil }

            let templateName = name.isEmpty ? "\(exerciseName) Timer" : name
            let created = TimerSpec.makeTemplate(named: templateName, from: draft)
            context.insert(created)
            templatesByName[templateName.localizedLowercase] = created
            return created
        }

        for (name, meta) in candidates.sorted(by: { $0.key < $1.key }) {
            let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }

            // Wall work logs as a climb rather than as a weighted session item. The file
            // now says so outright; the "boulder" substring is the fallback for CSVs
            // written before the column existed. Either way it only ever *fills* a blank
            // shape, never overrules a real classification.
            let shape = meta.shape
                ?? (trimmed.localizedLowercase.contains("boulder") ? .attempts : nil)

            // Already in the catalog: never overwrite, but fill anything still missing so
            // re-importing an improved CSV heals entries created by an earlier import.
            if let existing = existingByName[trimmed] {
                if existing.shapeKey == nil, let shape {
                    existing.shapeKey = shape.rawValue
                }
                if existing.repsText == nil { existing.repsText = metricText(meta.reps) }
                if existing.setsText == nil { existing.setsText = metricText(meta.sets) }
                if existing.durationText == nil {
                    existing.durationText = metricText(meta.duration).map { "\($0) min" }
                }
                if existing.restText == nil { existing.restText = trimmedOrNil(meta.restText) }
                if existing.notes == nil { existing.notes = meta.notes }
                if existing.timerTemplateId == nil, let template = resolveTimer(for: trimmed, meta) {
                    existing.timerTemplateId = template.id
                }
                continue
            }

            // Where the file says it belongs. Only when it doesn't do we fall back to the
            // old shelf — "Imported", subdivided by source plan — which is what put
            // re-imported exercises somewhere they had never been filed.
            let activity = CatalogSeeder.ensureActivity(
                trimmedOrNil(meta.activityName)
                    ?? (shape == .attempts ? "Imported Bouldering" : "Imported"),
                in: context
            )
            let planName = meta.planName?.trimmingCharacters(in: .whitespacesAndNewlines)
            let type = CatalogSeeder.ensureType(
                trimmedOrNil(meta.trainingTypeName)
                    ?? ((planName?.isEmpty == false) ? planName! : "Imported plan"),
                in: activity
            )

            CatalogSeeder.ensureExercise(
                trimmed,
                in: type,
                reps: metricText(meta.reps),
                duration: metricText(meta.duration).map { "\($0) min" },
                sets: metricText(meta.sets),
                rest: trimmedOrNil(meta.restText),
                notes: meta.notes
            )

            if let created = type.exercises.first(where: { $0.name == trimmed }) {
                existingByName[trimmed] = created
                if let shape {
                    created.shapeKey = shape.rawValue
                }
                if let template = resolveTimer(for: trimmed, meta) {
                    created.timerTemplateId = template.id
                }
            }
        }
    }
}

//recreate ClimbMedia
private func parseMediaRefs(_ raw: String?) -> [(assetLocalIdentifier: String, type: ClimbMediaType, createdAt: Date?)] {
    guard let raw, !raw.isEmpty else { return [] }

    let iso = ISO8601DateFormatter()
    return raw
        .split(separator: ";")
        .compactMap { part in
            let comps = part.split(separator: "|")
            guard comps.count >= 2 else { return nil }
            let id = String(comps[0])
            let typeRaw = String(comps[1])
            let type = ClimbMediaType(rawValue: typeRaw) ?? .photo
            let created: Date? = (comps.count >= 3) ? iso.date(from: String(comps[2])) : nil
            return (assetLocalIdentifier: id, type: type, createdAt: created)
        }
}

@MainActor
private func attachMedia(from raw: String?, to climb: ClimbEntry, in context: ModelContext) {
    let refs = parseMediaRefs(raw)
    
    let imageManager = PHCachingImageManager.default()
    let options = PHImageRequestOptions()
    options.deliveryMode = .opportunistic
    options.resizeMode = .fast
    options.isSynchronous = true
    options.isNetworkAccessAllowed = true
    
    let targetSize = CGSize(width: 200, height: 200)
    
    for ref in refs {
        var thumbData: Data? = nil
        
        let fetchResult = PHAsset.fetchAssets(
            withLocalIdentifiers: [ref.assetLocalIdentifier],
            options: nil
        )
        
        if let asset = fetchResult.firstObject {
            var thumbImage: UIImage?
            imageManager.requestImage(
                for: asset,
                targetSize: targetSize,
                contentMode: .aspectFill,
                options: options
            ) { image, _ in
                thumbImage = image
            }
            
            if let img = thumbImage {
                thumbData = img.jpegData(compressionQuality: 0.7)
            }
        }
        
        let media = ClimbMedia(
            assetLocalIdentifier: ref.assetLocalIdentifier,
            thumbnailData: thumbData,
            type: ref.type,
            createdAt: ref.createdAt ?? climb.dateLogged,
            climb: climb
        )
        context.insert(media)
    }
}


// MARK: - Deterministic ID helpers (TB2 parity)
private func stableID(climbUUID: String, day: Date, angle: Int?, isMirror: Bool?, isAscent: Bool) -> UUID {
    let dayEpoch = Int((day.timeIntervalSince1970 / 86400.0).rounded(.down))
    let key = "tb2|\(climbUUID)|\(dayEpoch)|\(angle ?? -999)|\((isMirror ?? false) ? 1 : 0)|\((isAscent) ? 1 : 0)"
    return deterministicUUID(from: key)
}

private func deterministicUUID(from string: String) -> UUID {
    let hash = SHA256.hash(data: Data(string.utf8))
    let bytes = Array(hash.prefix(16))
    let uuid = uuid_t(bytes[0],bytes[1],bytes[2],bytes[3],bytes[4],bytes[5],bytes[6],bytes[7],bytes[8],bytes[9],bytes[10],bytes[11],bytes[12],bytes[13],bytes[14],bytes[15])
    return UUID(uuid: uuid)
}

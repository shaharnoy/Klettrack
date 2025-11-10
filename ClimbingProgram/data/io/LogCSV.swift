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
        
        // Header extended with climb_id and tb2_uuid at the end (backward compatible)
        var rows: [String] = ["date,type,exercise_name,climb_type,grade,angle,holdColor,rope_type,style,attempts,wip,ispreviouslyClimbed,gym,reps,sets,duration,weight_kg,plan_id,plan_name,day_type,notes,climb_id,tb2_uuid"]

        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd"
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
                
                rows.append([
                    d,
                    "exercise", // type
                    csvEscape(i.exerciseName), // exercise_name
                    "", // climb_type
                    csvEscape(i.grade ?? ""), // grade
                    "", // angle
                    "", // holdColor
                    "", // rope_type
                    "", // style
                    "", // attempts
                    "", // wip
                    "", //ispreviouslyClimbed
                    "", // gym
                    i.reps.map{ String(format: "%.3f", $0) } ?? "",
                    i.sets.map{ String(format: "%.3f", $0) } ?? "",
                    i.duration.map{ String(format: "%.3f", $0) } ?? "",
                    i.weightKg.map { String(format: "%.3f", $0) } ?? "",
                    i.planSourceId?.uuidString ?? "",
                    csvEscape(i.planName ?? ""),
                    csvEscape(dayType),
                    csvEscape(i.notes ?? ""),
                    "", // climb_id (exercises don't use this)
                    ""  // tb2_uuid (exercises don't use this)
                ].joined(separator: ","))
            }
        }
        
        // Export climb entries
        for climb in climbEntries {
            let d = df.string(from: climb.dateLogged)
            
            rows.append([
                d,
                "climb",
                "", // exercise_name
                csvEscape(climb.climbType.rawValue),
                csvEscape(climb.grade),
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
                climb.id.uuidString,                  // climb_id
                csvEscape(climb.tb2ClimbUUID ?? "")   // tb2_uuid
            ].joined(separator: ","))
        }
        
        return LogCSVDocument(csv: rows.joined(separator: "\n"))
    }
}

// MARK: - Helpers

/// Basic CSV escaping (quote if needed; escape inner quotes)
private func csvEscape(_ s: String) -> String {
    if s.contains(",") || s.contains("\"") || s.contains("\n") {
        let escaped = s.replacingOccurrences(of: "\"", with: "\"\"")
        return "\"\(escaped)\""
    }
    return s
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
        reps.map{ String(format: "%.3f", $0) } ?? "",
        sets.map{ String(format: "%.3f", $0) } ?? "",
        duration.map { String(format: "%.3f", $0) } ?? "",
        weight.map { String(format: "%.3f", $0) } ?? "",
        planId?.uuidString ?? "",
        norm(planName)
        // Notes intentionally excluded from deduplication
    ].joined(separator: "|")
}

/// Build a dedupe signature for a climb entry
private func climbSignature(date: Date,
                           climbType: ClimbType,
                           grade: String,
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
            }
            
            let hasHeader = (idx(Cols.date) != nil && idx(Cols.type) != nil)
            let startIdx = hasHeader ? 1 : 0
            
            let df = ISO8601DateFormatter()
            df.formatOptions = [.withFullDate] // YYYY-MM-DD
            
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
                let dateStr, typeStr, exerciseName, climbTypeStr, gradeStr, angleStr, holdColorStr, ropeTypeStr, styleStr, attemptsStr, wipStr,ispreviouslyClimbedStr, gymStr, repsStr, setsStr, durationStr, weightStr, planIdStr, planName, dayTypeStr, notesRaw, climbIdStr, tb2UUIDStr: String
                
                if hasHeader {
                    dateStr      = val(parts, Cols.date)
                    typeStr      = val(parts, Cols.type)
                    exerciseName = val(parts, Cols.exercise)
                    climbTypeStr = val(parts, Cols.climbType)
                    gradeStr     = val(parts, Cols.grade)
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
                }
                
                // Minimal validity check
                guard
                    let dayDate = df.date(from: dateStr),
                    !typeStr.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                else { continue }
                
                // Normalize/convert
                let type = typeStr.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                let grade = gradeStr.trimmingCharacters(in: .whitespacesAndNewlines)
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
                
                out.append(Entry(
                    date: dayDate,
                    type: type,
                    name: name,
                    climbType: climbTypeStr.isEmpty ? nil : climbTypeStr,
                    grade: grade.isEmpty ? nil : grade,
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
                    tb2UUID: tb2uuidOpt
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
        
        // Track exercises by date for each plan to reconstruct plan structure
        var planExercisesByDate: [UUID: [Date: Set<String>]] = [:]
        
        // Track day types by date for each plan to preserve day type information
        var planDayTypesByDate: [UUID: [Date: String]] = [:]
        
        for (idx, e) in entries.enumerated() {
            // Progress from 0.5 → 1.0 during application
            if idx % 50 == 0 {
                let p = 0.5 + 0.5 * (Double(idx) / Double(entries.count))
                progress?(min(max(p, 0.5), 1.0))
            }
            
            let startOfDay = cal.startOfDay(for: e.date)
            
            if e.type == "exercise" {
                guard !e.name.isEmpty else { continue }
                
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
                
                // Handle plan reference if present
                if let planId = e.planId, !knownPlans.keys.contains(planId), let planName = e.planName {
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
                if let planId = e.planId {
                    if planExercisesByDate[planId] == nil { planExercisesByDate[planId] = [:] }
                    if planExercisesByDate[planId]![startOfDay] == nil { planExercisesByDate[planId]![startOfDay] = Set() }
                    planExercisesByDate[planId]![startOfDay]!.insert(e.name)
                    
                    if let dayTypeKey = e.dayTypeKey {
                        if planDayTypesByDate[planId] == nil { planDayTypesByDate[planId] = [:] }
                        planDayTypesByDate[planId]![startOfDay] = dayTypeKey
                    }
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
                        duration: e.duration
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
                        if let tb2 = e.tb2UUID { existing.tb2ClimbUUID = tb2 }
                    } else {
                        let climbEntry = ClimbEntry(
                            id: providedId,
                            climbType: climbType,
                            ropeClimbType: ropeClimbType,
                            grade: grade,
                            angleDegrees: e.angle,
                            style: e.style?.isEmpty == false ? e.style! : "Unknown",
                            attempts: e.attempts,
                            isWorkInProgress: e.isWIP,
                            isPreviouslyClimbed: e.ispreviouslyClimbed,
                            holdColor: e.holdColor.flatMap { HoldColor(rawValue: $0) },
                            gym: e.gym?.isEmpty == false ? e.gym! : "Unknown",
                            notes: e.notes,
                            dateLogged: startOfDay,
                            tb2ClimbUUID: e.tb2UUID
                        )
                        context.insert(climbEntry)
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
                            angleDegrees: e.angle,
                            style: e.style?.isEmpty == false ? e.style! : "Unknown",
                            attempts: e.attempts,
                            isWorkInProgress: e.isWIP,
                            isPreviouslyClimbed: e.ispreviouslyClimbed,
                            holdColor: e.holdColor.flatMap { HoldColor(rawValue: $0) },
                            gym: e.gym?.isEmpty == false ? e.gym! : "Unknown",
                            notes: e.notes,
                            dateLogged: startOfDay,
                            tb2ClimbUUID: tb2
                        )
                        context.insert(climbEntry)
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
                    angleDegrees: e.angle,
                    style: e.style?.isEmpty == false ? e.style! : "Unknown",
                    attempts: e.attempts,
                    isWorkInProgress: e.isWIP,
                    isPreviouslyClimbed: e.ispreviouslyClimbed,
                    holdColor: e.holdColor.flatMap { HoldColor(rawValue: $0) },
                    gym: e.gym?.isEmpty == false ? e.gym! : "Unknown",
                    notes: e.notes,
                    dateLogged: startOfDay
                )
                context.insert(climbEntry)
                inserted += 1
            }
        }
        
        // After processing all rows, populate the plans with their days and exercises
        for (planId, exercisesByDate) in planExercisesByDate {
            guard let plan = knownPlans[planId] else { continue }
            
            if plan.days.isEmpty {
                let sortedDates = Array(exercisesByDate.keys).sorted()
                for date in sortedDates {
                    let exercises = Array(exercisesByDate[date] ?? [])
                    if !exercises.isEmpty {
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
                        let planDay = PlanDay(date: date, type: resolvedType)
                        planDay.chosenExercises = exercises
                        plan.days.append(planDay)
                    }
                }
            }
        }
        
        try context.save()
        return inserted
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


//
//  LogCSV.swift
//  ClimbingProgram
//

import Foundation
import SwiftUI
import SwiftData
import UniformTypeIdentifiers

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

    /// Build a CSV snapshot from all Sessions + SessionItems in the store.
    static func makeExportCSV(context: ModelContext) -> LogCSVDocument {
        // Fetch sessions oldest → newest for nice reading
        let sessions: [Session] = (try? context.fetch(
            FetchDescriptor<Session>(sortBy: [SortDescriptor(\.date, order: .forward)])
        )) ?? []

        // Fetch all plans to look up day types
        let plans: [Plan] = (try? context.fetch(FetchDescriptor<Plan>())) ?? []
        
        var rows: [String] = ["date,exercise,reps,sets,weight_kg,plan_id,plan_name,day_type,notes"] // header with day_type

        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd"
        df.timeZone = TimeZone.current // Use current timezone consistently
        df.locale = Locale(identifier: "en_US_POSIX") // Ensure consistent formatting

        for s in sessions {
            // Use the session date directly without normalization to avoid timezone issues
            let d = df.string(from: s.date)
            for i in s.items {
                // Find the day type for this session item
                var dayType = ""
                if let planId = i.planSourceId {
                    // Find the plan and the corresponding day
                    if let plan = plans.first(where: { $0.id == planId }) {
                        let calendar = Calendar.current
                        let sessionStartOfDay = calendar.startOfDay(for: s.date)
                        if let planDay = plan.days.first(where: { calendar.startOfDay(for: $0.date) == sessionStartOfDay }) {
                            dayType = planDay.type.rawValue
                        }
                    }
                }
                
                rows.append([
                    d,
                    csvEscape(i.exerciseName),
                    i.reps.map{ String(format: "%.3f", $0) } ?? "",
                    i.sets.map{ String(format: "%.3f", $0) } ?? "",
                    i.weightKg.map { String(format: "%.3f", $0) } ?? "",
                    i.planSourceId?.uuidString ?? "",
                    csvEscape(i.planName ?? ""),
                    csvEscape(dayType),
                    csvEscape(i.notes ?? "")
                ].joined(separator: ","))
            }
        }
        return LogCSVDocument(csv: rows.joined(separator: "\n"))
    }

    /// Import CSV rows into SwiftData. Creates (or merges into) Sessions by date.
    /// - Parameters:
    ///   - url: CSV file URL
    ///   - context: SwiftData context
    ///   - tag: optional tag applied to each imported item, e.g. "import:2025-08-22"
    ///   - dedupe: if true, avoids inserting exact-duplicate rows (same day+name+numbers+notes)
    /// - Returns: number of inserted items
    @discardableResult
    static func importCSV(
        from url: URL,
        into context: ModelContext,
        tag: String? = nil,
        dedupe: Bool = true
    ) throws -> Int {

        // Security-scoped access for files coming from .fileImporter / document picker
        var didAccess = false
        if url.startAccessingSecurityScopedResource() { didAccess = true }
        defer { if didAccess { url.stopAccessingSecurityScopedResource() } }

        let data = try Data(contentsOf: url)
        guard let text = String(data: data, encoding: .utf8) else {
            throw CocoaError(.fileReadCorruptFile)
        }

        let lines = text.split(whereSeparator: \.isNewline).map(String.init)
        guard !lines.isEmpty else {
            throw CocoaError(.fileReadCorruptFile)
        }

        // Optional header on first line
        let first = lines[0].trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let startIdx = first.hasPrefix("date,") ? 1 : 0

        // Validate we have data rows
        if startIdx >= lines.count {
            throw CocoaError(.fileReadCorruptFile)
        }

        let df = ISO8601DateFormatter()
        df.formatOptions = [.withFullDate] // YYYY-MM-DD
        let calendar = Calendar.current

        // Track plans we create during import
        var knownPlans: [UUID: Plan] = [:]
        // Track exercises by date for each plan to reconstruct plan structure
        var planExercisesByDate: [UUID: [Date: Set<String>]] = [:]
        // Track day types by date for each plan to preserve day type information
        var planDayTypesByDate: [UUID: [Date: DayType]] = [:]
        
        var inserted = 0
        var hasValidRows = false

        for idx in startIdx..<lines.count {
            let parts = parseCSVLine(lines[idx])
            
            // Skip empty lines
            if parts.isEmpty || parts.allSatisfy({ $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) {
                continue
            }

            // Expect: date,exercise,reps,sets,weight_kg,plan_id,plan_name,day_type,notes (updated format)
            guard parts.count >= 2 else {
                if !hasValidRows {
                    throw CocoaError(.fileReadCorruptFile)
                }
                continue
            }

            let dateStr   = parts[safe: 0] ?? ""
            let name      = parts[safe: 1] ?? ""
            let repsStr   = parts[safe: 2] ?? ""
            let setsStr   = parts[safe: 3] ?? ""
            let weightStr = parts[safe: 4] ?? ""
            let planIdStr = parts[safe: 5] ?? ""
            let planName  = parts[safe: 6] ?? ""
            let dayTypeStr = parts[safe: 7] ?? ""  // New day_type field
            let notes     = parts[safe: 8] ?? ""   // Notes moved to position 8

            guard
                let dayDate = df.date(from: dateStr),
                !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            else {
                if !hasValidRows {
                    throw CocoaError(.fileReadCorruptFile)
                }
                continue
            }
            
            hasValidRows = true

            // Normalize date to start of day for consistency
            let startOfDay = calendar.startOfDay(for: dayDate)
            let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay)!
            
            // Find/create session on that day
            let descriptor = FetchDescriptor<Session>(predicate: #Predicate {
                $0.date >= startOfDay && $0.date < endOfDay
            })
            let existing = (try? context.fetch(descriptor)) ?? []
            let session = existing.first ?? {
                let s = Session(date: startOfDay) // Always use normalized date
                context.insert(s)
                return s
            }()

            // Parse numeric fields (empty -> nil)
            let reps = Double(repsStr.replacingOccurrences(of: ",", with: ".")
                .trimmingCharacters(in: .whitespacesAndNewlines)
        )
            let sets = Double(setsStr.replacingOccurrences(of: ",", with: ".")
                .trimmingCharacters(in: .whitespacesAndNewlines)
        )
            let weight = Double(
                weightStr
                    .replacingOccurrences(of: ",", with: ".")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            )
            
            // Handle plan reference
            var planId: UUID?
            var planNameToUse: String?
            if !planIdStr.isEmpty {
                if let uuid = UUID(uuidString: planIdStr) {
                    planId = uuid
                    planNameToUse = planName.isEmpty ? nil : planName
                    
                    // Create plan if it doesn't exist
                    if !planName.isEmpty && !knownPlans.keys.contains(uuid) {
                        // Check if plan already exists in DB
                        let planDescriptor = FetchDescriptor<Plan>(predicate: #Predicate<Plan> { $0.id == uuid })
                        if let existing = try? context.fetch(planDescriptor).first {
                            knownPlans[uuid] = existing
                        } else {
                            // Create new plan
                            let plan = Plan(id: uuid, name: planName, kind: .weekly, startDate: startOfDay)
                            context.insert(plan)
                            knownPlans[uuid] = plan
                        }
                    }
                    
                    // Track exercises for this plan and date to reconstruct plan structure
                    if planExercisesByDate[uuid] == nil {
                        planExercisesByDate[uuid] = [:]
                    }
                    if planExercisesByDate[uuid]![startOfDay] == nil {
                        planExercisesByDate[uuid]![startOfDay] = Set()
                    }
                    planExercisesByDate[uuid]![startOfDay]!.insert(name)
                    
                    // Track day type for this date if present
                    if !dayTypeStr.isEmpty, let dayType = DayType(rawValue: dayTypeStr) {
                        if planDayTypesByDate[uuid] == nil {
                            planDayTypesByDate[uuid] = [:]
                        }
                        planDayTypesByDate[uuid]![startOfDay] = dayType
                    }
                }
            }

            // DEDUPE within this session and globally if enabled
            if dedupe {
                let sig = itemSignature(date: session.date,
                                        name: name,
                                        reps: reps,
                                        sets: sets,
                                        weight: weight,
                                        planId: planId,
                                        planName: planNameToUse,
                                        notes: notes)
                
                // Check for exact duplicate in current session
                let existingItem = session.items.first { item in
                    let itemSig = itemSignature(date: session.date,
                                              name: item.exerciseName,
                                              reps: item.reps,
                                              sets: item.sets,
                                              weight: item.weightKg,
                                              planId: item.planSourceId,
                                              planName: item.planName,
                                              notes: item.notes)
                    return itemSig == sig
                }
                
                if existingItem != nil {
                    continue // Skip duplicate
                }
            }

            // Append & tag
            let newItem = SessionItem(
                exerciseName: name,
                planSourceId: planId,
                planName: planNameToUse,
                reps: reps,
                sets: sets,
                weightKg: weight,
                notes: notes.isEmpty ? nil : notes
            )
            newItem.sourceTag = tag
            session.items.append(newItem)
            inserted += 1
        }

        // If no valid rows were found, throw an error
        if !hasValidRows {
            throw CocoaError(.fileReadCorruptFile)
        }

        // After processing all rows, populate the plans with their days and exercises
        for (planId, exercisesByDate) in planExercisesByDate {
            guard let plan = knownPlans[planId] else { continue }
            
            // Only populate if the plan doesn't already have days (avoid overwriting existing plans)
            if plan.days.isEmpty {
                let sortedDates = Array(exercisesByDate.keys).sorted()
                
                for date in sortedDates {
                    let exercises = Array(exercisesByDate[date] ?? [])
                    if !exercises.isEmpty {
                        // Use the imported day type if available, otherwise default to climbingFull
                        let dayType = planDayTypesByDate[planId]?[date] ?? .climbingFull
                        let planDay = PlanDay(
                            date: date,
                            type: dayType
                        )
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
        weight.map { String(format: "%.3f", $0) } ?? "",
        planId?.uuidString ?? "",
        norm(planName)
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
        let name: String
        let reps: Double?
        let sets: Double?
        let weight: Double?
        let planId: UUID?
        let planName: String?
        let dayType: DayType?
        let notes: String?
    }

    /// Async importer: parses off-main, then mutates SwiftData on the main actor.
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

        // 1) Read + parse OFF-MAIN (no ModelContext captured)
        let entries: [Entry] = try await Task.detached(priority: .userInitiated) { () -> [Entry] in
            let data = try Data(contentsOf: url)
            guard let text = String(data: data, encoding: .utf8) else { return [] }

            let lines = text.split(whereSeparator: \.isNewline).map(String.init)
            guard !lines.isEmpty else { return [] }

            let first = lines[0].trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let startIdx = first.hasPrefix("date,") ? 1 : 0

            let df = ISO8601DateFormatter()
            df.formatOptions = [.withFullDate] // YYYY-MM-DD

            var out: [Entry] = []
            out.reserveCapacity(max(0, lines.count - startIdx))

            for (n, idx) in (startIdx..<lines.count).enumerated() {
                // brief cooperative yield to keep the system responsive
                if n % 500 == 0 { await Task.yield() }

                let parts = parseCSVLine(lines[idx])
                
                // Skip empty lines
                if parts.isEmpty || parts.allSatisfy({ $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) {
                    continue
                }
                
                guard parts.count >= 2 else { continue }

                let dateStr   = parts[safe: 0] ?? ""
                let nameRaw   = parts[safe: 1] ?? ""
                let repsStr   = parts[safe: 2] ?? ""
                let setsStr   = parts[safe: 3] ?? ""
                let weightStr = parts[safe: 4] ?? ""
                let planIdStr = parts[safe: 5] ?? ""
                let planName  = parts[safe: 6] ?? ""
                let dayTypeStr = parts[safe: 7] ?? ""  // Day type field
                let notesRaw  = parts[safe: 8] ?? ""   // Notes moved to position 8

                guard
                    let dayDate = df.date(from: dateStr),
                    !nameRaw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                else { continue }

                let name   = nameRaw.trimmingCharacters(in: .whitespacesAndNewlines)
                let reps   = Double(repsStr.replacingOccurrences(of: ",", with: ".")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                )
                let sets   = Double(setsStr.replacingOccurrences(of: ",", with: ".")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                )
                let weight = Double(weightStr
                    .replacingOccurrences(of: ",", with: ".")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                )
                let planId = UUID(uuidString: planIdStr)
                let dayType = !dayTypeStr.isEmpty ? DayType(rawValue: dayTypeStr) : nil
                let notes = notesRaw.trimmingCharacters(in: .whitespacesAndNewlines)
                let notesOpt = notes.isEmpty ? nil : notes

                out.append(Entry(
                    date: dayDate,
                    name: name,
                    reps: reps,
                    sets: sets,
                    weight: weight,
                    planId: planId,
                    planName: planName.isEmpty ? nil : planName,
                    dayType: dayType,
                    notes: notesOpt
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

        // 2) Apply ON MAIN (safe for ModelContext) + progressive progress
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
        var planDayTypesByDate: [UUID: [Date: DayType]] = [:]

        for (idx, e) in entries.enumerated() {
            // Progress from 0.5 → 1.0 during application
            if idx % 50 == 0 {
                let p = 0.5 + 0.5 * (Double(idx) / Double(entries.count))
                progress?(min(max(p, 0.5), 1.0))
            }

            // Find or create session for this day (normalized to startOfDay)
            let startOfDay = cal.startOfDay(for: e.date)
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
                // Check if plan already exists in DB
                let planDescriptor = FetchDescriptor<Plan>(predicate: #Predicate<Plan> { $0.id == planId })
                if let existing = try? context.fetch(planDescriptor).first {
                    knownPlans[planId] = existing
                } else {
                    // Create new plan
                    let plan = Plan(id: planId, name: planName, kind: .weekly, startDate: startOfDay)
                    context.insert(plan)
                    knownPlans[planId] = plan
                }
            }

            // Track exercises for plan reconstruction if planId exists
            if let planId = e.planId {
                if planExercisesByDate[planId] == nil {
                    planExercisesByDate[planId] = [:]
                }
                if planExercisesByDate[planId]![startOfDay] == nil {
                    planExercisesByDate[planId]![startOfDay] = Set()
                }
                planExercisesByDate[planId]![startOfDay]!.insert(e.name)
                
                // Track day type for this date if present
                if let dayType = e.dayType {
                    if planDayTypesByDate[planId] == nil {
                        planDayTypesByDate[planId] = [:]
                    }
                    planDayTypesByDate[planId]![startOfDay] = dayType
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
                    notes: e.notes
                )
                item.sourceTag = tag
                session.items.append(item)
                existing?.insert(sig)
                inserted += 1
            }

            sigCache[sid] = existing ?? []
        }

        // RECONSTRUCT PLAN STRUCTURE: assign exercises and day types to plan days
        for (planId, dateGroups) in planExercisesByDate {
            guard let plan = knownPlans[planId] else { continue }

            // Only populate if the plan doesn't already have days (avoid overwriting existing plans)
            if plan.days.isEmpty {
                let sortedDates = Array(dateGroups.keys).sorted()
                
                for date in sortedDates {
                    let exercises = Array(dateGroups[date] ?? [])
                    if !exercises.isEmpty {
                        // Use the imported day type if available, otherwise default to climbingFull
                        let dayType = planDayTypesByDate[planId]?[date] ?? .climbingFull
                        let planDay = PlanDay(
                            date: date,
                            type: dayType
                        )
                        planDay.chosenExercises = exercises
                        plan.days.append(planDay)
                    }
                }
            }
        }

        try? context.save()
        progress?(1.0)
        return inserted
    }
}

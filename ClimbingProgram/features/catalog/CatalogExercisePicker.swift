//
//  CatalogExercisePicker.swift
//  Klettrack
//  Created by Shahar Noy on 10.03.26.
//
import SwiftUI
import SwiftData

struct CatalogExercisePicker: View {
    @Binding var selected: [String]
    @Environment(\.dismiss) private var dismiss
    @Query(filter: #Predicate<Activity> { !$0.isSoftDeleted }, sort: \Activity.name) private var activities: [Activity]
    @State private var searchText = ""
    @State private var isSearchPresented = false

    private var catalogActivities: [CatalogActivityNode] {
        makeCatalogActivityNodes(from: activities)
    }

    private var hasData: Bool {
        !catalogActivities.isEmpty
    }

    private var allExerciseHits: [ExerciseHit] {
        var hits: [ExerciseHit] = []
        var seen: Set<UUID> = []

        for activity in catalogActivities {
            for type in activity.types {
                appendExerciseHits(from: type.exercises, tint: activity.tint, seen: &seen, hits: &hits)
                for combo in type.combinations {
                    appendExerciseHits(from: combo.exercises, tint: activity.tint, seen: &seen, hits: &hits)
                }
            }
        }

        return hits
    }

    private var filteredExerciseHits: [ExerciseHit] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return [] }
        return allExerciseHits.filter { hit in
            hit.name.localizedStandardContains(query) ||
            (hit.subtitle?.localizedStandardContains(query) ?? false)
        }
    }

    var body: some View {
        NavigationStack {
            if !hasData {
                VStack(spacing: 16) {
                    ProgressView()
                    Text("Loading catalog...")
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    if !searchText.isEmpty {
                        searchResultsSection(doneAction: dismiss.callAsFunction)
                    } else {
                        ForEach(catalogActivities) { activity in
                            NavigationLink {
                                TypesList(
                                    activity: activity,
                                    selected: $selected,
                                    onDone: dismiss.callAsFunction,
                                    allHits: allExerciseHits
                                )
                            } label: {
                                HStack(spacing: 10) {
                                    Circle().fill(activity.tint).frame(width: 8, height: 8)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(activity.name).font(.headline)
                                        Text("\(activity.types.count) types")
                                            .font(.footnote)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                    }
                }
                .searchable(
                    text: $searchText,
                    isPresented: $isSearchPresented,
                    placement: .navigationBarDrawer(displayMode: .always),
                    prompt: "Search exercises"
                )
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
            }
        }
        .navigationTitle("Catalog")
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") {
                    dismiss()
                }
            }

            ToolbarItem(placement: .topBarTrailing) {
                if isSearchPresented {
                    Button("Done") {
                        isSearchPresented = false
                        dismiss()
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func searchResultsSection(doneAction: @escaping () -> Void) -> some View {
        if filteredExerciseHits.isEmpty {
            ContentUnavailableView(
                "No matches",
                systemImage: "magnifyingglass",
                description: Text("Try a different search term.")
            )
        } else {
            Section {
                ForEach(filteredExerciseHits) { hit in
                    ExercisePickRow(
                        name: hit.name,
                        subtitle: hit.subtitle,
                        reps: hit.repsText,
                        sets: hit.setsText,
                        rest: hit.restText,
                        duration: hit.durationText,
                        tint: hit.tint,
                        isSelected: selected.contains(hit.name)
                    ) {
                        toggleSelection(hit.name)
                    }
                }
            } header: {
                HStack {
                    Text("Results")
                    Spacer()
                    Button("Done") {
                        isSearchPresented = false
                        doneAction()
                    }
                    .font(.subheadline)
                }
            }
        }
    }

    private func toggleSelection(_ name: String) {
        if let index = selected.firstIndex(of: name) {
            selected.remove(at: index)
        } else {
            selected.append(name)
        }
    }

    private func appendExerciseHits(
        from exercises: [CatalogExerciseNode],
        tint: Color,
        seen: inout Set<UUID>,
        hits: inout [ExerciseHit]
    ) {
        for exercise in exercises where seen.insert(exercise.id).inserted {
            hits.append(
                ExerciseHit(
                    id: exercise.id,
                    name: exercise.name,
                    subtitle: exercise.subtitle,
                    tint: tint,
                    repsText: exercise.repsText,
                    setsText: exercise.setsText,
                    restText: exercise.restText,
                    durationText: exercise.durationText
                )
            )
        }
    }
}

struct TypesList: View {
    let activity: CatalogActivityNode
    @Binding var selected: [String]
    let onDone: () -> Void
    let allHits: [ExerciseHit]
    @State private var searchText = ""
    @State private var isSearchPresented = false

    private var filteredHits: [ExerciseHit] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return [] }
        return allHits.filter { hit in
            hit.name.localizedStandardContains(query) ||
            (hit.subtitle?.localizedStandardContains(query) ?? false)
        }
    }

    var body: some View {
        List {
            if !searchText.isEmpty {
                SearchResultsList(
                    hits: filteredHits,
                    selected: $selected,
                    onDone: {
                        isSearchPresented = false
                        onDone()
                    }
                )
            } else {
                ForEach(activity.types) { trainingType in
                    NavigationLink {
                        if !trainingType.combinations.isEmpty {
                            CombosList(
                                trainingType: trainingType,
                                selected: $selected,
                                onDone: onDone,
                                allHits: allHits,
                                tint: activity.tint
                            )
                        } else {
                            ExercisesList(
                                trainingType: trainingType,
                                selected: $selected,
                                onDone: onDone,
                                allHits: allHits,
                                tint: activity.tint
                            )
                        }
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(trainingType.name).font(.headline)
                            if let description = trainingType.typeDescription, !description.isEmpty {
                                Text(description)
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                            }
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(activity.name)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Done", action: onDone)
            }
        }
        .searchable(
            text: $searchText,
            isPresented: $isSearchPresented,
            placement: .navigationBarDrawer(displayMode: .always),
            prompt: "Search exercises"
        )
        .autocorrectionDisabled()
        .textInputAutocapitalization(.never)
    }
}

struct CombosList: View {
    let trainingType: CatalogTypeNode
    @Binding var selected: [String]
    let onDone: () -> Void
    let allHits: [ExerciseHit]
    let tint: Color
    @State private var searchText = ""
    @State private var isSearchPresented = false

    private var filteredHits: [ExerciseHit] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return [] }
        return allHits.filter { hit in
            hit.name.localizedStandardContains(query) ||
            (hit.subtitle?.localizedStandardContains(query) ?? false)
        }
    }

    var body: some View {
        List {
            if !searchText.isEmpty {
                SearchResultsList(
                    hits: filteredHits,
                    selected: $selected,
                    onDone: {
                        isSearchPresented = false
                        onDone()
                    }
                )
            } else {
                ForEach(trainingType.combinations) { combo in
                    NavigationLink {
                        ComboExercisesList(
                            combo: combo,
                            selected: $selected,
                            tint: tint,
                            onDone: onDone,
                            allHits: allHits
                        )
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(combo.name).font(.headline)
                            if let description = combo.comboDescription, !description.isEmpty {
                                Text(description)
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                            }
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(trainingType.name)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Done", action: onDone)
            }
        }
        .searchable(
            text: $searchText,
            isPresented: $isSearchPresented,
            placement: .navigationBarDrawer(displayMode: .always),
            prompt: "Search exercises"
        )
        .autocorrectionDisabled()
        .textInputAutocapitalization(.never)
    }
}

struct ComboExercisesList: View {
    let combo: CatalogComboNode
    @Binding var selected: [String]
    let tint: Color
    let onDone: () -> Void
    let allHits: [ExerciseHit]
    @State private var searchText = ""
    @State private var isSearchPresented = false

    private var filteredHits: [ExerciseHit] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return [] }
        return allHits.filter { hit in
            hit.name.localizedStandardContains(query) ||
            (hit.subtitle?.localizedStandardContains(query) ?? false)
        }
    }

    var body: some View {
        List {
            if !searchText.isEmpty {
                SearchResultsList(
                    hits: filteredHits,
                    selected: $selected,
                    onDone: {
                        isSearchPresented = false
                        onDone()
                    }
                )
            } else {
                ForEach(combo.exercises) { exercise in
                    ExercisePickRow(
                        name: exercise.name,
                        subtitle: exercise.subtitle,
                        reps: exercise.repsText,
                        sets: exercise.setsText,
                        rest: exercise.restText,
                        duration: exercise.durationText,
                        tint: tint,
                        isSelected: selected.contains(exercise.name)
                    ) {
                        toggleSelection(exercise.name)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(combo.name)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Done", action: onDone)
            }
        }
        .searchable(
            text: $searchText,
            isPresented: $isSearchPresented,
            placement: .navigationBarDrawer(displayMode: .always),
            prompt: "Search exercises"
        )
        .autocorrectionDisabled()
        .textInputAutocapitalization(.never)
    }

    private func toggleSelection(_ name: String) {
        if let index = selected.firstIndex(of: name) {
            selected.remove(at: index)
        } else {
            selected.append(name)
        }
    }
}

struct ExercisesList: View {
    let trainingType: CatalogTypeNode
    @Binding var selected: [String]
    let onDone: () -> Void
    let allHits: [ExerciseHit]
    let tint: Color
    @State private var searchText = ""
    @State private var isSearchPresented = false

    private var filteredHits: [ExerciseHit] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return [] }
        return allHits.filter { hit in
            hit.name.localizedStandardContains(query) ||
            (hit.subtitle?.localizedStandardContains(query) ?? false)
        }
    }

    private var exercisesByArea: [(String, [CatalogExerciseNode])] {
        let grouped = Dictionary(grouping: trainingType.exercises) { $0.area ?? "" }
        if grouped.keys.contains("Fingers") || grouped.keys.contains("Pull") {
            return ["Fingers", "Pull"].compactMap { area in
                guard let exercises = grouped[area], !exercises.isEmpty else { return nil }
                return (area, exercises)
            }
        }

        return grouped
            .filter { !$0.key.isEmpty }
            .map { ($0.key, $0.value) }
            .sorted { $0.0 < $1.0 }
    }

    private var ungroupedExercises: [CatalogExerciseNode] {
        trainingType.exercises.filter { ($0.area ?? "").isEmpty }
    }

    var body: some View {
        List {
            if !searchText.isEmpty {
                SearchResultsList(
                    hits: filteredHits,
                    selected: $selected,
                    onDone: {
                        isSearchPresented = false
                        onDone()
                    }
                )
            } else {
                if !exercisesByArea.isEmpty {
                    ForEach(exercisesByArea, id: \.0) { area, exercises in
                        Section(area) {
                            ForEach(exercises) { exercise in
                                exerciseRow(exercise)
                            }
                        }
                    }
                }

                if !ungroupedExercises.isEmpty {
                    Section(exercisesByArea.isEmpty ? "Exercises" : "Other") {
                        ForEach(ungroupedExercises) { exercise in
                            exerciseRow(exercise)
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(trainingType.name)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done", action: onDone)
            }
        }
        .searchable(
            text: $searchText,
            isPresented: $isSearchPresented,
            placement: .navigationBarDrawer(displayMode: .always),
            prompt: "Search exercises"
        )
        .autocorrectionDisabled()
        .textInputAutocapitalization(.never)
    }

    @ViewBuilder
    private func exerciseRow(_ exercise: CatalogExerciseNode) -> some View {
        ExercisePickRow(
            name: exercise.name,
            subtitle: exercise.subtitle,
            reps: exercise.repsText,
            sets: exercise.setsText,
            rest: exercise.restText,
            duration: exercise.durationText,
            tint: tint,
            isSelected: selected.contains(exercise.name)
        ) {
            toggleSelection(exercise.name)
        }
    }

    private func toggleSelection(_ name: String) {
        if let index = selected.firstIndex(of: name) {
            selected.remove(at: index)
        } else {
            selected.append(name)
        }
    }
}

private struct SearchResultsList: View {
    let hits: [ExerciseHit]
    @Binding var selected: [String]
    let onDone: () -> Void

    var body: some View {
        if hits.isEmpty {
            ContentUnavailableView(
                "No matches",
                systemImage: "magnifyingglass",
                description: Text("Try a different search term.")
            )
        } else {
            Section {
                ForEach(hits) { hit in
                    ExercisePickRow(
                        name: hit.name,
                        subtitle: hit.subtitle,
                        reps: hit.repsText,
                        sets: hit.setsText,
                        rest: hit.restText,
                        duration: hit.durationText,
                        tint: hit.tint,
                        isSelected: selected.contains(hit.name)
                    ) {
                        toggleSelection(hit.name)
                    }
                }
            } header: {
                HStack {
                    Text("Results")
                    Spacer()
                    Button("Done", action: onDone)
                        .font(.subheadline)
                }
            }
        }
    }

    private func toggleSelection(_ name: String) {
        if let index = selected.firstIndex(of: name) {
            selected.remove(at: index)
        } else {
            selected.append(name)
        }
    }
}

private struct ExercisePickRow: View {
    let name: String
    let subtitle: String?
    let reps: String?
    let sets: String?
    let rest: String?
    let duration: String?
    let tint: Color
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Circle().fill(tint).frame(width: 8, height: 8)
                VStack(alignment: .leading, spacing: 4) {
                    Text(name).font(.subheadline).bold()
                    if let subtitle, !subtitle.isEmpty {
                        Text(subtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                    MetricRow(reps: reps, sets: sets, rest: rest, duration: duration)
                }
                Spacer()
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .imageScale(.large)
            }
            .padding(.vertical, 6)
        }
        .buttonStyle(.plain)
        .padding(.vertical, 6)
    }
}

private struct MetricRow: View {
    let reps: String?
    let sets: String?
    let rest: String?
    let duration: String?

    var body: some View {
        HStack(spacing: 12) {
            metric("Reps", reps)
            metric("Sets", sets)
            metric("Time", duration)
            metric("Rest", rest)
        }
    }

    @ViewBuilder
    private func metric(_ title: String, _ value: String?) -> some View {
        if let value, !value.isEmpty {
            Text("\(title): \(value)")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }
}

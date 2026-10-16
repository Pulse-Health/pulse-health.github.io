import Foundation

/// The built-in exercise library of the strength feature (the 36 exercises of the design) and its search.
public enum ExerciseLibrary {
    /// The 36 built-in exercises, in design order (ids, names, cues and defaults exactly as in the design).
    ///
    /// The entries carry no previous results (`previousSets` empty, `previousBestE1RM` 0): those come from the user's own
    /// history through `StrengthData.overlay`, so a new user starts with nothing to compare against (the PREVIOUS column shows a dash)
    /// and without a record to beat.
    public static let builtIn: [Exercise] = [
        row("bench", "Barbell bench press", .chest, "Shoulders · Triceps", .barbell, .weightReps,
            media: "bench", sets: 3, kg: 60, reps: 8, rest: 150,
            cues: [
                "Pull your shoulder blades back and down and keep your feet planted.",
                "Lower the bar to mid-chest with your elbows about 45–60° from your body.",
                "Press up and slightly back until your arms are straight.",
            ]),
        row("incline", "Incline dumbbell press", .chest, "Shoulders · Triceps", .dumbbell, .weightReps,
            media: "incline", sets: 3, kg: 24, reps: 10, rest: 90,
            cues: [
                "Set the bench to 30–45° and keep your back flat on the pad.",
                "Lower the dumbbells to chest level with your elbows under your wrists.",
                "Press up without letting the weights drift apart.",
            ]),
        row("crossover", "Cable crossover", .chest, "Shoulders", .cable, .weightReps,
            media: "crossover", sets: 3, kg: 15, reps: 12, rest: 60,
            cues: [
                "Step forward with a slight lean and a soft bend in your elbows.",
                "Bring your hands together in a wide arc in front of your chest.",
                "Pause, then open back up until you feel a stretch across your chest.",
            ]),
        row("pushup", "Push-up", .chest, "Shoulders · Triceps", .bodyweight, .repsOnly,
            media: "pushup", sets: 3, kg: 0, reps: 12, rest: 60,
            cues: [
                "Hands under your shoulders, body in one straight line.",
                "Lower your chest to just above the floor with your elbows about 45° out.",
                "Press back up without sagging at the hips.",
            ]),
        row("cpress", "Machine chest press", .chest, "Shoulders · Triceps", .machine, .weightReps,
            media: nil, sets: 3, kg: 40, reps: 10, rest: 90,
            cues: [
                "Set the seat so the handles line up with mid-chest.",
                "Press forward until your arms are almost straight, then return slowly.",
            ]),
        row("dips", "Chest dip", .chest, "Triceps · Shoulders", .bodyweight, .repsOnly,
            media: nil, sets: 3, kg: 0, reps: 8, rest: 90,
            cues: [
                "Lean your torso forward and keep your elbows slightly flared.",
                "Lower until your shoulders are just below your elbows, then press up.",
            ]),
        row("pullup", "Pull-up", .back, "Biceps · Mid back", .bodyweight, .repsOnly,
            media: "pullup", sets: 3, kg: 0, reps: 8, rest: 120,
            cues: [
                "Start from a dead hang with your shoulders pulled down.",
                "Drive your elbows toward your hips until your chin clears the bar.",
                "Lower all the way down under control.",
            ]),
        row("pulldown", "Lat pulldown", .back, "Biceps · Mid back", .cable, .weightReps,
            media: "pulldown", sets: 3, kg: 50, reps: 10, rest: 90,
            cues: [
                "Grip slightly wider than your shoulders and lean back a touch.",
                "Pull the bar to your upper chest, leading with your elbows.",
                "Let the bar rise until your arms are straight again.",
            ]),
        row("brow", "Barbell row", .back, "Biceps · Lats", .barbell, .weightReps,
            media: "brow", sets: 3, kg: 50, reps: 8, rest: 120,
            cues: [
                "Hinge at the hips with a flat back and the bar hanging below your knees.",
                "Row the bar to your lower ribs, squeezing your shoulder blades.",
                "Lower under control without letting your torso rise.",
            ]),
        row("crow", "Seated cable row", .back, "Biceps · Lats", .cable, .weightReps,
            media: "crow", sets: 3, kg: 45, reps: 10, rest: 90,
            cues: [
                "Sit tall with a slight bend in your knees.",
                "Pull the handle to your lower ribs and squeeze your shoulder blades together.",
                "Return slowly until your arms are straight without rounding your back.",
            ]),
        row("dbrow", "One-arm dumbbell row", .back, "Biceps · Lats", .dumbbell, .weightReps,
            media: nil, sets: 3, kg: 24, reps: 10, rest: 90,
            cues: [
                "Support yourself on a bench with a flat back.",
                "Row the dumbbell toward your hip and pause before lowering.",
            ]),
        row("deadlift", "Deadlift", .back, "Glutes · Hamstrings", .barbell, .weightReps,
            media: "deadlift", sets: 3, kg: 80, reps: 5, rest: 180,
            cues: [
                "Stand with the bar over mid-foot and grip just outside your legs.",
                "Pull the slack out, keep your back flat and push the floor away.",
                "Lock out hips and knees together, then lower the bar along your legs.",
            ]),
        row("facepull", "Face pull", .shoulders, "Mid back", .cable, .weightReps,
            media: "facepull", sets: 3, kg: 20, reps: 15, rest: 60,
            cues: [
                "Set the cable at face height with a rope attachment.",
                "Pull toward your face, splitting the rope and flaring your elbows high.",
                "Pause, then return under control.",
            ]),
        row("ohp", "Overhead press", .shoulders, "Triceps", .barbell, .weightReps,
            media: "ohp", sets: 3, kg: 40, reps: 8, rest: 120,
            cues: [
                "Grip just outside shoulder width and brace your core and glutes.",
                "Press the bar straight up, moving your head back and then through.",
                "Lock out overhead and lower under control to your collarbone.",
            ]),
        row("dbpress", "Dumbbell shoulder press", .shoulders, "Triceps", .dumbbell, .weightReps,
            media: nil, sets: 3, kg: 18, reps: 10, rest: 90,
            cues: [
                "Start with the dumbbells at shoulder height, palms forward.",
                "Press overhead until your arms are straight, then lower slowly.",
            ]),
        row("lateral", "Dumbbell lateral raise", .shoulders, "Side delts", .dumbbell, .weightReps,
            media: "lateral", sets: 3, kg: 8, reps: 15, rest: 60,
            cues: [
                "Stand tall with a slight bend in your elbows.",
                "Raise the dumbbells out to the sides until they reach shoulder height.",
                "Lower slowly and don't swing your torso.",
            ]),
        row("rdelt", "Reverse pec deck", .shoulders, "Mid back", .machine, .weightReps,
            media: nil, sets: 3, kg: 25, reps: 12, rest: 60,
            cues: [
                "Sit facing the pad with your arms level with your shoulders.",
                "Sweep your arms back in a wide arc and squeeze your rear delts.",
            ]),
        row("curl", "Barbell curl", .arms, "Biceps · Forearms", .barbell, .weightReps,
            media: "curl", sets: 3, kg: 30, reps: 10, rest: 75,
            cues: [
                "Stand tall with your elbows pinned to your sides.",
                "Curl the bar up without swinging your torso.",
                "Lower for a slow two-count to a full stretch.",
            ]),
        row("dbcurl", "Dumbbell curl", .arms, "Biceps · Forearms", .dumbbell, .weightReps,
            media: "dbcurl", sets: 3, kg: 12, reps: 10, rest: 75,
            cues: [
                "Keep your elbows by your sides and your wrists straight.",
                "Curl both dumbbells up, turning your palms toward your shoulders.",
                "Lower slowly to a full stretch.",
            ]),
        row("hammer", "Hammer curl", .arms, "Biceps · Forearms", .dumbbell, .weightReps,
            media: nil, sets: 3, kg: 12, reps: 10, rest: 75,
            cues: [
                "Hold the dumbbells with palms facing each other.",
                "Curl up without letting your elbows drift forward.",
            ]),
        row("pushdown", "Triceps pushdown", .arms, "Triceps", .cable, .weightReps,
            media: "pushdown", sets: 3, kg: 30, reps: 12, rest: 60,
            cues: [
                "Pin your elbows to your sides and keep your chest up.",
                "Push the handle down until your arms are fully straight.",
                "Let it rise back to elbow height without moving your upper arms.",
            ]),
        row("skull", "Skull crusher", .arms, "Triceps · Forearms", .barbell, .weightReps,
            media: "skull", sets: 3, kg: 25, reps: 10, rest: 75,
            cues: [
                "Lie on a bench holding the bar over your chest with straight arms.",
                "Bend only at the elbows to lower the bar toward your forehead.",
                "Extend back up without letting your elbows flare.",
            ]),
        row("ohtri", "Overhead triceps extension", .arms, "Triceps", .cable, .weightReps,
            media: nil, sets: 3, kg: 20, reps: 12, rest: 60,
            cues: [
                "Face away from the cable with your elbows pointing forward.",
                "Extend your arms overhead and return to a deep stretch.",
            ]),
        row("preacher", "Preacher curl", .arms, "Biceps", .machine, .weightReps,
            media: nil, sets: 3, kg: 25, reps: 10, rest: 75,
            cues: [
                "Rest your upper arms flat on the pad.",
                "Curl up and lower slowly without lifting your elbows.",
            ]),
        row("squat", "Back squat", .legs, "Glutes · Hamstrings", .barbell, .weightReps,
            media: "squat", sets: 3, kg: 60, reps: 6, rest: 180,
            cues: [
                "Set the bar on your upper back and brace before you unrack.",
                "Sit down and back until your thighs are at least parallel.",
                "Drive up through your whole foot, keeping your knees in line with your toes.",
            ]),
        row("legpress", "Leg press", .legs, "Glutes", .machine, .weightReps,
            media: "legpress", sets: 3, kg: 120, reps: 10, rest: 120,
            cues: [
                "Place your feet shoulder-width apart in the middle of the platform.",
                "Lower until your knees are about 90° without your hips lifting off the seat.",
                "Press through your heels without locking your knees.",
            ]),
        row("rdl", "Romanian deadlift", .legs, "Glutes · Lower back", .barbell, .weightReps,
            media: "rdl", sets: 3, kg: 60, reps: 8, rest: 120,
            cues: [
                "Soften your knees and push your hips straight back.",
                "Slide the bar down your thighs with a flat back until you feel a hamstring stretch.",
                "Squeeze your glutes to stand tall again.",
            ]),
        row("lunge", "Walking lunge", .legs, "Glutes", .dumbbell, .weightReps,
            media: nil, sets: 3, kg: 12, reps: 10, rest: 90,
            cues: [
                "Take a long step and lower your back knee toward the floor.",
                "Push through your front heel to step into the next rep.",
            ]),
        row("legext", "Leg extension", .legs, "Quads", .machine, .weightReps,
            media: "legext", sets: 3, kg: 40, reps: 12, rest: 75,
            cues: [
                "Align your knees with the machine's pivot and sit back in the seat.",
                "Extend until your legs are straight and squeeze your quads.",
                "Lower under control and don't let the stack crash.",
            ]),
        row("legcurl", "Lying leg curl", .legs, "Hamstrings", .machine, .weightReps,
            media: "legcurl", sets: 3, kg: 30, reps: 12, rest: 75,
            cues: [
                "Line up your knees with the machine's pivot point.",
                "Curl the pad toward your glutes without lifting your hips.",
                "Lower slowly to full extension.",
            ]),
        row("calf", "Standing calf raise", .legs, "Calves", .machine, .weightReps,
            media: "calf", sets: 4, kg: 60, reps: 12, rest: 60,
            cues: [
                "Place the balls of your feet on the platform with your heels hanging off.",
                "Rise as high as you can and pause at the top.",
                "Lower into a deep stretch before the next rep.",
            ]),
        row("hipthrust", "Hip thrust", .legs, "Glutes · Hamstrings", .barbell, .weightReps,
            media: "hipthrust", sets: 3, kg: 70, reps: 8, rest: 90,
            cues: [
                "Rest your upper back on a bench with the bar over your hips.",
                "Drive through your heels until your hips are fully extended.",
                "Tuck your chin and pause at the top before lowering.",
            ]),
        row("plank", "Plank", .core, "Abs", .bodyweight, .duration,
            media: "plank", sets: 3, kg: 0, reps: 45, rest: 45,
            cues: [
                "Elbows under your shoulders, body in a straight line from head to heels.",
                "Squeeze your glutes and brace your abs.",
                "Breathe steadily and stop when your hips start to sag.",
            ]),
        row("cablecrunch", "Cable crunch", .core, "Abs", .cable, .weightReps,
            media: "cablecrunch", sets: 3, kg: 30, reps: 15, rest: 60,
            cues: [
                "Kneel below a high pulley with the rope by your head.",
                "Curl your ribs toward your hips, rounding your spine.",
                "Return slowly without sitting back onto your heels.",
            ]),
        row("hlr", "Hanging leg raise", .core, "Hip flexors", .bodyweight, .repsOnly,
            media: nil, sets: 3, kg: 0, reps: 10, rest: 60,
            cues: [
                "Hang from the bar with your shoulders engaged.",
                "Raise your legs without swinging, then lower slowly.",
            ]),
        row("abwheel", "Ab wheel rollout", .core, "Shoulders", .other, .repsOnly,
            media: nil, sets: 3, kg: 0, reps: 8, rest: 60,
            cues: [
                "Start on your knees with the wheel under your shoulders.",
                "Roll out as far as you can keep your back flat, then pull back in.",
            ]),
    ]

    /// Built-in exercises keyed by id (the first entry wins should an id ever repeat).
    private static let byID: [String: Exercise] = Dictionary(
        builtIn.map { ($0.id, $0) },
        uniquingKeysWith: { first, _ in first }
    )

    /// The built-in exercise with the given id, or nil when there is none.
    public static func exercise(id: String) -> Exercise? {
        byID[id]
    }

    /// Every distinct media key of the built-in exercises, in library order.
    public static let mediaKeys: [String] = {
        var seen = Set<String>()
        var keys: [String] = []
        for exercise in builtIn {
            if let key = exercise.mediaKey, seen.insert(key).inserted {
                keys.append(key)
            }
        }
        return keys
    }()

    /// Filters by search text, muscle group and equipment, sorted by name (case-insensitive, then id).
    ///
    /// Every whitespace separated token of `query` must occur, ignoring case, in
    /// "name muscle equipment secondary". A blank query matches everything; nil filters match every value.
    public static func filter(
        _ exercises: [Exercise],
        query: String,
        muscle: MuscleGroup?,
        equipment: Equipment?
    ) -> [Exercise] {
        let tokens = query.lowercased().split(whereSeparator: { $0.isWhitespace }).map(String.init)
        var matches: [(key: String, offset: Int, exercise: Exercise)] = []
        for (offset, exercise) in exercises.enumerated() {
            if let muscle = muscle, exercise.muscle != muscle { continue }
            if let equipment = equipment, exercise.equipment != equipment { continue }
            if !tokens.isEmpty {
                let haystack = [exercise.name, exercise.muscle.rawValue, exercise.equipment.rawValue, exercise.secondary]
                    .joined(separator: " ")
                    .lowercased()
                if !tokens.allSatisfy({ haystack.contains($0) }) { continue }
            }
            matches.append((exercise.name.lowercased(), offset, exercise))
        }
        matches.sort { lhs, rhs in
            if lhs.key != rhs.key { return lhs.key < rhs.key }
            if lhs.exercise.id != rhs.exercise.id { return lhs.exercise.id < rhs.exercise.id }
            return lhs.offset < rhs.offset
        }
        return matches.map { $0.exercise }
    }

    /// Builds one library entry from a design row (`barKg` is 10 for the skull crusher, else 20).
    private static func row(
        _ id: String,
        _ name: String,
        _ muscle: MuscleGroup,
        _ secondary: String,
        _ equipment: Equipment,
        _ tracking: TrackingKind,
        media: String?,
        sets: Int,
        kg: Double,
        reps: Int,
        rest: Int,
        cues: [String]
    ) -> Exercise {
        Exercise(
            id: id,
            name: name,
            muscle: muscle,
            secondary: secondary,
            equipment: equipment,
            tracking: tracking,
            mediaKey: media,
            previousBestE1RM: 0,
            previousSets: [],
            defaults: ExerciseDefaults(sets: sets, weightKg: kg, reps: reps, restSeconds: rest),
            cues: cues,
            barKg: id == "skull" ? 10 : 20,
            isCustom: false
        )
    }
}

package health.pulse.strength.core

/** The built-in exercise library of the strength feature (the 36 exercises of the design) and its search. */
object ExerciseLibrary {
    /** The 36 built-in exercises, in design order (ids, names, cues and defaults exactly as in the design). */
    val builtIn: List<Exercise> = listOf(
        row(
            "bench", "Barbell bench press", MuscleGroup.CHEST, "Shoulders · Triceps", Equipment.BARBELL, TrackingKind.WEIGHT_REPS,
            media = "bench", e1RM = 99.0, last = listOf(50.0 to 8, 70.0 to 5, 80.0 to 6, 80.0 to 6, 80.0 to 5),
            sets = 3, kg = 60.0, reps = 8, rest = 150,
            cues = listOf(
                "Pull your shoulder blades back and down and keep your feet planted.",
                "Lower the bar to mid-chest with your elbows about 45–60° from your body.",
                "Press up and slightly back until your arms are straight.",
            ),
        ),
        row(
            "incline", "Incline dumbbell press", MuscleGroup.CHEST, "Shoulders · Triceps", Equipment.DUMBBELL, TrackingKind.WEIGHT_REPS,
            media = "incline", e1RM = 38.0, last = listOf(26.0 to 10, 26.0 to 10, 26.0 to 9),
            sets = 3, kg = 24.0, reps = 10, rest = 90,
            cues = listOf(
                "Set the bench to 30–45° and keep your back flat on the pad.",
                "Lower the dumbbells to chest level with your elbows under your wrists.",
                "Press up without letting the weights drift apart.",
            ),
        ),
        row(
            "crossover", "Cable crossover", MuscleGroup.CHEST, "Shoulders", Equipment.CABLE, TrackingKind.WEIGHT_REPS,
            media = "crossover", e1RM = 22.0, last = listOf(15.0 to 12, 15.0 to 12, 15.0 to 11),
            sets = 3, kg = 15.0, reps = 12, rest = 60,
            cues = listOf(
                "Step forward with a slight lean and a soft bend in your elbows.",
                "Bring your hands together in a wide arc in front of your chest.",
                "Pause, then open back up until you feel a stretch across your chest.",
            ),
        ),
        row(
            "pushup", "Push-up", MuscleGroup.CHEST, "Shoulders · Triceps", Equipment.BODYWEIGHT, TrackingKind.REPS_ONLY,
            media = "pushup", e1RM = 0.0, last = listOf(0.0 to 15),
            sets = 3, kg = 0.0, reps = 12, rest = 60,
            cues = listOf(
                "Hands under your shoulders, body in one straight line.",
                "Lower your chest to just above the floor with your elbows about 45° out.",
                "Press back up without sagging at the hips.",
            ),
        ),
        row(
            "cpress", "Machine chest press", MuscleGroup.CHEST, "Shoulders · Triceps", Equipment.MACHINE, TrackingKind.WEIGHT_REPS,
            media = null, e1RM = 0.0, last = listOf(),
            sets = 3, kg = 40.0, reps = 10, rest = 90,
            cues = listOf(
                "Set the seat so the handles line up with mid-chest.",
                "Press forward until your arms are almost straight, then return slowly.",
            ),
        ),
        row(
            "dips", "Chest dip", MuscleGroup.CHEST, "Triceps · Shoulders", Equipment.BODYWEIGHT, TrackingKind.REPS_ONLY,
            media = null, e1RM = 0.0, last = listOf(),
            sets = 3, kg = 0.0, reps = 8, rest = 90,
            cues = listOf(
                "Lean your torso forward and keep your elbows slightly flared.",
                "Lower until your shoulders are just below your elbows, then press up.",
            ),
        ),
        row(
            "pullup", "Pull-up", MuscleGroup.BACK, "Biceps · Mid back", Equipment.BODYWEIGHT, TrackingKind.REPS_ONLY,
            media = "pullup", e1RM = 0.0, last = listOf(0.0 to 8),
            sets = 3, kg = 0.0, reps = 8, rest = 120,
            cues = listOf(
                "Start from a dead hang with your shoulders pulled down.",
                "Drive your elbows toward your hips until your chin clears the bar.",
                "Lower all the way down under control.",
            ),
        ),
        row(
            "pulldown", "Lat pulldown", MuscleGroup.BACK, "Biceps · Mid back", Equipment.CABLE, TrackingKind.WEIGHT_REPS,
            media = "pulldown", e1RM = 0.0, last = listOf(55.0 to 10),
            sets = 3, kg = 50.0, reps = 10, rest = 90,
            cues = listOf(
                "Grip slightly wider than your shoulders and lean back a touch.",
                "Pull the bar to your upper chest, leading with your elbows.",
                "Let the bar rise until your arms are straight again.",
            ),
        ),
        row(
            "brow", "Barbell row", MuscleGroup.BACK, "Biceps · Lats", Equipment.BARBELL, TrackingKind.WEIGHT_REPS,
            media = "brow", e1RM = 0.0, last = listOf(60.0 to 8),
            sets = 3, kg = 50.0, reps = 8, rest = 120,
            cues = listOf(
                "Hinge at the hips with a flat back and the bar hanging below your knees.",
                "Row the bar to your lower ribs, squeezing your shoulder blades.",
                "Lower under control without letting your torso rise.",
            ),
        ),
        row(
            "crow", "Seated cable row", MuscleGroup.BACK, "Biceps · Lats", Equipment.CABLE, TrackingKind.WEIGHT_REPS,
            media = "crow", e1RM = 0.0, last = listOf(50.0 to 10),
            sets = 3, kg = 45.0, reps = 10, rest = 90,
            cues = listOf(
                "Sit tall with a slight bend in your knees.",
                "Pull the handle to your lower ribs and squeeze your shoulder blades together.",
                "Return slowly until your arms are straight without rounding your back.",
            ),
        ),
        row(
            "dbrow", "One-arm dumbbell row", MuscleGroup.BACK, "Biceps · Lats", Equipment.DUMBBELL, TrackingKind.WEIGHT_REPS,
            media = null, e1RM = 0.0, last = listOf(),
            sets = 3, kg = 24.0, reps = 10, rest = 90,
            cues = listOf(
                "Support yourself on a bench with a flat back.",
                "Row the dumbbell toward your hip and pause before lowering.",
            ),
        ),
        row(
            "deadlift", "Deadlift", MuscleGroup.BACK, "Glutes · Hamstrings", Equipment.BARBELL, TrackingKind.WEIGHT_REPS,
            media = "deadlift", e1RM = 0.0, last = listOf(100.0 to 5),
            sets = 3, kg = 80.0, reps = 5, rest = 180,
            cues = listOf(
                "Stand with the bar over mid-foot and grip just outside your legs.",
                "Pull the slack out, keep your back flat and push the floor away.",
                "Lock out hips and knees together, then lower the bar along your legs.",
            ),
        ),
        row(
            "facepull", "Face pull", MuscleGroup.SHOULDERS, "Mid back", Equipment.CABLE, TrackingKind.WEIGHT_REPS,
            media = "facepull", e1RM = 0.0, last = listOf(20.0 to 15),
            sets = 3, kg = 20.0, reps = 15, rest = 60,
            cues = listOf(
                "Set the cable at face height with a rope attachment.",
                "Pull toward your face, splitting the rope and flaring your elbows high.",
                "Pause, then return under control.",
            ),
        ),
        row(
            "ohp", "Overhead press", MuscleGroup.SHOULDERS, "Triceps", Equipment.BARBELL, TrackingKind.WEIGHT_REPS,
            media = "ohp", e1RM = 58.0, last = listOf(45.0 to 8, 45.0 to 8, 45.0 to 7),
            sets = 3, kg = 40.0, reps = 8, rest = 120,
            cues = listOf(
                "Grip just outside shoulder width and brace your core and glutes.",
                "Press the bar straight up, moving your head back and then through.",
                "Lock out overhead and lower under control to your collarbone.",
            ),
        ),
        row(
            "dbpress", "Dumbbell shoulder press", MuscleGroup.SHOULDERS, "Triceps", Equipment.DUMBBELL, TrackingKind.WEIGHT_REPS,
            media = null, e1RM = 0.0, last = listOf(),
            sets = 3, kg = 18.0, reps = 10, rest = 90,
            cues = listOf(
                "Start with the dumbbells at shoulder height, palms forward.",
                "Press overhead until your arms are straight, then lower slowly.",
            ),
        ),
        row(
            "lateral", "Dumbbell lateral raise", MuscleGroup.SHOULDERS, "Side delts", Equipment.DUMBBELL, TrackingKind.WEIGHT_REPS,
            media = "lateral", e1RM = 12.5, last = listOf(8.0 to 15, 8.0 to 15, 8.0 to 14),
            sets = 3, kg = 8.0, reps = 15, rest = 60,
            cues = listOf(
                "Stand tall with a slight bend in your elbows.",
                "Raise the dumbbells out to the sides until they reach shoulder height.",
                "Lower slowly and don't swing your torso.",
            ),
        ),
        row(
            "rdelt", "Reverse pec deck", MuscleGroup.SHOULDERS, "Mid back", Equipment.MACHINE, TrackingKind.WEIGHT_REPS,
            media = null, e1RM = 0.0, last = listOf(),
            sets = 3, kg = 25.0, reps = 12, rest = 60,
            cues = listOf(
                "Sit facing the pad with your arms level with your shoulders.",
                "Sweep your arms back in a wide arc and squeeze your rear delts.",
            ),
        ),
        row(
            "curl", "Barbell curl", MuscleGroup.ARMS, "Biceps · Forearms", Equipment.BARBELL, TrackingKind.WEIGHT_REPS,
            media = "curl", e1RM = 0.0, last = listOf(30.0 to 10),
            sets = 3, kg = 30.0, reps = 10, rest = 75,
            cues = listOf(
                "Stand tall with your elbows pinned to your sides.",
                "Curl the bar up without swinging your torso.",
                "Lower for a slow two-count to a full stretch.",
            ),
        ),
        row(
            "dbcurl", "Dumbbell curl", MuscleGroup.ARMS, "Biceps · Forearms", Equipment.DUMBBELL, TrackingKind.WEIGHT_REPS,
            media = "dbcurl", e1RM = 0.0, last = listOf(12.0 to 10),
            sets = 3, kg = 12.0, reps = 10, rest = 75,
            cues = listOf(
                "Keep your elbows by your sides and your wrists straight.",
                "Curl both dumbbells up, turning your palms toward your shoulders.",
                "Lower slowly to a full stretch.",
            ),
        ),
        row(
            "hammer", "Hammer curl", MuscleGroup.ARMS, "Biceps · Forearms", Equipment.DUMBBELL, TrackingKind.WEIGHT_REPS,
            media = null, e1RM = 0.0, last = listOf(),
            sets = 3, kg = 12.0, reps = 10, rest = 75,
            cues = listOf(
                "Hold the dumbbells with palms facing each other.",
                "Curl up without letting your elbows drift forward.",
            ),
        ),
        row(
            "pushdown", "Triceps pushdown", MuscleGroup.ARMS, "Triceps", Equipment.CABLE, TrackingKind.WEIGHT_REPS,
            media = "pushdown", e1RM = 43.0, last = listOf(30.0 to 12, 30.0 to 12, 30.0 to 11),
            sets = 3, kg = 30.0, reps = 12, rest = 60,
            cues = listOf(
                "Pin your elbows to your sides and keep your chest up.",
                "Push the handle down until your arms are fully straight.",
                "Let it rise back to elbow height without moving your upper arms.",
            ),
        ),
        row(
            "skull", "Skull crusher", MuscleGroup.ARMS, "Triceps · Forearms", Equipment.BARBELL, TrackingKind.WEIGHT_REPS,
            media = "skull", e1RM = 0.0, last = listOf(25.0 to 10),
            sets = 3, kg = 25.0, reps = 10, rest = 75,
            cues = listOf(
                "Lie on a bench holding the bar over your chest with straight arms.",
                "Bend only at the elbows to lower the bar toward your forehead.",
                "Extend back up without letting your elbows flare.",
            ),
        ),
        row(
            "ohtri", "Overhead triceps extension", MuscleGroup.ARMS, "Triceps", Equipment.CABLE, TrackingKind.WEIGHT_REPS,
            media = null, e1RM = 0.0, last = listOf(),
            sets = 3, kg = 20.0, reps = 12, rest = 60,
            cues = listOf(
                "Face away from the cable with your elbows pointing forward.",
                "Extend your arms overhead and return to a deep stretch.",
            ),
        ),
        row(
            "preacher", "Preacher curl", MuscleGroup.ARMS, "Biceps", Equipment.MACHINE, TrackingKind.WEIGHT_REPS,
            media = null, e1RM = 0.0, last = listOf(),
            sets = 3, kg = 25.0, reps = 10, rest = 75,
            cues = listOf(
                "Rest your upper arms flat on the pad.",
                "Curl up and lower slowly without lifting your elbows.",
            ),
        ),
        row(
            "squat", "Back squat", MuscleGroup.LEGS, "Glutes · Hamstrings", Equipment.BARBELL, TrackingKind.WEIGHT_REPS,
            media = "squat", e1RM = 0.0, last = listOf(80.0 to 6),
            sets = 3, kg = 60.0, reps = 6, rest = 180,
            cues = listOf(
                "Set the bar on your upper back and brace before you unrack.",
                "Sit down and back until your thighs are at least parallel.",
                "Drive up through your whole foot, keeping your knees in line with your toes.",
            ),
        ),
        row(
            "legpress", "Leg press", MuscleGroup.LEGS, "Glutes", Equipment.MACHINE, TrackingKind.WEIGHT_REPS,
            media = "legpress", e1RM = 0.0, last = listOf(140.0 to 10),
            sets = 3, kg = 120.0, reps = 10, rest = 120,
            cues = listOf(
                "Place your feet shoulder-width apart in the middle of the platform.",
                "Lower until your knees are about 90° without your hips lifting off the seat.",
                "Press through your heels without locking your knees.",
            ),
        ),
        row(
            "rdl", "Romanian deadlift", MuscleGroup.LEGS, "Glutes · Lower back", Equipment.BARBELL, TrackingKind.WEIGHT_REPS,
            media = "rdl", e1RM = 0.0, last = listOf(70.0 to 8),
            sets = 3, kg = 60.0, reps = 8, rest = 120,
            cues = listOf(
                "Soften your knees and push your hips straight back.",
                "Slide the bar down your thighs with a flat back until you feel a hamstring stretch.",
                "Squeeze your glutes to stand tall again.",
            ),
        ),
        row(
            "lunge", "Walking lunge", MuscleGroup.LEGS, "Glutes", Equipment.DUMBBELL, TrackingKind.WEIGHT_REPS,
            media = null, e1RM = 0.0, last = listOf(),
            sets = 3, kg = 12.0, reps = 10, rest = 90,
            cues = listOf(
                "Take a long step and lower your back knee toward the floor.",
                "Push through your front heel to step into the next rep.",
            ),
        ),
        row(
            "legext", "Leg extension", MuscleGroup.LEGS, "Quads", Equipment.MACHINE, TrackingKind.WEIGHT_REPS,
            media = "legext", e1RM = 0.0, last = listOf(45.0 to 12),
            sets = 3, kg = 40.0, reps = 12, rest = 75,
            cues = listOf(
                "Align your knees with the machine's pivot and sit back in the seat.",
                "Extend until your legs are straight and squeeze your quads.",
                "Lower under control and don't let the stack crash.",
            ),
        ),
        row(
            "legcurl", "Lying leg curl", MuscleGroup.LEGS, "Hamstrings", Equipment.MACHINE, TrackingKind.WEIGHT_REPS,
            media = "legcurl", e1RM = 0.0, last = listOf(35.0 to 12),
            sets = 3, kg = 30.0, reps = 12, rest = 75,
            cues = listOf(
                "Line up your knees with the machine's pivot point.",
                "Curl the pad toward your glutes without lifting your hips.",
                "Lower slowly to full extension.",
            ),
        ),
        row(
            "calf", "Standing calf raise", MuscleGroup.LEGS, "Calves", Equipment.MACHINE, TrackingKind.WEIGHT_REPS,
            media = "calf", e1RM = 0.0, last = listOf(60.0 to 12),
            sets = 4, kg = 60.0, reps = 12, rest = 60,
            cues = listOf(
                "Place the balls of your feet on the platform with your heels hanging off.",
                "Rise as high as you can and pause at the top.",
                "Lower into a deep stretch before the next rep.",
            ),
        ),
        row(
            "hipthrust", "Hip thrust", MuscleGroup.LEGS, "Glutes · Hamstrings", Equipment.BARBELL, TrackingKind.WEIGHT_REPS,
            media = "hipthrust", e1RM = 0.0, last = listOf(80.0 to 8),
            sets = 3, kg = 70.0, reps = 8, rest = 90,
            cues = listOf(
                "Rest your upper back on a bench with the bar over your hips.",
                "Drive through your heels until your hips are fully extended.",
                "Tuck your chin and pause at the top before lowering.",
            ),
        ),
        row(
            "plank", "Plank", MuscleGroup.CORE, "Abs", Equipment.BODYWEIGHT, TrackingKind.DURATION,
            media = "plank", e1RM = 0.0, last = listOf(0.0 to 45),
            sets = 3, kg = 0.0, reps = 45, rest = 45,
            cues = listOf(
                "Elbows under your shoulders, body in a straight line from head to heels.",
                "Squeeze your glutes and brace your abs.",
                "Breathe steadily and stop when your hips start to sag.",
            ),
        ),
        row(
            "cablecrunch", "Cable crunch", MuscleGroup.CORE, "Abs", Equipment.CABLE, TrackingKind.WEIGHT_REPS,
            media = "cablecrunch", e1RM = 0.0, last = listOf(35.0 to 15),
            sets = 3, kg = 30.0, reps = 15, rest = 60,
            cues = listOf(
                "Kneel below a high pulley with the rope by your head.",
                "Curl your ribs toward your hips, rounding your spine.",
                "Return slowly without sitting back onto your heels.",
            ),
        ),
        row(
            "hlr", "Hanging leg raise", MuscleGroup.CORE, "Hip flexors", Equipment.BODYWEIGHT, TrackingKind.REPS_ONLY,
            media = null, e1RM = 0.0, last = listOf(),
            sets = 3, kg = 0.0, reps = 10, rest = 60,
            cues = listOf(
                "Hang from the bar with your shoulders engaged.",
                "Raise your legs without swinging, then lower slowly.",
            ),
        ),
        row(
            "abwheel", "Ab wheel rollout", MuscleGroup.CORE, "Shoulders", Equipment.OTHER, TrackingKind.REPS_ONLY,
            media = null, e1RM = 0.0, last = listOf(),
            sets = 3, kg = 0.0, reps = 8, rest = 60,
            cues = listOf(
                "Start on your knees with the wheel under your shoulders.",
                "Roll out as far as you can keep your back flat, then pull back in.",
            ),
        ),
    )

    /** Built-in exercises keyed by id (the first entry wins should an id ever repeat). */
    private val byID: Map<String, Exercise> = buildMap {
        for (exercise in builtIn) if (!containsKey(exercise.id)) put(exercise.id, exercise)
    }

    /** The built-in exercise with the given id, or null when there is none. */
    fun exercise(id: String): Exercise? = byID[id]

    /** Every distinct media key of the built-in exercises, in library order. */
    val mediaKeys: List<String> = builtIn.mapNotNull { it.mediaKey }.distinct()

    /**
     * Filters by search text, muscle group and equipment, sorted by name (case-insensitive, then id).
     *
     * Every whitespace separated token of [query] must occur, ignoring case, in
     * "name muscle equipment secondary". A blank query matches everything; null filters match every value.
     */
    fun filter(exercises: List<Exercise>, query: String, muscle: MuscleGroup?, equipment: Equipment?): List<Exercise> {
        val tokens = query.lowercase().split(Regex("\\s+")).filter { it.isNotEmpty() }
        class Match(val key: String, val offset: Int, val exercise: Exercise)
        val matches = mutableListOf<Match>()
        for ((offset, exercise) in exercises.withIndex()) {
            if (muscle != null && exercise.muscle != muscle) continue
            if (equipment != null && exercise.equipment != equipment) continue
            if (tokens.isNotEmpty()) {
                val haystack = listOf(exercise.name, exercise.muscle.rawValue, exercise.equipment.rawValue, exercise.secondary)
                    .joinToString(" ")
                    .lowercase()
                if (!tokens.all { haystack.contains(it) }) continue
            }
            matches.add(Match(exercise.name.lowercase(), offset, exercise))
        }
        matches.sortWith { lhs, rhs ->
            if (lhs.key != rhs.key) return@sortWith lhs.key.compareTo(rhs.key)
            if (lhs.exercise.id != rhs.exercise.id) return@sortWith lhs.exercise.id.compareTo(rhs.exercise.id)
            lhs.offset.compareTo(rhs.offset)
        }
        return matches.map { it.exercise }
    }

    /** Builds one library entry from a design row (`barKg` is 10 for the skull crusher, else 20). */
    private fun row(
        id: String,
        name: String,
        muscle: MuscleGroup,
        secondary: String,
        equipment: Equipment,
        tracking: TrackingKind,
        media: String?,
        e1RM: Double,
        last: List<Pair<Double, Int>>,
        sets: Int,
        kg: Double,
        reps: Int,
        rest: Int,
        cues: List<String>,
    ): Exercise = Exercise(
        id = id,
        name = name,
        muscle = muscle,
        secondary = secondary,
        equipment = equipment,
        tracking = tracking,
        mediaKey = media,
        previousBestE1RM = e1RM,
        previousSets = last.map { PreviousSet(weightKg = it.first, reps = it.second) },
        defaults = ExerciseDefaults(sets = sets, weightKg = kg, reps = reps, restSeconds = rest),
        cues = cues,
        barKg = if (id == "skull") 10.0 else 20.0,
        isCustom = false,
    )
}

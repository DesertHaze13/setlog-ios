# Workout calculations

The canonical implementation is in `Sources/iOS/Domain/Models.swift`; the same model is compiled for iOS, watchOS, and macOS.

- A day's visible sets are all sets in its visible exercises. On Friday, only exercises in the selected plan count; the two Friday plans are not merged.
- Progress is the number of visible sets marked done divided by the number of visible sets, multiplied by 100 and rounded to the nearest whole percent. For example, 4 of 5 done sets is 80%.
- A day is finished when its explicit `finished` flag is true **or** progress is at least 80%. If there are no visible sets, progress is 100% when explicitly finished and 0% otherwise.
- Each dated history snapshot stores the day's progress, finished state, completed visible-set count, and total visible-set count. Past-week records retain their own day data rather than being recalculated from today's schedule.
- A week begins on Monday in the device's current calendar and time zone. At rollover, the previous week's seven days are archived under that Monday's date. The new week keeps the schedule and carries the last completed nonempty load into `last`, but clears completed-set flags and day notes.
- HealthKit Move, Exercise, and Stand rings are separate Apple Fitness data queried for the selected date. They do not affect workout progress or the 80% finish rule and are not uploaded to Firebase.

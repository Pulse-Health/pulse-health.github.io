import Foundation

// Linux-only stand-ins for Combine, used to type-check and test `StrengthStore` and `WorkoutController` off Apple
// platforms. Build with `swift build -Xswiftc -DPULSE_COMBINE_SHIM` / `swift test -Xswiftc -DPULSE_COMBINE_SHIM`.
// On Apple platforms the real Combine is imported instead and this file compiles to nothing.
#if PULSE_COMBINE_SHIM && !canImport(Combine)

/// Minimal stand-in for Combine's `ObservableObject` (no publisher; it only marks the class).
public protocol ObservableObject: AnyObject {}

/// Minimal stand-in for Combine's `@Published` (stores the value; publishes nothing).
@propertyWrapper
public struct Published<Value> {
    /// The wrapped value.
    public var wrappedValue: Value

    /// Wraps `wrappedValue`.
    public init(wrappedValue: Value) {
        self.wrappedValue = wrappedValue
    }
}

#endif

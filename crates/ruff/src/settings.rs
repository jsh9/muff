//! Settings for muff-specific rules and behavior.

/// Settings for the muff linter rules.
#[derive(Debug, Clone, Default)]
pub struct Settings {
    /// Whether to parenthesize tuple-in-subscript expressions.
    pub parenthesize_tuple_in_subscript: bool,
}

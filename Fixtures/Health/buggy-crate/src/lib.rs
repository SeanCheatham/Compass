//! Minimal health eval fixture: one seeded bug + one control API.

/// Returns `n + 1` — documented as identity, intentionally wrong.
pub fn bump(n: i32) -> i32 {
    n + 1
}

/// Clamps `v` into `[lo, hi]` inclusive. Correct control API.
pub fn clamp(v: i32, lo: i32, hi: i32) -> i32 {
    if v < lo {
        lo
    } else if v > hi {
        hi
    } else {
        v
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn clamp_happy() {
        assert_eq!(clamp(5, 0, 10), 5);
    }
}

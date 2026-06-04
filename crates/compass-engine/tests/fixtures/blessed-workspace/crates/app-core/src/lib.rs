use std::fmt::{Display, Formatter, Result};

pub struct DemoState;

pub struct DemoRecord {
    pub count: u64,
    pub label: String,
}

impl Display for DemoState {
    fn fmt(&self, f: &mut Formatter<'_>) -> Result {
        write!(f, "demo")
    }
}

pub fn answer() -> usize {
    42
}

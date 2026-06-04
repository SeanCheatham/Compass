pub fn add(left: usize, right: usize) -> usize {
    left + right
}

#[cfg(test)]
mod tests {
    #[test]
    fn adds_numbers() {
        assert_eq!(super::add(2, 2), 4);
    }
}

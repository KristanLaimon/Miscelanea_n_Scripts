#[derive(Clone, Copy, Default, PartialEq)]
enum Held {
    #[default]
    No,
    Passed,
    Blocked,
}

#[derive(Clone, Copy, Default)]
pub struct ButtonFilter {
    held: Held,
    last_release: Option<u32>,
}

impl ButtonFilter {
    /// True means suppress this event. Time is the wrapping Windows millisecond clock.
    pub fn suppress(&mut self, down: bool, time: u32, enabled: bool, threshold: u32) -> bool {
        if down {
            if self.held != Held::No {
                return true;
            }
            let blocked = enabled
                && self
                    .last_release
                    .is_some_and(|last| time.wrapping_sub(last) < threshold);
            self.held = if blocked { Held::Blocked } else { Held::Passed };
            if !enabled {
                self.last_release = None;
            }
            blocked
        } else {
            // Finish a suppressed pair even if Stop was pressed during that pair.
            let blocked = self.held == Held::Blocked;
            self.held = Held::No;
            self.last_release = enabled.then_some(time);
            blocked
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn bounce_pairs_are_blocked_and_the_quiet_period_restarts() {
        let mut f = ButtonFilter::default();
        for (down, time, blocked) in [
            (true, 0, false),
            (false, 1000, false),
            (true, 1003, true),
            (false, 1005, true),
            (true, 1049, true),
            (false, 1051, true),
            (true, 1101, false),
            (false, 1120, false),
        ] {
            assert_eq!(f.suppress(down, time, true, 50), blocked);
        }
    }

    #[test]
    fn intentional_double_click_and_drag_are_preserved() {
        let mut f = ButtonFilter::default();
        for (down, time) in [(true, 0), (false, 20), (true, 150), (false, 3000)] {
            assert!(!f.suppress(down, time, true, 50));
        }
    }

    #[test]
    fn stopping_still_drains_a_blocked_release() {
        let mut f = ButtonFilter::default();
        assert!(!f.suppress(true, 0, true, 50));
        assert!(!f.suppress(false, 10, true, 50));
        assert!(f.suppress(true, 12, true, 50));
        assert!(f.suppress(false, 14, false, 50));
        assert!(!f.suppress(true, 15, false, 50));
        assert!(!f.suppress(false, 16, false, 50));
        assert!(!f.suppress(true, 17, true, 50));
    }

    #[test]
    fn buttons_are_independent_and_clock_wraps() {
        let mut left = ButtonFilter::default();
        let mut right = ButtonFilter::default();
        assert!(!left.suppress(true, u32::MAX - 10, true, 50));
        assert!(!left.suppress(false, u32::MAX - 5, true, 50));
        assert!(left.suppress(true, 3, true, 50));
        assert!(!right.suppress(true, 3, true, 50));
        assert!(!right.suppress(false, 1000, true, 50));
    }

    #[test]
    fn duplicate_down_does_not_lose_the_original_release() {
        let mut f = ButtonFilter::default();
        assert!(!f.suppress(true, 1, true, 50));
        assert!(f.suppress(true, 2, true, 50));
        assert!(!f.suppress(false, 3, true, 50));
    }
}

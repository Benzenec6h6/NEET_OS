use serde::Serialize;
use std::io;

#[derive(Debug, Serialize)]
pub struct StepResult {
    pub name: &'static str,
    pub ok: bool,
    pub error: Option<String>,
}

#[derive(Debug, Default, Serialize)]
pub struct Report {
    pub steps: Vec<StepResult>,
}

impl Report {
    pub fn step(&mut self, name: &'static str, f: impl FnOnce() -> io::Result<()>) {
        let r = f();
        if let Err(e) = &r {
            eprintln!("neet: step '{name}' failed: {e}");
        }
        self.steps.push(StepResult {
            name,
            ok: r.is_ok(),
            error: r.err().map(|e| e.to_string()),
        });
    }
    pub fn is_ok(&self) -> bool {
        self.steps.iter().all(|s| s.ok)
    }
}

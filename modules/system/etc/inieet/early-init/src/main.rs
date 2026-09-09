use std::env;
use std::path::Path;
use std::process::exit;

fn main() {
    let args: Vec<String> = env::args().collect();
    if args.len() < 3 {
        eprintln!("usage: early-init <mount-plan.json> <root-prefix>");
        exit(1);
    }
    let plan_path = Path::new(&args[1]);
    let root = Path::new(&args[2]);

    let entries = match init_core::load_plan(plan_path) {
        Ok(e) => e,
        Err(e) => {
            eprintln!("early-init: fatal: failed to load plan: {e}");
            exit(1);
        }
    };
    if let Err(e) = init_core::apply_plan(&entries, root) {
        eprintln!("early-init: fatal: {e}");
        exit(1);
    }
}

use std::env;
use std::path::Path;
use std::process::exit;

fn main() {
    let args: Vec<String> = env::args().collect();
    if args.len() < 3 {
        eprintln!("usage: stage1-mount <mount-plan.json> <root-prefix>");
        exit(1);
    }
    let plan_path = Path::new(&args[1]);
    let root = Path::new(&args[2]);

    let entries = match neet_mount::load_plan(plan_path) {
        Ok(e) => e,
        Err(e) => {
            eprintln!("stage1-mount: fatal: failed to load plan: {e}");
            exit(1);
        }
    };

    // stage 1 は strict: どのマウント失敗も致命的として扱う
    if let Err(e) = neet_mount::apply_plan(&entries, root, true) {
        eprintln!("stage1-mount: fatal: {e}");
        exit(1);
    }
}

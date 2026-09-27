use bootspec::{BootspecV1, Document};
use std::env;
use std::fs;

fn main() {
    let args: Vec<String> = env::args().collect();
    let get = |flag: &str| -> String {
        args.iter()
            .position(|a| a == flag)
            .and_then(|i| args.get(i + 1))
            .cloned()
            .unwrap_or_default()
    };

    let kernel_params: Vec<String> = get("--kernel-params")
        .split_whitespace()
        .map(String::from)
        .collect();

    let spec = BootspecV1 {
        system: get("--system"),
        init: get("--init"),
        initrd: Some(get("--initrd")).filter(|s| !s.is_empty()),
        kernel: get("--kernel"),
        kernel_params,
        label: get("--label"),
        toplevel: get("--toplevel"),
    };

    // ★ Document でラップして "org.nixos.bootspec.v1" キーを持たせる
    let doc = Document {
        bootspec: spec,
        specialisations: None,
    };

    let out = get("--out");
    let json = serde_json::to_string_pretty(&doc).expect("serialize");
    fs::write(&out, json).expect("write boot.json");
}

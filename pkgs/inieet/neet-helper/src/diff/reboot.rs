use anyhow::Result;
use neet_core::manifest::Core;

pub fn check_reboot_required(new_core: &Core) -> Result<Option<String>> {
    let booted = match neet_core::manifest::booted() {
        Ok(b) => b,
        Err(_) => {
            return Ok(Some(
                "Running system predates core manifest (reboot once to adopt it)".into(),
            ))
        }
    };

    // フィンガープリントが完全に一致していれば再起動不要
    if booted.manifest.boot_fingerprint == new_core.manifest.boot_fingerprint {
        return Ok(None);
    }

    // 各要素（Store パスやカーネルパラメータ）を行ごとに分割して差分を照合
    let old_lines: Vec<&str> = booted.manifest.boot_fingerprint.lines().collect();
    let new_lines: Vec<&str> = new_core.manifest.boot_fingerprint.lines().collect();

    let mut reasons = Vec::new();

    // 新しい世代で追加・変更された行をチェック
    for item in &new_lines {
        if !old_lines.contains(item) {
            classify_reason(item, &mut reasons);
        }
    }

    // 古い世代から削除された項目がある場合（例: パラメータ削除やドライバ無効化）
    for item in &old_lines {
        if !new_lines.contains(item) {
            classify_reason(item, &mut reasons);
        }
    }

    reasons.dedup();

    let reason_str = if reasons.is_empty() {
        "Core boot configuration changed".to_string()
    } else {
        reasons.join(", ")
    };

    Ok(Some(reason_str))
}

/// Store パスやパラメータの文字列パターンから変更理由を分類する
fn classify_reason(item: &str, reasons: &mut Vec<&'static str>) {
    if item.contains("stage1-mount-plan") {
        reasons.push("Stage 1 (initrd) mount plan changed");
    } else if item.contains("mount-plan") {
        reasons.push("Filesystem / Storage mount plan changed");
    } else if item.contains("ucode") || item.contains("microcode") {
        reasons.push("CPU microcode updated");
    } else if item.contains("modprobe") {
        reasons.push("Modprobe configuration changed");
    } else if item.contains("graphics") || item.contains("nvidia") || item.contains("mesa") {
        reasons.push("Graphics drivers changed");
    } else if item.contains("firmware") {
        reasons.push("Hardware firmware updated");
    } else if item.contains("kernel") || item.contains("linux") || item.contains("modules") {
        reasons.push("Kernel / Modules updated");
    } else {
        // パスではなく "quiet loglevel=3 ..." などのカーネルパラメータ
        reasons.push("Kernel command-line parameters changed");
    }
}

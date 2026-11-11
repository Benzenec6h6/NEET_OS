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

    if booted.manifest.boot_fingerprint != new_core.manifest.boot_fingerprint {
        Ok(Some(
            "Kernel, modules, firmware, kernel params, or graphics drivers changed".into(),
        ))
    } else {
        Ok(None)
    }
}

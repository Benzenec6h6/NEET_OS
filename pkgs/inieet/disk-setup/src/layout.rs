//! パーティションサイズの解釈と GPT レイアウト計算（純粋関数）
//!
//! 実機でもイメージでも同じ計算を使うので、sgdisk 任せの「0 = 自動」は使わず、
//! 開始/終了セクタを明示して渡す。

/// パーティションの境界は 1MiB に揃える
pub const ALIGN: u64 = 1024 * 1024;
/// 末尾に残す GPT バックアップ領域（セクタ数。4Kn でも足りる保守的な値）
const GPT_TAIL_SECTORS: u64 = 34;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum SizeSpec {
    Bytes(u64),
    /// 残り全部
    Rest,
}

pub fn parse_size(s: &str) -> Result<SizeSpec, String> {
    if s == "100%" {
        return Ok(SizeSpec::Rest);
    }
    let bad = || format!("invalid size '{s}' (expected e.g. 512M, 4G, 100%)");
    let unit = s.chars().last().ok_or_else(bad)?;
    let mult: u64 = match unit {
        'K' => 1 << 10,
        'M' => 1 << 20,
        'G' => 1 << 30,
        'T' => 1 << 40,
        _ => return Err(bad()),
    };
    let n: u64 = s[..s.len() - 1].parse().map_err(|_| bad())?;
    n.checked_mul(mult)
        .filter(|b| *b > 0)
        .map(SizeSpec::Bytes)
        .ok_or_else(bad)
}

/// セクタ単位・終端含む（sgdisk の表記に合わせる）
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct Extent {
    pub start_sector: u64,
    pub end_sector: u64,
}

impl Extent {
    pub fn offset_bytes(&self, sector: u64) -> u64 {
        self.start_sector * sector
    }
    pub fn len_bytes(&self, sector: u64) -> u64 {
        (self.end_sector - self.start_sector + 1) * sector
    }
}

fn round_up(n: u64) -> u64 {
    n.div_ceil(ALIGN) * ALIGN
}

pub fn compute_layout(
    total_bytes: u64,
    sector: u64,
    specs: &[SizeSpec],
) -> Result<Vec<Extent>, String> {
    if sector == 0 || ALIGN % sector != 0 {
        return Err(format!("unsupported sector size {sector}"));
    }
    let total_sectors = total_bytes / sector;
    if total_sectors <= GPT_TAIL_SECTORS + 2 * ALIGN / sector {
        return Err(format!("disk too small ({total_bytes} bytes)"));
    }
    // 終端（排他的、バイト）。末尾の GPT 領域を避けて 1MiB に切り下げる
    let limit = ((total_sectors - GPT_TAIL_SECTORS) * sector / ALIGN) * ALIGN;

    let mut cur = ALIGN;
    let mut out = Vec::with_capacity(specs.len());
    for (i, spec) in specs.iter().enumerate() {
        let end = match spec {
            SizeSpec::Bytes(n) => cur + round_up(*n),
            SizeSpec::Rest if i + 1 == specs.len() => limit,
            SizeSpec::Rest => return Err("'100%' must be the last partition".into()),
        };
        if end > limit || end <= cur {
            return Err(format!(
                "partition #{} does not fit (needs up to {end} bytes, usable {limit})",
                i + 1
            ));
        }
        out.push(Extent {
            start_sector: cur / sector,
            end_sector: end / sector - 1,
        });
        cur = end;
    }
    Ok(out)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parse_sizes() {
        assert_eq!(parse_size("512M"), Ok(SizeSpec::Bytes(512 << 20)));
        assert_eq!(parse_size("4G"), Ok(SizeSpec::Bytes(4 << 30)));
        assert_eq!(parse_size("100%"), Ok(SizeSpec::Rest));
        assert!(parse_size("50%").is_err());
        assert!(parse_size("0M").is_err());
        assert!(parse_size("M").is_err());
        assert!(parse_size("").is_err());
        assert!(parse_size("あ").is_err());
    }

    #[test]
    fn layout_fills_rest_and_aligns() {
        let total = 4096 * ALIGN;
        let l = compute_layout(
            total,
            512,
            &[SizeSpec::Bytes(512 << 20), SizeSpec::Rest],
        )
        .unwrap();
        assert_eq!(l[0].start_sector, 2048);
        assert_eq!(l[0].len_bytes(512), 512 << 20);
        assert_eq!(l[1].start_sector * 512, 513 * ALIGN);
        // 末尾の GPT 領域に食い込まない
        assert!(l[1].end_sector < total / 512 - 33);
        assert_eq!((l[1].end_sector + 1) * 512 % ALIGN, 0);
    }

    #[test]
    fn layout_rejects_overflow_and_misplaced_rest() {
        assert!(compute_layout(100 * ALIGN, 512, &[SizeSpec::Bytes(200 * ALIGN)]).is_err());
        assert!(compute_layout(100 * ALIGN, 512, &[SizeSpec::Rest, SizeSpec::Bytes(ALIGN)]).is_err());
        assert!(compute_layout(ALIGN, 512, &[SizeSpec::Rest]).is_err());
    }

    #[test]
    fn layout_4k_sectors() {
        let l = compute_layout(1024 * ALIGN, 4096, &[SizeSpec::Bytes(ALIGN), SizeSpec::Rest]).unwrap();
        assert_eq!(l[0].start_sector, ALIGN / 4096);
        assert_eq!(l[0].len_bytes(4096), ALIGN);
    }
}

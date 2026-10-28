//! neet-uki
//!
//! A pure-Rust, zero-dependency Unified Kernel Image (UKI) builder.
//! Injects .osrel, .cmdline, .initrd, and .linux sections into a systemd-boot stub EFI binary.

use std::env;
use std::fs;
use std::io::{self};
use std::path::PathBuf;

const PE_MAGIC_PE32: u16 = 0x10b;
const PE_MAGIC_PE32_PLUS: u16 = 0x20b;

// IMAGE_SCN_CNT_INITIALIZED_DATA | IMAGE_SCN_MEM_READ
const SECTION_FLAGS_DATA: u32 = 0x40000040;

struct Args {
    stub_path: PathBuf,
    osrel_path: PathBuf,
    cmdline_str: Option<String>,
    cmdline_path: Option<PathBuf>,
    initrd_path: PathBuf,
    linux_path: PathBuf,
    out_path: PathBuf,
}

fn parse_args() -> Result<Args, String> {
    let mut args = env::args().skip(1);
    let mut stub_path = None;
    let mut osrel_path = None;
    let mut cmdline_str = None;
    let mut cmdline_path = None;
    let mut initrd_path = None;
    let mut linux_path = None;
    let mut out_path = None;

    while let Some(arg) = args.next() {
        match arg.as_str() {
            "--stub" => stub_path = Some(PathBuf::from(args.next().ok_or("missing --stub")?)),
            "--osrel" => osrel_path = Some(PathBuf::from(args.next().ok_or("missing --osrel")?)),
            "--cmdline" => cmdline_str = Some(args.next().ok_or("missing --cmdline")?),
            "--cmdline-file" => {
                cmdline_path = Some(PathBuf::from(args.next().ok_or("missing --cmdline-file")?))
            }
            "--initrd" => initrd_path = Some(PathBuf::from(args.next().ok_or("missing --initrd")?)),
            "--linux" => linux_path = Some(PathBuf::from(args.next().ok_or("missing --linux")?)),
            "--out" => out_path = Some(PathBuf::from(args.next().ok_or("missing --out")?)),
            "--help" | "-h" => {
                return Err("help".into());
            }
            other => return Err(format!("unknown option: {other}")),
        }
    }

    Ok(Args {
        stub_path: stub_path.ok_or("error: --stub is required")?,
        osrel_path: osrel_path.ok_or("error: --osrel is required")?,
        cmdline_str,
        cmdline_path,
        initrd_path: initrd_path.ok_or("error: --initrd is required")?,
        linux_path: linux_path.ok_or("error: --linux is required")?,
        out_path: out_path.ok_or("error: --out is required")?,
    })
}

fn align_up(val: u32, align: u32) -> u32 {
    if align == 0 {
        return val;
    }
    (val + align - 1) & !(align - 1)
}

struct SectionToAdd {
    name: &'static str,
    data: Vec<u8>,
}

fn main() -> io::Result<()> {
    let args = match parse_args() {
        Ok(a) => a,
        Err(msg) => {
            if msg == "help" {
                println!("usage: neet-uki --stub <stub.efi> --osrel <os-release> (--cmdline <str> | --cmdline-file <path>) --initrd <initrd> --linux <bzImage> --out <out.efi>");
                std::process::exit(0);
            }
            eprintln!("{msg}");
            std::process::exit(1);
        }
    };

    // 1. 各ペイロードの読み込み
    let stub_bytes = fs::read(&args.stub_path)?;
    let osrel_data = fs::read(&args.osrel_path)?;
    let cmdline_data = if let Some(text) = args.cmdline_str {
        let mut d = text.into_bytes();
        if !d.ends_with(b"\0") {
            d.push(b'\0'); // cmdline は NULL 終端が安全
        }
        d
    } else if let Some(path) = args.cmdline_path {
        let mut d = fs::read(path)?;
        if !d.ends_with(b"\0") {
            d.push(b'\0');
        }
        d
    } else {
        eprintln!("error: either --cmdline or --cmdline-file must be specified");
        std::process::exit(1);
    };
    let initrd_data = fs::read(&args.initrd_path)?;
    let linux_data = fs::read(&args.linux_path)?;

    let sections = vec![
        SectionToAdd {
            name: ".osrel",
            data: osrel_data,
        },
        SectionToAdd {
            name: ".cmdline",
            data: cmdline_data,
        },
        SectionToAdd {
            name: ".initrd",
            data: initrd_data,
        },
        SectionToAdd {
            name: ".linux",
            data: linux_data,
        },
    ];

    // 2. PE ヘッダーの解析
    if stub_bytes.len() < 0x40 {
        return Err(io::Error::new(
            io::ErrorKind::InvalidData,
            "stub too small for DOS header",
        ));
    }
    let pe_offset = u32::from_le_bytes(stub_bytes[0x3c..0x40].try_into().unwrap()) as usize;
    if stub_bytes.len() < pe_offset + 24 {
        return Err(io::Error::new(
            io::ErrorKind::InvalidData,
            "stub too small for PE header",
        ));
    }
    if &stub_bytes[pe_offset..pe_offset + 4] != b"PE\0\0" {
        return Err(io::Error::new(
            io::ErrorKind::InvalidData,
            "invalid PE signature",
        ));
    }

    let coff_offset = pe_offset + 4;
    let num_sections = u16::from_le_bytes(
        stub_bytes[coff_offset + 2..coff_offset + 4]
            .try_into()
            .unwrap(),
    );
    let opt_hdr_size = u16::from_le_bytes(
        stub_bytes[coff_offset + 16..coff_offset + 18]
            .try_into()
            .unwrap(),
    ) as usize;
    let opt_hdr_offset = coff_offset + 20;

    let opt_magic = u16::from_le_bytes(
        stub_bytes[opt_hdr_offset..opt_hdr_offset + 2]
            .try_into()
            .unwrap(),
    );
    if opt_magic != PE_MAGIC_PE32 && opt_magic != PE_MAGIC_PE32_PLUS {
        return Err(io::Error::new(
            io::ErrorKind::InvalidData,
            "unsupported PE optional header magic",
        ));
    }

    // SectionAlignment (offset 32), FileAlignment (offset 36)
    let section_alignment = u32::from_le_bytes(
        stub_bytes[opt_hdr_offset + 32..opt_hdr_offset + 36]
            .try_into()
            .unwrap(),
    );
    let file_alignment = u32::from_le_bytes(
        stub_bytes[opt_hdr_offset + 36..opt_hdr_offset + 40]
            .try_into()
            .unwrap(),
    );
    let size_of_headers = u32::from_le_bytes(
        stub_bytes[opt_hdr_offset + 60..opt_hdr_offset + 64]
            .try_into()
            .unwrap(),
    ) as usize;

    let section_headers_offset = opt_hdr_offset + opt_hdr_size;

    // 既存セクションを走査して最大の VMA と FileOffset を算出
    let mut next_vma = 0u32;
    let mut next_raw = 0u32;
    for i in 0..num_sections as usize {
        let sh = section_headers_offset + i * 40;
        let v_size = u32::from_le_bytes(stub_bytes[sh + 8..sh + 12].try_into().unwrap());
        let v_addr = u32::from_le_bytes(stub_bytes[sh + 12..sh + 16].try_into().unwrap());
        let raw_size = u32::from_le_bytes(stub_bytes[sh + 16..sh + 20].try_into().unwrap());
        let raw_ptr = u32::from_le_bytes(stub_bytes[sh + 20..sh + 24].try_into().unwrap());

        let end_vma = align_up(v_addr + v_size, section_alignment);
        if end_vma > next_vma {
            next_vma = end_vma;
        }
        let end_raw = align_up(raw_ptr + raw_size, file_alignment);
        if end_raw > next_raw {
            next_raw = end_raw;
        }
    }

    // 追加するセクションヘッダーがヘッダー領域に収まるか検証
    let new_total_sections = num_sections as usize + sections.len();
    let required_header_space = section_headers_offset + new_total_sections * 40;
    if required_header_space > size_of_headers {
        return Err(io::Error::new(
            io::ErrorKind::InvalidData,
            format!("not enough header space: required {required_header_space}, available {size_of_headers}"),
        ));
    }

    // 3. セクションヘッダーの追加とペイロードの付加
    let mut output = stub_bytes;
    // ファイル末尾を file_alignment に揃える
    let initial_padding = align_up(output.len() as u32, file_alignment) as usize - output.len();
    output.resize(output.len() + initial_padding, 0);

    let mut current_vma = next_vma;
    let mut current_raw = output.len() as u32;

    for (i, sec) in sections.iter().enumerate() {
        let sec_hdr_pos = section_headers_offset + (num_sections as usize + i) * 40;

        let mut name_buf = [0u8; 8];
        let name_bytes = sec.name.as_bytes();
        let copy_len = name_bytes.len().min(8);
        name_buf[..copy_len].copy_from_slice(&name_bytes[..copy_len]);

        let v_size = sec.data.len() as u32;
        let v_addr = current_vma;
        let raw_size = align_up(v_size, file_alignment);
        let raw_ptr = current_raw;

        // セクションヘッダー書き込み (40 bytes)
        output[sec_hdr_pos..sec_hdr_pos + 8].copy_from_slice(&name_buf);
        output[sec_hdr_pos + 8..sec_hdr_pos + 12].copy_from_slice(&v_size.to_le_bytes());
        output[sec_hdr_pos + 12..sec_hdr_pos + 16].copy_from_slice(&v_addr.to_le_bytes());
        output[sec_hdr_pos + 16..sec_hdr_pos + 20].copy_from_slice(&raw_size.to_le_bytes());
        output[sec_hdr_pos + 20..sec_hdr_pos + 24].copy_from_slice(&raw_ptr.to_le_bytes());
        // Relocations, LineNumbers (0)
        output[sec_hdr_pos + 24..sec_hdr_pos + 36].fill(0);
        // Characteristics
        output[sec_hdr_pos + 36..sec_hdr_pos + 40]
            .copy_from_slice(&SECTION_FLAGS_DATA.to_le_bytes());

        // ペイロードデータをファイル末尾に追加（アライメントのゼロ埋め含む）
        output.extend_from_slice(&sec.data);
        let pad = raw_size - v_size;
        output.resize(output.len() + pad as usize, 0);

        println!(
            "neet-uki: section {:<8} VMA: 0x{:08x}..0x{:08x} (size: {} KB)",
            sec.name,
            v_addr,
            v_addr + v_size,
            (v_size + 1023) / 1024
        );

        current_vma = align_up(current_vma + v_size, section_alignment);
        current_raw += raw_size;
    }

    // 4. COFF / Optional ヘッダーの更新
    // NumberOfSections を更新
    output[coff_offset + 2..coff_offset + 4]
        .copy_from_slice(&(new_total_sections as u16).to_le_bytes());

    // SizeOfImage を更新 (オフセット 56)
    let final_image_size = align_up(current_vma, section_alignment);
    output[opt_hdr_offset + 56..opt_hdr_offset + 60]
        .copy_from_slice(&final_image_size.to_le_bytes());

    // 5. 出力ファイルに書き出し
    if let Some(parent) = args.out_path.parent() {
        fs::create_dir_all(parent)?;
    }
    fs::write(&args.out_path, &output)?;

    println!(
        "neet-uki: successfully generated UKI at {} (total size: {} MB)",
        args.out_path.display(),
        (output.len() + 1048575) / 1048576
    );

    Ok(())
}

use anyhow::{anyhow, Context, Result};
use std::str::FromStr;
use tss_esapi::{
    attributes::SessionAttributesBuilder,
    constants::SessionType,
    handles::{NvIndexHandle, NvIndexTpmHandle, TpmHandle},
    interface_types::{
        algorithm::HashingAlgorithm, resource_handles::NvAuth, session_handles::PolicySession,
    },
    structures::{Digest, PcrSelectionListBuilder, PcrSlot, SymmetricDefinition},
    Context as TssContext, TctiNameConf,
};

/// デフォルトの NVRAM インデックス (Owner NV Index)
pub const DEFAULT_AGE_NV_INDEX: u32 = 0x01500000;

/// TPM 2.0 NVRAM から age 秘密鍵を安全に読み出し、age::Identity を復元する
pub fn load_tpm_identity(nv_index_raw: u32) -> Result<Box<dyn age::Identity>> {
    let tcti = TctiNameConf::from_str("device:/dev/tpmrm0")
        .context("Failed to configure TCTI for /dev/tpmrm0")?;
    let mut ctx = TssContext::new(tcti).context("Failed to connect to TPM 2.0 device")?;

    let nv_tpm_handle = NvIndexTpmHandle::new(nv_index_raw)
        .map_err(|e| anyhow!("Invalid NV index 0x{:08x}: {:?}", nv_index_raw, e))?;
    let esys_handle = ctx
        .tr_from_tpm_public(TpmHandle::NvIndex(nv_tpm_handle))
        .context("Failed to retrieve ESYS handle for NV index from TPM")?;
    let nv_handle = NvIndexHandle::from(esys_handle);

    let (session_attrs, session_attrs_mask) = SessionAttributesBuilder::new()
        .with_decrypt(true)
        .with_encrypt(true)
        .build();

    let session = ctx
        .start_auth_session(
            None,
            None,
            None,
            SessionType::Policy,
            SymmetricDefinition::AES_256_CFB,
            HashingAlgorithm::Sha256,
        )
        .context("Failed to start TPM policy session")?;

    let session_handle = session.ok_or_else(|| anyhow!("Expected auth session handle"))?;
    ctx.tr_sess_set_attributes(session_handle, session_attrs, session_attrs_mask)?;

    // ★ 修正点1: まずは PCR 7 (セキュアブート状態) のみに絞る
    // (rebuild で UKI が更新されてもアンシール不能にならないようにするため)
    let pcr_selection = PcrSelectionListBuilder::new()
        .with_selection(HashingAlgorithm::Sha256, &[PcrSlot::Slot7])
        .build()
        .context("Failed to build PCR selection")?;

    let policy_session = PolicySession::try_from(session_handle)
        .context("Failed to convert AuthSession to PolicySession")?;
    ctx.policy_pcr(policy_session, Digest::default(), pcr_selection)
        .context("TPM PCR policy check failed (PCR 7 mismatch)")?;

    // 3. NVRAM からデータを読み出し
    ctx.set_sessions((Some(session_handle), None, None));
    let raw_data = ctx
        .nv_read(NvAuth::NvIndex(nv_handle), nv_handle, 128, 0)
        .context("Failed to read age secret key from TPM NVRAM")?;

    // ★ 修正点2: NULLバイト (0x00) や余計な改行・空白を完全に切り捨てる
    // 最初の NULL バイトが出現した位置まででスライスを打ち切る
    let valid_bytes = match raw_data.iter().position(|&b| b == 0) {
        Some(pos) => &raw_data[..pos],
        None => raw_data.as_slice(),
    };

    let key_str = std::str::from_utf8(valid_bytes)
        .context("TPM NVRAM data is not valid UTF-8 string")?
        .trim();

    // 4. age::x25519::Identity ("AGE-SECRET-KEY-1...") としてパース
    let identity = age::x25519::Identity::from_str(key_str).map_err(|e| {
        anyhow!(
            "Failed to parse age secret key from TPM (key_str: '{}'): {}",
            key_str,
            e
        )
    })?;

    Ok(Box::new(identity))
}

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
    // 1. /dev/tpmrm0 (カーネル内蔵リソースマネージャ) と接続
    let tcti = TctiNameConf::from_str("device:/dev/tpmrm0")
        .context("Failed to configure TCTI for /dev/tpmrm0")?;
    let mut ctx = TssContext::new(tcti).context("Failed to connect to TPM 2.0 device")?;

    // TPM 物理インデックスから ESYS ハンドルを取得
    let nv_tpm_handle = NvIndexTpmHandle::new(nv_index_raw)
        .map_err(|e| anyhow!("Invalid NV index 0x{:08x}: {:?}", nv_index_raw, e))?;
    let esys_handle = ctx
        .tr_from_tpm_public(TpmHandle::NvIndex(nv_tpm_handle))
        .context("Failed to retrieve ESYS handle for NV index from TPM")?;
    let nv_handle = NvIndexHandle::from(esys_handle);

    // 2. PCR 7 (SecureBoot) と PCR 11 (UKI) のセッションポリシーを作成
    // ※ セッション暗号化 (Parameter Encryption) を有効にしてバス盗聴を遮断
    // 7.7 では build() が (SessionAttributes, SessionAttributesMask) のタプルを返します
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
            SymmetricDefinition::AES_256_CFB, // 暗号化アルゴリズムを明示指定
            HashingAlgorithm::Sha256,
        )
        .context("Failed to start TPM policy session")?;

    let session_handle = session.ok_or_else(|| anyhow!("Expected auth session handle"))?;
    // ESYS 仕様名に合わせた tr_sess_set_attributes に変更
    ctx.tr_sess_set_attributes(session_handle, session_attrs, session_attrs_mask)?;

    // PCR 7 と 11 を選択 (.with_size_of_select(3) は省略可能で自動計算されます)
    let pcr_selection = PcrSelectionListBuilder::new()
        .with_selection(HashingAlgorithm::Sha256, &[PcrSlot::Slot7, PcrSlot::Slot11])
        .build()
        .context("Failed to build PCR selection")?;

    // ポリシーを実行 (PCR 7+11 の現在の値と一致するかハードウェア検証)
    let policy_session = PolicySession::try_from(session_handle)
        .context("Failed to convert AuthSession to PolicySession")?;
    ctx.policy_pcr(policy_session, Digest::default(), pcr_selection)
        .context("TPM PCR policy check failed (PCR 7 or 11 mismatch: tampering detected!)")?;

    // 3. NVRAM からデータを読み出し (最大 128 バイト程度)
    ctx.set_sessions((Some(session_handle), None, None));
    let raw_data = ctx
        .nv_read(NvAuth::NvIndex(nv_handle), nv_handle, 128, 0)
        .context("Failed to read age secret key from TPM NVRAM")?;

    let key_str = std::str::from_utf8(raw_data.as_slice())
        .context("TPM NVRAM data is not valid UTF-8 string")?
        .trim();

    // 4. age::x25519::Identity ("AGE-SECRET-KEY-1...") としてパース
    let identity = age::x25519::Identity::from_str(key_str)
        .map_err(|e| anyhow!("Failed to parse age secret key from TPM: {}", e))?;

    Ok(Box::new(identity))
}

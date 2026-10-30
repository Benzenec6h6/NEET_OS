NV_INDEX="0x01500000"
PCR_LIST="sha256:7,11"

if [ "$(id -u)" -ne 0 ]; then
    echo "neet-tpm-enroll: error: root privileges are required (run with sudo or doas)." >&2
    exit 1
fi

echo "==> NEET OS: Initializing TPM 2.0 secret store..."

TMP_DIR=$(mktemp -d -t tpm-enroll.XXXXXX)
mount -t tmpfs none "$TMP_DIR"

cleanup() {
    umount "$TMP_DIR" 2>/dev/null || true
    rm -rf "$TMP_DIR"
}
trap cleanup EXIT

# 1. PCR 7+11 からアクセスポリシーを生成
tpm2_pcrread "$PCR_LIST" -o "$TMP_DIR/pcr.bin"
tpm2_createpolicy --policy-pcr --pcr-list "$PCR_LIST" -f "$TMP_DIR/pcr.bin" --policy "$TMP_DIR/pcr.policy"

# 2. 既存スロットがあれば解放
tpm2_nvundefine "$NV_INDEX" -C o 2>/dev/null || true

# 3. NVRAM スロットを定義
tpm2_nvdefine "$NV_INDEX" \
    -C o \
    -s 128 \
    -a "ownerread|policyread|ownerwrite" \
    -L "$TMP_DIR/pcr.policy"

# 4. age 鍵ペアを生成し、秘密鍵はファイルを作らず直接 TPM に書き込む
KEY_OUTPUT=$(age-keygen 2>&1)
PUB_KEY=$(echo "$KEY_OUTPUT" | grep -o 'age1[0-9a-z]\+')

echo "$KEY_OUTPUT" | grep -v "^#" | tr -d '\r\n' | tpm2_nvwrite "$NV_INDEX" -C o -i -
unset KEY_OUTPUT

echo ""
echo "==> SUCCESS: Master age identity has been sealed into TPM2 NVRAM."
echo "Add the following public key to 'neet.security.secrets.editor.publicKeys':"
echo ""
echo "  \"$PUB_KEY\""
echo ""

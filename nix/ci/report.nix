{
  pkgs,
  lib,
  checkList,
}:
pkgs.runCommand "ci-summary-report" {} ''
  mkdir -p $out
  reportMd="$out/report.md"
  hasFailed=0

  echo "## 🛠️ NEET OS - CI Summary Report" >> "$reportMd"
  echo "" >> "$reportMd"
  echo "| Check | Status |" >> "$reportMd"
  echo "| :--- | :---: |" >> "$reportMd"

  # サマリーテーブル
  ${lib.concatMapStringsSep "\n" (item: ''
      status=$(cat "${item.path}/status")
      if [ "$status" = "OK" ]; then
        icon="✅ **PASS**"
      else
        icon="❌ **FAIL**"
        hasFailed=1
      fi
      printf "| %-35s | %s |\n" "${item.name}" "$icon" >> "$reportMd"
    '')
    checkList}

  # 失敗した項目の詳細（GitHub上で折りたたみ表示）
  ${lib.concatMapStringsSep "\n" (item: ''
      status=$(cat "${item.path}/status")
      if [ "$status" != "OK" ]; then
        echo "" >> "$reportMd"
        echo "<details open><summary>❌ <b>Details: ${item.name}</b></summary>" >> "$reportMd"
        echo "" >> "$reportMd"
        echo "\`\`\`text" >> "$reportMd"
        cat "${item.path}/log.txt" >> "$reportMd"
        echo "\`\`\`" >> "$reportMd"
        echo "</details>" >> "$reportMd"
      fi
    '')
    checkList}

  # 失敗フラグをファイルに残す (derivation 自体は exit 0 で完了させる)
  if [ $hasFailed -ne 0 ]; then
    touch $out/failed
  fi

  # コンソール (ログ) にも出力
  cat "$reportMd"
''

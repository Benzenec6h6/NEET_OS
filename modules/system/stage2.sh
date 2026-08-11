#!/bin/sh

# エラー時に停止、未定義変数の使用禁止
set -eu

echo "NEET OS Stage 2: Preparing environment..."

export PATH="/bin:@systemPath@/bin:@s6@/bin"

echo "NEET OS Stage 2: Running activation script..."
# NixOSのactivationScriptを実行
@activationScript@

echo "NEET OS Stage 2: Starting s6-svscan..."
# s6-svscanを実行してサービス管理を開始
exec @s6@/bin/s6-svscan /run/service

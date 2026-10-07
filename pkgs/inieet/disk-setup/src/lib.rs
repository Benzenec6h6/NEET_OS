//! disk-setup: disk-plan.json を解釈して、パーティション作成・mkfs・マウントを行う
//!
//! 方針:
//! - Nix 側が宣言から disk-plan.json（識別子はすべて eval 時に確定済み）を吐く
//! - ここは「平坦な plan を順に実行するだけ」。コマンド列の組み立ては純粋関数に分け、単体テストする
//! - 実機（`format`）とイメージ（`image`）で同じ plan・同じレイアウト計算・同じ mkfs 引数を使う

pub mod exec;
pub mod image;
pub mod layout;
pub mod plan;
pub mod steps;

use std::io;

pub(crate) fn err(msg: impl Into<String>) -> io::Error {
    io::Error::other(msg.into())
}

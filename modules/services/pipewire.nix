{
  config,
  pkgs,
  lib,
  ...
}: let
  cfg = config.services.pipewire;
  inherit (lib) mkOption mkEnableOption mkIf types;

  hasUdev = config.services.deviceManager == "gardendevd";
in {
  options.services.pipewire = {
    enable = mkEnableOption "PipeWire multimedia service";

    audio.enable = mkOption {
      type = types.bool;
      default = true;
      description = "PipeWire を主オーディオサーバーとして使用するか";
    };

    alsa.enable = mkOption {
      type = types.bool;
      default = true;
      description = "ALSA アプリケーションの音声を PipeWire にリダイレクトするか";
    };

    pulse.enable = mkOption {
      type = types.bool;
      default = true;
      description = "PulseAudio エミュレーション (pipewire-pulse) を有効にするか";
    };

    package = mkOption {
      type = types.package;
      default = pkgs.pipewire;
      description = "使用する PipeWire パッケージ";
    };

    fallbackStaticNodes = mkOption {
      type = types.bool;
      default = !hasUdev; # udev が使えない環境（mdevd等）なら自動で true
      description = ''
        udev が存在しない環境で、ALSA デバイス (hw:0,0) を直接静的ノードとして登録するかどうか。
      '';
    };
  };

  config = mkIf cfg.enable {
    # リアルタイムスケジューリングのため RTKit も自動でオンに
    services.rtkit.enable = lib.mkDefault true;

    services.udev.extraRules = ''
      SUBSYSTEM=="sound", KERNEL=="controlC*", ENV{SOUND_INITIALIZED}="1"
    '';

    environment.etc."pipewire/pipewire.conf.d/10-fallback-static-alsa.conf" = mkIf cfg.fallbackStaticNodes {
      text = ''
        context.objects = [
          { factory = adapter
            args = {
              factory.name     = api.alsa.pcm.sink
              node.name        = "alsa-sink"
              node.description = "Default ALSA Sink"
              media.class      = "Audio/Sink"
              api.alsa.path    = "hw:0,0"
              audio.position   = [ FL FR ]
            }
          }
        ]
      '';
    };

    environment.systemPackages = [
      cfg.package
      pkgs.alsa-utils
      pkgs.alsa-ucm-conf # ノートPC内蔵スピーカー等の初期化に必須
    ];

    # 1. ALSA の出力を PipeWire プラグイン経由にする (/etc/asound.conf)
    environment.etc."asound.conf".text = mkIf cfg.alsa.enable ''
      <confdir:pcm/default.conf>

      pcm.!default {
        type pipewire
        playback_node "-1"
        capture_node "-1"
      }

      ctl.!default {
        type pipewire
      }
    '';

    # 2. ALSA プラグインの探索パスを ALSA アプリに知らせる
    environment.etc."alsa/conf.d/50-pipewire.conf".source = "${cfg.package}/share/alsa/alsa.conf.d/50-pipewire.conf";
    environment.etc."alsa/conf.d/99-pipewire-default.conf".source = "${cfg.package}/share/alsa/alsa.conf.d/99-pipewire-default.conf";
  };
}

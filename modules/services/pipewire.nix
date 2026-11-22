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
      default = !hasUdev;
      description = ''
        udev が存在しない環境で、ALSA デバイス (hw:0,0) を直接静的ノードとして登録するかどうか。
      '';
    };
  };

  # ─── ユーザーごとの設定・s6 サービス ───
  options.neet.users = mkOption {
    type = types.attrsOf (types.submodule ({
      name,
      config,
      ...
    }: {
      options.services.pipewire = {
        enable = mkOption {
          type = types.bool;
          default = cfg.enable && config.isSessionUser;
          description = "ユーザー '${name}' で PipeWire s6 サービスを起動するか";
        };

        pulse = {
          enable = mkOption {
            type = types.bool;
            default = cfg.pulse.enable;
            description = "PulseAudio 互換レイヤーを起動するか";
          };
        };
      };

      config = mkIf config.services.pipewire.enable {
        # ★ s6.services に定義
        s6.services.pipewire = {
          type = "longrun";
          dependencies = ["dbus"];
          run = ''
            #!/bin/sh
            exec ${cfg.package}/bin/pipewire
          '';
        };

        s6.services.pipewire-pulse = mkIf config.services.pipewire.pulse.enable {
          type = "longrun";
          dependencies = ["pipewire"];
          run = ''
            #!/bin/sh
            exec ${cfg.package}/bin/pipewire -c pipewire-pulse.conf
          '';
        };
      };
    }));
  };

  config = mkIf cfg.enable {
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
      pkgs.alsa-ucm-conf
    ];

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

    environment.etc."alsa/conf.d/50-pipewire.conf".source = "${cfg.package}/share/alsa/alsa.conf.d/50-pipewire.conf";
    environment.etc."alsa/conf.d/99-pipewire-default.conf".source = "${cfg.package}/share/alsa/alsa.conf.d/99-pipewire-default.conf";
  };
}

let
  sup-shell = import ../nix/ruby4.0-shell.nix;
  pkgs = sup-shell.pkgs;
  fileset = pkgs.lib.fileset;
  sup = fileset.toSource {
    root = ../..;
    fileset = fileset.difference ../.. ../../contrib;
  };
  ht = pkgs.rustPlatform.buildRustPackage (finalAttrs: {
    pname = "ht";
    version = "0.4.0";
    src = pkgs.fetchFromGitHub {
      owner = "andyk";
      repo = "ht";
      tag = "v${finalAttrs.version}";
      hash = "sha256-LKa5nnGhQITf0SDzE17NUJ9KQ6Soq6jOBWoTONRxiCc=";
    };
    cargoHash = "sha256-FlR7bvQAZZIJaONOGsZUtSuUOvAVeDXJQaEkvXYxp1w=";
  });
  deps = with pkgs; [
    sup-shell.gems.wrappedRuby
    gnupg
    ncurses
    which
    rsync
    libfaketime
    ht
  ];

  now = "2026-04-21 20:00:00";
  lists.supmua = pkgs.fetchgit {
    name = "supmua-list";
    url = "https://supmua.dev/lists/supmua/0";
    rev = "5bb23abca5490dc0d946312a8dbc3ece92bbfa95";
    hash = "sha256-c25+ZfDOz8oSx95p1Mq7LI35n1F4IFDWog4YZUn644M=";
    deepClone = true;
  };
  lists.sup-devel = pkgs.fetchgit {
    name = "sup-devel-list";
    url = "https://supmua.dev/lists/sup-devel/0";
    rev = "5e44841d194d5bfb581022d5951e0964a1d85edd";
    hash = "sha256-g9tPF97noIVoc3xfWM6D+aNDWOyn2SX967YsO4jabpM=";
    deepClone = true;
  };
  lists.sup-talk = pkgs.fetchgit {
    name = "sup-talk-list";
    url = "https://supmua.dev/lists/sup-talk/0";
    rev = "93f1725cde6bb046a7a086eb1b99342a3371802c";
    hash = "sha256-ksbTPTcE7ueGKWjC+rC1xkiRF4/MpJcSqJhoA735G/Y=";
    deepClone = true;
  };
  lists-as-maildir = builtins.mapAttrs (
    name: pirepo:
    pkgs.stdenv.mkDerivation {
      name = "${name}-as-maildir";
      nativeBuildInputs = with pkgs; [ git ];
      buildCommand = ''
        mkdir -p $out/{cur,new,tmp}
        export GIT_DIR=${pirepo}/.git
        git rev-list HEAD | while read sha ; do
          git show $sha:m >$out/new/$sha:2,S
        done
      '';
    }
  ) lists;
  sup-is-plain-text = ./sup-is-plain-text.msg;
  sup-is-plain-text-applied = ./sup-is-plain-text-applied.msg;
  misc-maildir = pkgs.stdenv.mkDerivation {
    name = "sup-screenshots-misc-maildir";
    nativeBuildInputs = with pkgs; [
      curl
      python3
    ];
    buildCommand = ''
      mkdir -p $out/{cur,new,tmp}
      cp ${sup-is-plain-text} $out/cur/sup-is-plain-text:2,S
      cp ${sup-is-plain-text-applied} $out/cur/sup-is-plain-text-applied:2,S
    '';
  };

  # Build a fake .sup directory for screenshots.
  sup-base = pkgs.stdenv.mkDerivation {
    name = "sup-base-for-screenshots";
    nativeBuildInputs = deps;
    env = {
      TZ = "UTC";
      USER = "nobody";
      LANG = "C.UTF-8";
    };
    buildCommand = ''
      mkdir -p $out

      cat >$out/config.yaml <<EOF
      ---
      :accounts:
        :default:
          :name: Sup User
          :email: sup@example.invalid
          :sendmail: /bin/false
      :sync_back_to_maildir: false
      :editor: /bin/false
      :poll_interval: 86400
      EOF

      cat >$out/sources.yaml <<EOF
      ---
      - !<tag:supmua.org,2006-10-01/Redwood/Maildir>
        uri: maildir://${lists-as-maildir.supmua}
        usual: true
        archived: false
        id: 1
        labels: [supmua]
      - !<tag:supmua.org,2006-10-01/Redwood/Maildir>
        uri: maildir://${lists-as-maildir.sup-devel}
        usual: true
        archived: false
        id: 2
        labels: [sup-devel]
      - !<tag:supmua.org,2006-10-01/Redwood/Maildir>
        uri: maildir://${lists-as-maildir.sup-talk}
        usual: true
        archived: false
        id: 3
        labels: [sup-talk]
      - !<tag:supmua.org,2006-10-01/Redwood/Maildir>
        uri: maildir://${misc-maildir}
        usual: true
        archived: false
        id: 4
        labels: []
      EOF

      export SUP_BASE=$(readlink -f $out)
      faketime -m "${now}" ruby ${sup}/bin/sup-sync
    '';
  };

  # For each scene in scenes.yaml, drive sup in ht (a headless terminal)
  # and capture the final screen state.
  screenshots-ansi = pkgs.stdenv.mkDerivation {
    name = "sup-screenshots-ansi";
    nativeBuildInputs = deps;
    env = {
      TZ = "UTC";
      USER = "nobody";
      LANG = "C.UTF-8";
    };
    buildCommand = ''
      faketime -m "${now}" ruby ${./shoot.rb} \
        --sup-base=${sup-base} \
        --sup=${sup}/bin/sup \
        --scenes-yaml=${./scenes.yaml} \
        --out=$out
    '';
  };

  # Render the ANSI screens in a headless Wayland terminal.
  iosevka = pkgs.iosevka-bin.override { variant = "SS09"; };
  fonts-conf = pkgs.writeText "sup-screenshots-fonts.conf" ''
    <?xml version="1.0"?>
    <!DOCTYPE fontconfig SYSTEM "urn:fontconfig:fonts.dtd">
    <fontconfig>
      <dir>${iosevka}/share/fonts</dir>
      <dir>${pkgs.dejavu_fonts.minimal}/share/fonts</dir>
      <cachedir prefix="xdg">fontconfig</cachedir>
      <config></config>
    </fontconfig>
  '';
  sway-conf = pkgs.writeText "sup-screenshots-sway.conf" ''
    output HEADLESS-1 mode 3840x2160 scale 2
    output HEADLESS-1 background #000000 solid_color
    default_border none
    default_floating_border none
    gaps inner 0
    gaps outer 0
    xwayland disable
  '';
  foot-conf = pkgs.writeText "sup-screenshots-foot.ini" ''
    [main]
    font=Iosevka Term:size=12
    [colors-dark]
    # https://github.com/tinted-theming/tinted-terminal/blob/main/themes/foot/base16-pop.ini
    foreground=d0d0d0
    background=000000
    regular0=000000 # black
    regular1=eb008a # red
    regular2=37b349 # green
    regular3=f8ca12 # yellow
    regular4=0e5a94 # blue
    regular5=b31e8d # magenta
    regular6=00aabb # cyan
    regular7=d0d0d0 # white
    bright0=505050 # bright black
    bright1=eb008a # bright red
    bright2=37b349 # bright green
    bright3=f8ca12 # bright yellow
    bright4=0e5a94 # bright blue
    bright5=b31e8d # bright magenta
    bright6=00aabb # bright cyan
    bright7=ffffff # bright white
    16=f29333
    17=7a2d00
    18=202020
    19=303030
    20=b0b0b0
    21=e0e0e0
  '';
  screenshots = pkgs.stdenv.mkDerivation {
    name = "sup-screenshots";
    nativeBuildInputs = with pkgs; [
      dbus
      foot
      ghostty
      grim
      jq
      sway
      procps
    ];
    env = {
      LANG = "C.UTF-8";
      FONTCONFIG_FILE = fonts-conf;
      WLR_BACKENDS = "headless";
      WLR_RENDERER = "pixman";
      LIBGL_ALWAYS_SOFTWARE = "1";
      WLR_LIBINPUT_NO_DEVICES = "1";
    };
    buildCommand = ''
      export HOME=$(mktemp -d)
      export XDG_RUNTIME_DIR=$HOME/run
      mkdir -p $XDG_RUNTIME_DIR
      export SWAYSOCK=$XDG_RUNTIME_DIR/sway.sock
      dbus-run-session --config-file ${pkgs.dbus}/share/dbus-1/session.conf sway -c ${sway-conf} &
      while ! test -S $SWAYSOCK ; do sleep 0.1 ; done
      export WAYLAND_DISPLAY=wayland-1

      mkdir -p $out
      for f in ${screenshots-ansi}/* ; do
        rm -f done
        foot -c ${foot-conf} -W 120x28 --hold sh -c "echo -ne '\e[H\e[?25l' ; cat $f ; touch done" &
        foot_pid=$!
        while ! test -f done ; do sleep 0.1 ; done
        geometry=$(swaymsg -t get_tree | jq -r 'recurse(.nodes[]?) | select(.app_id == "foot").geometry | "\(.x),\(.y) \(.width)x\(.height)"')
        grim -g "$geometry" $out/$(basename ''${f%.ansi}).png
        kill -TERM $foot_pid
        wait $foot_pid || :
      done
    '';
  };
in
screenshots

let
  pkgs = import (builtins.fetchGit {
    url = "https://github.com/NixOS/nixpkgs";
    ref = "refs/heads/master";
    rev = "402cc3633cc60dfc50378197305c984518b30773";
  }) {};
  gems = pkgs.bundlerEnv {
    name = "ruby2.7-gems-for-sup";
    ruby = pkgs.ruby_2_7;
    gemfile = ./Gemfile;
    lockfile = ./Gemfile.lock;
    gemset = ./gemset.nix;
    gemConfig = pkgs.defaultGemConfig // {
      ncursesw = attrs: (pkgs.defaultGemConfig.ncursesw attrs) // {
        dontBuild = false;
        patches = [
          (pkgs.fetchpatch {
            url = "https://github.com/sup-heliotrope/ncursesw-ruby/commit/1db8ae8d06ce906ddd8b3910782897084eb5cdcc.patch?full_index=1";
            hash = "sha256-1uGV1iTYitstzmmIvGlQC+3Pc7qf3XApawt1Kacu8XA=";
          })
          (pkgs.fetchpatch {
            url = "https://github.com/sup-heliotrope/ncursesw-ruby/commit/d0005dbe5ec0992cb2e38ba0f162a2d92554c169.patch?full_index=1";
            sha256 = "sha256-JNKXhXHEMGvNeDIFMCAYT+VTHQAfzJRAZxGqDREV300=";
          })
        ];
      };
    };
  };
in pkgs.mkShell { packages = [ gems gems.wrappedRuby pkgs.pandoc ]; }

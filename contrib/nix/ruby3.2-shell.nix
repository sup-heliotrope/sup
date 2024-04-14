let
  pkgs = import (builtins.fetchGit {
    url = "https://github.com/NixOS/nixpkgs";
    ref = "refs/heads/master";
    rev = "0e2ba0d131331e318eba20fcb03db0372dc2a926";
  }) {};
  gems = pkgs.bundlerEnv {
    name = "ruby3.2-gems-for-sup";
    ruby = pkgs.ruby_3_2;
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

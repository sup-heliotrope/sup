let
  pkgs = import (builtins.fetchGit {
    url = "https://github.com/danc86/nixpkgs";
    ref = "refs/heads/old-rubies-for-sup";
    rev = "a19c3284e36dd21c032f3495afdc6f8919b59497";
  }) {};
  gems = pkgs.bundlerEnv {
    name = "ruby2.4-gems-for-sup";
    ruby = pkgs.ruby_2_4.override { useRailsExpress = false; };
    gemfile = ./Gemfile;
    lockfile = ./ruby2.4-Gemfile.lock;
    gemset = ./ruby2.4-gemset.nix;
    gemConfig = pkgs.defaultGemConfig // {
      ncursesw = attrs: (pkgs.defaultGemConfig.ncursesw attrs) // {
        dontBuild = false;
        patches = [
          (pkgs.fetchpatch {
            url = "https://github.com/sup-heliotrope/ncursesw-ruby/commit/1db8ae8d06ce906ddd8b3910782897084eb5cdcc.patch?full_index=1";
            sha256 = "sha256-1uGV1iTYitstzmmIvGlQC+3Pc7qf3XApawt1Kacu8XA=";
          })
          (pkgs.fetchpatch {
            url = "https://github.com/sup-heliotrope/ncursesw-ruby/commit/d0005dbe5ec0992cb2e38ba0f162a2d92554c169.patch?full_index=1";
            sha256 = "sha256-JNKXhXHEMGvNeDIFMCAYT+VTHQAfzJRAZxGqDREV300=";
          })
        ];
      };
      # Workaround: remove rake from nativeBuildInputs, otherwise it causes
      # xapian-bindings to build against the default Ruby version
      # instead of our chosen version.
      xapian-ruby = attrs: pkgs.defaultGemConfig.xapian-ruby attrs // {
        dependencies = [ "rake" ];
        nativeBuildInputs = [ pkgs.pkg-config ];
      };
    };
  };
in pkgs.mkShell { nativeBuildInputs = [ gems gems.wrappedRuby pkgs.pandoc ]; }

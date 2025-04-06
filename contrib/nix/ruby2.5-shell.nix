let
  pkgs = import (builtins.fetchGit {
    url = "https://github.com/danc86/nixpkgs";
    ref = "refs/heads/old-rubies-for-sup";
    rev = "a19c3284e36dd21c032f3495afdc6f8919b59497";
  }) {};
  gems = pkgs.bundlerEnv {
    name = "ruby2.5-gems-for-sup";
    ruby = pkgs.ruby_2_5.override { useRailsExpress = false; };
    gemfile = ./Gemfile;
    lockfile = ./ruby2.5-Gemfile.lock;
    gemset = ./ruby2.5-gemset.nix;
    gemConfig = pkgs.defaultGemConfig // {
      fiddle = attrs: {
        buildInputs = [ pkgs.libffi ];
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

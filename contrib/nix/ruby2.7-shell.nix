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
      # Workaround for a new error in clang 16 (MacOS):
      # https://github.com/blackwinter/unicode/pull/11
      unicode = attrs: {
        buildFlags = [
          "--with-cflags=-Wno-incompatible-function-pointer-types"
        ];
      };
    };
  };
in pkgs.mkShell { packages = [ gems gems.wrappedRuby pkgs.pandoc ]; }

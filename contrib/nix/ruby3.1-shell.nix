let
  pkgs = import (builtins.fetchGit {
    url = "https://github.com/NixOS/nixpkgs";
    ref = "refs/heads/master";
    rev = "0e2ba0d131331e318eba20fcb03db0372dc2a926";
  }) {};
  gems = pkgs.bundlerEnv {
    name = "ruby3.1-gems-for-sup";
    ruby = pkgs.ruby_3_1;
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

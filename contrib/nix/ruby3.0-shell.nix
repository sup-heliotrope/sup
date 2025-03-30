let
  pkgs = import (builtins.fetchGit {
    url = "https://github.com/NixOS/nixpkgs";
    ref = "refs/heads/master";
    rev = "402cc3633cc60dfc50378197305c984518b30773";
  }) {};
  gems = pkgs.bundlerEnv {
    name = "ruby3.0-gems-for-sup";
    ruby = pkgs.ruby_3_0;
    gemfile = ./Gemfile;
    lockfile = ./ruby3.0-Gemfile.lock;
    gemset = ./ruby3.0-gemset.nix;
  };
in pkgs.mkShell { packages = [ gems gems.wrappedRuby pkgs.pandoc ]; }

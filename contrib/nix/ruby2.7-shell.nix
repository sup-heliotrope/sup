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
    lockfile = ./ruby2.7-Gemfile.lock;
    gemset = ./ruby2.7-gemset.nix;
  };
in pkgs.mkShell { packages = [ gems gems.wrappedRuby pkgs.pandoc ]; }

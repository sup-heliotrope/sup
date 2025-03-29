let
  pkgs = import (builtins.fetchGit {
    url = "https://github.com/NixOS/nixpkgs";
    ref = "refs/heads/master";
    rev = "5d0ebea1934d80948ff7b84f3b06e4ec9d99ee49";
  }) {};
  gems = pkgs.bundlerEnv {
    name = "ruby3.4-gems-for-sup";
    ruby = pkgs.ruby_3_4;
    gemfile = ./Gemfile;
    lockfile = ./Gemfile.lock;
    gemset = ./gemset.nix;
  };
in pkgs.mkShell { packages = [ gems gems.wrappedRuby pkgs.pandoc ]; }

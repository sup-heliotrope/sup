let
  pkgs = import (builtins.fetchGit {
    url = "https://github.com/NixOS/nixpkgs";
    ref = "refs/heads/master";
    rev = "f5ffd5787786dde3a8bf648c7a1b5f78c4e01abb";
  }) {};
  gems = pkgs.bundlerEnv {
    name = "ruby3.0-gems-for-sup";
    ruby = pkgs.ruby_3_0;
    gemfile = ./Gemfile;
    lockfile = ./Gemfile.lock;
    gemset = ./gemset.nix;
  };
in pkgs.mkShell { packages = [ gems gems.wrappedRuby pkgs.pandoc ]; }

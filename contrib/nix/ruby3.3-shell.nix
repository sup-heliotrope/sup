let
  pkgs = import (builtins.fetchGit {
    url = "https://github.com/NixOS/nixpkgs";
    ref = "refs/heads/master";
    rev = "0e2ba0d131331e318eba20fcb03db0372dc2a926";
  }) {};
  gems = pkgs.bundlerEnv {
    name = "ruby3.3-gems-for-sup";
    ruby = pkgs.ruby_3_3;
    gemfile = ./Gemfile;
    lockfile = ./Gemfile.lock;
    gemset = ./gemset.nix;
  };
in pkgs.mkShell { packages = [ gems gems.wrappedRuby pkgs.pandoc ]; }

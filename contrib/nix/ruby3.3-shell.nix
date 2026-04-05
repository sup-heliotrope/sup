let
  pkgs = import (builtins.fetchGit {
    url = "https://github.com/NixOS/nixpkgs";
    ref = "refs/heads/master";
    rev = "6de3b4b649253e8e0c7229edc3726d8a717b93fe";
  }) {};
  gems = pkgs.bundlerEnv {
    name = "ruby3.3-gems-for-sup";
    ruby = pkgs.ruby_3_3;
    gemfile = ./Gemfile;
    lockfile = ./Gemfile.lock;
    gemset = ./gemset.nix;
  };
in pkgs.mkShell { packages = [ gems gems.wrappedRuby pkgs.pandoc ]; }

let
  pkgs = import (builtins.fetchGit {
    url = "https://github.com/NixOS/nixpkgs";
    ref = "refs/heads/master";
    rev = "5d0ebea1934d80948ff7b84f3b06e4ec9d99ee49";
  }) {};
  gems = pkgs.bundlerEnv {
    name = "ruby3.3-gems-for-sup";
    ruby = pkgs.ruby_3_3;
    gemfile = ./Gemfile;
    lockfile = ./Gemfile.lock;
    gemset = ./gemset.nix;
    gemConfig = pkgs.defaultGemConfig // {
      # Workaround for Sup issue #623
      ncursesw = attrs: pkgs.defaultGemConfig.ncursesw attrs // {
        src = pkgs.fetchFromGitHub {
          owner = "danc86";
          repo = "ncursesw-ruby";
          rev = "43cfa21f781e9412dc73d0d4a44b3ec0bf4a3c8d";
          hash = "sha256-MkXFwhbtL9aJOMqn1IR5DKMXcnKHzICjb/rVhDDLL94=";
        };
      };
    };
  };
in pkgs.mkShell { packages = [ gems gems.wrappedRuby pkgs.pandoc ]; }

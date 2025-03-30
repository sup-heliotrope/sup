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
    gemConfig = pkgs.defaultGemConfig // {
      # Temporarily pull from my fork: https://github.com/Garaio-REM/xapian-ruby/pull/11
      xapian-ruby = attrs: pkgs.defaultGemConfig.xapian-ruby attrs // {
        version = "1.4.27";
        src = pkgs.fetchurl {
          url = "https://github.com/danc86/xapian-ruby/releases/download/v1.4.27/xapian-ruby-1.4.27.gem";
          sha256 = "sha256-E5U/4NEFkChMJtrMj8oCqKPgTYyKku5OXGcPQvhN4xM=";
        };
      };
    };
  };
in pkgs.mkShell { packages = [ gems gems.wrappedRuby pkgs.pandoc ]; }

let
  pkgs = import (builtins.fetchGit {
    url = "https://github.com/NixOS/nixpkgs";
    ref = "refs/heads/master";
    rev = "3ef1d2a9602c18f8742e1fb63d5ae9867092e3d6";
  }) {};
  gems = pkgs.bundlerEnv {
    name = "ruby2.6-gems-for-sup";
    ruby = pkgs.ruby_2_6;
    gemfile = ./Gemfile;
    lockfile = ./ruby2.6-Gemfile.lock;
    gemset = ./ruby2.6-gemset.nix;
    gemConfig = pkgs.defaultGemConfig // {
      fiddle = attrs: {
        buildInputs = [ pkgs.libffi ];
      };
      # Workaround for a new error in clang 16 (MacOS):
      # https://github.com/blackwinter/unicode/pull/11
      unicode = attrs: {
        buildFlags = [
          "--with-cflags=-Wno-incompatible-function-pointer-types"
        ];
      };
      # Workaround: remove rake from nativeBuildInputs, otherwise it causes
      # xapian-bindings to build against the default Ruby version
      # instead of our chosen version.
      xapian-ruby = attrs: pkgs.defaultGemConfig.xapian-ruby attrs // {
        dependencies = [ "rake" ];
        nativeBuildInputs = [ pkgs.pkg-config ];
      };
    };
  };
in pkgs.mkShell { packages = [ gems gems.wrappedRuby pkgs.pandoc ]; }

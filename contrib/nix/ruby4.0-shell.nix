let
  pkgs = import (builtins.fetchGit {
    url = "https://github.com/NixOS/nixpkgs";
    ref = "refs/heads/master";
    rev = "6de3b4b649253e8e0c7229edc3726d8a717b93fe";
  }) { };
  gems = pkgs.bundlerEnv {
    name = "ruby4.0-gems-for-sup";
    ruby = pkgs.ruby_4_0;
    gemfile = ./Gemfile;
    lockfile = ./Gemfile.lock;
    gemset = ./gemset.nix;
    gemConfig = pkgs.defaultGemConfig // {
      rmail = attrs: {
        dontBuild = false;
        patches = [
          # Frozen string literals: https://github.com/terceiro/rmail/pull/13
          (pkgs.fetchpatch2 {
            name = "rmail-frozen-string-literals.patch";
            url = "https://github.com/terceiro/rmail/pull/13/commits/27f455af1fea0be0aa09959cc2237cbdf68de2a1.patch";
            hash = "sha256-N5X9zix+WPoEugp2DBTu7dRDmesrF5pT/8Td2wraYoA=";
          })
        ];
      };
      xapian-ruby =
        attrs:
        pkgs.defaultGemConfig.xapian-ruby attrs
        // {
          env.LANG = "C.UTF-8";
        };
    };
  };
in
pkgs.mkShell {
  packages = [
    gems
    gems.wrappedRuby
    pkgs.pandoc
  ];
}

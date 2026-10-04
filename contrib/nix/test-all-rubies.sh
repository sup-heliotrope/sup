#!/usr/bin/env bash
set -e
cd "$(dirname "$0")/../.."
for rubyversion in 2.4 2.5 2.6 2.7 3.0 3.1 3.2 3.3 3.4 4.0 ; do
    nix-build contrib/nix/ruby$rubyversion-shell.nix -A inputDerivation -o contrib/nix/.ruby$rubyversion-shell-inputs
    nix-shell contrib/nix/ruby$rubyversion-shell.nix --run 'rake ci'
done

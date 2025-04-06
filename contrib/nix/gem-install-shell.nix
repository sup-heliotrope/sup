{ pkgs ? import <nixpkgs> {} }:
pkgs.mkShell {
  packages = with pkgs; [
    ncurses
    ncurses.dev
    libffi
    libffi.dev
    libuuid
    libuuid.dev
    ruby_3_2
    zlib
    zlib.dev
  ];
}

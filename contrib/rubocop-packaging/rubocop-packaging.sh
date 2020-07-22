#!/bin/sh

set -euf

if [ ! -f .rubocop.yml ]; then
    echo ".rubocop.yml not found in current working directory: `pwd`" >&2
    echo "To run, first 'cd' to the directory that contains this script" >&2
    exit 1
fi

rm -f Gemfile.lock

echo "[rubocop-packaging] Running 'bundle install'..."
bundle install --path=.bundle

echo "[rubocop-packaging] Running RuboCop Packaging checks"
bundle exec rubocop --only Packaging ../..

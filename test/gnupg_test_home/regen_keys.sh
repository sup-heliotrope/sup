#!/bin/bash
#
# re-generate test keys for the sup test base
#
# https://github.com/sup-heliotrope/sup/wiki/Development%3A-Crypto
# 
# Requires GPG 2.1+ installed as "gpg2"
# 
# GPG 2.1+ by default uses pubring.kbx - but this isn't backwards compatible
# with GPG 1 or GPG 2.0.
# Workaround:
#   - Create empty pubring.gpg file, which causes GPG 2.1+ to use this
#     backwards-compatible store.
#   - Manually export private key copy to secring.gpg, which would be used
#     by GPG 1.

set -e -u -o pipefail

pushd $(dirname $0)

echo "Generating keys in: $(pwd)..."

echo "Checking gpg2 version"
gpg2 --version | head -1

echo "Deleting all existing test keys"
rm -f \
    *.gpg \
    *.asc \
    private-keys-v1.d/*.key \
    .gpg-v21-migrated

echo "Generating key pair for test receiver (email sup-test-2@foo.bar.asc)"
touch pubring.gpg  # So GPG 2.1+ writes to pubring.gpg instead of pubring.kbx
gpg2 \
    --homedir . \
    --batch \
    --pinentry-mode loopback \
    --passphrase '' \
    --quick-generate-key sup-test-2@foo.bar rsa encrypt,sign 0

echo "Exporting public key only for test receiver (file sup-test-2@foo.bar.asc)"
gpg2 \
    --homedir . \
    --armor \
    --output sup-test-2@foo.bar.asc \
    --export sup-test-2@foo.bar

echo "Backing up secret key for test receiver (file receiver_secring.gpg)"
gpg2 \
    --homedir . \
    --export-secret-keys \
    >receiver_secring.gpg

echo "Backing up pubring.gpg for test receiver (file receiver_pubring.gpg)"
cp -a pubring.gpg receiver_pubring.gpg

echo "Clearing key store, so we can start from a blank slate for next key(s)"
rm -f pubring.gpg trustdb.gpg private-keys-v1.d/*.key .gpg-v21-migrated

echo "Generating key pair for sender (email sup-test-1@foo.bar)"
touch pubring.gpg  # So GPG 2.1+ writes to pubring.gpg instead of pubring.kbx
gpg2 \
    --homedir . \
    --batch \
    --pinentry-mode loopback \
    --passphrase '' \
    --quick-generate-key sup-test-1@foo.bar rsa encrypt,sign 0

echo "Importing public key for receiver, into sender's key store"
gpg2 \
    --homedir . \
    --import sup-test-2@foo.bar.asc

echo "Copy private key also to secring.gpg (old format used by GPG 1)"
gpg2 \
    --homedir . \
    --export-secret-keys \
    >secring.gpg

echo "Done."

echo "We now have two non-expiring public keys (receiver & sender):"
gpg2 --homedir . --list-keys

echo "And we also have only *one* corresponding private key (sender only):"
gpg2 --homedir . --list-secret-keys

popd

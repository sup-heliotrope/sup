#! /bin/bash
#
# re-generate test keys for the sup test base
#
# https://github.com/sup-heliotrope/sup/wiki/Development%3A-Crypto

pushd $(dirname $0)

export GNUPGHOME="$(pwd)"

echo "genrating keys in: $GNUPGHOME.."

rm *.gpg *.asc

echo "generate receiver key.."
gpg --batch --gen-key key2.gen

echo "export receiver key.."

gpg --output sup-test-2@foo.bar.asc --armor --export sup-test-2@foo.bar

mv trustdb.gpg receiver_trustdb.gpg
mv secring.gpg receiver_secring.gpg
mv pubring.gpg receiver_pubring.gpg

echo "generate sender key.."
gpg --batch --gen-key key1.gen

echo "generate ecc key.."
gpg --batch --gen-key key_ecc.gen

echo "import receiver key.."
gpg --import sup-test-2@foo.bar.asc



popd


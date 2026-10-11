# Test-only signing key

`mafateeh-test.keystore` (alias `mafateeh-test`, password `mafateeh-test-only`) signs the
**development/test** APKs built by GitHub Actions when no private signing secrets are configured.

- It is public on purpose, like Android's `debug.keystore`, so successive test builds can be
  installed over each other on a headset without losing local progress.
- It must **never** be used for a store submission or any distribution that needs a trusted identity.
- For a real release, add repository secrets `MAFATEEH_KEYSTORE_B64`, `MAFATEEH_KEYSTORE_ALIAS` and
  `MAFATEEH_KEYSTORE_PASSWORD` (see `docs/quest-native-build.md`); the build then uses that key and
  this file is ignored. Never commit a production key or its password.

# Security Policy

## Supported code

Security fixes target the latest code on `main` and, when practical, the most
recent App Store or TestFlight build. Older builds are not maintained separately.

## Report a vulnerability privately

Do not open a public issue for a vulnerability or include exploit details,
credentials, personal data, or precise location information in a public post.

Use GitHub's **Report a vulnerability** button on the repository's Security tab:

<https://github.com/rupayon123/gta-free-stem-ios/security/advisories/new>

If GitHub does not show that private form, use the
[public support page](https://gta-free-stem.vercel.app/support/) only to request
a private contact method. Do not include vulnerability details in that public
request.

Please include, when safe:

- the affected app version, Apple platform, OS version, and device type
- a concise description and impact
- reproducible steps or a minimal proof of concept
- whether credentials, local app data, or another person's information may be
  exposed
- any suggested mitigation

The maintainer will acknowledge and assess reports as capacity permits, avoid
unnecessary disclosure, and coordinate publication after a fix when possible.

## Security-sensitive project rules

- Never commit certificates, provisioning profiles, `.ipa` files, private keys,
  API tokens, OAuth secrets, backend credentials, or real user data.
- Keep browsing account-free and keep location access optional and limited to
  while-use permission.
- Do not persist bearer tokens in `UserDefaults`.
- Require HTTPS for production network traffic and validate externally supplied
  opportunity data.
- Keep App Store privacy details accurate before external testing or release.

Incorrect public opportunity information is a content issue rather than a
software vulnerability. Report it in the
[opportunity-data repository](https://github.com/rupayon123/gta-free-stem-opportunities/issues/new/choose)
without including private information.

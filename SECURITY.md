# Security Policy

## Supported Branch

Security fixes are accepted against `main`.

## Reporting A Vulnerability

Please do not open a public issue for account, authentication, credential, or data-access vulnerabilities. Use a private GitHub security advisory where available, or contact the maintainer directly.

Include:

- a short summary of the issue
- steps to reproduce
- affected app screens, files, or API routes
- whether any real user data, tokens, or credentials may be exposed

## App Safety Defaults

- Do not commit certificates, provisioning profiles, `.ipa` files, private keys, API tokens, OAuth secrets, or backend admin credentials.
- Keep browsing account-free.
- Keep location access optional and limited to while-using permission.
- Do not persist bearer tokens in `UserDefaults`.
- Require HTTPS for production API traffic.
- Keep App Store privacy details accurate before TestFlight external testing.
- Keep account deletion, privacy policy, support URL, and terms ready before a public App Store release.

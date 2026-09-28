# Security policy

## Supported versions

| Version | Supported |
|---|---|
| 1.0.x | Yes |
| < 1.0 | No |

Hangly is a single-developer project. There is one supported version at a time:
the latest release.

## Reporting a vulnerability

**Please do not open a public issue for a security problem.**

Report it privately through GitHub's
[security advisories](../../security/advisories/new), which lets us discuss and
fix the problem before any detail becomes public.

Please include:

- What the problem is, and what an attacker could do with it
- The version of Hangly and of macOS
- Steps to reproduce, or a proof of concept if you have one
- Anything you think the fix should take into account

## What to expect

- **Acknowledgement within 72 hours.** If you have not heard back in that time,
  assume the notification was missed and open a public issue saying only that you
  are waiting on a security response — no detail.
- **An assessment within a week**, including whether it is accepted, what severity
  it is judged at, and a rough timeline.
- **Credit in the advisory and the changelog**, unless you would rather not be
  named.

This is a spare-time project, so please be realistic about response times outside
those windows. Serious issues will always be prioritised over features.

## Scope

Hangly runs entirely on your Mac. It makes no network calls, has no server, no
accounts and no telemetry, so the usual categories of web vulnerability do not
apply.

What is in scope:

- Anything that lets code or data from outside the app gain execution — the
  most likely surface is image import, which parses untrusted files with
  ImageIO and Vision
- Anything that reads or writes outside the app's own settings and its
  Application Support folder
- Privilege issues around the login item registration
- A way to make the app disclose something about the user's system

What is out of scope:

- The app ships unsandboxed, by design, because a sandboxed app cannot register
  itself as a login item from an arbitrary location. That is a documented
  trade-off, not a vulnerability.
- Releases before 1.0 are not signed with an Apple Developer ID. The resulting
  Gatekeeper warning is expected and documented.
- Anything requiring an attacker to already have code execution on the machine.

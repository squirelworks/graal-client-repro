# Windows SmartScreen and code signing

## Windows says "Windows protected your PC"

The Windows exes are not code-signed yet, so the first time you start one
that came from a download, Microsoft Defender SmartScreen shows a blue
**"Windows protected your PC"** box with *Publisher: Unknown publisher*.
That is a reputation check, not a virus finding: SmartScreen stops any
downloaded program that is unsigned and that it has not seen many people
run. Any of these gets past it:

- **Run it once anyway.** Click **More info**, then **Run anyway**.
  Windows remembers that exe and does not ask again.
- **Unblock the zip before extracting it.** A browser marks every
  download as "from the internet" (the Mark of the Web), and Explorer
  copies that mark onto every file it extracts. Right-click the zip,
  **Properties**, tick **Unblock** at the bottom, **OK**, then extract.
  Nothing in the folder is asked about again.
- **Unblock a folder you already extracted**, in PowerShell:

  ```powershell
  Get-ChildItem -Recurse .\graal-2.22-GNW03014-v0.0.1-windows | Unblock-File
  ```

If Defender itself reports a threat (a red box, or the file vanishes)
that is a different thing: please open an issue with the name it gives.

## What the builds already do about it

Every Windows client carries a version block (product `graal-delphi`,
company `squirelworks`, the release version, a description naming the
build) and an application manifest (`common/win/graal-delphi.manifest`:
runs as the user, never asks for admin, declares Windows 7 to 11). They
set the DEP and ASLR flags, are not packed or compressed, and the zips
hold only the client, no test programs. That makes them look like an
ordinary program to SmartScreen and to antivirus heuristics, but it does
not remove the "Unknown publisher" box. Only a code signature does.

A new build folder gets its `src/<Program>.rc` and the `{$R}` line from
`python3 scripts/win/make_winres.py`; CI fails until it has them.

## Signing (what it would take)

SmartScreen only trusts a publisher, and a publisher is a code-signing
certificate from a certificate authority Windows trusts. A self-signed
certificate does nothing for anyone else's PC. The options:

- **Azure Trusted Signing** (Microsoft's own signing service, about
  US$10 a month). Individual developers can sign up (when last checked,
  only in the US and Canada) if they can pass
  Microsoft's identity check; it needs an Azure subscription, a Trusted
  Signing account, an identity validation, and a certificate profile.
  The release workflow would then sign each exe with Microsoft's
  `trusted-signing-action` before packing, using three repository
  secrets for an Azure app registration. Signed files build SmartScreen
  reputation quickly, often from the first release.
- **A standard (OV) code-signing certificate** from a CA such as
  Sectigo, DigiCert or SSL.com, roughly US$200 to 500 a year. Since 2023
  the key must live on a hardware token or in the CA's cloud signing
  service, so CI signs through the CA's cloud tool. OV certificates
  still start with no reputation: the box keeps showing until enough
  people have run the signed files.
- **SignPath Foundation** signs open-source projects for free, but the
  repository needs an OSI licence first (it has one now: Apache-2.0, see
  the licence section of the [README](../README.md#licence)).

Whichever is chosen, the signing step goes in `.github/workflows/release.yml`
on the Windows job, between "Build and test" and "Pack".

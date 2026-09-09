# License & Open Source Status

## Is the IRX License 1.0 open source?

Yes, in the commonly understood sense of the term. The license grants
everyone the right to use, copy, modify, merge, publish, distribute,
sublicense, and sell the software. The source code is freely available,
freely modifiable, and freely redistributable.

## Is it OSI-approved?

No. The Open Source Initiative (OSI) maintains the formal Open Source
Definition — a 10-point checklist that a license must satisfy to carry
the OSI "certified open source" designation. The IRX License has not been
submitted to the OSI for review, and conditions 2 and 3 (preservation of
authorship and mandatory modification notices) may not align with every
element of the OSI definition.

This is a legal formality. It has no bearing on your practical freedoms
to use, modify, or share the software.

## Does OSI approval matter for this project?

Generally, no. OSI approval is relevant for:

- Inclusion in Linux distribution repositories that require
  OSI-approved licenses

- Corporate legal departments that mandate OSI compliance

- Formal procurement processes

ArtixForge is a modular deployment framework — it includes an installer
TUI, system migration tools, an ISO builder, a source-based build system
(anvil/Power User Mode), and ARM cross-compilation support. The project is
distributed as a toolkit for advanced Artix Linux deployment. The license
protects what the author cares about — integrity, respect, and explicit
attribution — while preserving all the freedoms users expect from open
source software.

## Why the name "IRX"?

IRX stands for **Integrity, Respect, eXplicit attribution**. These are the
principles the license exists to protect. The code is free. The credit is
not. The license makes that distinction legally precise.

## Does the IRX License discriminate against fields of endeavor?

No. The license does not restrict how the software is used, who may use
it, or for what purpose. It solely requires that attribution be preserved,
that modifications be clearly marked, and that modified versions not be
presented as the original. This is an attribution and integrity
requirement, not a field-of-use restriction. The software may be used
commercially, academically, militarily, or for any other purpose without
limitation.

## Does the patent grant change anything for users?

Yes, in a good way. Section 5 of the IRX License includes a patent grant.
Contributors grant users a patent license covering their contributions.
If a user initiates patent litigation against the project, that user's
patent license terminates. This protects users from patent claims by
contributors while preventing bad-faith litigation.

## What happens if someone violates the license?

Section 7 provides a 30-day cure period. If the violation is cured within
that period, rights are automatically reinstated. Termination applies only
to the party in violation. Licenses granted to third parties who received
copies before termination survive, provided those third parties are not
themselves in violation.

## Is ArtixForge a fork of Artix Linux?

No. ArtixForge is an independent installer for Artix Linux. It does not
repackage, relicense, or redistribute Artix Linux. The installed system
is standard Artix Linux, fully compatible with all official repositories
and packages.

## Is Power User Mode a separate distribution?

No. Power User Mode builds select packages from source during installation.
The base system is installed from Artix repositories using `basestrap`. The
package manager is `pacman`. The installed system identifies as Artix Linux.
Power User Mode is a build overlay, not a distribution.

## Does the IRX License apply to systems installed by ArtixForge?

No. ArtixForge is a deployment tool. The systems it installs are standard
Artix Linux systems, governed by the licenses of the software installed on
them. The IRX License applies only to ArtixForge itself, not to the output
it produces.

## What if the Artix Linux project objects to this project?

ArtixForge exists to serve the Artix community. It drives adoption, eases
installation, and respects the Artix ecosystem. If Artix maintainers ever
express concerns about branding, attribution, or scope, the project will
engage in good faith to address them.

## Why not use an existing OSI-approved license?

The MIT license grants all the freedoms the author wanted — use, copy,
modify, distribute, even sell. The IRX License adds exactly what matters:

- **Integrity**: Modified versions must be clearly marked as modified.
- **Respect**: The original author's name and project branding cannot be
  used to promote derived works without permission.
- **eXplicit attribution**: The original authorship must be preserved and
  cannot be misrepresented.

These conditions matter to the author. They prevent "embrace, rename,
extinguish" tactics and ensure that if someone improves ArtixForge, the
original authorship is never erased.

There is no plan to seek OSI approval. The license is stable, clear, and
grants all essential freedoms.

## Could the license prevent inclusion in a distribution?

Possibly — but mostly in theory. Some distributions (Debian, Fedora,
openSUSE) require OSI-approved licenses for their main repositories. The
IRX License has not been submitted for OSI review, so ArtixForge would not
qualify for inclusion in those repositories.

In practice, this rarely matters because:

- **Custom repositories**: ArtixForge can be distributed via any custom
  pacman repo without OSI approval.

- **ISO bundling**: The project generates ISOs. Those ISOs can include
  ArtixForge regardless of distribution policies.

- **Container / script distribution**: Users clone and run directly from
  GitHub. No package repository involvement is required.

If a distribution wants to package ArtixForge but hits license policy
issues, the author is open to discussing relicensing specific components
under an OSI-approved dual license. The core framework (the install
script, anvil, migrations) will remain under the IRX License.
# License & Open Source Status

## Is the CLEAR License v1 open source?

Yes, in the commonly understood sense of the term. The license grants
everyone the right to use, copy, modify, merge, publish, distribute,
sublicense, and sell the software. The source code is freely available,
freely modifiable, and freely redistributable.

## Is it OSI-approved?

No. The Open Source Initiative (OSI) maintains the formal Open Source
Definition — a 10-point checklist that a license must satisfy to carry
the OSI "certified open source" designation. The CLEAR License has not
been submitted to the OSI for review, and some of its conditions
(preservation of authorship, mandatory modification notices, and the
restriction on combining with Copyleft-licensed material) may not align
with every element of the OSI definition.

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
(anvil/Power User Mode), and ARM cross-compilation support. The project
is distributed as a toolkit for advanced Artix Linux deployment. The
license protects what the author cares about — attribution, integrity,
and clarity about what has been modified — while preserving all the
freedoms users expect from open source software.

## Does the CLEAR License discriminate against fields of endeavor?

No. The license does not restrict how the software is used, who may use
it, or for what purpose. It requires that attribution be preserved, that
modifications be clearly marked, and that modified versions not be
presented as the original. This is an attribution and integrity
requirement, not a field-of-use restriction. The software may be used
commercially, academically, militarily, or for any other purpose without
limitation.

## Does the patent grant change anything for users?

Yes, in a good way. Section 5 of the CLEAR License includes a patent
grant. The Copyright Holder and each Contributor grant users a patent
license covering the Software and their Contributions. If a user
initiates patent litigation against any entity alleging that the Software
or a Contribution constitutes patent infringement, that user's patent
license terminates. This protects users from patent claims by contributors
while preventing bad-faith litigation.

## What happens if someone violates the license?

Section 7 provides a 30-day cure period. If the violation is cured within
that period, rights continue in full force. Termination applies only to
the party in violation. Third parties who received the Software from the
violating party prior to termination are deemed to have accepted a direct
license from the Copyright Holder on the same terms, provided they are
not themselves in violation.

## What is the "No Copyleft Combination" clause?

Section 11 prohibits distributing a Combined Work — a single work that
incorporates CLEAR-licensed code and material from a GPL, LGPL, or AGPL
work in a manner that copyright law would treat as a combined or
derivative work. This is why the license is not compatible with copyleft
licenses.

The clause does **not** prohibit:

- Distributing CLEAR-licensed software alongside GPL-licensed software as
  separate, independent programs on the same medium (mere aggregation)
- Calling the `tui` binary from a bash script, regardless of the script's
  license
- Producing Independent Works — programs that use the Software's output
  but do not incorporate its source code — as long as Section 9 is
  invoked by the Copyright Holder

For ArtixForge itself, this clause has no practical effect: the project
is bash scripts that invoke other tools as subprocesses. Subprocess
invocation is aggregation, not combination.

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

## Does the CLEAR License apply to systems installed by ArtixForge?

No. ArtixForge is a deployment tool. The systems it installs are standard
Artix Linux systems, governed by the licenses of the software installed on
them. The CLEAR License applies only to ArtixForge itself, not to the
output it produces.

## What if the Artix Linux project objects to this project?

ArtixForge exists to serve the Artix community. It drives adoption, eases
installation, and respects the Artix ecosystem. If Artix maintainers ever
express concerns about branding, attribution, or scope, the project will
engage in good faith to address them.

## Why not use an existing OSI-approved license?

The MIT license grants all the freedoms the author wanted — use, copy,
modify, distribute, even sell. The CLEAR License adds exactly what
matters:

- **Attribution**: The original authorship must be preserved and cannot
  be misrepresented.
- **Integrity**: Modified versions must be clearly marked as modified.
- **Respect**: The original author's name and project branding cannot be
  used to promote derived works without permission.
- **Clarity**: The license states its terms plainly, including the limits
  of what is permitted.

These conditions matter to the author. They prevent "embrace, rename,
extinguish" tactics and ensure that if someone improves ArtixForge, the
original authorship is never erased.

There is no plan to seek OSI approval. The license is stable, clear, and
grants all essential freedoms.

## Could the license prevent inclusion in a distribution?

Possibly — but mostly in theory. Some distributions (Debian, Fedora,
openSUSE) require OSI-approved licenses for their main repositories. The
CLEAR License has not been submitted for OSI review, so ArtixForge would
not qualify for inclusion in those repositories.

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
script, anvil, migrations) will remain under the CLEAR License.

## What changed from IRX License 1.0 to CLEAR License v1?

Three substantive changes:

- **Section 11 (No Copyleft Combination)**: A new restriction prohibiting
  distribution of Combined Works — works that combine the licensed code
  with GPL/LGPL/AGPL code in a way that forms a single derivative work.
  Aggregation of separate programs is unaffected.

- **Definition of "Material Modification"**: The definition now
  distinguishes source-code changes from configuration changes. Changing
  a config file or a build flag is not a Material Modification. Rewriting
  or substantially modifying the source is.

- **Stronger definitions**: The license now includes formal definitions
  for "Distribute Publicly", "Copyleft License", "Combined Work", and
  "Independent Work". These are used in the operative clauses and
  eliminate ambiguity about what they mean in context.

Section 9 (Optional Independent Work Clause) is retained, with expanded
wording about how it is activated.

Prior releases of ArtixForge were distributed under the IRX License 1.0.
The license change is not retroactive: v9.5.1.1 and earlier remain under
IRX. v9.5.1.2 and later are under CLEAR.
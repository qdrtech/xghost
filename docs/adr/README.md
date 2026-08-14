# Architecture decision records

This directory holds the architecture decision records (ADRs) for xghost. An
ADR records one decision, the context that forced it, the options considered,
and the consequences the project accepts.

Read the ADRs to learn why the project is built the way it is. Read the code to
learn how.

## Index

| ADR                                                | Title                              | Status   |
| -------------------------------------------------- | ---------------------------------- | -------- |
| [0001](0001-prescribed-config-architecture.md)     | Prescribed config architecture     | accepted |
| [0002](0002-the-bridge-to-the-generated-output.md) | The bridge to the generated output | accepted |

## Format

xghost uses a reduced form of [MADR](https://adr.github.io/madr/) (Markdown Any
Decision Record). The section table below is authoritative. Where the upstream
MADR template differs, this file wins. This spec drops the YAML front matter,
uses sentence case headings rather than title case, and has no "Pros and Cons
of the Options" section.

MADR is chosen over the Nygard format because it gives the considered options a
section of their own. Several xghost decisions exist only in relation to the
option they reject, so a reader needs the rejected options on the page. The
Nygard format records the decision and its consequences without that
comparison. This spec also requires the decision drivers, so the forces behind
a decision stay on the page.

Copy `template.md` to start a new ADR. The template fixes the section order,
the heading depth, and the form of the status and date.

An ADR contains the sections below. A section marked `Required = Yes` is always
present. A section marked `Required = No` is optional. Leave an optional
section out when it has nothing to record.

| Section                       | Required | Content                                                   |
| ----------------------------- | -------- | --------------------------------------------------------- |
| Title                         | Yes      | `# NNNN. Short decision statement or topic`               |
| Status and date               | Yes      | The current status and the date of the last status change |
| Context and problem statement | Yes      | The situation and the question the ADR answers            |
| Decision drivers              | Yes      | The forces that constrain the answer                      |
| Considered options            | Yes      | Every option that was genuinely on the table              |
| Decision outcome              | Yes      | The chosen option and the reason it was chosen            |
| Consequences                  | Yes      | What becomes easier and what becomes harder               |
| Confirmation                  | No       | How the project checks that the decision is upheld        |
| More information              | No       | Evidence, references, related ADRs                        |

The markup rules are fixed:

- The title is a level 1 heading. A section is a level 2 heading. A subsection
  inside a section is a level 3 heading.
- The status and the date are two bullets under the title, in that order:
  `- Status: accepted` and `- Date: 2026-08-12`.
- The date is written as `YYYY-MM-DD`.

## Numbering

ADRs are numbered sequentially from `0001`. The number is four digits, zero
padded. A number is assigned when the ADR is written and is never reused and
never renumbered. Gaps are permitted; a rejected ADR keeps its number.

## Filenames

`NNNN-short-title-in-kebab-case.md`

The slug is lower case, uses hyphens between words, and matches the title of
the ADR. Example: `0001-prescribed-config-architecture.md`.

## Status values

| Status               | Meaning                                                     |
| -------------------- | ----------------------------------------------------------- |
| `proposed`           | Written and open for discussion. Not yet in force.          |
| `accepted`           | In force. The code is expected to follow it.                |
| `rejected`           | Considered and declined. Kept so the reasoning is not lost. |
| `deprecated`         | No longer relevant. No replacement.                         |
| `superseded by NNNN` | Replaced by a later ADR.                                    |

## Rules

- One decision per ADR. Split a decision that needs two titles.
- Do not edit the decision of an accepted ADR. Write a new ADR and set the old
  one to `superseded by NNNN`.
- Corrections to wording, links, and typos in an accepted ADR are permitted.
- Record the option that was rejected, and the reason. An ADR that lists one
  option records a fact rather than a decision.
- Add the new ADR to the index above.

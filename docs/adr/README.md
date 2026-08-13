# Architecture decision records

This directory holds the architecture decision records (ADRs) for xghost. An
ADR records one decision, the context that forced it, the options considered,
and the consequences the project accepts.

Read the ADRs to learn why the project is built the way it is. Read the code to
learn how.

## Format

xghost uses [MADR](https://adr.github.io/madr/) (Markdown Any Decision Record).

MADR is chosen over the Nygard format because it names the considered options
and the decision drivers as separate, required sections. Several xghost
decisions exist only in relation to the option they reject, so a reader needs
the rejected options on the page. The Nygard format records the decision and
its consequences without that comparison.

Each ADR contains these sections:

| Section                       | Required | Content                                                     |
| ----------------------------- | -------- | ----------------------------------------------------------- |
| Title                         | Yes      | `# NNNN. Short decision statement`                          |
| Status, date                   | Yes      | The current status and the date of the last status change    |
| Context and problem statement | Yes      | The situation and the question the ADR answers               |
| Decision drivers              | No       | The forces that constrain the answer                         |
| Considered options            | Yes      | Every option that was genuinely on the table                 |
| Decision outcome              | Yes      | The chosen option and the reason it was chosen               |
| Consequences                  | Yes      | What becomes easier and what becomes harder                  |
| Confirmation                  | No       | How the project checks that the decision is upheld           |
| More information              | No       | Evidence, references, related ADRs                           |

## Numbering

ADRs are numbered sequentially from `0001`. The number is four digits, zero
padded. A number is assigned when the ADR is written and is never reused and
never renumbered. Gaps are permitted; a rejected ADR keeps its number.

## Filenames

`NNNN-short-title-in-kebab-case.md`

The slug is lower case, uses hyphens between words, and matches the title of
the ADR. Example: `0001-prescribed-config-architecture.md`.

## Status values

| Status            | Meaning                                                       |
| ----------------- | ------------------------------------------------------------- |
| `proposed`        | Written and open for discussion. Not yet in force.            |
| `accepted`        | In force. The code is expected to follow it.                  |
| `rejected`        | Considered and declined. Kept so the reasoning is not lost.   |
| `deprecated`      | No longer relevant. No replacement.                           |
| `superseded by NNNN` | Replaced by a later ADR.                                   |

## Rules

- One decision per ADR. Split a decision that needs two titles.
- Do not edit the decision of an accepted ADR. Write a new ADR and set the old
  one to `superseded by NNNN`.
- Corrections to wording, links, and typos in an accepted ADR are permitted.
- Record the option that was rejected, and the reason. An ADR that lists one
  option records a fact rather than a decision.

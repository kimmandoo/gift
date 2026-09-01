# Rules

Commit per each query session.
Commit messages must follow `type(scope): subject`, for example `feat(trading): harden futures runtime`.
When strategy code, strategy defaults, or strategy selection behavior changes, run the relevant backtest before completion and report the result.

# Changelog

When a feature is added, a bug is fixed, or any breaking change is introduced, upsert to the CHANGELOG.md file.
The changelog should be written in the past tense and follow the same format as the commit messages.
Group changelog entries under reverse-chronological `## YYYY-MM-DD` headings using the date of the change.
Add new entries under the current date heading, creating it when needed.

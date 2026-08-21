# A fixture migration with no metadata block. The runner refuses it, because a
# migration that has not said what it does cannot be reported when it fails and
# cannot be read against the policy of ADR 0001.

printf '0001\n' >>"$MIGRATION_LOG"

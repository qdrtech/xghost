# A fixture migration. It is not a migration of this project: it lives under
# tests/ because a fixture that shipped in migrations/ would be a migration
# every user runs.
#
# It records every invocation in MIGRATION_LOG, so a test counts how many times
# it ran, and it makes its side effect exactly once however often it runs, which
# is what "safe to run twice" means.
#
# @xghost-migration
# summary: Record the package the bar needs.
# effect: install-package
# @end-xghost-migration

printf '0001\n' >>"$MIGRATION_LOG"

if ! grep -qxF 'the-bar-package' "$MIGRATION_PACKAGES" 2>/dev/null; then
	printf 'the-bar-package\n' >>"$MIGRATION_PACKAGES"
fi

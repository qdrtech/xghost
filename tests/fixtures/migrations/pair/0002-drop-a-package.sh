# A fixture migration. See 0001-record-a-package.sh.
#
# @xghost-migration
# summary: Drop the package nothing reads any more.
# effect: drop-package
# @end-xghost-migration

printf '0002\n' >>"$MIGRATION_LOG"

if grep -qxF 'the-old-package' "$MIGRATION_PACKAGES" 2>/dev/null; then
	grep -vxF 'the-old-package' "$MIGRATION_PACKAGES" >"$MIGRATION_PACKAGES.new" || :
	mv "$MIGRATION_PACKAGES.new" "$MIGRATION_PACKAGES"
fi

# A fixture migration that runs after the failing one, so a test tells a run
# that stopped from a run that carried on.
#
# @xghost-migration
# summary: Remove the generated file of a bundle that is gone.
# effect: remove-generated-file
# @end-xghost-migration

printf '0003\n' >>"$MIGRATION_LOG"

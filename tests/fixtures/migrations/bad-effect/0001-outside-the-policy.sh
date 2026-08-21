# A fixture migration that declares an effect the policy does not permit.
# ADR 0001 permits five, and editing a configuration file is not one of them.
#
# @xghost-migration
# summary: Patch the configuration file of the user.
# effect: edit-config-file
# @end-xghost-migration

printf '0001\n' >>"$MIGRATION_LOG"

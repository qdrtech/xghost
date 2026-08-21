# A fixture migration that fails. The status it ends with is the one the report
# of the runner names, so it is a value no shell produces by accident.
#
# @xghost-migration
# summary: Enable the unit of the notification centre.
# effect: enable-unit
# @end-xghost-migration

printf '0002\n' >>"$MIGRATION_LOG"
exit 7

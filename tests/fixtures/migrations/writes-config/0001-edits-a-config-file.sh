# A fixture migration that is inside the metadata rules and outside the policy:
# it declares a permitted effect and then writes into the configuration
# directory of the user. It is what the policy check of tests/migrations.bats is
# run against, and it is the reason that check exists.
#
# It writes nothing when it runs, because no test runs it. The line below is
# text the check reads.
#
# @xghost-migration
# summary: Set a key in the configuration of the user.
# effect: set-desktop-key
# @end-xghost-migration

if false; then
	printf 'gaps-in=8\n' >>"$XDG_CONFIG_HOME/hypr/hyprland.conf"
fi

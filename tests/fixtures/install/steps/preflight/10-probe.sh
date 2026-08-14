# The step the runner is tested against. PROBE says how it ends.
case ${PROBE:-ok} in
fail)
	install_fail "the probe failed on purpose" "read tests/install.bats"
	;;
crash)
	# A command that fails and is not guarded. 'set -e' ends the step, and the
	# runner names it all the same.
	false
	printf 'this line is never reached\n'
	;;
esac
install_say "probe preflight"

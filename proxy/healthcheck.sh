#!/usr/bin/env bash
# Send a COMPLETE http request, not a bare socket open.
#
# Two reasons. A headerless connect-and-close is logged by squid no matter what
# the access_log ACL says, because there is no request to evaluate, and it would
# bury the real audit trail under one line every few seconds. And a complete
# request tests more: a 403 here proves squid is listening AND that the policy
# engine is denying a source outside localnet, rather than merely that a port is
# open.
set -uo pipefail
exec 3<>/dev/tcp/127.0.0.1/3128 || exit 1
printf 'HEAD http://squid.internal/ HTTP/1.0\r\n\r\n' >&3 || exit 1
head -1 <&3 | grep -q '403' || exit 1
exit 0

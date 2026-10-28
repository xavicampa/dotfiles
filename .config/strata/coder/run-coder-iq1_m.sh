#!/bin/sh
cd "/opt/strata/terminal"
exec "/opt/strata/terminal/python/bin/python3" "/opt/strata/terminal/serve/server.py" "--engine" "strata" "--config" "/data/install/strata-coder-iq1_m.json" "--port" "8080" "--open"

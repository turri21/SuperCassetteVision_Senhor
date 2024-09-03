#!/usr/bin/env python3

import sys

fn = sys.argv[1]

with open(fn, 'rb') as f:
    data = f.read()

if len(data) % 8192 != 0:
    sys.exit(0)

# Trivial checksum
csum = 0
for b in data:
    csum += int(b)

print(f"{csum:08x} {fn}")


# Local Variables:
# compile-command: "find -L rom -type f -print0 | xargs -0 -n 1 ./scan-rom.py"
# End:

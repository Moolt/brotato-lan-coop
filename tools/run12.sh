#!/usr/bin/env bash
# Real players at scale (docs/testing.md, "Many real players"): the host and ND clients on this PC,
# NN clients on a second PC, each client behind tools/netsim.py (delay, jitter, bursts, loss).
# Usage: SCRATCH=<dir holding game/> tools/run12.sh <name> [ENV=val ...]
#   ENV applies to every instance; HOST_EXTRA="A=1 B=2" to the host only, CLIENT_ENV="..." to the
#   clients only (e.g. TARGET_FPS=60); ND, NN, PROFILES_D, PROFILES_N, NB (ssh target), HOST_IP,
#   NB_GODOT (the Godot binary on the second PC), LIMIT (seconds), DIRECT=1 (the second PC's
#   clients join the host directly, without netsim).
# The second PC needs ~/.cache/brotest/game (a test copy: rsync -aL <scratch>/game/ there) and
# a graphical session; logs end up in <scratch>/runs/<name>/ (the second PC's in nb/).
repo="$(cd "$(dirname "$0")/.." && pwd)"
S=${SCRATCH:?set SCRATCH to the scratch dir holding game/}
G="$repo/../Godot/Godot_v3.7-dev1_x11.64"
GN=${NB_GODOT:-'~/Documents/Projects/Ai/brotato-multiplayer/Godot/Godot_v3.7-dev1_x11.64'}
NB=${NB:-malte@192.168.178.20}
HOST_IP=${HOST_IP:-192.168.178.28}
[ -f $S/game/project.godot ] || { echo "no game copy"; exit 1; }
name=$1; shift
D=$S/runs/$name; mkdir -p $D
for kv in "$@"; do export "$kv"; done
ND=${ND:-6}; NN=${NN:-5}
# One profile per client link, cycled.
PROFILES_D=(${PROFILES_D:-lan wifi wifi wifips bad wifi})
PROFILES_N=(${PROFILES_N:-wifi wifips wifi wifips bad})
TOTAL=$((1 + ND + NN))
export SHOT_DIR=$D
LIMIT=${LIMIT:-600}
envs="CLIENT_WALK=${CLIENT_WALK:-1} JITTER_LOG=${JITTER_LOG:-1} PERF_LOG=${PERF_LOG:-} WAVES=${WAVES:-1} TEST_VOLUME=0 MORTAL=${MORTAL:-}"

nspecs=""
for i in $(seq 1 $NN); do nspecs="$nspecs $((25100 + i)):${PROFILES_N[$(( (i - 1) % ${#PROFILES_N[@]} ))]}"; done
dspecs=""
for i in $(seq 1 $ND); do dspecs="$dspecs $((25000 + i)):${PROFILES_D[$(( (i - 1) % ${#PROFILES_D[@]} ))]}"; done
echo "desktop links:$dspecs  notebook links:$nspecs" | tee $D/links.txt
python3 -u $repo/tools/netsim.py 127.0.0.1 24999 $dspecs > $D/netsim_desktop.log 2>&1 &
PROXY=$!

# Second PC (skipped with NN=0): sync driver + mod, start its proxy and clients.
SSHP=""
if [ "$NN" -gt 0 ]; then
rsync -aL --delete $S/game/mods-unpacked/Moolt-Lan_Coop/ $NB:.cache/brotest/game/mods-unpacked/Moolt-Lan_Coop/
rsync -aL $S/game/lan_test_driver.gd $repo/tools/netsim.py $NB:.cache/brotest/
ssh $NB 'cp ~/.cache/brotest/lan_test_driver.gd ~/.cache/brotest/game/'
cat > $D/nb.sh <<EOF
cd ~/.cache/brotest
[ -f netsim.pid ] && kill \$(cat netsim.pid) 2>/dev/null; sleep 0.3
mkdir -p ~/.cache/brotest/runs/$name
export DISPLAY=:0 XDG_RUNTIME_DIR=/run/user/1000 XAUTHORITY=\$(ls /run/user/1000/.mutter-Xwaylandauth.*)
nohup python3 -u netsim.py $HOST_IP 24999 $nspecs > runs/$name/netsim.log 2>&1 &
echo \$! > netsim.pid
pids=""
for i in \$(seq 1 $NN); do
  u=~/.cache/brotest/udata/n\$i; mkdir -p \$u; [ -d \$u/BrotatoLanTest ] || cp -a ~/.local/share/BrotatoLanTest \$u/
  x=\$(( ((i - 1) % 3) * 640 )); y=\$(( ((i - 1) / 3) * 360 ))
  vblank_mode=0 __GL_SYNC_TO_VBLANK=0 XDG_DATA_HOME=\$u JOIN_ADDR=\$( [ "$DIRECT" = 1 ] && echo $HOST_IP:24999 || echo 127.0.0.1:\$((25100 + i)) ) PLAYER_NAME=Nb\$i PICK=\$((i + 6)) SHOT_DIR=~/.cache/brotest/runs/$name $envs $EXTRA_ENV $CLIENT_ENV \\
    timeout $LIMIT nohup $GN --path game --resolution 640x360 --position \$x,\$y -- join > runs/$name/nb\$i.log 2>&1 &
  pids="\$pids \$!"
  sleep 0.4
done
wait \$pids
kill \$(cat netsim.pid)
EOF
scp -q $D/nb.sh $NB:.cache/brotest/nb.sh
ssh $NB 'bash ~/.cache/brotest/nb.sh' > $D/nb_ssh.log 2>&1 &
SSHP=$!
fi

cd $S
timeout $LIMIT nohup env EXPECT=$TOTAL FAKES=0 $envs $EXTRA_ENV HOST_ENV=1 $HOST_EXTRA $G --path game --resolution 1280x720 --position 0,0 -- host > $D/host.log 2>&1 &
HOSTP=$!
sleep 1
for i in $(seq 1 $ND); do
	u=$S/udata/d$i; mkdir -p $u; [ -d $u/BrotatoLanTest ] || cp -a ~/.local/share/BrotatoLanTest $u/
	x=$(( 1280 + ((i - 1) % 2) * 640 )); y=$(( ((i - 1) / 2) * 360 ))
	XDG_DATA_HOME=$u JOIN_ADDR=127.0.0.1:$((25000 + i)) PLAYER_NAME=Desk$i PICK=$i env $envs $EXTRA_ENV $CLIENT_ENV \
		timeout $LIMIT nohup $G --path game --resolution 640x360 --position $x,$y -- join > $D/d$i.log 2>&1 &
	CLIENTS="$CLIENTS $!"
	sleep 0.4
done
wait $HOSTP
sleep 5
[ -n "$CLIENTS" ] && wait $CLIENTS 2>/dev/null
sleep 3
kill $PROXY
if [ -n "$SSHP" ]; then
	wait $SSHP
	mkdir -p $D/nb; rsync -a $NB:.cache/brotest/runs/$name/ $D/nb/
fi
echo "done $name"
grep -a "SCRIPT\|ERROR" $D/*.log $D/nb/*.log | grep -v "_first != nullptr\|self_list.h\|still in use\|ObjectDB\|leaked\|MemoryPool\|resources still" | head -30

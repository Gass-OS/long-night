#!/data/data/com.termux/files/usr/bin/bash
# Fix: two functions had the same name (_make_coin) in city.gd and stage2.gd.
# GDScript refuses to compile a script with duplicate function names, so the whole
# script was dropped (grey screen on stage 2, no coins/shops/missions on stage 1).
set -e
cd ~/long-night

for f in city.gd stage2.gd; do
	if [ -f "$f" ]; then
		sed -i 's/^func _make_coin() -> AudioStreamWAV:/func _make_coin_sfx() -> AudioStreamWAV:/' "$f"
		sed -i 's/_sfx_player("coin", _make_coin, -9.0)/_sfx_player("coin", _make_coin_sfx, -9.0)/' "$f"
		sed -i 's/_sfx_player(_make_coin(), -9.0)/_sfx_player(_make_coin_sfx(), -9.0)/' "$f"
	fi
done

echo "Duplicate function names left (should print nothing under each file):"
for f in city.gd stage2.gd thug.gd medina.gd; do
	if [ -f "$f" ]; then
		echo "-- $f"
		grep -o '^func [a-zA-Z_0-9]*' "$f" | sort | uniq -d
	fi
done

git add -A
git commit -m "Fix duplicate _make_coin function (city.gd, stage2.gd)"
git push
echo "OK: pushed, build is starting"

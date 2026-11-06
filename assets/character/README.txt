REAL CHARACTER (optional). Godot 4.3 imports FBX and GLB.

1) boy.fbx   = the character WITH skin (T-pose). boy.glb also works.
2) One file per animation, WITHOUT skin, "In Place" ticked, same character:
   idle  walk  run  jump  fall  crouch_idle  crouch_walk  push  die
   (.fbx or .glb). Missing animations are skipped or replaced by a similar one.

Mixamo (free Adobe account): pick a character, then download these animations:
Idle, Walking, Running, Jump, Falling Idle, Crouch Idle, Crouch Walk, Pushing, Dying.
Rename the files as listed above and copy them into this folder, then commit and push.

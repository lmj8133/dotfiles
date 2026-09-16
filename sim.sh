#!/usr/bin/env bash
set -euo pipefail          # EXACTLY bootstrap.sh line 2
SB="$1"
deploy_claude_files() {
  local config_dir="$1"
  mkdir -p "$config_dir"
  cp -r ./claude/* "$config_dir/"
  echo "[INFO] Copied ./claude/* -> $config_dir/"
}
install_official_skills() {
  local skills_src="$1" config_dir="$2"
  local installed=0 skipped=0
  echo "[INFO] Installing Anthropic official skills to $config_dir/skills/"
  mkdir -p "$config_dir/skills"
  for skill_dir in "$skills_src"/*; do
    if [[ -d "$skill_dir" && -f "$skill_dir/SKILL.md" ]]; then
      local skill_name; skill_name=$(basename "$skill_dir")
      local target_dir="$config_dir/skills/$skill_name"
      if [[ -d "$target_dir" ]]; then
        echo "[INFO] $skill_name already exists, skip"
        ((++skipped))
      else
        cp -r "$skill_dir" "$target_dir"
        echo "[INFO] Installed skill: $skill_name"
        ((++installed))
      fi
    fi
  done
  echo "[INFO] Installed $installed ($skipped skipped)"
}
cd "$SB/repo"
for d in "$SB/alt"; do deploy_claude_files "$d"; done
echo ">>> REACHED SKILLS PHASE <<<"
for d in "$SB/alt"; do install_official_skills "$SB/srcskills" "$d"; done
echo ">>> SCRIPT COMPLETED <<<"

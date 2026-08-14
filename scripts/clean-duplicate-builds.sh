#!/bin/bash
# Elimina copias duplicadas de VibePrompt.app generadas por builds/archives,
# dejando como "la actual" únicamente la instalada en /Applications.
#
# Uso:
#   ./scripts/clean-duplicate-builds.sh            # pide confirmación
#   ./scripts/clean-duplicate-builds.sh --yes       # sin confirmación

set -euo pipefail

KEEP_APP="/Applications/VibePrompt.app"
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DERIVED_DATA_GLOB="$HOME/Library/Developer/Xcode/DerivedData/VibePrompt-"*

AUTO_YES=false
if [[ "${1:-}" == "--yes" || "${1:-}" == "-y" ]]; then
    AUTO_YES=true
fi

echo "Se conservará: $KEEP_APP"
echo ""
echo "Se eliminará:"

TARGETS=()

# Carpeta build/ del repo (DerivedData local, .xcarchive, DMGs generados)
if [[ -d "$PROJECT_ROOT/build" ]]; then
    echo "  - $PROJECT_ROOT/build/  ($(du -sh "$PROJECT_ROOT/build" 2>/dev/null | cut -f1))"
    TARGETS+=("$PROJECT_ROOT/build")
fi

# DerivedData de Xcode para este proyecto (Debug/Release duplicados)
shopt -s nullglob
for dir in $DERIVED_DATA_GLOB; do
    [[ -d "$dir" ]] || continue
    echo "  - $dir  ($(du -sh "$dir" 2>/dev/null | cut -f1))"
    TARGETS+=("$dir")
done
shopt -u nullglob

if [[ ${#TARGETS[@]} -eq 0 ]]; then
    echo "  (nada que limpiar, ya está todo consolidado en $KEEP_APP)"
    exit 0
fi

if ! $AUTO_YES; then
    read -r -p $'\n¿Confirmar borrado? [y/N] ' reply
    case "$reply" in
        [yY]|[yY][eE][sS]) ;;
        *) echo "Cancelado."; exit 1 ;;
    esac
fi

for target in "${TARGETS[@]}"; do
    rm -rf "$target"
    echo "Eliminado: $target"
done

echo ""
echo "Listo. Única copia restante: $KEEP_APP"

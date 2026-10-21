#!/bin/bash
# pack_test.sh <core> <YYYYMMDD> <mra dir> [zip name] : test zip with the CI build of <core> and its MRAs
#   rbf from branch builds-<core> (comad: builds), renamed TomSVR_<core>_<date>.rbf; MRAs "(JT<CORE>)" -> "[TomSVR]",
#   <rbf>jt<core></rbf> -> TomSVR_<core>. Writes /mnt/project-files/test/<zip name or TomSVR_<core>_test.zip>.
set -e
C=$1; D=$2; M=$3; Z=${4:-TomSVR_${C}_test.zip}
R=$(cd "$(dirname "$0")/.." && pwd)
B=builds-$C; [ "$C" = comad ] && B=builds
T=$(mktemp -d); mkdir -p "$T/_Arcade/cores"
git -C "$R" fetch -q origin "$B"
git -C "$R" show "FETCH_HEAD:jt$C.rbf" > "$T/_Arcade/cores/TomSVR_${C}_$D.rbf"
U=$(echo "JT$C" | tr a-z A-Z)
for f in "$M"/*.mra; do
    n=$(basename "$f" | sed "s/ ($U)\.mra$/ [TomSVR].mra/")
    sed -e "s/ ($U)</ [TomSVR]</" -e "s#<rbf>jt$C</rbf>#<rbf>TomSVR_$C</rbf>#" \
        -e "s/on $U, /on TomSVR_$C, /" -e "s/Requires jt$C\.rbf/Requires TomSVR_$C.rbf/" "$f" > "$T/_Arcade/$n"
done
mkdir -p /mnt/project-files/test; rm -f "/mnt/project-files/test/$Z"
(cd "$T" && zip -qr "/mnt/project-files/test/$Z" _Arcade)
unzip -l "/mnt/project-files/test/$Z" | tail -n +4 | head -n -2
rm -rf "$T"

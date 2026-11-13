#!/usr/bin/env bash
# Interprète le champ « quand » du direct. Écrit dans GITHUB_OUTPUT : mode (maintenant | programme | annuler),
# at (horodatage Unix), at_iso (UTC, pour YouTube), affiche (heure de Paris + heure du Golfe).
# Formats acceptés (heure de PARIS par défaut) :
#   maintenant | 2026-11-15 21:30 | 15/11/2026 21:30 | 15/11 21h30 | demain 21h | aujourd'hui 22:15 | 21h30 (aujourd'hui)
#   + « Riyad / KSA / Golfe / Doha / Koweït » = heure de Riyad ; « Dubaï / UAE / Oman » = heure de Dubaï
#   annuler = supprime le direct programmé
set -euo pipefail
out() { echo "$1=$2" >> "${GITHUB_OUTPUT:-/dev/stdout}"; }
die() { echo "::error::$*"; exit 1; }

Q="$(printf '%s' "${QUAND:-}" | tr '[:upper:]' '[:lower:]' | sed -E "s/[’']/'/g; s/^[[:space:]]+|[[:space:]]+$//g")"
case "$Q" in
  ""|maintenant|now|direct|"tout de suite"|immediat|immédiat) out mode maintenant; echo "Direct : maintenant"; exit 0 ;;
  annuler|annule|cancel|stop|supprimer) out mode annuler; echo "Annulation du direct programmé"; exit 0 ;;
esac

ZONE="Europe/Paris"; ZN="Paris"
if grep -Eq "riyad|riyadh|ksa|saoudi|golfe|gulf|qatar|doha|kowe|kuwait|bahre|gmt\+3|utc\+3" <<<"$Q"; then ZONE="Asia/Riyadh"; ZN="Riyad"
elif grep -Eq "duba|uae|emirat|abu ?dhabi|oman|mascate|muscat|gmt\+4|utc\+4" <<<"$Q"; then ZONE="Asia/Dubai"; ZN="Dubaï"; fi
S=$(sed -E "s/(heure de |heure d'|à |a )?(riyadh?|ksa|saoudie?|golfe|gulf|qatar|doha|kowe[iï]t|kuwait|bahre[iï]n|dubaï|dubai|uae|émirats|emirats|abu ?dhabi|oman|mascate|muscat|(gmt|utc)\+[34])//g" <<<"$Q")
S=$(sed -E "s/après-demain|apres-demain|apres demain|après demain/+2 days/; s/demain/tomorrow/; s/aujourd'hui|aujourdhui|ce soir|ce matin/today/; s/ à / /g; s/\ble\b//g" <<<"$S")
S=$(sed -E 's/([0-9]{1,2})h([0-9]{2})/\1:\2/g; s/([0-9]{1,2})h\b/\1:00/g' <<<"$S")
# jj/mm[/aaaa] -> aaaa-mm-jj (année en cours ; si la date est déjà passée : l'an prochain)
if ! [[ "$S" =~ [0-9]{4}-[0-9]{1,2}-[0-9]{1,2} ]] && [[ "$S" =~ ([0-9]{1,2})[/.]([0-9]{1,2})([/.]([0-9]{2,4}))? ]]; then
  all=${BASH_REMATCH[0]}; d=${BASH_REMATCH[1]}; m=${BASH_REMATCH[2]}; ygiven=${BASH_REMATCH[4]:-}
  y=${ygiven:-$(TZ=$ZONE date +%Y)}; [ ${#y} -eq 2 ] && y="20$y"
  iso=$(printf '%04d-%02d-%02d' "$((10#$y))" "$((10#$m))" "$((10#$d))")
  if [ -z "$ygiven" ] && [ "$(TZ=$ZONE date -d "$iso 23:59" +%s 2>/dev/null || echo 0)" -lt "$(date +%s)" ]; then
    iso=$(printf '%04d-%02d-%02d' "$((10#$y + 1))" "$((10#$m))" "$((10#$d))"); fi
  S="${S/$all/$iso}"
fi
S=$(tr -s ' ' <<<"$S" | sed -E 's/^ +| +$//g')
AT=$(TZ=$ZONE date -d "$S" +%s 2>/dev/null) || die "Date/heure non comprise : « ${QUAND} ». Exemples : « 2026-11-15 21:30 », « 15/11 21h30 », « demain 21h », « demain 21h Riyad », ou « maintenant »."
NOW=$(date +%s)
[ "$AT" -ge $((NOW + 300)) ] || die "Heure « ${QUAND} » = $(TZ=Europe/Paris date -d "@$AT" '+%d/%m/%Y %H:%M') (Paris) : déjà passée ou dans moins de 5 min. Pour diffuser tout de suite : quand = maintenant."
[ "$AT" -le $((NOW + 30 * 86400)) ] || die "Heure « ${QUAND} » à plus de 30 jours : programme-la plus tard."
JOURS=(dimanche lundi mardi mercredi jeudi vendredi samedi)
AFF="${JOURS[$(TZ=Europe/Paris date -d "@$AT" +%w)]} $(TZ=Europe/Paris date -d "@$AT" '+%d/%m/%Y %H:%M') (Paris) = $(TZ=Asia/Riyadh date -d "@$AT" '+%H:%M') à Riyad"
out mode programme; out at "$AT"; out at_iso "$(date -u -d "@$AT" +%Y-%m-%dT%H:%M:%SZ)"; out affiche "$AFF"
echo "Direct programmé : $AFF (saisi en heure de $ZN)"

#!/bin/bash
# shellcheck disable=SC2059  # color variables inside printf formats are intentional
#
# mac-inspect: one-shot, read-only health and authenticity report for a Mac.
# https://github.com/rif-qi/mac-inspect
#
# Uses only tools built into macOS. Makes no network requests and writes nothing.
# The serial number, Apple ID, network names and device names are never printed.
#
#   bash mac-inspect.sh              full report, no password needed
#   bash mac-inspect.sh --deep       adds live CPU/GPU power, clocks and thermal pressure
#                                  (Apple's powermetrics; asks for your Mac password)
#   NO_COLOR=1 bash mac-inspect.sh   plain text, for pasting somewhere
#
# From GitHub, without downloading:
#   curl -fsSL https://raw.githubusercontent.com/rif-qi/mac-inspect/main/mac-inspect.sh | bash
#   curl -fsSL https://raw.githubusercontent.com/rif-qi/mac-inspect/main/mac-inspect.sh | bash -s -- --deep

VERSION="1.0.0"
export LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8
PATH=/usr/bin:/bin:/usr/sbin:/sbin:/usr/libexec:/opt/homebrew/bin:/usr/local/bin

DEEP=0
for arg in "$@"; do
  case "$arg" in
    --deep) DEEP=1 ;;
    -v|--version) echo "mac-inspect $VERSION"; exit 0 ;;
    -h|--help)
      echo "mac-inspect $VERSION: read-only health and authenticity report for a Mac"
      echo
      echo "Usage: mac-inspect.sh [--deep] [--help] [--version]"
      echo "  --deep       also sample live CPU/GPU power, clocks and thermal pressure"
      echo "               (uses Apple's powermetrics; asks for your Mac password)"
      echo "  NO_COLOR=1   plain-text output, e.g. NO_COLOR=1 bash mac-inspect.sh"
      echo
      echo "Run from GitHub:"
      echo "  curl -fsSL https://raw.githubusercontent.com/rif-qi/mac-inspect/main/mac-inspect.sh | bash"
      echo "  curl -fsSL https://raw.githubusercontent.com/rif-qi/mac-inspect/main/mac-inspect.sh | bash -s -- --deep"
      echo
      echo "More: https://github.com/rif-qi/mac-inspect"
      exit 0 ;;
    *) echo "mac-inspect: unknown option '$arg' (try --help)" >&2; exit 2 ;;
  esac
done
if [ "$(uname -s)" != "Darwin" ]; then echo "mac-inspect only runs on macOS." >&2; exit 1; fi

if [ -t 1 ] && [ -z "${NO_COLOR:-}" ]; then
  B=$'\033[1m' D=$'\033[2m' G=$'\033[32m' Y=$'\033[33m' R=$'\033[31m' C=$'\033[36m' P=$'\033[35m' N=$'\033[0m'
else
  B='' D='' G='' Y='' R='' C='' P='' N=''
fi

# Four levels: ✓ ok · ! watch (wear, settings) · ✗ problem (needs action)
# · ⚑ suspicious (signs of replaced, fake or tampered parts/system).
# Each finding is also counted against the area it was found in, for the verdict table.
SEC_NAMES=(); SEC_W=(); SEC_B=(); SEC_S=(); SI=-1; AREA=""
SUS_L=(); BAD_L=(); WARN_L=()
section() {
  printf "\n${B}${C}%s${N}\n" "$1"
  if [ -n "${2:-}" ]; then SI=${#SEC_NAMES[@]}; SEC_NAMES[$SI]="$2"; SEC_W[$SI]=0; SEC_B[$SI]=0; SEC_S[$SI]=0; AREA="$2"
  else SI=-1; AREA="$1"; fi
}
ok()   { printf "  ${G}✓${N} %-17s %s\n" "$1" "$2"; }
info() { printf "  ${D}·${N} %-17s %s\n" "$1" "$2"; }
warn() { printf "  ${Y}!${N} %-17s %s\n" "$1" "$2"; WARN_L+=("${D}$AREA ·${N} $1: $2"); [ "$SI" -ge 0 ] && SEC_W[$SI]=$(( SEC_W[SI] + 1 )); }
bad()  { printf "  ${R}✗${N} %-17s %s\n" "$1" "$2"; BAD_L+=("${D}$AREA ·${N} $1: $2"); [ "$SI" -ge 0 ] && SEC_B[$SI]=$(( SEC_B[SI] + 1 )); }
sus()  { printf "  ${P}⚑${N} %-17s ${P}%s${N}\n" "$1" "$2"; SUS_L+=("${D}$AREA ·${N} $1: $2"); [ "$SI" -ge 0 ] && SEC_S[$SI]=$(( SEC_S[SI] + 1 )); }

# Value after "Key:" in system_profiler / diskutil text output.
field() {
  printf '%s\n' "$1" | awk -v k="$2" '{ l=$0; sub(/^[ \t]+/,"",l)
    if (index(l, k ":")==1) { v=substr(l, length(k)+2); sub(/^[ \t]+/,"",v); print v; exit } }'
}
# Top-level value of "Key" = value in ioreg output.
ioval() { printf '%s\n' "$IOBAT" | awk -v k="\"$1\" = " '{ i=index($0,k); if (i) { print substr($0, i+length(k)); exit } }'; }
lt() { awk -v a="$1" -v b="$2" 'BEGIN{exit !(a+0 < b+0)}'; }
kb_human() { awk -v k="$1" 'BEGIN{ if (k>=1048576) printf "%.1f GB", k/1048576; else printf "%d MB", k/1024 }'; }
gb() { awk -v b="$1" 'BEGIN{printf "%.1f", b/1073741824}'; }

[ -t 2 ] && printf "${D}Collecting (about 6 seconds)…${N}" >&2

# ─── gather (slow calls first) ─────────────────────────────────────────────
HW=$(system_profiler SPHardwareDataType 2>/dev/null)
DISP=$(system_profiler SPDisplaysDataType 2>/dev/null)
WIFI=$(system_profiler SPAirPortDataType 2>/dev/null)
BT=$(system_profiler SPBluetoothDataType 2>/dev/null)
CPULINE=$(top -l 2 -n 0 -s 1 2>/dev/null | grep 'CPU usage' | tail -1)
MODEL=$(field "$HW" "Model Name"); MID=$(field "$HW" "Model Identifier"); MNUM=$(field "$HW" "Model Number")
CHIP=$(field "$HW" "Chip"); [ -z "$CHIP" ] && CHIP=$(field "$HW" "Processor Name")
CORES=$(field "$HW" "Total Number of Cores")
GPUCORES=$(field "$DISP" "Total Number of Cores")
GPUNAME=$(field "$DISP" "Chipset Model"); METAL=$(field "$DISP" "Metal Support"); [ -z "$METAL" ] && METAL=$(field "$DISP" "Metal Family")
NCPU=$(sysctl -n hw.ncpu)

[ -t 2 ] && printf "\r\033[K" >&2

# ─── header ────────────────────────────────────────────────────────────────
RULE="────────────────────────────────────────────────────────────"
printf "${B}  MAC INSPECTION REPORT${N}  ${D}%s · mac-inspect %s${N}\n" "$(date '+%Y-%m-%d %H:%M')" "$VERSION"
printf "  %s · %s · macOS %s\n" "${MODEL:-Mac}" "${CHIP:-unknown chip}" "$(sw_vers -productVersion)"
printf "${D}%s${N}\n" "$RULE"

# ─── system ────────────────────────────────────────────────────────────────
section "SYSTEM" "System"
info "Model" "${MODEL} (${MID})${MNUM:+ · $MNUM}"
CORETXT=$(printf '%s' "$CORES" | sed -E 's/^([0-9]+) \(([0-9]+) performance and ([0-9]+) efficiency\)/\1 cores (\2 performance + \3 efficiency)/; s/^([0-9]+)$/\1 cores/')
info "CPU" "${CHIP}${CORETXT:+ · $CORETXT}"
info "GPU" "${GPUNAME:-unknown}${GPUCORES:+ · $GPUCORES cores}${METAL:+ · $METAL}"
info "Memory" "$(( $(sysctl -n hw.memsize) / 1073741824 )) GB"
info "macOS" "$(sw_vers -productVersion) ($(sw_vers -buildVersion))"
FW=$(field "$HW" "System Firmware Version"); [ -n "$FW" ] && info "Firmware" "$FW"
[ "$(sysctl -n kern.hv_vmm_present 2>/dev/null)" = "1" ] && sus "Virtual machine" "This is a VM, not a real Mac: none of the hardware results can be trusted"
BOOT=$(sysctl -n kern.boottime | sed -E 's/^[^0-9]*([0-9]+).*/\1/')
UP=$(( $(date +%s) - BOOT )); UPD=$((UP/86400)); UPH=$((UP%86400/3600)); UPM=$((UP%3600/60))
UPTXT="${UPD}d ${UPH}h ${UPM}m"
if [ "$UPD" -ge 14 ]; then warn "Uptime" "$UPTXT (a restart often helps after 2+ weeks)"; else ok "Uptime" "$UPTXT"; fi

# ─── performance ───────────────────────────────────────────────────────────
section "PERFORMANCE" "Performance"
IDLE=$(printf '%s' "$CPULINE" | sed -E 's/.* ([0-9.]+)% idle.*/\1/')
if [ -n "$IDLE" ]; then
  BUSY=$(awk -v i="$IDLE" 'BEGIN{printf "%.0f", 100-i}')
  if lt "$BUSY" 60; then ok "CPU in use" "${BUSY}% right now"
  elif lt "$BUSY" 85; then warn "CPU in use" "${BUSY}% right now (busy)"
  else bad "CPU in use" "${BUSY}% right now (maxed out)"; fi
fi
GPUUTIL=$(ioreg -r -d 1 -c IOAccelerator -w0 2>/dev/null | grep -oE '"Device Utilization %"=[0-9]+' | head -1 | cut -d= -f2)
if [ -n "$GPUUTIL" ]; then
  if [ "$GPUUTIL" -lt 60 ]; then ok "GPU in use" "${GPUUTIL}% right now"
  elif [ "$GPUUTIL" -lt 85 ]; then warn "GPU in use" "${GPUUTIL}% right now (busy)"
  else bad "GPU in use" "${GPUUTIL}% right now (maxed out)"; fi
fi
read -r L1 L5 L15 <<<"$(sysctl -n vm.loadavg | tr -d '{}')"
RATIO=$(awk -v l="$L5" -v n="$NCPU" 'BEGIN{printf "%.2f", l/n}')
LTXT="$L1 · $L5 · $L15  (1/5/15 min, $NCPU cores)"
if lt "$RATIO" 0.7; then ok "Load average" "$LTXT"
elif lt "$RATIO" 1.0; then warn "Load average" "$LTXT, fairly busy"
else bad "Load average" "$LTXT, overloaded"; fi
TH=$(pmset -g therm 2>/dev/null)
SPEED=$(printf '%s\n' "$TH" | awk -F'= *' '/CPU_Speed_Limit/{print $2+0; exit}')
if [ -n "$SPEED" ]; then
  if [ "$SPEED" -lt 100 ]; then bad "Throttling" "CPU limited to ${SPEED}% by heat"
  else ok "Throttling" "None (CPU speed limit 100%)"; fi
elif printf '%s' "$TH" | grep -q 'No thermal warning level has been recorded'; then ok "Throttling" "None recorded"
else warn "Throttling" "macOS has recorded a thermal warning"; fi
LPM=$(pmset -g 2>/dev/null | awk '/lowpowermode/{print $2; exit}')
case "$LPM" in
  1) warn "Low Power Mode" "On (CPU and GPU deliberately slowed to save battery)" ;;
  0) ok "Low Power Mode" "Off" ;;
esac

# ─── live power (optional, needs password) ─────────────────────────────────
if [ "$DEEP" = 1 ]; then
  section "LIVE POWER & CLOCKS" "Live power"
  printf "  ${D}powermetrics is Apple's own tool; it needs your Mac password to sample for 2 seconds.${N}\n"
  if sudo -p "  Mac password: " -v; then
    PM=$(sudo powermetrics --samplers cpu_power,gpu_power,thermal -i 2000 -n 1 2>/dev/null)
    pm() { printf '%s\n' "$PM" | awk -v re="$1" '$0 ~ re { sub(/^[^:]*: */,""); sub(/ *\(.*/,""); print; exit }'; }
    PRES=$(pm '^Current pressure level:')
    case "$PRES" in
      Nominal) ok "Thermal pressure" "Nominal (no heat limits)" ;;
      Moderate) warn "Thermal pressure" "Moderate (warm, may slow down)" ;;
      "") ;;
      *) bad "Thermal pressure" "$PRES (being slowed by heat)" ;;
    esac
    # Power values come as "119 mW" (Apple silicon) or "3.45W" (Intel); normalize to mW.
    mw() { printf '%s' "$1" | awk '{ v=$1+0; if ($1 ~ /W$/ || $2 ~ /^W/) v*=1000; print int(v) }'; }
    # Highest frequency listed in a residency histogram line = that block's top speed.
    maxmhz() { printf '%s\n' "$PM" | awk -v re="$1" '$0 ~ re { m=0; s=$0
      while (match(s, /[0-9]+ MHz/)) { v=substr(s,RSTART,RLENGTH)+0; if (v>m) m=v; s=substr(s,RSTART+RLENGTH) }
      if (m>0) print m; exit }'; }
    CPUW=$(pm '^CPU Power:'); GPUW=$(pm '^GPU Power:'); ALLW=$(pm '^Combined Power')
    INTELW=$(pm '^Intel energy model derived package power')
    [ -n "$CPUW" ] && info "CPU power" "$CPUW"
    [ -n "$GPUW" ] && info "GPU power" "$GPUW"
    [ -n "$ALLW" ] && info "Chip power total" "$ALLW"
    [ -n "$INTELW" ] && info "Package power" "$INTELW"
    ECL=$(pm '^E-Cluster HW active frequency:' | awk '{print $1+0}')
    EMAX=$(maxmhz '^E-Cluster HW active residency:')
    PCL=$(printf '%s\n' "$PM" | awk '/^P[0-9]*-Cluster HW active frequency:/{sub(/^[^:]*: */,""); printf "%s%d", sep, $1+0; sep=" / "}')
    PAVG=$(printf '%s\n' "$PM" | awk '/^P[0-9]*-Cluster HW active frequency:/{sub(/^[^:]*: */,""); s+=$1; n++} END{ if (n) printf "%d", s/n }')
    PMAX=$(maxmhz '^P[0-9]*-Cluster HW active residency:')
    [ -n "$ECL" ] && info "Efficiency cores" "$ECL MHz${EMAX:+ of $EMAX MHz max}"
    [ -n "$PCL" ] && info "Performance cores" "$PCL MHz${PMAX:+ of $PMAX MHz max}"
    INTF=$(pm '^System Average frequency as fraction of nominal')
    [ -n "$INTF" ] && info "CPU clocks" "$INTF of nominal"
    GF=$(pm '^GPU (HW )?active frequency:' | awk '{print $1+0}'); GR=$(pm '^GPU (HW )?active residency:')
    GMAX=$(maxmhz '^GPU (HW )?active residency:')
    [ -n "$GF$GR" ] && info "GPU" "${GR:+$GR busy}${GF:+ at $GF MHz}${GMAX:+ (max $GMAX MHz)}"
    if [ -z "$PM" ]; then
      info "powermetrics" "No data returned"
    else
      # Plain-English reading of the numbers above.
      TOT=$(mw "${ALLW:-${INTELW:-$CPUW}}")
      if [ -n "$INTELW" ]; then IDLE_MW=3000; else IDLE_MW=1000; fi
      if   [ "${TOT:-0}" -lt "$IDLE_MW" ]; then LOADTXT="idle"
      elif [ "$TOT" -lt 5000 ];  then LOADTXT="light use"
      elif [ "$TOT" -lt 15000 ]; then LOADTXT="moderate load"
      else LOADTXT="heavy load"; fi
      PPCT=""; [ -n "$PAVG" ] && [ -n "$PMAX" ] && PPCT=$(( PAVG * 100 / PMAX ))
      note() { printf "    ${D}→${N} %s\n" "$1"; }
      printf "\n  ${B}What this means${N}\n"
      note "The chip is drawing $(awk -v m="${TOT:-0}" 'BEGIN{ if (m<1000) printf "%d mW", m; else printf "%.1f W", m/1000 }'): $LOADTXT. Apple silicon idles below 1 W and can reach tens of watts flat out."
      if [ -n "$PPCT" ]; then
        if [ "$LOADTXT" = "idle" ] || [ "$LOADTXT" = "light use" ]; then
          note "Performance cores are at ~${PPCT}% of top speed. That's normal with little work to do: macOS slows them down to save power."
        elif [ "$PPCT" -lt 60 ] && [ "$PRES" = "Nominal" ]; then
          warn "Clock speed" "Busy but cores only at ~${PPCT}% of top speed with no heat limit (Low Power Mode or energy settings may be capping it)"
        else
          note "Performance cores are at ~${PPCT}% of top speed under load."
        fi
      fi
      case "$PRES" in
        Nominal) note "Thermal pressure Nominal: nothing is being slowed by heat right now." ;;
        Moderate) note "Thermal pressure Moderate: the Mac is warm and may start slowing down; check the vents and what's running." ;;
        "") ;;
        *) note "Thermal pressure $PRES: the Mac is actively slowing itself to cool down. Check the vents, fans and what's running." ;;
      esac
      [ -n "$GR" ] && lt "${GR%\%}" 5 && note "The GPU is basically idle (${GR} busy)."
      [ "$LPM" = "1" ] && note "Low Power Mode is on, which also caps the clocks. Turn it off (System Settings → Battery) to get full speed."
      if [ "$LOADTXT" = "idle" ] || [ "$LOADTXT" = "light use" ]; then
        note "To test real performance, run --deep again during heavy work (video export, build, game). Power should rise and thermal pressure should stay Nominal or Moderate."
      fi
    fi
  else
    info "powermetrics" "Skipped (no password entered)"
  fi
fi

# ─── memory ────────────────────────────────────────────────────────────────
section "MEMORY" "Memory"
case "$(sysctl -n kern.memorystatus_vm_pressure_level 2>/dev/null)" in
  1) ok "Pressure" "Normal" ;;
  2) warn "Pressure" "Warning (apps are competing for memory)" ;;
  4) bad "Pressure" "Critical (the Mac is out of memory)" ;;
  *) info "Pressure" "Unknown" ;;
esac
VM=$(vm_stat)
PGSZ=$(printf '%s\n' "$VM" | sed -nE 's/.*page size of ([0-9]+) bytes.*/\1/p')
vmp() { printf '%s\n' "$VM" | awk -F': *' -v k="$1" '$1==k{gsub(/\./,"",$2); print $2+0; exit}'; }
ANON=$(vmp "Anonymous pages"); PURG=$(vmp "Pages purgeable"); WIRED=$(vmp "Pages wired down"); COMP=$(vmp "Pages occupied by compressor")
if [ -n "$PGSZ" ] && [ -n "$ANON" ]; then
  APPB=$(( (ANON - PURG) * PGSZ )); WIREDB=$(( WIRED * PGSZ )); COMPB=$(( COMP * PGSZ ))
  info "Used" "$(gb $((APPB + WIREDB + COMPB))) GB of $(( $(sysctl -n hw.memsize) / 1073741824 )) GB (apps $(gb $APPB) · system $(gb $WIREDB) · compressed $(gb $COMPB))"
fi
SWAPM=$(sysctl -n vm.swapusage | sed -E 's/.*used = ([0-9.]+)M.*/\1/')
SWAPTXT=$(awk -v m="$SWAPM" 'BEGIN{ if (m>=1024) printf "%.1f GB", m/1024; else printf "%.0f MB", m }')
if lt "$SWAPM" 4096; then ok "Swap used" "$SWAPTXT"; else warn "Swap used" "$SWAPTXT (heavy; close apps or tabs)"; fi

# ─── storage ───────────────────────────────────────────────────────────────
section "STORAGE" "Storage"
DI=$(diskutil info disk0 2>/dev/null)
SSD=$(field "$DI" "Device / Media Name"); DSIZE=$(field "$DI" "Disk Size" | sed 's/ (.*//')
info "Drive" "${SSD:-internal disk}${DSIZE:+ · $DSIZE}"
SMART=$(field "$DI" "SMART Status")
case "$SMART" in
  Verified) ok "SMART status" "Verified" ;;
  "Not Supported"|"") info "SMART status" "${SMART:-Not reported}" ;;
  *) bad "SMART status" "$SMART (back up now)" ;;
esac
VOL=/System/Volumes/Data; [ -d "$VOL" ] || VOL=/
read -r SIZEK AVAILK <<<"$(df -k "$VOL" | awk 'NR==2{print $2, $4}')"
FREEGB=$(awk -v a="$AVAILK" 'BEGIN{printf "%.1f", a*1024/1e9}')
TOTGB=$(awk -v s="$SIZEK" 'BEGIN{printf "%.0f", s*1024/1e9}')
FPCT=$(awk -v a="$AVAILK" -v s="$SIZEK" 'BEGIN{printf "%.0f", a*100/s}')
FTXT="$FREEGB GB of $TOTGB GB (${FPCT}%)"
if [ "$FPCT" -ge 20 ]; then ok "Free space" "$FTXT"
elif [ "$FPCT" -ge 10 ]; then warn "Free space" "$FTXT, getting low"
else bad "Free space" "$FTXT, too low (slows the Mac down)"; fi
SNAPS=$(tmutil listlocalsnapshots / 2>/dev/null | grep -c 'com.apple')
if [ "$SNAPS" -gt 0 ]; then info "Local snapshots" "$SNAPS Time Machine snapshot(s) holding disk space"; else ok "Local snapshots" "None"; fi
if command -v smartctl >/dev/null 2>&1; then
  SC=$(smartctl -a disk0 2>/dev/null)
  WEAR=$(printf '%s\n' "$SC" | awk -F': *' '/Percentage Used/{gsub("%","",$2); print $2+0; exit}')
  WRITTEN=$(printf '%s\n' "$SC" | awk -F': *' '/Data Units Written/{sub(/.*\[/,"",$2); sub(/\].*/,"",$2); print $2; exit}')
  if [ -n "$WEAR" ]; then
    if [ "$WEAR" -lt 50 ]; then ok "SSD wear" "${WEAR}% used${WRITTEN:+ · $WRITTEN written}"
    elif [ "$WEAR" -lt 80 ]; then warn "SSD wear" "${WEAR}% used${WRITTEN:+ · $WRITTEN written}"
    else bad "SSD wear" "${WEAR}% used${WRITTEN:+ · $WRITTEN written}"; fi
  fi
fi

# ─── battery ───────────────────────────────────────────────────────────────
IOBAT=$( { ioreg -rn AppleSmartBattery -w0; ioreg -rc AppleSmartBatteryPack -w0; } 2>/dev/null)
section "BATTERY" "Battery"
if [ -z "$IOBAT" ]; then
  info "Battery" "None (desktop Mac)"
else
  PW=$(system_profiler SPPowerDataType 2>/dev/null)
  BATT=$(pmset -g batt)
  SRC=$(printf '%s\n' "$BATT" | sed -nE "1s/.*'(.*)'.*/\1/p")
  CHG=$(printf '%s\n' "$BATT" | awk -F'\t' 'NR==2{print $2}' | sed -E 's/ *present: true//; s/;/ ·/g')
  info "Charge" "${CHG}${SRC:+ · on $SRC}"
  COND=$(field "$PW" "Condition")
  case "$COND" in
    Normal) ok "Condition" "Normal" ;;
    "") ;;
    *) bad "Condition" "$COND" ;;
  esac
  DESIGN=$(ioval DesignCapacity); RAWMAX=$(ioval AppleRawMaxCapacity)
  MAXCAP=$(field "$PW" "Maximum Capacity"); HEALTH=${MAXCAP%\%}
  if [ -z "$HEALTH" ] && [ -n "$RAWMAX" ] && [ "${DESIGN:-0}" -gt 0 ]; then HEALTH=$((RAWMAX*100/DESIGN)); fi
  if [ -n "$HEALTH" ]; then
    HTXT="${HEALTH}% of original"
    [ -n "$RAWMAX" ] && [ -n "$DESIGN" ] && HTXT="$HTXT ($RAWMAX / $DESIGN mAh)"
    if [ "$HEALTH" -ge 80 ]; then ok "Health" "$HTXT"
    elif [ "$HEALTH" -ge 70 ]; then warn "Health" "$HTXT, aging"
    else bad "Health" "$HTXT, worn (consider replacing)"; fi
  fi
  CYCLES=$(ioval CycleCount)
  if [ -n "$CYCLES" ]; then
    if [ "$CYCLES" -lt 800 ]; then ok "Cycle count" "$CYCLES of ~1000 rated"
    elif [ "$CYCLES" -lt 1000 ]; then warn "Cycle count" "$CYCLES of ~1000 rated"
    else bad "Cycle count" "$CYCLES, past the ~1000 rated cycles"; fi
  fi
  TEMP=$(ioval Temperature)
  if [ -n "$TEMP" ]; then
    TC=$(awk -v t="$TEMP" 'BEGIN{printf "%.1f", t/100}')
    if lt "$TC" 40; then ok "Temperature" "${TC} °C"
    elif lt "$TC" 45; then warn "Temperature" "${TC} °C, warm"
    else bad "Temperature" "${TC} °C, hot"; fi
  fi
  PFS=$(ioval PermanentFailureStatus)
  if [ -n "$PFS" ]; then
    if [ "$PFS" = "0" ]; then ok "Fault flags" "None"; else bad "Fault flags" "Battery reports a permanent failure ($PFS)"; fi
  fi
fi

# ─── charger (laptops; only checkable while plugged in) ────────────────────
if [ -n "$IOBAT" ]; then
  CB=$(printf '%s\n' "$PW" | awk '/AC Charger Information:/{f=1; next} f && /^ {0,4}[^ ]/{f=0} f')
  CWATT=$(field "$CB" "Wattage (W)")
  if [ "$(field "$CB" "Connected")" = "Yes" ] || [ -n "$CWATT" ]; then
    section "CHARGER" "Charger"
    CMAN=$(field "$CB" "Manufacturer"); CNAME=$(field "$CB" "Name"); CSER=$(field "$CB" "Serial Number")
    CFW=$(field "$CB" "Firmware Version")
    info "Adapter" "${CNAME:-Unnamed adapter}${CWATT:+ · $CWATT W}${CFW:+ · firmware $CFW}"
    # Genuine Apple adapters report Apple as maker plus a serial number; fakes usually get one of these wrong.
    case "$CMAN" in
      *Apple*)
        if [ ${#CSER} -ge 8 ]; then ok "Maker" "Apple, with a serial number (not shown)"
        else sus "Maker" "Claims to be Apple but has no serial number: possibly counterfeit"; fi ;;
      "")
        if printf '%s' "$CNAME" | grep -qi 'apple\|USB-C Power Adapter\|MagSafe'; then sus "Maker" "Named like an Apple adapter but reports no maker: possibly counterfeit"
        else warn "Maker" "Not reported (generic charger; prefer Apple or a reputable brand)"; fi ;;
      *)
        if printf '%s' "$CNAME" | grep -qi 'apple'; then sus "Maker" "Named like an Apple adapter but made by $CMAN: possibly counterfeit"
        else info "Maker" "Third-party: $CMAN (fine if it's a reputable brand)"; fi ;;
    esac
    if [ -n "$CWATT" ]; then
      MINW=30; printf '%s' "$MODEL" | grep -q 'MacBook Pro' && MINW=60
      if [ "$CWATT" -lt "$MINW" ]; then warn "Power" "$CWATT W is low for this $MODEL: slow charging, and it may drain under heavy load"
      else ok "Power" "$CWATT W"; fi
    fi
    VOLTMV=$(ioreg -rn AppleSmartBattery -w0 2>/dev/null | grep -oE '"AdapterVoltage"=[0-9]+' | head -1 | cut -d= -f2)
    [ -z "$VOLTMV" ] && VOLTMV=$(pmset -g adapter 2>/dev/null | awk -F'= *' '/Voltage/{print $2+0; exit}')
    if [ -n "$VOLTMV" ] && [ "$VOLTMV" -gt 0 ]; then
      VTXT=$(awk -v v="$VOLTMV" 'BEGIN{printf "%.0f V", v/1000}')
      if [ "$VOLTMV" -lt 9000 ]; then warn "Voltage" "$VTXT only: slow charging (weak charger, or a cable that doesn't support fast charging)"
      else ok "Voltage" "$VTXT negotiated (fast charging works)"; fi
    fi
    BPCT=$(printf '%s\n' "$BATT" | awk -F'\t' 'NR==2{print $2+0}')
    CSTATE=$(printf '%s\n' "$BATT" | awk -F'\t' 'NR==2{print $2}' | awk -F'; *' '{print $2}')
    case "$CSTATE" in
      charging|"finishing charge") ok "Charging" "Yes, at ${BPCT}%" ;;
      charged) ok "Charging" "Full" ;;
      *)
        if [ "${BPCT:-100}" -lt 75 ]; then warn "Charging" "Plugged in but not charging at ${BPCT}%: check the cable, port and charger (or a charge-limit setting)"
        else info "Charging" "Paused at ${BPCT}% (normal: Optimized Battery Charging holds around 80%)"; fi ;;
    esac
  else
    section "CHARGER"
    info "Charger" "Not connected: plug it in and run again to check it"
  fi
fi

# ─── display & wireless ────────────────────────────────────────────────────
section "DISPLAY & WIRELESS" "Display & wireless"
printf '%s\n' "$DISP" | awk '
  /Display Type:/ { sub(/^[^:]*: */,""); t=$0 }
  /Resolution:/   { sub(/^[^:]*: */,""); r=$0 }
  /^ {8}[^ ].*:$/ { if (r!="") { print (t!=""?t:"External display") "|" r }; t=""; r="" }
  END { if (r!="") print (t!=""?t:"External display") "|" r }' |
while IFS='|' read -r dtype dres; do info "Display" "$dtype · $dres"; done
WSTATUS=$(field "$WIFI" "Status")
CUR=$(printf '%s\n' "$WIFI" | awk '/Current Network Information:/{f=1; next} /Other Local Wi-Fi Networks:/{f=0} f')
if [ "$WSTATUS" = "Connected" ] && [ -n "$CUR" ]; then
  CH=$(field "$CUR" "Channel"); PHY=$(field "$CUR" "PHY Mode"); RATE=$(field "$CUR" "Transmit Rate")
  RSSI=$(field "$CUR" "Signal / Noise" | awk '{print $1}')
  BAND=$(printf '%s' "$CH" | sed -nE 's/.*\(([0-9]+)GHz.*/\1/p'); [ "$BAND" = "2" ] && BAND="2.4"
  WTXT="Connected${BAND:+ · $BAND GHz}${PHY:+ · $PHY}${RATE:+ · $RATE Mbps link}"
  info "Wi-Fi" "$WTXT"
  if [ -n "$RSSI" ]; then
    if [ "$RSSI" -ge -67 ]; then ok "Wi-Fi signal" "$RSSI dBm (good)"
    elif [ "$RSSI" -ge -75 ]; then warn "Wi-Fi signal" "$RSSI dBm (weak)"
    else bad "Wi-Fi signal" "$RSSI dBm (very weak)"; fi
  fi
elif [ -n "$WSTATUS" ]; then
  info "Wi-Fi" "$WSTATUS"
else
  bad "Wi-Fi" "No Wi-Fi hardware detected (faulty or disconnected)"
fi
BTSTATE=$(field "$BT" "State"); BTCHIP=$(field "$BT" "Chipset")
if [ -n "$BTSTATE" ]; then info "Bluetooth" "$BTSTATE${BTCHIP:+ · $BTCHIP}"
else bad "Bluetooth" "No Bluetooth hardware detected"; fi

# ─── account & security ────────────────────────────────────────────────────
section "ACCOUNT & SECURITY" "Security"
MM=$(defaults export MobileMeAccounts - 2>/dev/null)
NACC=$(printf '%s' "$MM" | grep -c '<key>AccountID</key>')
if [ "${NACC:-0}" -gt 0 ]; then
  svc() { printf '%s\n' "$MM" | awk -v want="$1" '
    /<dict>/{d++; en[d]=""; nm[d]=""}
    /<key>Enabled<\/key>/{getline; en[d]=($0 ~ /true/)?"on":"off"}
    /<key>Name<\/key>/{getline; gsub(/.*<string>|<\/string>.*/,""); nm[d]=$0}
    /<\/dict>/{ if (nm[d]==want && en[d]!="") { print en[d]; exit } d-- }'; }
  DRIVE=$(svc MOBILE_DOCUMENTS); KC=$(svc KEYCHAIN_SYNC)
  info "Apple Account" "Signed in${DRIVE:+ · iCloud Drive $DRIVE}${KC:+ · Keychain sync $KC} (a seller must sign out before handover)"
else
  ok "Apple Account" "Not signed in"
fi
ALOCK=$(field "$HW" "Activation Lock Status")
case "$ALOCK" in
  Enabled)  warn "Activation Lock" "On: fine for the owner, but a Mac you buy must have it OFF, or it stays locked to the seller's Apple Account" ;;
  Disabled) ok "Activation Lock" "Off" ;;
esac
NUSERS=$(dscl . -list /Users UniqueID 2>/dev/null | awk '$2>=500' | wc -l | tr -d ' ')
if [ "$NUSERS" -le 1 ]; then ok "Local accounts" "$NUSERS user account"
else info "Local accounts" "$NUSERS user accounts (a Mac you buy should be erased, with only the account you create)"; fi
if csrutil status 2>/dev/null | grep -q 'status: enabled'; then ok "SIP" "On"
else sus "SIP" "Off: core system protection disabled, rare on a normal Mac (tampering or unsupported mods)"; fi
if fdesetup status 2>/dev/null | grep -q 'is On'; then ok "FileVault" "On (disk encrypted)"; else warn "FileVault" "Off (disk not encrypted)"; fi
if spctl --status 2>/dev/null | grep -q 'enabled'; then ok "Gatekeeper" "On"; else warn "Gatekeeper" "Off (unsigned apps can run)"; fi
if socketfilterfw --getglobalstate 2>/dev/null | grep -q 'enabled'; then ok "Firewall" "On"; else info "Firewall" "Off (macOS default)"; fi
if bioutil -r -s 2>/dev/null | grep -q 'Biometrics functionality: 1'; then ok "Touch ID" "On"; fi
ENR=$(profiles status -type enrollment 2>/dev/null)
DEP=$(printf '%s\n' "$ENR" | awk -F': ' '/Enrolled via DEP/{print $2; exit}')
MDM=$(printf '%s\n' "$ENR" | awk -F': ' '/MDM enrollment/{print $2; exit}')
MDMHOST=$(printf '%s\n' "$ENR" | sed -nE 's#.*MDM server: *[A-Za-z]+://([^/:]+).*#\1#p' | head -1)
if [ "$DEP" = "Yes" ]; then
  sus "Managed (MDM)" "Auto-enrolled by an organization${MDMHOST:+ ($MDMHOST)}: it re-enrolls even after erasing. Don't buy unless the organization releases it"
elif [ "${MDM%% *}" = "Yes" ]; then
  sus "Managed (MDM)" "Enrolled${MDMHOST:+ ($MDMHOST)}: can be locked, wiped or monitored remotely. Expected on a company Mac, a red flag on a personal or used one"
elif [ -n "$MDM" ]; then
  ok "Managed (MDM)" "Not enrolled"
fi
NPROF=$(profiles list 2>/dev/null | grep -c 'attribute: profileIdentifier')
if [ "$NPROF" -gt 0 ]; then warn "Config profiles" "$NPROF installed: check you recognize them (System Settings → Privacy & Security → Profiles)"
else ok "Config profiles" "None for this user"; fi
NBG=$(ls /Library/LaunchAgents /Library/LaunchDaemons ~/Library/LaunchAgents 2>/dev/null | grep -E '\.plist$' | grep -vc '^com\.apple\.')
info "Background items" "$NBG third-party (review in System Settings → General → Login Items & Extensions)"

# ─── parts & reliability (clues, not proof) ────────────────────────────────
section "PARTS & RELIABILITY  ${D}(clues, not proof)${N}" "Parts & reliability"
case "$MNUM" in
  M*) ok "Sold as" "New retail unit (model number starts with M)" ;;
  P*) ok "Sold as" "New, personalized/engraved (model number starts with P)" ;;
  F*) info "Sold as" "Apple Certified Refurbished (model number starts with F)" ;;
  N*) info "Sold as" "Apple service replacement unit (model number starts with N)" ;;
  "") ;;
  *)  sus "Sold as" "Unusual model-number prefix ($MNUM)" ;;
esac
SER=$(ioreg -rd1 -c IOPlatformExpertDevice 2>/dev/null | sed -nE 's/.*"IOPlatformSerialNumber" = "([^"]*)".*/\1/p')
if printf '%s' "$SER" | grep -qE '^[A-Z0-9]{10,12}$' && ! printf '%s' "$SER" | grep -qE '^0+$'; then
  ok "Serial number" "Present, valid format (not shown)"
else
  sus "Serial number" "Missing or invalid: typical of a logic board replaced outside Apple"
fi
case "$SSD" in
  APPLE*) ok "SSD" "Apple original ($SSD)" ;;
  "") ;;
  *) sus "SSD" "Non-Apple drive ($SSD): replaced or upgraded" ;;
esac
if printf '%s' "$MODEL" | grep -q 'MacBook'; then
  BIDISP=$(printf '%s\n' "$DISP" | awk -F': *' '/Display Type:/ && tolower($2) ~ /built-in/ {print $2; exit}')
  if [ -n "$BIDISP" ]; then ok "Screen" "Identifies as an Apple panel ($BIDISP)"
  elif printf '%s' "$DISP" | grep -q 'Connection Type: Internal'; then warn "Screen" "Built-in panel doesn't identify as an Apple display (possibly a replacement screen)"
  else warn "Screen" "Built-in display not detected (lid closed, or disconnected)"; fi
fi
if [ -n "$IOBAT" ]; then
  CELL=$(printf '%s\n' "$IOBAT" | sed -nE 's/.*"ManufacturerData" = <([0-9a-fA-F]+)>.*/\1/p' | head -1 | xxd -r -p 2>/dev/null |
         LC_ALL=C tr -c 'A-Z' ' ' | tr -s ' ' '\n' | grep -E '^[A-Z]{3}$' | tail -1)
  GAUGE=$(ioval DeviceName | tr -d '"')
  case "$CELL" in
    ATL|SMP|SWD|DSY|LGC|SNY|SDI|BYD|SCP|SUN) ok "Battery cells" "$CELL, a known Apple battery supplier${GAUGE:+ · gauge $GAUGE}" ;;
    "") warn "Battery cells" "Maker not reported (common on third-party batteries)${GAUGE:+ · gauge $GAUGE}" ;;
    *)  sus "Battery cells" "Unknown maker code $CELL: likely a third-party battery${GAUGE:+ · gauge $GAUGE}" ;;
  esac
  BSER=$(ioval Serial | tr -d '"')
  if [ ${#BSER} -ge 10 ] && ! printf '%s' "$BSER" | grep -qE '^0+$'; then ok "Battery serial" "Present (not shown)"
  else sus "Battery serial" "Missing or blank: typical of third-party batteries"; fi
  if [ -n "$RAWMAX" ] && [ "${DESIGN:-0}" -gt 0 ] && [ $((RAWMAX * 100 / DESIGN)) -gt 105 ]; then
    sus "Battery capacity" "Claims more than its design capacity ($RAWMAX / $DESIGN mAh): fake or reprogrammed battery"
  fi
  if [ -n "$CYCLES" ] && [ "$CYCLES" -lt 10 ]; then
    info "Battery age" "Only $CYCLES cycles: new or recently replaced battery (ask for the receipt)"
  fi
fi
if [ -r /Library/Logs/DiagnosticReports ]; then
  PANICS=$(find /Library/Logs/DiagnosticReports -maxdepth 2 -iname '*panic*' ! -name '.*' -mtime -30 2>/dev/null | wc -l | tr -d ' ')
  if [ "$PANICS" -eq 0 ]; then ok "Crashes (30 days)" "No kernel panics"
  elif [ "$PANICS" -le 2 ]; then warn "Crashes (30 days)" "$PANICS kernel panic(s) (the whole Mac restarted)"
  else bad "Crashes (30 days)" "$PANICS kernel panics (possible hardware fault)"; fi
fi

# ─── top processes ─────────────────────────────────────────────────────────
procs() {
  ps -Aco pcpu=,rss=,comm= "$1" | head -5 | while read -r cpu rss name; do
    printf "    %5s%%  %8s   %.42s\n" "$cpu" "$(kb_human "$rss")" "$name"
  done
}
section "TOP PROCESSES"
printf "  ${D}by CPU      CPU    MEMORY   NAME${N}\n";    procs -r
printf "  ${D}by memory   CPU    MEMORY   NAME${N}\n";    procs -m

# ─── summary ───────────────────────────────────────────────────────────────
printf "\n${D}%s${N}\n" "$RULE"
printf "${B}  VERDICT${N}\n"
i=0
while [ "$i" -lt "${#SEC_NAMES[@]}" ]; do
  s=${SEC_S[$i]}; b=${SEC_B[$i]}; w=${SEC_W[$i]}; v=""
  [ "$s" -gt 0 ] && v="${P}⚑ $s suspicious${N}"
  [ "$b" -gt 0 ] && v="${v:+$v · }${R}✗ $b problem$([ "$b" -gt 1 ] && echo s)${N}"
  [ "$w" -gt 0 ] && v="${v:+$v · }${Y}! $w to watch${N}"
  if [ -z "$v" ]; then
    case "${SEC_NAMES[$i]}" in
      Parts*)    v="${G}✓ No signs of replaced or non-genuine parts${N}" ;;
      Security*) v="${G}✓ No locks, management or tampering found${N}" ;;
      *)         v="${G}✓ OK${N}" ;;
    esac
  fi
  printf "  %-20s %s\n" "${SEC_NAMES[$i]}" "$v"
  i=$((i + 1))
done
NS=${#SUS_L[@]}; NB=${#BAD_L[@]}; NW=${#WARN_L[@]}
printf "\n"
if [ "$NS" -gt 0 ]; then
  printf "  ${P}${B}⚑ SUSPICIOUS: %d finding(s) to explain before trusting or buying this Mac.${N}\n" "$NS"
elif [ "$NB" -gt 0 ]; then
  printf "  ${R}${B}✗ Nothing suspicious, but %d problem(s) need action.${N}\n" "$NB"
elif [ "$NW" -gt 0 ]; then
  printf "  ${Y}${B}! Nothing suspicious. Healthy overall, %d thing(s) to watch.${N}\n" "$NW"
else
  printf "  ${G}${B}✓ Nothing suspicious. All checks look healthy.${N}\n"
fi
group() {
  local title="$1"; shift
  [ "$#" -eq 0 ] && return
  printf "\n  %s\n" "$title"
  for line in "$@"; do printf "    %s\n" "$line"; done
}
group "${P}${B}⚑ Suspicious${N} ${D}(possible replaced, fake, locked or tampered)${N}" "${SUS_L[@]}"
group "${R}${B}✗ Problems${N} ${D}(need action)${N}" "${BAD_L[@]}"
group "${Y}${B}! Watch${N} ${D}(wear, settings, things to confirm)${N}" "${WARN_L[@]}"
[ "$DEEP" = 0 ] && printf "\n  ${D}Tip: add --deep for live CPU/GPU power, clocks and thermal pressure (asks for your password).${N}\n"

# ─── interactive tests (by hand) ───────────────────────────────────────────
printf "\n${D}%s${N}\n" "$RULE"
printf "${B}  TEST BY HAND${N}  ${D}(Cmd + double-click a link to open it)${N}\n"
hand() { printf "\n  ${B}%s${N}  %s\n" "$1" "$2"; shift 2; for l in "$@"; do printf "    ${D}→${N} %s\n" "$l"; done; }
hand "Keyboard" "https://www.keyboardtester.com/tester.html" \
  "Press every key once, including Fn, arrows and the top row. Each key should light up; a key that doesn't, or types twice, is faulty."
hand "Display" "https://www.eizo.be/monitor-test/" \
  "Go full screen. On the plain white, black, red, green and blue screens, look for dead or stuck pixels." \
  "On black, check for light bleeding at the edges; on gray, check for blotches. Gradients should be smooth, without bands."
if printf '%s' "$DISP" | grep -q 'XDR'; then FPSNOTE="This is a ProMotion screen, so it should reach 120 fps."
else FPSNOTE="This screen should show a steady 60 fps."; fi
hand "Screen smoothness" "https://www.testufo.com" \
  "$FPSNOTE A moving UFO with no stutter is good."
hand "Speakers" "https://www.audiocheck.net/audiotests_stereo.php" \
  "Left/Right test: you should hear the voice only from the left, then only the right, then both. Wrong side or silence = a dead speaker." \
  "Bass test at about 70% volume: https://www.audiocheck.net/audiotests_frequencychecklow.php" \
  "Listen for buzzing, rattling or crackling as the tones play. Quiet (but clean) low notes are normal on laptop speakers."
hand "Camera & microphone" "https://webcamtests.com  ·  https://www.onlinemictest.com" \
  "The picture should be sharp with no dead spots; the mic meter should move when you speak." \
  "The built-in Photo Booth and Voice Memos apps test the same thing without giving a website access. If you use the sites, revoke the browser permission afterwards."
hand "Trackpad & ports" "(no website needed)" \
  "Click all four corners and the center, try a firm Force Click on a word, and test two-finger scrolling." \
  "Plug something into every port; check it appears in  → About This Mac → More Info → System Report → USB / Thunderbolt." \
  "Charge from each USB-C / MagSafe port: charging should start within a few seconds on every one. Run the report again while plugged in to check the charger."
hand "Apple Diagnostics" "(built in)" \
  "Shut down, hold the power button until 'Loading startup options' appears, then press Cmd+D. It tests the hardware and gives Apple reference codes."
printf "\n${D}%s${N}\n" "$RULE"
printf "  ${D}mac-inspect %s · https://github.com/rif-qi/mac-inspect · results are clues, not proof${N}\n\n" "$VERSION"
